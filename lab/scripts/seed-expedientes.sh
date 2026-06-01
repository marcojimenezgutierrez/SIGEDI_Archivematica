#!/usr/bin/env bash
set -euo pipefail

# Crea 12 expedientes de práctica para el curso.
# Requiere definir TRANSFERS_DIR (ruta del host que corresponde al Transfer source).
: "${TRANSFERS_DIR:?Debes definir TRANSFERS_DIR, por ejemplo /mnt/c/ArchivematicaDrop/transfers}"

N="${N:-12}"
PREFIX="${PREFIX:-U}"
SUFFIX="${SUFFIX:-_EXP-001}"

mkdir -p "$TRANSFERS_DIR"

# --- Decoder robusto (limpia caracteres no-base64 y decodifica con Python) ---
decode_b64_to_file() {
  local out="$1"
  python3 - <<'PY' "$out"
import base64, re, sys
out = sys.argv[1]
data = sys.stdin.read()
# Deja solo el alfabeto base64 (evita CRLF, espacios, etc.)
data = re.sub(r'[^A-Za-z0-9+/=]', '', data)
raw = base64.b64decode(data)
with open(out, "wb") as f:
    f.write(raw)
PY
}

make_case() {
  local i="$1"
  local id
  id=$(printf "%s%02d%s" "$PREFIX" "$i" "$SUFFIX")
  local dir="$TRANSFERS_DIR/$id"
  mkdir -p "$dir"

  # Estructura simple (para empezar)
  mkdir -p "$dir/documentos" "$dir/imagenes" "$dir/notas"

  {
    echo "Expediente: $id"
    echo "Fecha: $(date -Iseconds)"
    echo "Contenido de práctica para Archivematica."
  } > "$dir/notas/README.txt"

  # PDF mínimo (válido)
  cat <<'B64' | decode_b64_to_file "$dir/documentos/${id}-documento.pdf"
JVBERi0xLjQKJeLjz9MKMSAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgMiAwIFI+PgplbmRvYmoK
MiAwIG9iago8PC9UeXBlL1BhZ2VzL0tpZHNbMyAwIFJdL0NvdW50IDE+PgplbmRvYmoKMyAwIG9iago8
PC9UeXBlL1BhZ2UvUGFyZW50IDIgMCBSL01lZGlhQm94WzAgMCA2MTIgNzkyXS9Db250ZW50cyA0IDAg
Ui9SZXNvdXJjZXM8PC9Gb250PDwvRjEgNSAwIFI+Pj4+PgplbmRvYmoKNCAwIG9iago8PC9MZW5ndGgg
NTE+PnN0cmVhbQpCVCAvRjEgMjQgVGYgNzIgNzIwIFRkIChBcmNoaXZlbWF0aWNhIExhYiBQREYpIFRq
IEVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PC9UeXBlL0ZvbnQvU3VidHlwZS9UeXBlMS9CYXNl
Rm9udC9IZWx2ZXRpY2E+PgplbmRvYmoKeHJlZgowIDYKMDAwMDAwMDAwMCA2NTUzNSBmIAowMDAwMDAw
MDE4IDAwMDAwIG4gCjAwMDAwMDAwNzMgMDAwMDAgbiAKMDAwMDAwMDEyOCAwMDAwMCBuIAowMDAwMDAw
MjQxIDAwMDAwIG4gCjAwMDAwMDAzNjAgMDAwMDAgbiAKdHJhaWxlcgo8PC9TaXplIDYvUm9vdCAxIDAg
Uj4+CnN0YXJ0eHJlZgo0NTUKJSVFT0YK
B64

  # JPG mínimo (válido)
  cat <<'B64' | decode_b64_to_file "$dir/imagenes/${id}-imagen.jpg"
/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEhUQEBAVFhUVFRUVFRUVFRUVFRUVFRUWFhUY
HSggGBolGxUVITEhJSkrLi4uFx8zODMsNygtLisBCgoKDg0OGxAQGy0lICYtLS0tLS0tLS0tLS0t
LS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAEAAQAMBIgACEQEDEQH/xAAX
AAEBAQEAAAAAAAAAAAAAAAAAAQIG/8QAFhABAQEAAAAAAAAAAAAAAAAAAAER/8QAFQEBAQAAAAAAAA
AAAAAAAAAAAgP/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwDgAqAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//Z
B64

  # Archivo de texto
  printf "Acta simple de %s\n\n(Contenido de ejemplo)\n" "$id" > "$dir/documentos/${id}-acta.txt"

  # Subexpediente (estructura)
  mkdir -p "$dir/documentos/anexos"
  echo "Anexo 1 de $id" > "$dir/documentos/anexos/${id}-anexo1.txt"

  echo "Creado: $dir"
}

for i in $(seq 1 "$N"); do
  make_case "$i"
done

echo
echo "OK. Se crearon $N expedientes en: $TRANSFERS_DIR"
echo "En el Dashboard, usa Transfer source → selecciona la carpeta Uxx_EXP-001 → Start transfer."