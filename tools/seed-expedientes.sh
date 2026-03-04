#!/usr/bin/env bash
set -euo pipefail

# Crea 12 expedientes de práctica para el curso.
# Requiere definir TRANSFERS_DIR (ruta del host que corresponde al Transfer source).
: "${TRANSFERS_DIR:?Debes definir TRANSFERS_DIR, por ejemplo /mnt/c/ArchivematicaDrop/transfers}"

N="${N:-12}"
PREFIX="${PREFIX:-U}"
SUFFIX="${SUFFIX:-_EXP-001}"

mkdir -p "$TRANSFERS_DIR"

# Tiny sample assets (base64)
TINY_PDF_B64="JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgMiAwIFI+PgplbmRvYmoKMiAwIG9iago8PC9UeXBlL1BhZ2VzL0tpZHNbMyAwIFJdL0NvdW50IDE+PgplbmRvYmoKMyAwIG9iago8PC9UeXBlL1BhZ2UvUGFyZW50IDIgMCBSL01lZGlhQm94WzAgMCA2MTIgNzkyXS9Db250ZW50cyA0IDAgUi9SZXNvdXJjZXM8PC9Gb250PDwvRjEgNSAwIFI+Pj4+PgplbmRvYmoKNCAwIG9iago8PC9MZW5ndGggNTE+PnN0cmVhbQpCVCAvRjEgMjQgVGYgNzIgNzIwIFRkIChBcmNoaXZlbWF0aWNhIExhYiBQREYpIFRqIEVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PC9UeXBlL0ZvbnQvU3VidHlwZS9UeXBlMS9CYXNlRm9udC9IZWx2ZXRpY2E+PgplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAwMDE4IDAwMDAwIG4gCjAwMDAwMDAwNzMgMDAwMDAgbiAKMDAwMDAwMDEyOCAwMDAwMCBuIAowMDAwMDAwMjQxIDAwMDAwIG4gCjAwMDAwMDAzNjAgMDAwMDAgbiAKdHJhaWxlcgo8PC9TaXplIDYvUm9vdCAxIDAgUj4+CnN0YXJ0eHJlZgo0NTUKJSVFT0YK"
TINY_JPG_B64="/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEhUQEBAVFhUVFRUVFRUVFRUVFRUVFRUWFhUYHSggGBolGxUVITEhJSkrLi4uFx8zODMsNygtLisBCgoKDg0OGxAQGy0lICYtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAEAAQAMBIgACEQEDEQH/xAAXAAEBAQEAAAAAAAAAAAAAAAAAAQIG/8QAFhABAQEAAAAAAAAAAAAAAAAAAAER/8QAFQEBAQAAAAAAAAAAAAAAAAAAAgP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwDgAqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//Z"

make_case() {
  local i="$1"
  local id
  id=$(printf "%s%02d%s" "$PREFIX" "$i" "$SUFFIX")
  local dir="$TRANSFERS_DIR/$id"
  mkdir -p "$dir"

  # Estructura simple (para empezar)
  mkdir -p "$dir/documentos" "$dir/imagenes" "$dir/notas"

  echo "Expediente: $id" > "$dir/notas/README.txt"
  echo "Fecha: $(date -Iseconds)" >> "$dir/notas/README.txt"
  echo "Contenido de práctica para Archivematica." >> "$dir/notas/README.txt"

  # PDF y JPG de ejemplo (sin dependencias externas)
  echo "$TINY_PDF_B64" | base64 -d > "$dir/documentos/$id-documento.pdf"
  echo "$TINY_JPG_B64" | base64 -d > "$dir/imagenes/$id-imagen.jpg"

  # Archivo de texto
  printf "Acta simple de %s\n\n(Contenido de ejemplo)\n" "$id" > "$dir/documentos/$id-acta.txt"

  # Un subexpediente para probar estructura
  mkdir -p "$dir/documentos/anexos"
  echo "Anexo 1 de $id" > "$dir/documentos/anexos/$id-anexo1.txt"

  echo "Creado: $dir"
}

for i in $(seq 1 "$N"); do
  make_case "$i"
done

echo
echo "OK. Se crearon $N expedientes en: $TRANSFERS_DIR"
echo "En el Dashboard, usa Transfer source → selecciona la carpeta Uxx_EXP-001 → Start transfer."
