#!/usr/bin/env bash
set -euo pipefail

# === Configuración (puedes sobreescribir por variables de entorno) ===
REPO_URL="${REPO_URL:-https://github.com/artefactual/archivematica.git}"
REPO_BRANCH="${REPO_BRANCH:-qa/1.x}"
BASE_DIR="${BASE_DIR:-$HOME/src}"
CLONE_DIR="${CLONE_DIR:-$BASE_DIR/archivematica}"
HACK_DIR="${HACK_DIR:-$CLONE_DIR/hack}"
VM_MAX_MAP_COUNT="${VM_MAX_MAP_COUNT:-262144}"

# === Buzón de transferencias para SIGEDI (host -> contenedor) ===
SIGEDI_HOST_TRANSFER_DIR="${SIGEDI_HOST_TRANSFER_DIR:-/mnt/d/ArchivematicaDrop/transfer-source}"
SIGEDI_CONTAINER_TRANSFER_DIR="${SIGEDI_CONTAINER_TRANSFER_DIR:-/home/transfer-source-sigedi}"

# === “FTP” para archivistas (recomendado: SFTP) ===
SFTP_ENABLE="${SFTP_ENABLE:-1}"
SFTP_SERVICE_NAME="${SFTP_SERVICE_NAME:-sigedi-sftp}"
SFTP_IMAGE="${SFTP_IMAGE:-atmoz/sftp:latest}"
SFTP_HOST_PORT="${SFTP_HOST_PORT:-6222}"

SFTP_USER="${SFTP_USER:-archivista}"
SFTP_PASS="${SFTP_PASS:-Archivista2026}"
SFTP_UID="${SFTP_UID:-1001}"
SFTP_GID="${SFTP_GID:-1001}"
SFTP_DIR="${SFTP_DIR:-transfer-source-sigedi}"  # carpeta visible al usuario dentro del SFTP

# Credenciales por defecto (hack/dev)
AM_USER="${AM_USER:-test}"
AM_PASS="${AM_PASS:-test}"
SS_USER="${SS_USER:-test}"
SS_PASS="${SS_PASS:-test}"

# === Utilidades ===
log() { printf "\n[%s] %s\n" "$(date +'%F %T')" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
is_wsl() { grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; }

install_apt_packages() {
  local pkgs=("$@")
  log "Instalando dependencias con apt: ${pkgs[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${pkgs[@]}"
}

check_docker() {
  have docker || die "No encuentro 'docker' en tu WSL. Activa Docker Desktop + WSL Integration para tu distro e instala el CLI si hace falta."
  docker info >/dev/null 2>&1 || die "Docker no responde. Abre Docker Desktop y asegúrate de que el motor esté corriendo y WSL Integration esté habilitado."
  docker compose version >/dev/null 2>&1 || die "No encuentro 'docker compose'. Asegúrate de tener el plugin de Compose disponible en Docker Desktop."
}

set_vm_max_map_count() {
  log "Ajustando vm.max_map_count=${VM_MAX_MAP_COUNT} (requisito típico para Elasticsearch)…"

  if is_wsl && have wsl.exe; then
    if wsl.exe -l -q 2>/dev/null | tr -d '\r' | grep -qx "docker-desktop"; then
      log "Detectado Docker Desktop (distro: docker-desktop). Aplicando sysctl ahí…"
      wsl.exe -d docker-desktop -u root -- sh -lc "
        set -e
        sysctl -w vm.max_map_count=${VM_MAX_MAP_COUNT} >/dev/null
        mkdir -p /etc/sysctl.d || true
        echo 'vm.max_map_count=${VM_MAX_MAP_COUNT}' > /etc/sysctl.d/99-archivematica-elasticsearch.conf || true
        cat /proc/sys/vm/max_map_count
      " || die "No pude ajustar vm.max_map_count dentro de docker-desktop."
      return 0
    fi
  fi

  log "Aplicando sysctl en este host Linux (puede no afectar Docker Desktop si el motor corre en otra VM)…"
  sudo sysctl -w "vm.max_map_count=${VM_MAX_MAP_COUNT}" >/dev/null
  if ! sudo grep -qE "^vm\.max_map_count\s*=\s*${VM_MAX_MAP_COUNT}\s*$" /etc/sysctl.conf; then
    echo "vm.max_map_count=${VM_MAX_MAP_COUNT}" | sudo tee -a /etc/sysctl.conf >/dev/null
  fi
  cat /proc/sys/vm/max_map_count
}

clone_or_update_repo() {
  mkdir -p "$BASE_DIR"

  if [ -d "$CLONE_DIR/.git" ]; then
    log "Repo ya existe en: $CLONE_DIR — actualizando (pull --rebase + submodules)…"
    git -C "$CLONE_DIR" fetch --all --prune
    git -C "$CLONE_DIR" checkout "$REPO_BRANCH"
    git -C "$CLONE_DIR" pull --rebase
    git -C "$CLONE_DIR" submodule update --init --recursive
  else
    log "Clonando Archivematica ($REPO_BRANCH) con submódulos en: $CLONE_DIR"
    git clone "$REPO_URL" --branch "$REPO_BRANCH" --recurse-submodules "$CLONE_DIR"
  fi

  [ -d "$HACK_DIR" ] || die "No encuentro el directorio hack en $HACK_DIR. ¿Cambió la estructura del repo?"
}

# === crea/actualiza docker-compose.override.yml para montar el buzón SIGEDI ===
configure_sigedi_transfer_mount() {
  log "Configurando buzón SIGEDI (bind mount) para Transfer source…"

  if is_wsl; then
    [ -d /mnt/d ] || die "No existe /mnt/d. ¿La unidad D: está montada en WSL? Ajusta SIGEDI_HOST_TRANSFER_DIR si tu disco es otro."
  fi

  mkdir -p "$SIGEDI_HOST_TRANSFER_DIR"

  # Best-effort permisos (en /mnt/d puede ser emulado; sirve para evitar bloqueos de escritura)
  chmod -R a+rwx "$SIGEDI_HOST_TRANSFER_DIR" 2>/dev/null || true

  local mount_line="${SIGEDI_HOST_TRANSFER_DIR}:${SIGEDI_CONTAINER_TRANSFER_DIR}"
  local override_file="$HACK_DIR/docker-compose.override.yml"

  local targets=("archivematica-storage-service" "archivematica-dashboard" "archivematica-mcp-server" "archivematica-mcp-client")
  local svc_list
  svc_list="$(cd "$HACK_DIR" && docker compose config --services)"

  local existing_targets=()
  for s in "${targets[@]}"; do
    if echo "$svc_list" | grep -qx "$s"; then
      existing_targets+=("$s")
    fi
  done
  if [ "${#existing_targets[@]}" -eq 0 ]; then
    die "No pude detectar servicios target en docker compose. Revisa que estés en el hack correcto y que docker compose funcione."
  fi

  if [ ! -f "$override_file" ]; then
    log "Creando $override_file con el bind mount solicitado…"
    {
      echo "services:"
      for s in "${existing_targets[@]}"; do
        echo "  $s:"
        echo "    volumes:"
        echo "      - $mount_line"
      done
    } > "$override_file"
    return 0
  fi

  if grep -Fq "$mount_line" "$override_file"; then
    log "Ya existe el mount en $override_file — no se realizan cambios."
    return 0
  fi

  log "Actualizando $override_file para añadir el bind mount (sin duplicados)…"
  python3 - "$override_file" "$mount_line" "${existing_targets[@]}" <<'PY'
import sys, re

path = sys.argv[1]
mount = sys.argv[2]
services = sys.argv[3:]

lines = open(path, "r", encoding="utf-8").read().splitlines()

def has_services_key(ls):
    return any(re.match(r'^services:\s*$', l) for l in ls)

def find_service_block(ls, svc):
    pat = re.compile(rf'^\s{{2}}{re.escape(svc)}:\s*$')
    for i,l in enumerate(ls):
        if pat.match(l):
            j = i+1
            while j < len(ls):
                if re.match(r'^\s{2}[A-Za-z0-9_.-]+:\s*$', ls[j]):
                    break
                j += 1
            return i, j
    return None

def ensure_mount_in_block(ls, start, end):
    block = ls[start:end]
    if any(mount in l for l in block):
        return ls

    vol_idx = None
    for k in range(start, end):
        if re.match(r'^\s{4}volumes:\s*$', ls[k]):
            vol_idx = k
            break

    if vol_idx is None:
        insert_at = start + 1
        ls.insert(insert_at, "    volumes:")
        ls.insert(insert_at + 1, f"      - {mount}")
        return ls

    insert_at = vol_idx + 1
    while insert_at < end and re.match(r'^\s{6}-\s+', ls[insert_at]):
        insert_at += 1
    ls.insert(insert_at, f"      - {mount}")
    return ls

if not has_services_key(lines):
    lines.append("")
    lines.append("services:")

for svc in services:
    blk = find_service_block(lines, svc)
    if blk is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append(f"  {svc}:")
        lines.append("    volumes:")
        lines.append(f"      - {mount}")
    else:
        s,e = blk
        lines = ensure_mount_in_block(lines, s, e)

open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY

  log "OK. Bind mount añadido: $mount_line"
}

# === NUEVO: agrega un servicio SFTP (FTP seguro) al override ===
configure_sigedi_sftp_service() {
  [ "$SFTP_ENABLE" = "1" ] || { log "SFTP deshabilitado (SFTP_ENABLE=$SFTP_ENABLE)."; return 0; }

  log "Configurando servicio SFTP en docker-compose.override.yml…"
  local override_file="$HACK_DIR/docker-compose.override.yml"
  [ -f "$override_file" ] || die "No existe $override_file. Debe crearse primero (configure_sigedi_transfer_mount)."

  local sftp_mount="${SIGEDI_HOST_TRANSFER_DIR}:/home/${SFTP_USER}/${SFTP_DIR}"
  local sftp_cmd="${SFTP_USER}:${SFTP_PASS}:${SFTP_UID}:${SFTP_GID}:${SFTP_DIR}"

  python3 - "$override_file" "$SFTP_SERVICE_NAME" "$SFTP_IMAGE" "$SFTP_HOST_PORT" "$sftp_mount" "$sftp_cmd" <<'PY'
import sys, re

path, svc, image, hostport, mount, cmd = sys.argv[1:7]
lines = open(path, "r", encoding="utf-8").read().splitlines()

def has_services_key(ls):
    return any(re.match(r'^services:\s*$', l) for l in ls)

def service_exists(ls, name):
    pat = re.compile(rf'^\s{{2}}{re.escape(name)}:\s*$')
    return any(pat.match(l) for l in ls)

if not has_services_key(lines):
    lines.append("")
    lines.append("services:")

if service_exists(lines, svc):
    # Asegurar que el mount existe; si no, no tocamos demasiado para no romper YAML existente.
    if not any(mount in l for l in lines):
        # Insertar mount de forma conservadora: al final del bloque del servicio si lo encontramos.
        pat = re.compile(rf'^\s{{2}}{re.escape(svc)}:\s*$')
        start = None
        for i,l in enumerate(lines):
            if pat.match(l):
                start = i
                break
        if start is not None:
            end = start+1
            while end < len(lines) and not re.match(r'^\s{2}[A-Za-z0-9_.-]+:\s*$', lines[end]):
                end += 1
            # Añadir una sección volumes si no existe dentro del bloque.
            block = lines[start:end]
            if not any(re.match(r'^\s{4}volumes:\s*$', x) for x in block):
                insert_at = start+1
                lines.insert(insert_at, "    volumes:")
                lines.insert(insert_at+1, f"      - {mount}")
            else:
                # Insertar bajo volumes:
                for j in range(start, end):
                    if re.match(r'^\s{4}volumes:\s*$', lines[j]):
                        k = j+1
                        while k < end and re.match(r'^\s{6}-\s+', lines[k]):
                            k += 1
                        lines.insert(k, f"      - {mount}")
                        break
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    sys.exit(0)

# Agregar bloque completo al final
if lines and lines[-1].strip():
    lines.append("")
lines.extend([
    f"  {svc}:",
    f"    image: {image}",
    f"    container_name: {svc}",
    f"    restart: unless-stopped",
    f"    ports:",
    f"      - \"{hostport}:22\"",
    f"    volumes:",
    f"      - {mount}",
    f"    command: \"{cmd}\"",
])

open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY

  log "OK. Servicio SFTP agregado/actualizado: $SFTP_SERVICE_NAME (puerto $SFTP_HOST_PORT)"
}

write_readme() {
  local readme_file="$HACK_DIR/readme.md"

  # IP sugerida (mejor esfuerzo). En WSL esto puede no ser el IP final del host Windows,
  # así que también imprimimos "localhost" como opción.
  local ip_guess
  ip_guess="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  [ -n "${ip_guess:-}" ] || ip_guess="localhost"

  cat > "$readme_file" <<EOF
# SIGEDI — Archivematica (Docker) + Buzón de Transferencias + SFTP

## Accesos
- Archivematica (Dashboard): http://127.0.0.1:62080/
- Storage Service:          http://127.0.0.1:62081/

> Nota: si accedes desde otra PC, usa el IP del servidor Windows/host en lugar de 127.0.0.1.

## Credenciales (entorno hack/dev)
- Archivematica:
  - usuario: \`${AM_USER}\`
  - clave:   \`${AM_PASS}\`
- Storage Service:
  - usuario: \`${SS_USER}\`
  - clave:   \`${SS_PASS}\`

## Buzón SIGEDI (Transfer source)
- En Windows:  D:\\ArchivematicaDrop\\transfer-source
- En WSL:      ${SIGEDI_HOST_TRANSFER_DIR}
- En contenedor (Archivematica): ${SIGEDI_CONTAINER_TRANSFER_DIR}

**Uso:** Copia aquí carpetas de expedientes (ej: \`U01_EXP-001/\`) y luego en el Dashboard:
Transfer → Standard transfer → Browse → selecciona la carpeta → Start transfer.

## SFTP (FTP seguro) para subir expedientes al buzón
- Host:  \`${ip_guess}\`  (o el IP real del host/servidor; si estás local, puedes usar \`localhost\`)
- Puerto: \`${SFTP_HOST_PORT}\`
- Usuario: \`${SFTP_USER}\`
- Clave:   \`${SFTP_PASS}\`
- Carpeta destino (remota): \`/home/${SFTP_USER}/${SFTP_DIR}\`

**Cliente recomendado:** WinSCP o FileZilla → Protocolo SFTP.

## Comandos útiles (desde ${HACK_DIR})
- Ver logs:           \`docker compose logs --follow\`
- Parar stack:        \`docker compose down\`
- Borrar TODO (data): \`make flush\`

EOF

  log "README generado: $readme_file"
}

run_install_steps() {
  log "Entrando a: $HACK_DIR"
  cd "$HACK_DIR"

  configure_sigedi_transfer_mount
  configure_sigedi_sftp_service

  log "Creando volúmenes externos (make create-volumes)…"
  make create-volumes

  log "Construyendo imágenes (make build)… (puede tardar bastante)"
  make build

  log "Levantando servicios (docker compose up -d)…"
  docker compose up -d

  log "Bootstrap de bases de datos y configuración inicial (make bootstrap)…"
  make bootstrap

  log "Reiniciando servicios de Archivematica (make restart-am-services)…"
  make restart-am-services
}

print_access_info() {
  cat <<EOF

Listo ✅

Acceso (en tu host):
- Dashboard:       http://127.0.0.1:62080/
- Storage Service: http://127.0.0.1:62081/

Credenciales por defecto (entorno hack/dev):
- Archivematica:   ${AM_USER} / ${AM_PASS}
- Storage Service: ${SS_USER} / ${SS_PASS}

Buzón SIGEDI (para que archivistas depositen expedientes):
- En Windows:     D:\\ArchivematicaDrop\\transfer-source
- En WSL:         ${SIGEDI_HOST_TRANSFER_DIR}
- En contenedor:  ${SIGEDI_CONTAINER_TRANSFER_DIR}

SFTP (FTP seguro) para cargar expedientes al buzón:
- Host:      (tu IP del host/servidor o localhost)
- Puerto:    ${SFTP_HOST_PORT}
- Usuario:   ${SFTP_USER}
- Clave:     ${SFTP_PASS}
- Carpeta:   /home/${SFTP_USER}/${SFTP_DIR}

Se generó:
- ${HACK_DIR}/readme.md

EOF
}

main() {
  log "Verificando dependencias básicas…"
  have sudo || die "Necesito 'sudo' disponible."
  have git || install_apt_packages git
  have make || install_apt_packages make
  have curl || install_apt_packages curl
  have python3 || install_apt_packages python3

  check_docker
  set_vm_max_map_count
  clone_or_update_repo
  run_install_steps
  write_readme
  print_access_info
}

main "$@"