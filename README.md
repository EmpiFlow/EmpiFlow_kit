# EmpiFlow kit

**ERPNext 15 with Frappe HR, plus Metabase, on one Windows laptop.** No cloud account, no server, no IT
department: one installer, a browser tab, and your data stays on the machine.

- **ERPNext 15** — accounting, sales, buying, stock, projects, HR master data
- **Frappe HR 15.64.8** — employees, attendance, leave, payroll setup, appraisals
- **Metabase** — dashboards and questions asked straight against the ERPNext database, read-only
- MariaDB and Redis run inside the stack and are **never** exposed to your network

Everything is published on `127.0.0.1` only, so the ERPNext instance is reachable from this laptop and from
nowhere else.

> **This is a testing kit, not a server.** It is sized for one person working at a time. A few people
> browsing at once may work, but concurrent use has not been tested and is not supported. Use it to
> evaluate ERPNext + Frappe HR + Metabase, not to run a business on.

## What you need

| | |
|---|---|
| Windows | Windows 10 (build 19041+) or Windows 11, 64-bit. macOS and Linux are **not** supported by v1. |
| Memory | **8 GB installed** is the minimum and the recommended size. Windows shows an 8 GB machine as about 7.7 GB usable; the installer checks the installed capacity. 6 GB is not supported. |
| Disk | 15 GB free (20 GB recommended) on the drive that will hold the WSL disk — `C:` by default, or the drive you choose in `WSL_ROOT`. |
| Internet | Only for the download. After that the kit runs offline. |
| Time | About 20 minutes, most of it waiting for the first start. |

## Install

1. **Download** this repository: green **Code** button → **Download ZIP**. Windows extracts it as a folder
   named `EmpiFlow_kit-main`; **rename that folder to `EmpiFlow`** (or move everything inside it into an empty
   `C:\EmpiFlow`), so the commands below match — the kit itself works from any folder name, the rename only keeps
   the documented paths true. Do not run it from inside a OneDrive folder.
2. **Double-click `Install.cmd`.** It:
   - checks the machine first (the same checks as `scripts\doctor.cmd`) and **changes nothing** if a
     prerequisite is wrong;
   - asks five questions — press Enter to accept each default;
   - sets up **WSL 2 + the Docker engine** if this machine has neither, asking Windows for administrator
     rights **once** (a UAC prompt). If Windows needs a restart, it says so, and you run `Install.cmd` again;
   - downloads the image (~1.5 GB) and starts the stack. The long work runs in the background while a
     **progress window** shows every line and a heartbeat, so you can see it is alive;
   - creates the **EmpiFlow_kit** folder on your Desktop with the four shortcuts.
3. The first start takes 5–15 minutes. When it finishes, your browser opens on **<http://127.0.0.1:8080>** —
   log in as `Administrator` with the password you typed.

You can run the check on its own at any time: double-click `scripts\doctor.cmd`. It prints one line per check,
tells you what to fix, and leaves the window open.

### If you already have Docker Desktop

The kit never requires Docker Desktop, and the recommended route installs its own engine. If Docker Desktop is
already installed and running, the kit uses it and changes nothing.

> **Docker Desktop licence.** Docker Desktop is not part of this kit. If you use it, Docker's own subscription
> terms apply — at the time of writing it is free for personal use, education, and businesses with fewer than
> 250 employees **and** less than $10M annual revenue; larger organisations need a paid Docker subscription.
> Check <https://www.docker.com/pricing/> before relying on it at work. The kit's own WSL 2 + Docker Engine
> route needs no Docker Desktop account or licence.

The full walkthrough: [`docs/00-client-guide.md`](docs/00-client-guide.md) (start here), then
[`docs/01-install-windows.md`](docs/01-install-windows.md). After the install:
[`docs/02-first-steps.md`](docs/02-first-steps.md). When something fails:
[`docs/03-troubleshooting.md`](docs/03-troubleshooting.md).

## Everyday use

The installer creates an **EmpiFlow_kit** folder on your Desktop and in the Start menu:

| item | what it does |
|---|---|
| **1 Start EmpiFlow** | starts WSL, the Docker engine, ERPNext and Metabase |
| **2 Stop EmpiFlow** | stops the containers and the WSL engine; **your data is kept** |
| **3 ERPNext** | opens <http://127.0.0.1:8080> |
| **4 Metabase** | opens <http://127.0.0.1:3000> |

Undo the folder with `scripts\shortcuts.cmd -Remove`; recreate it with `scripts\shortcuts.cmd`.

Advanced commands (all double-clickable in `scripts\`):

| what | how |
|---|---|
| what is running | `scripts\status.cmd` |
| apply an edited `.env` | `scripts\restart.cmd` |
| see a log | `scripts\logs.cmd create-site` |
| start at logon | `scripts\autostart.cmd` · undo: `scripts\autostart.cmd -Remove` |
| machine check | `scripts\doctor.cmd` |

## First run

1. **Run the ERPNext setup wizard** — it is waiting the first time you log in. Until it completes, ERPNext has
   no currency and no chart of accounts. For Malaysia, choose the chart **`Standard`**, not
   `Standard Template` (which does not exist). Details: `docs/02-first-steps.md`.
2. **Connect Metabase** — first run creates Metabase's *own* admin account, then *Add database → MySQL*:
   host `db`, port `3306`, **Database name `empiflow_local`** (type it in the Database name field; it is your
   site name `empiflow.local` with dots replaced by underscores), user `metabase_ro`, password
   `MB_RO_PASSWORD` from `.env`.

## This repository

| path | what it is |
|---|---|
| `compose.yml` | the eleven services (D-001) |
| `Dockerfile` · `apps.json` | the ERPNext + Frappe HR image, built by CI (D-003, D-011) |
| `docker/create-site.sh` | first-run: site, apps, production flags, the read-only Metabase user |
| `scripts/` | doctor, install, start/stop/status/restart/logs, autostart, shortcuts, engine-install |
| `docs/` | client guide, install, first steps, troubleshooting |
| `.github/workflows/` | builds the image, publishes `:dev` and `:sha-<commit>`; promotion is a separate, explicit step |
| `LICENSE` | MIT for the kit's own files; upstream licences are named there and below |

The image is **not** built on your laptop: `compose.yml` pulls a pinned tag from GitHub's registry
(`ghcr.io/empiflow/empiflow-kit-erpnext`). That tag is only promoted after the acceptance suite has passed against
it on a real laptop.

**Kit version:** `v1.0.1` — scripts and docs only (the installer, stop/start, the docs). The container image is
still **`v1.0.0`**, the tag the acceptance suite passed; nothing in this release changes it.

## Limits worth knowing

- **Windows only.** The installer refuses other systems with an explicit message and changes nothing.
- **Testing scale.** One laptop, one site, one person at a time. This is not a multi-user or production server;
  concurrent users are not tested.
- **8 GB is the floor.** The installer caps WSL at 3 GB with 6 GB of swap and returns page cache to Windows.
  Below 8 GB installed, `doctor` refuses and installs nothing.
- **Your data lives in Docker volumes.** `scripts\stop.cmd` keeps it; `docker compose down -v` deletes it. Back up
  with ERPNext's own backup (`/app/backup`), described in `docs/03-troubleshooting.md`.
- **Default passwords are default.** Change `ADMIN_PASSWORD` and `MB_RO_PASSWORD` in `.env` before the first start
  if the laptop leaves your desk.
- **The WSL disk is 2–4 GB.** It goes on `C:` by default. If `C:` is small, run
  `.\Install.cmd -WslRoot D:\EmpiFlow\wsl` on the first install (or set `WSL_ROOT` in `.env` before it).

## Licence and provenance

The kit's own files are **MIT** licensed — see [`LICENSE`](LICENSE). The image packages unmodified, publicly
available software under its own licences: ERPNext and Frappe HR are GPL-3.0, the Frappe Framework is MIT,
Metabase is AGPL-3.0, MariaDB is GPL-2.0, Redis 7.2 is BSD-3-Clause and nginx is BSD-2-Clause, each as published
by its project. No Frappe repository is forked or modified.
