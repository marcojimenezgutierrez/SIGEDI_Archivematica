# Technical Specification: Archivematica & AtoM Integration on WSL2/Docker

**Author**: Marco Antonio Jiménez Gutiérrez  
**Contact**: marco.jimenezgutierrez@ucr.ac.cr  
**Context**: This project was developed to support the Universidad de Costa Rica (UCR) and the Archivo Universitario Rafael Obregón Loría (AUROL).

This document details the architecture, scripts, and configurations required to deploy and integrate Archivematica (1.x) and AtoM (2.x) locally using Docker on a Windows/WSL2 host. It is specifically tailored to ensure successful DIP (Dissemination Information Package) uploads from Archivematica to AtoM, including the correct generation of thumbnails and digital object derivatives.

---

## 1. Architecture Overview

Because both systems run in isolated Docker containers, they do not inherently share a file system. To allow Archivematica to hand off a DIP to AtoM without relying on external network transfers (like SSH/SCP), we utilize a **Shared Host Volume (Bind Mount)**.

- **Host Path (Windows/WSL):** `C:\ArchivematicaDrop\transfer-share` (mapped in WSL as `/mnt/c/ArchivematicaDrop/transfer-share`)
- **Archivematica Container Path:** `/home/transfer-share-from-archivematica`
- **AtoM Container Path:** `/home/transfer-share-from-atom`

When Archivematica places a DIP in its container path, Docker instantly mirrors it to the host, and AtoM picks it up from its own respective container path.

---

## 2. Installation Scripts

The deployment relies on two primary bash scripts executed within the WSL Ubuntu environment. Both scripts have been patched to automatically handle the shared volume mounts by injecting `docker-compose.override.yml` files.

### `install_archivematica.sh`
- **Purpose**: Clones the Archivematica source code, applies necessary system limits (`vm.max_map_count` for Elasticsearch), injects the volume bind mounts, and starts the container stack via `make bootstrap`.
- **Key Actions**:
  - Automatically creates the `transfer-source` and `transfer-share` directories on the host.
  - Modifies the Archivematica compose configuration to mount the host share to `/home/transfer-share-from-archivematica` across the `storage-service`, `dashboard`, `mcp-server`, and `mcp-client` containers.
  - Optionally configures a local SFTP container for archivists to drop files.

### `install_atom.sh`
- **Purpose**: Clones the AtoM repository, builds frontend assets, loads a demo database, and configures the environment for development and plugin usage.
- **Key Actions**:
  - Mounts the host share to `/home/transfer-share-from-atom` in the `atom` and `atom_worker` containers.
  - Executes a post-startup hook (`ensure_transfer_dir_in_containers`) to assign `www-data:www-data` ownership to the shared directory. **This is critical** for allowing the AtoM worker to read the DIP payload and generate thumbnails.
  - Modifies `ProjectConfiguration.class.php` to enable `qtSwordPlugin`—the necessary API endpoint for receiving SWORD deposits from Archivematica.

---

## 3. Required Application Configurations

Even with the scripts automating the infrastructure, you must apply the following settings in the web interfaces to finalize the pipeline.

### A. Archivematica Dashboard (AtoM DIP Upload)
Navigate to **Administration > AtoM DIP upload** in the Archivematica dashboard (`http://localhost:62080`):

![Archivematica AtoM DIP Upload Configuration](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349431146.png)

| Setting | Value | Explanation |
| :--- | :--- | :--- |
| **Upload URL** | `http://host.docker.internal:63001/index.php` | Instructs the container to route traffic back through the host machine to reach AtoM's exposed port. Using `localhost` here would fail because it points inside the Archivematica container. |
| **Login email** | `demo@example.com` | The AtoM administrator email. |
| **Login password** | `demo` | The AtoM administrator password. |
| **AtoM version** | `2.x` | The major version of the destination AtoM instance. |
| **Rsync target** | `/home/transfer-share-from-archivematica` | The path *inside the Archivematica container* where the DIP will be placed before AtoM takes over. |
| **REST API key** | *(Your AtoM API Key)* | Required for metadata mapping and authorization. |

### B. Archivematica Storage Locations
Verify that your pipeline locations are correctly configured in the Storage Service (`http://localhost:62081/locations/`).

![Archivematica Storage Locations](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349534024.png)

### C. AtoM Global Settings (SWORD Deposit)
Because `qtSwordPlugin` does not have a dedicated settings page, the deposit directory must be configured at the application level.

Navigate to **Admin > Settings > Global** in AtoM (`http://localhost:63001`):

![AtoM SWORD Deposit Configuration](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349573700.png)

> [!IMPORTANT]  
> If the "SWORD deposit directory" field is missing from the Global UI, the setting is hardcoded via the `apps/qubit/config/app.yml` configuration file with the parameter `sword_deposit_dir: /home/transfer-share-from-atom`. You must clear the Symfony cache (`php symfony cc`) and restart the `atom_worker` for this change to take effect.

| Setting | Value | Explanation |
| :--- | :--- | :--- |
| **SWORD deposit directory** | `/home/transfer-share-from-atom` | The path *inside the AtoM container* where it will look to find the DIP payload handed off by Archivematica. |

---

## 4. Recommendations for Local Testing

To validate the integration from start to finish, follow this testing workflow:

1. **Drop a Payload**: Place a folder containing images or PDFs into the source directory on your Windows host (`C:\ArchivematicaDrop\transfer-source`).
2. **Start a Transfer**: In Archivematica, go to the **Transfer** tab, browse the source directory, select your payload, and start a standard transfer.
3. **Generate the DIP**: Process the transfer through the Archivematica pipeline until you reach the "Upload DIP" micro-service. Select the AtoM target you configured.
4. **Monitor the Logs**: If the upload fails or hangs, the best way to debug is by watching the container logs side-by-side in WSL:
   ```bash
   # In one terminal: Watch Archivematica MCP Client
   cd ~/src/archivematica/hack
   docker compose logs -f archivematica-mcp-client
   
   # In another terminal: Watch AtoM Worker (Thumbnail generation)
   cd ~/src/atom
   export COMPOSE_FILE="docker/docker-compose.dev.yml:docker/docker-compose.override.yml"
   docker compose logs -f atom_worker
   ```
5. **Verify Thumbnails**: Once the upload completes, navigate to AtoM. The descriptive record should exist, and opening it should reveal the digital object viewer alongside successfully generated thumbnail derivatives.

---

## 5. Considerations for Using SSH/Rsync (Remote Setup)

The architecture described above utilizes a shared Docker volume, which is ideal when both systems run on the same physical host. However, if Archivematica and AtoM are hosted on entirely separate servers, they cannot share a local volume. In a distributed setup, you must configure the pipeline to transfer the DIP over the network using Rsync via SSH. 

Implementing Rsync over SSH fundamentally changes the configuration for both systems:

### Archivematica (Sender) Configurations
1. **SSH Key Pair Generation**: 
   - An SSH key pair must be generated for the user running the `archivematica-mcp-client` service (often `archivematica` or `root` inside the Docker container).
2. **Dashboard Rsync Target**: 
   - Instead of a local path, the `Rsync target` must be formatted as a remote SSH connection string: `user@atom-server.com:/path/to/remote/deposit/directory/`.
3. **Dashboard Rsync Command**: 
   - If a custom SSH key or non-standard port is used, the `Rsync command` field must specify the exact SSH shell. For example: `ssh -i /home/archivematica/.ssh/id_rsa -p 2222`.

### AtoM (Receiver) Configurations
1. **SSH Server & Network Access**: 
   - The server hosting AtoM must have an SSH daemon (`sshd`) running and accessible from the Archivematica server's IP address.
2. **Authorized Keys**: 
   - The public SSH key generated by Archivematica's client must be added to the `~/.ssh/authorized_keys` file of the dedicated user on the AtoM server (e.g., the `www-data` user, or a specific `atom` user).
3. **Directory Permissions**: 
   - The remote user receiving the SSH connection must have write permissions to the defined SWORD deposit directory. If the SSH user is different from the PHP-FPM user (`www-data`), you must ensure the directory is accessible to both (e.g., through a shared group with `chmod g+s` and `775` permissions), so the AtoM worker can still process the incoming files.
