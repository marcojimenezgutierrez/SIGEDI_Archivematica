# Consideraciones para producción

**Contexto**: Universidad de Costa Rica (UCR) — Archivo Universitario Rafael Obregón Loría (AUROL).

> ⚠️ **El entorno que despliegan los scripts de este repositorio es de desarrollo, capacitación y pruebas. NO es apto para producción.**

Este documento explica **por qué** el entorno actual no debe usarse para custodiar material archivístico real y **qué exige** un despliegue de producción. Para la propuesta de infraestructura y el plan por fases, vea [`trabajo_futuro_infraestructura.md`](trabajo_futuro_infraestructura.md).

---

## 1. Por qué el entorno actual no es de producción

El entorno se construye deliberadamente sobre las herramientas **de desarrollo** de Archivematica y AtoM. Eso es correcto para aprender, desarrollar plugins y validar la integración, pero inadecuado para datos reales.

### 1.1 Se basa en herramientas de desarrollo (por diseño)

| Elemento | Situación actual | Riesgo en producción |
|:---|:---|:---|
| Archivematica | Rama **`qa/1.x`** (QA, no estable) desplegada con el stack **`hack/`** (`make bootstrap`, `make flush`) | El `hack` es el entorno de desarrollo de Artefactual; no es la vía de despliegue soportada para producción |
| AtoM | **`docker-compose.dev.yml`** + `tools:purge --demo` | El purge borra la base de datos y carga datos de demostración; orientado a desarrollo |
| Versionado | Ramas móviles (`qa/1.x`) e imágenes `:latest` (SFTP) | Builds no reproducibles; el comportamiento puede cambiar entre instalaciones |

### 1.2 Seguridad de nivel desarrollo

| Elemento | Situación actual | Requisito de producción |
|:---|:---|:---|
| Credenciales | Fijas: `test`/`test`, `demo`/`demo`, SFTP `archivista`/`Archivista2026` | Credenciales propias, gestión de secretos, rotación |
| Cifrado en tránsito | HTTP plano en puertos `localhost` (62080/62081/63001) | HTTPS/TLS mediante proxy inverso |
| Permisos del buzón compartido | **`chmod 0777`** en `transfer-share` | Propiedad y grupo con privilegio mínimo, o transferencia por SSH/Rsync sin montaje compartido |
| Exposición de red | Servicios accesibles directamente | Cortafuegos; solo el proxy inverso expuesto |

### 1.3 Brechas operativas

| Área | Situación actual | Requisito de producción |
|:---|:---|:---|
| Respaldos | Ninguno | Respaldo de base de datos, índices y **almacén de AIP**, con copia externa y verificación de integridad (fixity) |
| Almacenamiento | Único host, disco compartido con el SO | Almacén de AIP dedicado y respaldado, idealmente separado del host de aplicación |
| Disponibilidad | Único host, todo en un stack Docker | Redundancia/HA según criticidad |
| Observabilidad | Sin monitoreo ni rotación de logs | Monitoreo, alertas (especialmente de espacio en disco), gestión de logs |
| Dimensionamiento | Sin ajustar | CPU/RAM/disco planificados por componente |

---

## 2. Para qué SÍ sirve el entorno actual

- **Capacitación** con el material de `lab/` y `teaching-kit/`.
- **Validar el flujo de integración** Archivematica → AtoM (transferencia → SIP → AIP → DIP → publicación).
- **Desarrollo de plugins** de AtoM.
- **Pruebas de concepto** antes de invertir en infraestructura de producción.

---

## 3. Qué exige un despliegue de producción (resumen)

| Área | Requisito |
|:---|:---|
| **Versiones** | Fijar una versión estable de Archivematica + Storage Service compatible; desplegar con la vía de producción de Artefactual (Ansible), no con `hack/` |
| **AtoM** | Instalación/compose de producción, sin `--demo`, base de datos real |
| **Almacenamiento** | Almacén de AIP dedicado y respaldado; copia externa; verificación de integridad periódica |
| **Seguridad** | Credenciales y secretos gestionados, HTTPS, SFTP endurecido, permisos de mínimo privilegio, cortafuegos |
| **Operación** | Respaldos automatizados y restauraciones probadas, monitoreo, gestión de logs, planificación de capacidad |
| **Red** | Nombres DNS, certificados, proxy inverso; si Archivematica y AtoM están en servidores distintos, usar SSH/Rsync (Sección 4 de la especificación técnica) en lugar del montaje compartido |

El detalle de infraestructura (VM o servidores físicos), dimensionamiento y el plan por fases está en [`trabajo_futuro_infraestructura.md`](trabajo_futuro_infraestructura.md).

---

## 4. Referencias

- Documentación oficial de Archivematica: https://www.archivematica.org/en/docs/
- Documentación oficial de AtoM: https://www.accesstomemory.org/en/docs/
- Especificación técnica de la integración (este repo): [`technical_spec.md`](technical_spec.md) / [`especificacion_tecnica.md`](especificacion_tecnica.md)
