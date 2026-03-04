#!/usr/bin/env bash
set -euo pipefail

# Reset del laboratorio (seguro por defecto).
# - Limpia expedientes de práctica en TRANSFERS_DIR
# - Reinicia servicios (opcional)
# - Modo --hard: reset total (make flush / docker volume cleanup) con --force

usage() {
  cat <<EOF
Uso:
  TRANSFERS_DIR=/ruta/al/buzon bash reset-lab.sh [--restart] [--hard --force] [--hack-dir /ruta/hack]

Opciones:
  --restart     Reinicia servicios del stack (docker compose restart)
  --hack-dir    Ruta al directorio 'hack' donde corre docker compose (solo si --restart o --hard)
  --hard        Reset total (borrado de datos del entorno de práctica). Requiere --force.
  --force       Confirmación requerida para --hard (evita borrado accidental)

EOF
}

RESTART=0
HARD=0
FORCE=0
HACK_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --restart) RESTART=1; shift ;;
    --hard) HARD=1; shift ;;
    --force) FORCE=1; shift ;;
    --hack-dir) HACK_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1"; usage; exit 1 ;;
  esac
done

if [ -z "${TRANSFERS_DIR:-}" ]; then
  echo "Debes definir TRANSFERS_DIR."
  usage
  exit 1
fi

echo "[1/3] Limpiando expedientes de práctica del buzón…"
bash cleanup-expedientes.sh

if [ "$RESTART" -eq 1 ]; then
  [ -n "$HACK_DIR" ] || { echo "Falta --hack-dir para reiniciar"; exit 1; }
  echo "[2/3] Reiniciando servicios (docker compose restart)…"
  ( cd "$HACK_DIR" && docker compose restart )
else
  echo "[2/3] Reinicio de servicios omitido (usa --restart si lo necesitas)."
fi

if [ "$HARD" -eq 1 ]; then
  if [ "$FORCE" -ne 1 ]; then
    echo "Para evitar borrados accidentales, --hard requiere --force."
    exit 1
  fi
  [ -n "$HACK_DIR" ] || { echo "Falta --hack-dir para --hard"; exit 1; }
  echo "[3/3] Reset total (make flush)…"
  ( cd "$HACK_DIR" && make flush )
else
  echo "[3/3] Reset total omitido."
fi

echo "OK. Reset finalizado."
