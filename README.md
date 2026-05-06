# SIGEDI_Archivematica
Proyecto de prueba integración de SIGEDI con Archivematica

# SIGEDI — Archivematica (Docker) + Buzón de Transferencias + SFTP

## Accesos
- Archivematica (Dashboard): http://127.0.0.1:62080/
- Storage Service:          http://127.0.0.1:62081/

> Nota: si accedes desde otra PC, usa el IP del servidor Windows/host en lugar de 127.0.0.1.

## Credenciales (entorno hack/dev)
- Archivematica:
  - usuario: `test`
  - clave:   `test`
- Storage Service:
  - usuario: `test`
  - clave:   `test`

## Buzón SIGEDI (Transfer source)
- En Windows:  D:\ArchivematicaDrop\transfer-source
- En WSL:      /mnt/d/ArchivematicaDrop/transfer-source
- En contenedor (Archivematica): /home/transfer-source-sigedi

**Uso:** Copia aquí carpetas de expedientes (ej: `U01_EXP-001/`) y luego en el Dashboard:
Transfer → Standard transfer → Browse → selecciona la carpeta → Start transfer.

## SFTP (FTP seguro) para subir expedientes al buzón
- Host:  `192.168.107.80`  (o el IP real del host/servidor; si estás local, puedes usar `localhost`)
- Puerto: `6222`
- Usuario: `archivista`
- Clave:   `Archivista2026`
- Carpeta destino (remota): `/home/archivista/transfer-source-sigedi`

**Cliente recomendado:** WinSCP o FileZilla → Protocolo SFTP.

## Comandos útiles (desde /home/laboarchi/src/archivematica/hack)
- Ver logs:           `docker compose logs --follow`
- Parar stack:        `docker compose down`
- Borrar TODO (data): `make flush`

# AtoM 2.10 — Entorno Docker de desarrollo para plugins

El script `install-atom-dev-docker-wsl.sh` crea un entorno AtoM 2.10 orientado a desarrollo de plugins en Ubuntu 24.04.2 LTS sobre Microsoft WSL 2 con Docker Desktop.

La base es el entorno Docker Compose oficial de AtoM:

https://www.accesstomemory.org/es/docs/2.10/dev-manual/env/compose/

## Instalación rápida

```bash
chmod +x install-atom-dev-docker-wsl.sh
./install-atom-dev-docker-wsl.sh
```

Por defecto el script:

- Clona AtoM desde `https://github.com/artefactual/atom.git`.
- Usa la rama `stable/2.10.x`.
- Instala/clona el código en `$HOME/src/atom`.
- Usa `docker/docker-compose.dev.yml`.
- Ajusta `vm.max_map_count=262144` para Elasticsearch.
- Levanta los contenedores con `docker compose up -d`.
- Espera a que `atom`, `percona` y `elasticsearch` estén listos.
- Ejecuta `php -d memory_limit=-1 symfony tools:purge --demo`.
- Ejecuta `npm install` y `npm run build`.
- Reinicia `atom_worker`.

## Acceso a AtoM

- URL: http://localhost:63001
- Usuario demo: `demo@example.com`
- Clave demo: `demo`

## Desarrollo de plugins

El entorno Docker Compose oficial monta el árbol fuente completo de AtoM dentro de los contenedores. Por eso la carpeta recomendada para trabajar plugins desde WSL 2 es:

- En WSL/host: `$HOME/src/atom/plugins`
- En contenedor: `/atom/src/plugins`

No montes otra carpeta directamente sobre `/atom/src/plugins`, porque ocultaría los plugins nativos que vienen en AtoM.

Después de cambiar clases PHP o configuración de un plugin:

```bash
cd "$HOME/src/atom"
export COMPOSE_FILE="$HOME/src/atom/docker/docker-compose.dev.yml"
docker compose exec atom php symfony cc
```

## Crear plugin base opcional

Para crear un plugin Symfony 1.x mínimo:

```bash
ATOM_PLUGIN_NAME=arSigediPlugin ./install-atom-dev-docker-wsl.sh
```

Esto crea:

```text
$HOME/src/atom/plugins/arSigediPlugin/
  config/arSigediPluginConfiguration.class.php
  lib/
  modules/
  web/
  README.md
```

Para crear un tema basado en el esqueleto Bootstrap 5 de AtoM:

```bash
ATOM_PLUGIN_NAME=arSigediThemePlugin ATOM_CREATE_BS5_THEME=1 ./install-atom-dev-docker-wsl.sh
```

## Variables útiles del script

- `ATOM_BRANCH`: rama de AtoM. Valor por defecto: `stable/2.10.x`.
- `ATOM_CLONE_DIR`: directorio local del clon. Valor por defecto: `$HOME/src/atom`.
- `ATOM_PLUGIN_NAME`: nombre de plugin a crear. Debe terminar en `Plugin`.
- `ATOM_CREATE_BS5_THEME`: usa `1` para crear un tema BS5 desde `arThemeB5Plugin`.
- `ATOM_PURGE_DEMO`: usa `0` para no reinicializar la base de datos con datos demo.
- `ATOM_WAIT_TIMEOUT`: segundos máximos de espera para `atom`, `percona` y `elasticsearch`. Valor por defecto: `300`.
- `VM_MAX_MAP_COUNT`: valor de `vm.max_map_count`. Valor por defecto: `262144`.

Ejemplo con timeout mayor:

```bash
ATOM_WAIT_TIMEOUT=600 ./install-atom-dev-docker-wsl.sh
```

Ejemplo sin reinicializar datos:

```bash
ATOM_PURGE_DEMO=0 ./install-atom-dev-docker-wsl.sh
```

## Comandos útiles de AtoM

```bash
cd "$HOME/src/atom"
export COMPOSE_FILE="$HOME/src/atom/docker/docker-compose.dev.yml"

docker compose ps
docker compose logs -f atom atom_worker nginx
docker compose exec atom bash
docker compose exec atom php symfony cc
docker compose exec atom npm install
docker compose exec atom npm run build
docker compose restart atom_worker
docker compose down
```

## Solución de problemas

Si aparece `SQLSTATE[HY000] [2002] Connection refused` durante `tools:purge --demo`, normalmente significa que Percona todavía no estaba listo. La versión actual del script espera explícitamente a MySQL/Percona y Elasticsearch antes de ejecutar el purge.

Si el equipo está lento en el primer arranque, aumenta el timeout:

```bash
ATOM_WAIT_TIMEOUT=600 ./install-atom-dev-docker-wsl.sh
```

El mensaje `PHP Deprecated: Creation of dynamic property sfPhing...` puede aparecer con dependencias antiguas de Symfony/Phing usadas por AtoM; no es el fallo principal si el error real es `Connection refused`.
