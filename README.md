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

