# SIGEDI_Archivematica

Reference repository for integrating [Archivematica](https://www.archivematica.org) and [AtoM](https://www.accesstomemory.org) in a Docker/WSL2 environment, developed for the Archivo Universitario Rafael Obregón Loría (AUROL) at the Universidad de Costa Rica (UCR).

The project covers automated deployment of both systems, archival transfer workflows, and hands-on training materials for digital preservation practitioners.

## Scope and limitations

> ⚠️ **This is a development, training, and testing environment. It is NOT production-ready.**

The installers intentionally build on the upstream **developer** tooling: Archivematica's `hack/` stack on the `qa/1.x` branch, AtoM's `docker-compose.dev.yml`, a demo-data purge, default credentials (`test`/`test`, `demo`/`demo`), plain-HTTP localhost ports, and a `chmod 0777` shared directory. These choices are appropriate for learning, plugin development, and validating the Archivematica ↔ AtoM integration — and disqualifying for handling real archival material.

For the full reasoning and what a production deployment requires, see:

- [`docs/consideraciones_produccion.md`](docs/consideraciones_produccion.md) — production considerations (ES)
- [`docs/trabajo_futuro_infraestructura.md`](docs/trabajo_futuro_infraestructura.md) — infrastructure roadmap toward production, on VMs or bare-metal servers (ES)

## Repository structure

| Folder | Contents |
|:---|:---|
| `installation/` | Automated Docker setup scripts for Archivematica and AtoM |
| `docs/` | Technical specification (EN/ES) and installation runbook |
| `lab/` | Basic practice transfers (U01–U12) and transfer-source management scripts |
| `lab-advanced/` | Realistic transfer examples with EAD, METS, and XAdES metadata |
| `teaching-kit/` | Instructor lab guides (Laboratorio 1–3) |

## Documentation

- **Installation** — see [`docs/Runbook_Instalacion_Archivematica_y_AtoM_en_Docker_v1.0.docx`](docs/Runbook_Instalacion_Archivematica_y_AtoM_en_Docker_v1.0.docx) for step-by-step setup instructions.
- **Architecture** — [`docs/technical_spec.md`](docs/technical_spec.md) (English) / [`docs/especificacion_tecnica.md`](docs/especificacion_tecnica.md) (Spanish) describe the integration design.
- **Production considerations** — [`docs/consideraciones_produccion.md`](docs/consideraciones_produccion.md) (ES) explains why this environment is not production-ready and what production demands.
- **Infrastructure roadmap** — [`docs/trabajo_futuro_infraestructura.md`](docs/trabajo_futuro_infraestructura.md) (ES) is the future-work plan to reach a production deployment on VMs or bare-metal servers.
- **Metadata guide** — [`lab-advanced/Guia_Metadatos_Transfer_Archivematica_v1.1b.docx`](lab-advanced/Guia_Metadatos_Transfer_Archivematica_v1.1b.docx) covers how to structure EAD, METS, and CSV metadata for transfers.
- **Lab guides** — [`teaching-kit/`](teaching-kit/) contains the three hands-on lab guides and instructor notes.

## License

MIT — see [LICENSE](LICENSE).
