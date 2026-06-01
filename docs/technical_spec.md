# Technical Specification: Archivematica & AtoM Integration on WSL2/Docker

**Author**: Marco Antonio Jiménez Gutiérrez  
**Contact**: marco.jimenezgutierrez@ucr.ac.cr  
**Context**: Developed for the Universidad de Costa Rica (UCR) — Archivo Universitario Rafael Obregón Loría (AUROL).

This document describes the architecture and configuration required to integrate Archivematica (1.x) and AtoM (2.x) running on the same Docker/WSL2 host, with specific focus on enabling DIP uploads from Archivematica to AtoM including thumbnail generation.

For installation steps, see the [Runbook](Runbook_Instalacion_Archivematica_y_AtoM_en_Docker_v1.0.docx).

---

## Quick Reference

### Service URLs and credentials

| Service | URL | Username | Password |
|:---|:---|:---|:---|
| Archivematica Dashboard | http://localhost:62080 | `test` | `test` |
| Archivematica Storage Service | http://localhost:62081 | `test` | `test` |
| AtoM | http://localhost:63001 | `demo@example.com` | `demo` |

> These are the default dev/hack environment credentials. Change them before any production use.

### SFTP access (archivists uploading transfers)

Archivists deposit transfer packages into the system over SFTP using any standard client (WinSCP, FileZilla, or `sftp` CLI).

| Field | Value |
|:---|:---|
| Protocol | SFTP |
| Host | IP of the Windows host (or `localhost` if connecting from the same machine) |
| Port | `6222` |
| Username | `archivista` |
| Password | `Archivista2026` |
| Remote folder | `/home/archivista/transfer-source-sigedi` |

Files placed in that remote folder appear immediately in the Archivematica transfer source.

---

## 1. Architecture Overview

Both systems run in isolated Docker containers and do not share a filesystem by default. The integration uses two **host bind mounts** that bridge the gap without requiring network transfers between containers.

```
[Archivist]
    │
    │  SFTP (port 6222)
    ▼
[transfer-source]  ←── Windows: C:\ArchivematicaDrop\transfer-source
    │                   WSL:     /mnt/c/ArchivematicaDrop/transfer-source
    │                   Container: /home/transfer-source-sigedi
    │  Standard Transfer
    ▼
[Archivematica]  ──→  SIP / AIP (preserved)
    │
    │  DIP Upload (SWORD via qtSwordPlugin)
    ▼
[transfer-share]   ←── Windows: C:\ArchivematicaDrop\transfer-share
    │                   WSL:     /mnt/c/ArchivematicaDrop/transfer-share
    │                   Archivematica container: /home/transfer-share-from-archivematica
    │                   AtoM container:          /home/transfer-share-from-atom
    │
    ▼
[AtoM]  ──→  Descriptive record + digital object + thumbnails (published)
```

### The two shared directories

| Directory | Host path | Purpose |
|:---|:---|:---|
| `transfer-source` | `C:\ArchivematicaDrop\transfer-source` | Archivists drop transfer packages here; Archivematica reads them as a transfer source |
| `transfer-share` | `C:\ArchivematicaDrop\transfer-share` | Archivematica writes DIPs here; AtoM reads them from its own container mount |

The installation scripts inject both paths into `docker-compose.override.yml` automatically.

---

## 2. Integration Configuration

Even with the infrastructure automated by the install scripts, the following settings must be applied manually in the web interfaces to complete the integration.

### A. Archivematica Dashboard — AtoM DIP Upload

Navigate to **Administration → AtoM DIP upload** in the Archivematica Dashboard (http://localhost:62080).

![Archivematica AtoM DIP Upload Configuration](images/media__1780349431146.png)

| Setting | Value | Notes |
|:---|:---|:---|
| Upload URL | `http://host.docker.internal:63001/index.php` | Routes from the Archivematica container back through the host to AtoM's port. Using `localhost` here would resolve inside the Archivematica container and fail. |
| Login email | `demo@example.com` | AtoM administrator account |
| Login password | `demo` | AtoM administrator password |
| AtoM version | `2.x` | |
| Rsync target | `/home/transfer-share-from-archivematica` | Path *inside the Archivematica container* where the DIP is placed |
| REST API key | *(see below)* | Required for authorization and metadata mapping |

**Getting the AtoM REST API key:** In AtoM, go to **Admin → Users**, edit the administrator user, and copy the value from the **REST API key** field. If it is empty, click **Generate** to create one.

### B. Archivematica Storage Service — Verify pipeline locations

Navigate to **Locations** in the Storage Service (http://localhost:62081/locations/) and confirm that the pipeline's transfer source and AIP storage locations are active and pointing to the expected paths.

![Archivematica Storage Locations](images/media__1780349534024.png)

### C. AtoM Global Settings — SWORD deposit directory

Navigate to **Admin → Settings → Global** in AtoM (http://localhost:63001).

![AtoM SWORD Deposit Configuration](images/media__1780349573700.png)

| Setting | Value | Notes |
|:---|:---|:---|
| SWORD deposit directory | `/home/transfer-share-from-atom` | Path *inside the AtoM container* where it looks for incoming DIPs |

> **If the field is missing from the UI:** The setting can be hardcoded in `apps/qubit/config/app.yml` as `sword_deposit_dir: /home/transfer-share-from-atom`. After editing, clear the Symfony cache (`php symfony cc`) and restart `atom_worker`.

---

## 3. End-to-End Workflow

Use this sequence to validate the integration from start to finish.

1. **Deposit a transfer** — Copy a folder containing PDFs or images to the transfer source:
   - Via SFTP: connect with the credentials above and upload to `/home/archivista/transfer-source-sigedi`
   - Directly on the host: copy to `C:\ArchivematicaDrop\transfer-source`

2. **Start a transfer in Archivematica** — Dashboard → **Transfer** tab → Standard transfer → Browse → select the folder → Start transfer.

3. **Process through the pipeline** — Approve each micro-service step until the **Upload DIP** micro-service appears. Select the configured AtoM upload target.

4. **Monitor logs** — If the upload fails or stalls, watch the relevant container logs side by side:

   ```bash
   # Archivematica MCP Client (sends the DIP)
   cd ~/src/archivematica/hack
   docker compose logs -f archivematica-mcp-client

   # AtoM Worker (receives DIP, generates thumbnails)
   cd ~/src/atom
   export COMPOSE_FILE="docker/docker-compose.dev.yml:docker/docker-compose.override.yml"
   docker compose logs -f atom_worker
   ```

5. **Verify in AtoM** — Navigate to http://localhost:63001. The descriptive record should be present and the digital object viewer should show the uploaded files with generated thumbnails.

---

## 4. Remote Setup: SSH/Rsync

The shared bind-mount architecture works only when both systems run on the same physical host. For distributed deployments (Archivematica and AtoM on separate servers), the DIP must travel over the network via Rsync/SSH.

### Archivematica side (sender)

1. Generate an SSH key pair for the `archivematica-mcp-client` container user.
2. Set **Rsync target** to a remote SSH path: `user@atom-server.example.com:/path/to/deposit/`
3. If using a non-standard port or key: set **Rsync command** to `ssh -i /home/archivematica/.ssh/id_rsa -p 2222`

### AtoM side (receiver)

1. Ensure `sshd` is running and reachable from the Archivematica server's IP.
2. Add the Archivematica public key to `~/.ssh/authorized_keys` of the receiving user.
3. Ensure the receiving user has write permission to the SWORD deposit directory. If the SSH user differs from the PHP-FPM user (`www-data`), use a shared group with `chmod g+s` and `775` permissions so the AtoM worker can still read the files.
