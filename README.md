# SIGEDI_Archivematica

Reference repository for integrating [Archivematica](https://www.archivematica.org) and [AtoM](https://www.accesstomemory.org) in a Docker/WSL2 environment, developed for the Archivo Universitario Rafael Obregón Loría (AUROL) at the Universidad de Costa Rica (UCR).

The project covers automated deployment of both systems, archival transfer workflows, and hands-on training materials for digital preservation practitioners.

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
- **Metadata guide** — [`lab-advanced/Guia_Metadatos_Transfer_Archivematica_v1.1b.docx`](lab-advanced/Guia_Metadatos_Transfer_Archivematica_v1.1b.docx) covers how to structure EAD, METS, and CSV metadata for transfers.
- **Lab guides** — [`teaching-kit/`](teaching-kit/) contains the three hands-on lab guides and instructor notes.

## License

MIT — see [LICENSE](LICENSE).
