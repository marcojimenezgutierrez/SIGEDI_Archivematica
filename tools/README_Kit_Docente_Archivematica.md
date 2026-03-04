# Kit del docente — Curso práctico Archivematica (3 días)

Este kit incluye scripts opcionales para preparar expedientes de práctica y limpiar la carpeta de transferencias.

## Requisitos
- Ejecutar en el **host** donde está montada la carpeta usada como *Transfer source*.
- Bash (Linux/WSL).
- Permisos de escritura sobre la carpeta de transferencias.

## Variables clave
- `TRANSFERS_DIR`: ruta en el host donde se copian los expedientes para que Archivematica los vea.
  - Ejemplo (WSL sobre Windows): `/mnt/c/ArchivematicaDrop/transfers`
  - Ejemplo (Linux): `/srv/archivematica/transfers`

## Scripts
1) `seed-expedientes.sh`
   - Crea 12 expedientes de práctica: `U01_EXP-001` … `U12_EXP-001`.
   - Incluye archivos de ejemplo (PDF/JPG/TXT) y una estructura simple.

2) `cleanup-expedientes.sh`
   - Borra los expedientes de práctica del buzón (solo los Uxx_EXP-001).

3) `reset-lab.sh`
   - Reinicia servicios (opcional) y limpia expedientes de práctica.
   - Tiene modo `--hard` para *reset total* (requiere `--force`).

## Uso rápido
```bash
export TRANSFERS_DIR="/mnt/c/ArchivematicaDrop/transfers"
bash seed-expedientes.sh
# ... dar clase ...
bash cleanup-expedientes.sh
```

## Accesos del entorno
- Archivematica Dashboard: http://10.248.36.168:62080
- Storage Service: http://10.248.36.168:62081
