# Trabajo futuro: infraestructura para producción

**Contexto**: Universidad de Costa Rica (UCR) — Archivo Universitario Rafael Obregón Loría (AUROL).

Este documento es el **plan de trabajo futuro** para llevar el entorno actual (desarrollo/capacitación) hacia un despliegue de **producción**, con énfasis en la **infraestructura**: máquinas virtuales (VM) o servidores físicos (bare-metal). Complementa a [`consideraciones_produccion.md`](consideraciones_produccion.md), que explica por qué el entorno actual no es apto para producción.

> Este es un documento de planificación. No describe el estado actual del repositorio, sino la dirección recomendada.

---

## 1. Objetivo

Operar Archivematica (preservación) y AtoM (acceso/difusión) de forma confiable, segura y respaldada para custodiar material archivístico real del AUROL, con un camino de crecimiento desde un piloto hasta un servicio robusto.

---

## 2. Topologías propuestas

Tres niveles, de menor a mayor robustez. Se recomienda avanzar por fases (Sección 8).

### Opción A — Servidor único (VM o bare-metal)

Todo en un host: Archivematica, Storage Service y AtoM (cada uno con su Elasticsearch y su base de datos).

```
            ┌──────────────────────────────────────────┐
            │  Host de producción (VM o bare-metal)     │
            │                                           │
 Internet ─▶│  Proxy inverso (HTTPS) ─┬─ Archivematica  │
            │                          ├─ Storage Svc   │
            │                          └─ AtoM           │
            │  Almacén de AIP (volumen dedicado)        │
            └──────────────────────────────────────────┘
```

- **Apto para**: piloto y colecciones pequeñas/medianas.
- **Pros**: simple de operar; el buzón compartido sigue funcionando con un bind mount local.
- **Contras**: sin redundancia; Elasticsearch + ClamAV + FITS + dos bases de datos compiten por recursos.

### Opción B — Dos servidores (Archivematica separado de AtoM)

Archivematica/Storage Service en un host; AtoM en otro. El DIP viaja por la red mediante **SSH/Rsync** (no hay montaje compartido).

```
 ┌─────────────────────────────┐        SSH/Rsync        ┌─────────────────────────┐
 │ Host A (VM/bare-metal)      │  ───────────────────▶   │ Host B (VM/bare-metal)  │
 │  Archivematica + Storage    │   depósito del DIP      │  AtoM + Elasticsearch   │
 │  Almacén de AIP             │                         │  + Percona/MySQL        │
 └─────────────────────────────┘                         └─────────────────────────┘
```

- **Apto para**: producción donde se quiere aislar el acceso público (AtoM) de la preservación (Archivematica).
- **Pros**: superficie de ataque separada; recursos dedicados por sistema; elimina la necesidad de `chmod 0777`.
- **Contras**: requiere configurar SSH/Rsync (ver Sección 4 de la especificación técnica).

### Opción C — Producción robusta (componentes separados)

Separación por tier: aplicación, búsqueda (Elasticsearch), base de datos (Percona/MySQL) y almacenamiento de AIP, cada uno escalable y respaldado de forma independiente. Reservado para crecimiento y alta criticidad (ver Sección 7).

---

## 3. VM vs bare-metal

| Criterio | Máquina virtual (vSphere/Proxmox/nube) | Servidor físico (bare-metal) |
|:---|:---|:---|
| Snapshots / respaldo de imagen | Sí (rápido, integral) | No nativo |
| Recuperación y migración | Sencilla (mover la VM) | Manual |
| Rendimiento de E/S y CPU | Muy bueno; hay overhead | Máximo, sin overhead |
| Almacenamiento grande de AIP | Depende del datastore/SAN | Ideal con discos locales/JBOD grandes |
| Operación | Más simple para TI institucional | Requiere más gestión |

**Recomendación general**: usar **VM** para el tier de aplicación (Archivematica, Storage Service, AtoM) por la facilidad de respaldo, snapshots y migración; considerar **bare-metal o almacenamiento dedicado (NAS/SAN)** para el **almacén de AIP** cuando el volumen de datos crezca, por rendimiento y costo por TB. Un esquema híbrido (app en VM + almacenamiento dedicado) suele ser el mejor equilibrio.

---

## 4. Dimensionamiento orientativo

Punto de partida; ajustar según el volumen real y monitoreo.

| Componente | vCPU | RAM | Disco | Notas |
|:---|:---|:---|:---|:---|
| Archivematica + Storage Service | 4–8 | 16–32 GB | SO 50–100 GB + área de procesamiento | Elasticsearch, ClamAV y FITS son intensivos; requiere `vm.max_map_count=262144` |
| AtoM (app + Elasticsearch + Percona) | 2–4 | 8–16 GB | SO 50 GB | Elasticsearch propio; también requiere `vm.max_map_count` |
| Almacén de AIP | — | — | Según colección + crecimiento | **El dato canónico de preservación**; volumen dedicado, respaldado y con fixity |

Notas:
- El **almacén de AIP** es lo más importante de respaldar y dimensionar: planifique el crecimiento a varios años.
- Disco rápido (SSD/NVMe) para Elasticsearch y bases de datos; el almacén de AIP puede ser de mayor capacidad y menor costo.

---

## 5. Sistema operativo y aprovisionamiento

- **SO**: Ubuntu LTS (22.04 / 24.04) en todos los hosts.
- **Aprovisionamiento reproducible**: gestionar la configuración con **Ansible** (no instalación manual). Artefactual publica roles/playbooks de despliegue de producción para Archivematica; preferirlos sobre el stack `hack/` de desarrollo.
- **Versionado fijo**: fijar versiones estables de Archivematica, Storage Service y AtoM (nada de `qa/1.x` ni imágenes `:latest`).
- **Parámetros de kernel**: `vm.max_map_count=262144` persistente en `/etc/sysctl.d/`.

---

## 6. Seguridad, red y almacenamiento

### 6.1 Seguridad

- **Credenciales y secretos**: eliminar las credenciales por defecto; usar un gestor de secretos o, como mínimo, archivos `.env` con permisos restringidos.
- **HTTPS**: terminación TLS en un proxy inverso (Nginx/Apache) con certificados de la CA institucional o Let's Encrypt.
- **Permisos**: reemplazar `chmod 0777` por propiedad/grupo de mínimo privilegio; en la Opción B desaparece al usar SSH/Rsync.
- **SFTP endurecido**: autenticación por clave, `chroot`, `fail2ban`, puerto restringido por cortafuegos.
- **Cortafuegos**: exponer solo 443 (y el SFTP si aplica); los servicios internos no deben ser accesibles desde fuera.

### 6.2 Red

- Nombres **DNS** para cada servicio y certificados asociados.
- Proxy inverso como único punto de entrada HTTP(S).
- En despliegues distribuidos (Opción B/C), reglas de red entre hosts solo para los puertos necesarios (SSH/Rsync).

### 6.3 Almacenamiento y respaldos

- **Regla 3-2-1**: 3 copias, 2 medios, 1 fuera del sitio.
- Respaldar: bases de datos (Percona/MySQL), configuración y, sobre todo, el **almacén de AIP**.
- **Verificación de integridad (fixity)** periódica de los AIP.
- Los índices de Elasticsearch pueden reconstruirse desde la base de datos; aun así, planifique su recuperación.
- **Probar las restauraciones** regularmente (un respaldo no verificado no es un respaldo).

---

## 7. Alta disponibilidad y escalado (futuro)

Cuando la criticidad lo justifique (Opción C):

- Elasticsearch en clúster dedicado.
- Replicación de base de datos.
- Múltiples `mcp-client` de Archivematica para procesar en paralelo.
- Balanceador de carga frente a AtoM.
- Almacén de AIP en almacenamiento de objetos o NAS/SAN con redundancia.

---

## 8. Plan por fases (roadmap)

| Fase | Alcance | Resultado |
|:---|:---|:---|
| **0 — PoC (actual)** | Entorno de desarrollo/capacitación de este repositorio | Integración validada; equipo capacitado |
| **1 — Piloto** | Opción A en una **VM**; versiones fijas, HTTPS, credenciales propias, respaldos básicos | Servicio interno con datos reales acotados |
| **2 — Producción** | Opción A robusta u Opción B (dos servidores); respaldos automatizados + restauraciones probadas, monitoreo, fixity | Servicio de producción soportado |
| **3 — HA/Escalado** | Opción C; separación de tiers, redundancia | Servicio resiliente y escalable |

---

## 9. Decisiones pendientes

- ¿VM, bare-metal o híbrido para el almacén de AIP?
- ¿Topología A (un host) o B (dos hosts) para la primera producción?
- Política de retención y dimensionamiento del crecimiento del almacén de AIP.
- CA y gestión de certificados institucionales.
- Herramienta de respaldo y destino de la copia externa.
- Responsable de operación (monitoreo, parches, restauraciones).

---

## 10. Referencias

- Despliegue de Archivematica (producción): https://www.archivematica.org/en/docs/
- Documentación de AtoM: https://www.accesstomemory.org/en/docs/
- Especificación técnica de la integración (este repo): [`especificacion_tecnica.md`](especificacion_tecnica.md)
- Consideraciones de producción: [`consideraciones_produccion.md`](consideraciones_produccion.md)
