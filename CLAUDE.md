# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

SIGEDI_Archivematica is a **reference / training** repo for integrating **Archivematica** (preservation) and **AtoM** (access/discovery) on Docker, for the Archivo Universitario Rafael Obregón Loría (AUROL), Universidad de Costa Rica (UCR).

> ⚠️ It is a **development / training / testing** environment, **NOT production-ready** (qa/1.x hack stack, AtoM dev compose + demo purge, default creds, HTTP, `chmod 0777`). See `docs/consideraciones_produccion.md` and `docs/trabajo_futuro_infraestructura.md`.

Most documentation **content is in Spanish**; **internal folder/file names are in English**.

## Repository layout

| Path | Contents |
|:---|:---|
| `installation/` | `install_archivematica.sh`, `install_atom.sh` — Docker setup scripts (bash) |
| `docs/` | Technical spec (`technical_spec.md` EN / `especificacion_tecnica.md` ES, + PDFs), runbook docx, production docs, `images/` |
| `lab/` | Basic training: `lab/scripts/` (seed/cleanup/reset) + `lab/expedientes/` (U01–U12 practice cases) |
| `lab-advanced/` | Realistic transfers (EC608, ED2794-2026, TC739) with EAD/METS/CSV/XAdES metadata |
| `teaching-kit/` | Instructor lab guides (Laboratorio 1–3) docx + kit README |

## Architecture (the integration)

Two host **bind mounts** bridge the two isolated Docker stacks:
- `transfer-source` — archivists drop SIPs (via SFTP, port 6222); Archivematica ingests.
- `transfer-share` — Archivematica writes the DIP; AtoM reads it (SWORD via qtSwordPlugin) → published record + thumbnails.

Both installers resolve host paths via `resolve_host_transfer_dirs()` + the shared `TRANSFER_BASE_DIR` contract, and **must land on the same `transfer-share` path** or the bridge breaks.

## Environment awareness (important)

Scripts auto-detect WSL2 vs native Linux:
- **WSL2 + Docker Desktop**: `TRANSFER_BASE_DIR=/mnt/c/ArchivematicaDrop`
- **Native Linux server**: `TRANSFER_BASE_DIR=$HOME/ArchivematicaDrop`
- Override with `TRANSFER_BASE_DIR` (use the **same value** for both installers; on native, run both as the **same OS user**).

Known environment-specific gotchas already handled in the scripts:
- Native Linux needs `make create-volumes` + `mkdir -p ~/.am/...` (dockerd won't auto-create bind-volume sources).
- DIP `rsync exit 23`: fixed via `ensure_share_dir_perms_in_containers()` (AM) + `chmod 0777` in both installers (shared inode, different internal UIDs). Also recommend Dashboard **Rsync command**: `rsync --no-perms --no-owner --no-group --no-times --omit-dir-times -O -r`.

## Open / pending work

- **qtSwordPlugin "Ability not defined: qtSwordPluginWorker"**: `install_atom.sh` does NOT yet enable qtSwordPlugin (the technical spec wrongly claims it does). Need the user's `~/src/atom/config/ProjectConfiguration.class.php` to add a precise, idempotent enable step (then `php symfony cc` + restart `atom_worker`, after any `tools:purge --demo`). Manual fix meanwhile: enable plugin in AtoM UI → cc → restart worker.

## Conventions

- **Default service access**: AM Dashboard 62080, Storage Service 62081 (`test`/`test`); AtoM 63001 (`demo@example.com`/`demo`); SFTP 6222 (`archivista`/`Archivista2026`). All dev-only.
- **Folder names English, doc content Spanish.** Technical spec exists in EN + ES — keep both in sync when editing, and **regenerate PDFs** after editing the markdown.
- **PDF regeneration**: from `docs/`, `md-to-pdf technical_spec.md` and `md-to-pdf especificacion_tecnica.md` (Node tool, install globally with `npm i -g md-to-pdf` if missing). Images are referenced relatively as `images/...`.
- After editing a script, validate with `bash -n <script>`.

## Working environment notes (Windows host)

- Repo lives at `C:\git\SIGEDI_Archivematica`; git/gh run via **PowerShell**, bash tooling via Git Bash / WSL.
- `gh` CLI is installed and authenticated. PATH may need refreshing in PowerShell:
  `$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")`
- **Commit messages / PR bodies**: write them to a temp file and use `git commit -F` / `gh pr create --body-file`. Inline here-strings break on `D:\`, `→`, and other special chars in PowerShell.
- Default branch is `main`. Workflow used: feature branch → commit → push → `gh pr create` → `gh pr merge --merge --delete-branch`.

## Git history context (this work)

Recent merged PRs: repo reorg + docs overhaul (#1), installer native-Linux support (#2), DIP rsync exit-23 container perms (#3), production scope + infrastructure roadmap docs (#4).
