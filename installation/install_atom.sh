#!/usr/bin/env bash
set -euo pipefail

# AtoM 2.10 development environment for WSL 2 + Docker Desktop or a native
# Linux server (e.g. Ubuntu 22.04). The environment is auto-detected.
#
# This script follows the official AtoM Docker Compose development workflow:
# https://www.accesstomemory.org/es/docs/2.10/dev-manual/env/compose/
#
# It is focused on plugin development. The official compose file bind-mounts
# the full AtoM source tree into the application containers:
#
#   Host path:          $ATOM_CLONE_DIR/plugins
#   Container path:     /atom/src/plugins
#
# Work in the host path from your shell, VS Code, or (on WSL) Windows access to
# the WSL files. Do not add a separate bind mount directly over
# /atom/src/plugins: doing that would hide the native AtoM plugins shipped in
# the source tree.
#
# Usage:
#   chmod +x install_atom.sh
#   ./install_atom.sh
#
# Optional examples:
#   ATOM_BRANCH=qa/2.x ./install_atom.sh
#   ATOM_CLONE_DIR=$HOME/src/atom-dev ./install_atom.sh
#   ATOM_PLUGIN_NAME=arSigediPlugin ./install_atom.sh
#   ATOM_PLUGIN_NAME=arSigediThemePlugin ATOM_CREATE_BS5_THEME=1 ./install_atom.sh
#   ATOM_PURGE_DEMO=0 ./install_atom.sh
#
# Important variables:
#   ATOM_REPO_URL              Default: https://github.com/artefactual/atom.git
#   ATOM_BRANCH                Default: stable/2.10.x
#   ATOM_BASE_DIR              Default: $HOME/src
#   ATOM_CLONE_DIR             Default: $ATOM_BASE_DIR/atom
#   ATOM_PLUGIN_NAME           Optional plugin directory/class prefix to create
#   ATOM_CREATE_BS5_THEME      Default: 0. Use 1 to clone arThemeB5Plugin skeleton
#   ATOM_PURGE_DEMO            Default: 1. Use 0 to skip database purge/demo load
#   ATOM_WAIT_TIMEOUT          Default: 300 seconds for database/search startup
#   VM_MAX_MAP_COUNT           Default: 262144

ATOM_REPO_URL="${ATOM_REPO_URL:-https://github.com/artefactual/atom.git}"
ATOM_BRANCH="${ATOM_BRANCH:-stable/2.10.x}"
ATOM_BASE_DIR="${ATOM_BASE_DIR:-$HOME/src}"
ATOM_CLONE_DIR="${ATOM_CLONE_DIR:-$ATOM_BASE_DIR/atom}"
ATOM_PLUGIN_NAME="${ATOM_PLUGIN_NAME:-}"
ATOM_CREATE_BS5_THEME="${ATOM_CREATE_BS5_THEME:-0}"
ATOM_PURGE_DEMO="${ATOM_PURGE_DEMO:-1}"
ATOM_UPDATE_REPO="${ATOM_UPDATE_REPO:-1}"
ATOM_WAIT_TIMEOUT="${ATOM_WAIT_TIMEOUT:-300}"
ATOM_WAIT_INTERVAL="${ATOM_WAIT_INTERVAL:-5}"
VM_MAX_MAP_COUNT="${VM_MAX_MAP_COUNT:-262144}"

THEME_SKELETON_REPO="${THEME_SKELETON_REPO:-https://github.com/artefactual-labs/arThemeB5Plugin.git}"
THEME_SKELETON_NAME="arThemeB5Plugin"

# === Buzón de transferencias compartido entre Archivematica y AtoM (host -> contenedor) ===
# La ruta del host se resuelve según el entorno en resolve_host_transfer_dirs() y
# DEBE coincidir con ARCHIVEMATICATOATOM_HOST_TRANSFER_DIR de install_archivematica.sh
# para que el bind mount conecte ambos stacks:
#   - WSL 2 + Docker Desktop -> /mnt/c/ArchivematicaDrop/transfer-share
#   - Servidor Linux nativo  -> $HOME/ArchivematicaDrop/transfer-share
# Puedes forzarla exportando ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR (o TRANSFER_BASE_DIR).
ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR="${ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR:-}"
ATOMTOARCHIVEMATICA_CONTAINER_TRANSFER_DIR="${ATOMTOARCHIVEMATICA_CONTAINER_TRANSFER_DIR:-/home/transfer-share-from-atom}"

# Base común para las rutas del host. DEBE ser idéntica a la usada en install_archivematica.sh.
TRANSFER_BASE_DIR="${TRANSFER_BASE_DIR:-}"

COMPOSE_FILE_VALUE=""

log() {
  printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"
}

warn() {
  printf '\nWARNING: %s\n' "$*" >&2
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

is_wsl() {
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

is_arm() {
  case "$(uname -m)" in
    arm64|aarch64) return 0 ;;
    *) return 1 ;;
  esac
}

# Resuelve la ruta del host del buzón compartido según el entorno. DEBE producir la
# misma ruta que install_archivematica.sh para que el bind mount conecte ambos stacks:
#   - WSL 2 + Docker Desktop: la unidad C: de Windows (compartida con ambos stacks)
#   - Servidor Linux nativo:  un directorio bajo el HOME del usuario
# Respeta cualquier override por variable de entorno.
resolve_host_transfer_dirs() {
  if [ -z "$TRANSFER_BASE_DIR" ]; then
    if is_wsl && [ -d /mnt/c ]; then
      TRANSFER_BASE_DIR="/mnt/c/ArchivematicaDrop"
    else
      TRANSFER_BASE_DIR="$HOME/ArchivematicaDrop"
    fi
  fi
  ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR="${ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR:-$TRANSFER_BASE_DIR/transfer-share}"
  log "Ruta del host (buzón compartido) -> share: ${ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR}"
}

install_apt_packages() {
  local pkgs=("$@")

  have sudo || die "sudo is required to install missing packages: ${pkgs[*]}"
  log "Installing missing apt packages: ${pkgs[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${pkgs[@]}"
}

ensure_command() {
  local cmd="$1"
  local pkg="${2:-$1}"

  if ! have "$cmd"; then
    install_apt_packages "$pkg"
  fi
}

check_host() {
  log "Checking WSL 2, Docker, and required tools..."

  if ! is_wsl; then
    warn "This host does not look like WSL. The script can still run on Linux, but it was designed for WSL 2 + Docker Desktop."
  fi

  ensure_command git git
  ensure_command curl curl
  ensure_command sudo sudo

  have docker || die "docker was not found. Enable Docker Desktop WSL integration for this distro, then try again."
  # docker info >/dev/null 2>&1 || die "Docker is not responding. Start Docker Desktop and enable WSL integration for this distro."
  docker compose version >/dev/null 2>&1 || die "docker compose was not found. Install/enable the Docker Compose plugin."
}

set_vm_max_map_count() {
  log "Setting vm.max_map_count=${VM_MAX_MAP_COUNT} for Elasticsearch..."

  if is_wsl && have wsl.exe; then
    if wsl.exe -l -q 2>/dev/null | tr -d '\r' | grep -qx "docker-desktop"; then
      log "Docker Desktop detected. Applying sysctl inside the docker-desktop WSL distro."
      wsl.exe -d docker-desktop -u root -- sh -lc "
        set -e
        sysctl -w vm.max_map_count=${VM_MAX_MAP_COUNT} >/dev/null
        mkdir -p /etc/sysctl.d
        echo 'vm.max_map_count=${VM_MAX_MAP_COUNT}' > /etc/sysctl.d/99-atom-elasticsearch.conf
        cat /proc/sys/vm/max_map_count
      " >/dev/null || die "Could not set vm.max_map_count inside docker-desktop."
      return 0
    fi
  fi

  sudo sysctl -w "vm.max_map_count=${VM_MAX_MAP_COUNT}" >/dev/null

  if ! sudo grep -qE "^vm\.max_map_count\s*=\s*${VM_MAX_MAP_COUNT}\s*$" /etc/sysctl.conf 2>/dev/null; then
    printf 'vm.max_map_count=%s\n' "$VM_MAX_MAP_COUNT" | sudo tee -a /etc/sysctl.conf >/dev/null \
      || warn "Could not persist vm.max_map_count in /etc/sysctl.conf. The current session was updated."
  fi
}

clone_or_update_atom() {
  mkdir -p "$ATOM_BASE_DIR"

  if [ -d "$ATOM_CLONE_DIR/.git" ]; then
    log "AtoM repository already exists: $ATOM_CLONE_DIR"

    if [ "$ATOM_UPDATE_REPO" != "1" ]; then
      log "Skipping repository update because ATOM_UPDATE_REPO=$ATOM_UPDATE_REPO."
      return 0
    fi

    log "Fetching and fast-forwarding branch $ATOM_BRANCH when possible..."
    git -C "$ATOM_CLONE_DIR" fetch origin "$ATOM_BRANCH"
    git -C "$ATOM_CLONE_DIR" checkout "$ATOM_BRANCH"
    git -C "$ATOM_CLONE_DIR" pull --ff-only origin "$ATOM_BRANCH"
    return 0
  fi

  log "Cloning AtoM branch $ATOM_BRANCH into $ATOM_CLONE_DIR..."
  git clone --branch "$ATOM_BRANCH" "$ATOM_REPO_URL" "$ATOM_CLONE_DIR"
}

configure_compose_file() {
  local dev_file="$ATOM_CLONE_DIR/docker/docker-compose.dev.yml"
  local arm_file="$ATOM_CLONE_DIR/docker/docker-compose.override.arm.yml"

  [ -f "$dev_file" ] || die "Missing AtoM compose file: $dev_file"

  COMPOSE_FILE_VALUE="$dev_file"

  if is_arm; then
    [ -f "$arm_file" ] || die "ARM host detected, but missing override file: $arm_file"
    COMPOSE_FILE_VALUE="${COMPOSE_FILE_VALUE}:${arm_file}"
    log "ARM host detected. Using compose override for linux/amd64-only services."
  fi

  export COMPOSE_FILE="$COMPOSE_FILE_VALUE"
  log "COMPOSE_FILE=$COMPOSE_FILE"
}

# === crea/actualiza docker-compose.override.yml para montar el atom to archivematica ===
configure_atomtoarchivematica_transfer_mount() {
  log "Configurando buzón Atom to Archivematica (bind mount) para Transfer share…"

  if is_wsl; then
    [ -d /mnt/c ] || die "No existe /mnt/c. ¿La unidad C: está montada en WSL? Ajusta ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR si tu disco es otro."
  fi

  mkdir -p "$ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR"

  # Best-effort permisos (en /mnt/d puede ser emulado; sirve para evitar bloqueos de escritura)
  chmod -R a+rwx "$ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR" 2>/dev/null || true

  local mount_line="${ATOMTOARCHIVEMATICA_HOST_TRANSFER_DIR}:${ATOMTOARCHIVEMATICA_CONTAINER_TRANSFER_DIR}"
  local override_file="$ATOM_CLONE_DIR/docker/docker-compose.override.yml"

  log "Configurando el bind mount en el docker-compose.override.yml para los servicios atom y atom_worker…"

  python3 - "$override_file" "$mount_line" <<'PY'
import sys
import re

path = sys.argv[1]
mount = sys.argv[2]
services = ["atom", "atom_worker"]

try:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
except FileNotFoundError:
    lines = []

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

if not lines:
    lines = ["services:"]
elif not has_services_key(lines):
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

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY

  # === Agregar el override al COMPOSE_FILE para que Docker Compose lo lea ===
  # Cuando COMPOSE_FILE está definido explícitamente, Docker Compose NO lee
  # docker-compose.override.yml automáticamente. Debemos incluirlo manualmente.
  if [ -n "${COMPOSE_FILE:-}" ]; then
    case "$COMPOSE_FILE" in
      *"$override_file"*)
        log "El override ya está incluido en COMPOSE_FILE."
        ;;
      *)
        export COMPOSE_FILE="${COMPOSE_FILE}:${override_file}"
        COMPOSE_FILE_VALUE="${COMPOSE_FILE_VALUE}:${override_file}"
        log "Override añadido a COMPOSE_FILE=$COMPOSE_FILE"
        ;;
    esac
  else
    export COMPOSE_FILE="$override_file"
    COMPOSE_FILE_VALUE="$override_file"
    log "COMPOSE_FILE=$COMPOSE_FILE (solo override)"
  fi

  log "Bind mount configurado con éxito para atom y atom_worker."
}

validate_plugin_name() {
  local name="$1"

  [ -n "$name" ] || return 0

  case "$name" in
    *Plugin) ;;
    *) die "ATOM_PLUGIN_NAME must end with Plugin, for example arSigediPlugin." ;;
  esac

  if ! printf '%s' "$name" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*Plugin$'; then
    die "ATOM_PLUGIN_NAME must be a valid PHP class-style name, for example arSigediPlugin."
  fi
}

create_minimal_plugin() {
  local plugin_name="$1"
  local plugin_dir="$ATOM_CLONE_DIR/plugins/$plugin_name"
  local config_dir="$plugin_dir/config"
  local config_file="$config_dir/${plugin_name}Configuration.class.php"

  if [ -d "$plugin_dir" ]; then
    log "Plugin directory already exists: $plugin_dir"
    return 0
  fi

  log "Creating minimal AtoM/Symfony 1.x plugin skeleton: $plugin_name"
  mkdir -p "$config_dir" "$plugin_dir/lib" "$plugin_dir/modules" "$plugin_dir/web"

  cat > "$config_file" <<EOF
<?php

class ${plugin_name}Configuration extends sfPluginConfiguration
{
  public function initialize()
  {
  }
}
EOF

  cat > "$plugin_dir/README.md" <<EOF
# $plugin_name

AtoM plugin skeleton for development.

Host path:

\`\`\`
$plugin_dir
\`\`\`

Container path:

\`\`\`
/atom/src/plugins/$plugin_name
\`\`\`

After changing PHP classes or configuration, clear the Symfony cache:

\`\`\`bash
docker compose exec atom php symfony cc
\`\`\`
EOF
}

rename_theme_skeleton_files() {
  local plugin_name="$1"
  local plugin_dir="$ATOM_CLONE_DIR/plugins/$plugin_name"
  local old_config="$plugin_dir/config/${THEME_SKELETON_NAME}Configuration.class.php"
  local new_config="$plugin_dir/config/${plugin_name}Configuration.class.php"

  if [ -f "$old_config" ] && [ ! -f "$new_config" ]; then
    mv "$old_config" "$new_config"
  fi

  if [ -f "$new_config" ]; then
    sed -i "s/${THEME_SKELETON_NAME}Configuration/${plugin_name}Configuration/g" "$new_config"
    sed -i "s/${THEME_SKELETON_NAME}/${plugin_name}/g" "$new_config"
  fi
}

create_bs5_theme_plugin() {
  local plugin_name="$1"
  local plugin_dir="$ATOM_CLONE_DIR/plugins/$plugin_name"

  if [ -d "$plugin_dir" ]; then
    log "Theme/plugin directory already exists: $plugin_dir"
    return 0
  fi

  log "Cloning AtoM Bootstrap 5 theme skeleton into plugins/$plugin_name..."
  git clone --depth=1 "$THEME_SKELETON_REPO" "$plugin_dir"
  rm -rf "$plugin_dir/.git"
  rm -f "$plugin_dir/README.md"
  rename_theme_skeleton_files "$plugin_name"
}

prepare_optional_plugin() {
  validate_plugin_name "$ATOM_PLUGIN_NAME"

  if [ -z "$ATOM_PLUGIN_NAME" ]; then
    return 0
  fi

  if [ "$ATOM_CREATE_BS5_THEME" = "1" ]; then
    create_bs5_theme_plugin "$ATOM_PLUGIN_NAME"
  else
    create_minimal_plugin "$ATOM_PLUGIN_NAME"
  fi
}

wait_for_atom_exec() {
  local start="$SECONDS"

  log "Waiting for the atom container to accept exec commands..."

  until docker compose exec -T atom php -r 'echo "ok\n";' >/dev/null 2>&1; do
    if (( SECONDS - start >= ATOM_WAIT_TIMEOUT )); then
      docker compose ps
      die "The atom container did not become ready within ${ATOM_WAIT_TIMEOUT}s."
    fi

    sleep "$ATOM_WAIT_INTERVAL"
  done
}

wait_for_mysql() {
  local start="$SECONDS"

  log "Waiting for Percona/MySQL to accept connections from AtoM..."

  until docker compose exec -T atom php -r '
    $dsn = getenv("ATOM_MYSQL_DSN");
    $user = getenv("ATOM_MYSQL_USERNAME");
    $password = getenv("ATOM_MYSQL_PASSWORD");

    try {
      new PDO($dsn, $user, $password, [PDO::ATTR_TIMEOUT => 2]);
      exit(0);
    } catch (Throwable $e) {
      fwrite(STDERR, $e->getMessage() . PHP_EOL);
      exit(1);
    }
  ' >/dev/null 2>&1; do
    if (( SECONDS - start >= ATOM_WAIT_TIMEOUT )); then
      docker compose ps
      docker compose logs --tail=80 percona
      die "Percona/MySQL did not become ready within ${ATOM_WAIT_TIMEOUT}s."
    fi

    sleep "$ATOM_WAIT_INTERVAL"
  done
}

wait_for_elasticsearch() {
  local start="$SECONDS"

  log "Waiting for Elasticsearch to accept HTTP requests from AtoM..."

  until docker compose exec -T atom php -r '
    $host = getenv("ATOM_ELASTICSEARCH_HOST") ?: "elasticsearch";
    $context = stream_context_create(["http" => ["timeout" => 2]]);
    $response = @file_get_contents("http://" . $host . ":9200", false, $context);
    exit($response === false ? 1 : 0);
  ' >/dev/null 2>&1; do
    if (( SECONDS - start >= ATOM_WAIT_TIMEOUT )); then
      docker compose ps
      docker compose logs --tail=80 elasticsearch
      die "Elasticsearch did not become ready within ${ATOM_WAIT_TIMEOUT}s."
    fi

    sleep "$ATOM_WAIT_INTERVAL"
  done
}

wait_for_services() {
  wait_for_atom_exec
  wait_for_mysql
  wait_for_elasticsearch
}

# === Asegura que el directorio de transferencia exista dentro de los contenedores ===
# Docker crea el punto de montaje como root:root al usar bind mounts. Sin embargo,
# los procesos de AtoM corren como www-data (UID 33), por lo que necesitamos crear
# el directorio y ajustar los permisos explícitamente tras levantar los contenedores.
ensure_transfer_dir_in_containers() {
  local dir="$ATOMTOARCHIVEMATICA_CONTAINER_TRANSFER_DIR"
  local services=("atom" "atom_worker")

  log "Asegurando que el directorio de transferencia '$dir' exista en los contenedores con permisos correctos…"

  for svc in "${services[@]}"; do
    log "  → Contenedor '$svc': creando '$dir' y ajustando permisos para www-data…"
    docker compose exec -T --user root "$svc" \
      sh -c "mkdir -p '$dir' && chown www-data:www-data '$dir' && chmod 775 '$dir'" || {
        warn "No se pudo crear/ajustar '$dir' en el contenedor '$svc'. Verificar manualmente."
      }
  done

  log "Directorio de transferencia verificado en todos los contenedores."
}

compose_up_and_initialize() {
  log "Starting AtoM containers. The first build can take several minutes."
  cd "$ATOM_CLONE_DIR"
  docker compose up -d
  wait_for_services
  ensure_transfer_dir_in_containers

  if [ "$ATOM_PURGE_DEMO" = "1" ]; then
    warn "Running tools:purge --demo. This resets/populates the AtoM database for development."
    docker compose exec -T atom php -d memory_limit=-1 symfony tools:purge --demo
  else
    log "Skipping database purge/demo load because ATOM_PURGE_DEMO=$ATOM_PURGE_DEMO."
  fi

  log "Installing and building AtoM frontend assets inside the atom container..."
  docker compose exec -T atom npm install
  docker compose exec -T atom npm run build

  log "Restarting atom_worker after database initialization/build."
  docker compose restart atom_worker
}

print_reference() {
  cat <<EOF

AtoM development environment is ready or being started.

Access:
  URL:      http://localhost:63001
  User:     demo@example.com
  Password: demo

Plugin development paths:
  Host path:      $ATOM_CLONE_DIR/plugins
  Container path: /atom/src/plugins

Do not bind-mount another host directory over /atom/src/plugins. The official
development compose file already mounts the full source tree at /atom/src, and
mounting over /atom/src/plugins would hide AtoM's built-in plugins.

Useful commands:
  cd "$ATOM_CLONE_DIR"
  export COMPOSE_FILE="$COMPOSE_FILE_VALUE"
  docker compose ps
  docker compose logs -f atom atom_worker nginx
  docker compose exec atom bash
  docker compose exec atom php symfony cc
  docker compose exec atom npm install
  docker compose exec atom npm run build
  docker compose down

Optional plugin helpers:
  ATOM_PLUGIN_NAME=arSigediPlugin ./install_atom.sh
  ATOM_PLUGIN_NAME=arSigediThemePlugin ATOM_CREATE_BS5_THEME=1 ./install_atom.sh

EOF
}

main() {
  check_host
  resolve_host_transfer_dirs
  set_vm_max_map_count
  clone_or_update_atom
  configure_compose_file
  configure_atomtoarchivematica_transfer_mount
  prepare_optional_plugin
  compose_up_and_initialize
  print_reference
}

main "$@"
