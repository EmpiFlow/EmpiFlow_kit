# EmpiFlow kit

**ERPNext 15 with Frappe HR, plus Metabase, on one Windows laptop.** No cloud account, no server, no IT
department: one installer, a browser tab, and your data stays on the machine.

- **ERPNext 15** — accounting, sales, buying, stock, projects, HR master data
- **Frappe HR 15.64.8** — employees, attendance, leave, payroll setup, appraisals
- **Metabase** — dashboards and questions asked straight against the ERPNext database, read-only
- MariaDB and Redis run inside the stack and are **never** exposed to your network

Everything is published on `127.0.0.1` only, so the ERPNext instance is reachable from this laptop and from
nowhere else.

## What you need

| | |
|---|---|
| Windows | Windows 10 (build 19041+) or Windows 11, 64-bit. macOS and Linux are **not** supported by v1. |
| Memory | 8 GB recommended. 6 GB works if you close other programs during the first start. |
| Disk | 15 GB free (20 GB recommended). |
| Internet | Only for the download. After that the kit runs offline. |

## Install

1. **Download** this repository: green **Code** button → **Download ZIP**, then extract it to a folder such as
   `C:\EmpiFlow`. Do not run it from inside a OneDrive folder.
2. **Check the machine** — double-click `scripts\doctor.cmd`. It opens a window, prints one line per check and
   tells you what to fix if something is missing. Nothing is changed by this step.
3. **Install** — double-click `Install.cmd`. It asks five questions (press Enter to accept each default), then
   downloads the image and starts the stack. The first start takes 5–15 minutes.
4. Open **<http://127.0.0.1:8080>** — log in as `Administrator`, password = the one you typed.

If step 2 says *no Docker engine*, either install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
or let the kit install a Docker engine itself: open **Windows PowerShell as administrator**, go to this folder and
run:

```powershell
Install.cmd -InstallEngine
```

It enables WSL 2, may ask you to restart Windows once, and finishes on the second run.

The full walkthrough, screenshots-in-words included: [`docs/01-install-windows.md`](docs/01-install-windows.md).
After the install: [`docs/02-first-steps.md`](docs/02-first-steps.md). When something fails:
[`docs/03-troubleshooting.md`](docs/03-troubleshooting.md).

## Everyday use

| what | how |
|---|---|
| start | `scripts\start.cmd` |
| stop (data kept) | `scripts\stop.cmd` |
| what is running | `scripts\status.cmd` |
| apply an edited `.env` | `scripts\restart.cmd` |
| see a log | `scripts\logs.cmd create-site` |
| start at logon | `scripts\autostart.cmd` · undo: `scripts\autostart.cmd -Remove` |
| desktop shortcuts | `scripts\shortcuts.cmd` · undo: `scripts\shortcuts.cmd -Remove` |

## This repository

| path | what it is |
|---|---|
| `compose.yml` | the eleven services (D-001) |
| `Dockerfile` · `apps.json` | the ERPNext + Frappe HR image, built by CI (D-003, D-011) |
| `docker/create-site.sh` | first-run: site, apps, production flags, the read-only Metabase user |
| `scripts/` | doctor, install, start/stop/status/restart/logs, autostart, shortcuts |
| `docs/` | install, first steps, troubleshooting |
| `.github/workflows/` | builds the image, publishes `:dev` and `:sha-<commit>`; promotion is a separate, explicit step |

The image is **not** built on your laptop: `compose.yml` pulls a pinned tag from GitHub's registry
(`ghcr.io/empiflow/empiflow-kit-erpnext`). That tag is only promoted after the acceptance suite has passed against
it on a real laptop.

## Limits worth knowing

- **Windows only.** The installer refuses other systems with an explicit message and changes nothing.
- **One site, one laptop.** This is a working kit, not a multi-user server. A LAN demo is a one-line change in
  `.env`, documented in `docs/01-install-windows.md`.
- **Your data lives in Docker volumes.** `scripts\stop.cmd` keeps it; `docker compose down -v` deletes it. Back up
  with ERPNext's own backup (`/app/backup`), described in `docs/03-troubleshooting.md`.
- **Default passwords are default.** Change `ADMIN_PASSWORD` and `MB_RO_PASSWORD` in `.env` before the first start
  if the laptop leaves your desk.

## Licence and provenance

The kit packages unmodified, publicly available software: ERPNext, Frappe Framework, Frappe HR (all
GPL-3.0/AGPL-3.0 as published by Frappe Technologies), Metabase, MariaDB, Redis and nginx. This repository adds
the compose file, the installer and the documentation. No Frappe repository is forked or modified.
