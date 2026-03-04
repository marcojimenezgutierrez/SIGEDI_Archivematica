#!/usr/bin/env bash
set -euo pipefail

: "${TRANSFERS_DIR:?Debes definir TRANSFERS_DIR, por ejemplo /mnt/c/ArchivematicaDrop/transfers}"

N="${N:-12}"
PREFIX="${PREFIX:-U}"
SUFFIX="${SUFFIX:-_EXP-001}"

for i in $(seq 1 "$N"); do
  id=$(printf "%s%02d%s" "$PREFIX" "$i" "$SUFFIX")
  target="$TRANSFERS_DIR/$id"
  if [ -d "$target" ]; then
    rm -rf "$target"
    echo "Borrado: $target"
  fi
done

echo "OK. Limpieza completa en: $TRANSFERS_DIR"
