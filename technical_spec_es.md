# Especificación Técnica: Integración de Archivematica y AtoM en WSL2/Docker

**Autor**: Marco Antonio Jiménez Gutiérrez  
**Contacto**: marco.jimenezgutierrez@ucr.ac.cr  
**Contexto**: Este proyecto fue desarrollado para apoyar a la Universidad de Costa Rica (UCR) y al Archivo Universitario Rafael Obregón Loría (AUROL).

Este documento detalla la arquitectura, los scripts y las configuraciones necesarias para desplegar e integrar Archivematica (1.x) y AtoM (2.x) localmente utilizando Docker en un entorno Windows/WSL2. Está diseñado específicamente para garantizar la carga exitosa de un DIP (Paquete de Información de Difusión) desde Archivematica hacia AtoM, incluyendo la generación correcta de miniaturas y derivados de los objetos digitales.

---

## 1. Resumen de la Arquitectura

Debido a que ambos sistemas se ejecutan en contenedores de Docker aislados, no comparten un sistema de archivos de forma inherente. Para permitir que Archivematica transfiera un DIP a AtoM sin depender de transferencias de red externas (como SSH/SCP), utilizamos un **Volumen Compartido del Host (Bind Mount)**.

- **Ruta del Host (Windows/WSL):** `C:\ArchivematicaDrop\transfer-share` (mapeada en WSL como `/mnt/c/ArchivematicaDrop/transfer-share`)
- **Ruta del contenedor de Archivematica:** `/home/transfer-share-from-archivematica`
- **Ruta del contenedor de AtoM:** `/home/transfer-share-from-atom`

Cuando Archivematica coloca un DIP en la ruta de su contenedor, Docker lo refleja instantáneamente en el host, y AtoM lo recoge desde su respectiva ruta interna en su propio contenedor.

---

## 2. Scripts de Instalación

El despliegue se basa en dos scripts bash principales ejecutados dentro del entorno Ubuntu en WSL. Ambos scripts han sido parcheados para manejar automáticamente el montaje del volumen compartido mediante la inyección de archivos `docker-compose.override.yml`.

### `install_archivematica.sh`
- **Propósito**: Clona el código fuente de Archivematica, aplica los límites del sistema necesarios (`vm.max_map_count` para Elasticsearch), inyecta los montajes de volumen y levanta los contenedores mediante `make bootstrap`.
- **Acciones Clave**:
  - Crea automáticamente los directorios `transfer-source` y `transfer-share` en el host.
  - Modifica la configuración de compose de Archivematica para montar la carpeta compartida en `/home/transfer-share-from-archivematica` en los contenedores `storage-service`, `dashboard`, `mcp-server` y `mcp-client`.
  - Configura opcionalmente un contenedor SFTP local para que los archivistas suban archivos.

### `install_atom.sh`
- **Propósito**: Clona el repositorio de AtoM, compila los recursos del frontend, carga una base de datos de demostración y configura el entorno para desarrollo y uso de plugins.
- **Acciones Clave**:
  - Monta la carpeta compartida en `/home/transfer-share-from-atom` en los contenedores `atom` y `atom_worker`.
  - Ejecuta una acción post-inicio (`ensure_transfer_dir_in_containers`) para asignar los permisos `www-data:www-data` al directorio compartido. **Esto es crítico** para permitir que el worker de AtoM pueda leer el DIP y generar las miniaturas.
  - Modifica `ProjectConfiguration.class.php` para habilitar `qtSwordPlugin`—el endpoint de API necesario para recibir depósitos SWORD desde Archivematica.

---

## 3. Configuraciones Requeridas en la Aplicación

A pesar de que los scripts automatizan la infraestructura, es necesario aplicar las siguientes configuraciones en las interfaces web para finalizar la integración.

### A. Panel de Archivematica (Carga de DIP a AtoM)
Navegue a **Administration > AtoM DIP upload** en el panel de Archivematica (`http://localhost:62080`):

![Archivematica AtoM DIP Upload Configuration](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349431146.png)

| Configuración | Valor | Explicación |
| :--- | :--- | :--- |
| **Upload URL** | `http://host.docker.internal:63001/index.php` | Indica al contenedor que enrute el tráfico de regreso a través del host para llegar al puerto expuesto de AtoM. Usar `localhost` aquí fallaría porque apuntaría al interior del contenedor de Archivematica. |
| **Login email** | `demo@example.com` | El correo electrónico del administrador de AtoM. |
| **Login password** | `demo` | La contraseña del administrador de AtoM. |
| **AtoM version** | `2.x` | La versión principal de la instancia destino de AtoM. |
| **Rsync target** | `/home/transfer-share-from-archivematica` | La ruta *dentro del contenedor de Archivematica* donde se colocará el DIP antes de que AtoM asuma el control. |
| **REST API key** | *(Su AtoM API Key)* | Requerida para el mapeo de metadatos y la autorización. |

### B. Ubicaciones de Almacenamiento de Archivematica
Verifique que las ubicaciones del pipeline estén correctamente configuradas en el Servicio de Almacenamiento (Storage Service) (`http://localhost:62081/locations/`).

![Archivematica Storage Locations](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349534024.png)

### C. Configuraciones Globales de AtoM (Depósito SWORD)
Debido a que `qtSwordPlugin` no cuenta con una página de configuración dedicada en la interfaz, el directorio de depósito debe configurarse a nivel de aplicación.

Navegue a **Admin > Settings > Global** en AtoM (`http://localhost:63001`):

![AtoM SWORD Deposit Configuration](C:/Users/mjimenez/.gemini/antigravity/brain/1af2dfda-387f-4463-920d-849a2036e5dd/media__1780349573700.png)

> [!IMPORTANT]  
> Si el campo "SWORD deposit directory" no aparece en la interfaz Global, la configuración está parametrizada mediante el archivo `apps/qubit/config/app.yml` con el valor `sword_deposit_dir: /home/transfer-share-from-atom`. Debe vaciar el caché de Symfony (`php symfony cc`) y reiniciar el `atom_worker` para que este cambio surta efecto.

| Configuración | Valor | Explicación |
| :--- | :--- | :--- |
| **SWORD deposit directory** | `/home/transfer-share-from-atom` | La ruta *dentro del contenedor de AtoM* donde buscará encontrar el DIP enviado por Archivematica. |

---

## 4. Recomendaciones para Pruebas Locales

Para validar la integración de principio a fin, siga este flujo de pruebas:

1. **Colocar los Archivos**: Inserte una carpeta con imágenes o archivos PDF en el directorio de origen en su host de Windows (`C:\ArchivematicaDrop\transfer-source`).
2. **Iniciar una Transferencia**: En Archivematica, vaya a la pestaña **Transfer**, explore el directorio de origen, seleccione sus archivos e inicie una transferencia estándar.
3. **Generar el DIP**: Procese la transferencia a través del pipeline de Archivematica hasta llegar al microservicio "Upload DIP". Seleccione el objetivo de AtoM que configuró.
4. **Monitorear los Logs**: Si la carga falla o se queda atascada, la mejor manera de depurar es observar los registros de los contenedores lado a lado en WSL:
   ```bash
   # En una terminal: Monitorear el MCP Client de Archivematica
   cd ~/src/archivematica/hack
   docker compose logs -f archivematica-mcp-client
   
   # En otra terminal: Monitorear el Worker de AtoM (Generación de miniaturas)
   cd ~/src/atom
   export COMPOSE_FILE="docker/docker-compose.dev.yml:docker/docker-compose.override.yml"
   docker compose logs -f atom_worker
   ```
5. **Verificar las Miniaturas**: Una vez que se completa la carga, navegue a AtoM. El registro descriptivo debería existir, y al abrirlo debería revelarse el visor de objetos digitales junto con las miniaturas derivadas generadas exitosamente.

---

## 5. Consideraciones al Usar SSH/Rsync (Configuración Remota)

La arquitectura descrita anteriormente utiliza un volumen compartido de Docker, el cual es ideal cuando ambos sistemas se ejecutan en el mismo host físico. Sin embargo, si Archivematica y AtoM están alojados en servidores completamente separados, no pueden compartir un volumen local. En una configuración distribuida, se debe configurar el pipeline para transferir el DIP a través de la red utilizando Rsync vía SSH.

Implementar Rsync sobre SSH cambia fundamentalmente la configuración en ambos sistemas:

### Configuraciones en Archivematica (Remitente)
1. **Generación de Claves SSH**: 
   - Se debe generar un par de claves SSH para el usuario que ejecuta el servicio `archivematica-mcp-client` (frecuentemente `archivematica` o `root` dentro del contenedor de Docker).
2. **Rsync Target (Panel de Control)**: 
   - En lugar de una ruta local, el `Rsync target` debe ser formateado como una cadena de conexión remota SSH: `usuario@servidor-atom.com:/ruta/hacia/el/directorio/remoto/`.
3. **Comando Rsync (Panel de Control)**: 
   - Si se usa una clave SSH personalizada o un puerto no estándar, el campo `Rsync command` debe especificar el entorno SSH exacto. Por ejemplo: `ssh -i /home/archivematica/.ssh/id_rsa -p 2222`.

### Configuraciones en AtoM (Receptor)
1. **Servidor SSH y Acceso de Red**: 
   - El servidor que aloja a AtoM debe tener un demonio SSH (`sshd`) en ejecución y ser accesible desde la dirección IP del servidor de Archivematica.
2. **Claves Autorizadas (Authorized Keys)**: 
   - La clave SSH pública generada por el cliente de Archivematica debe añadirse al archivo `~/.ssh/authorized_keys` del usuario dedicado en el servidor de AtoM (por ejemplo, el usuario `www-data` o un usuario específico de `atom`).
3. **Permisos de Directorio**: 
   - El usuario remoto que recibe la conexión SSH debe tener permisos de escritura en el directorio de depósito SWORD definido. Si el usuario SSH es diferente al usuario de PHP-FPM (`www-data`), debe asegurar que el directorio sea accesible para ambos (por ejemplo, mediante un grupo compartido con `chmod g+s` y permisos `775`), de manera que el worker de AtoM pueda procesar los archivos entrantes.
