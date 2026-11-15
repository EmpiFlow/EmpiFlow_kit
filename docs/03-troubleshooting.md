# 03 — Troubleshooting

*Find your symptom in the first column. Every fix here was measured on a real install (2026-11-15, Windows 11
Home, 8 GB, Docker inside WSL 2), not guessed.*

---

## Start here

```powershell
cd C:\EmpiFlow
scripts\doctor.cmd          # is the machine ready?
scripts\status.cmd          # is the stack running?
scripts\logs.cmd create-site   # did the site get created?
```

`doctor` checks the machine without changing it; `status` shows each container and whether the two web pages
answer. Nine times out of ten the answer is in those two.

---

## The symptoms

### `[FAIL] no Docker engine answers`

Docker is not installed, or not running. Two fixes:

- **Docker Desktop** is installed but closed → start it from the Start menu, wait for the whale to stop
  animating, run `scripts\doctor.cmd` again.
- **Nothing is installed** → open PowerShell *as administrator* in `C:\EmpiFlow` and run
  `Install.cmd -InstallEngine`. It installs WSL 2 + the Docker engine, asks for one restart, and finishes on the
  second run. Details: `docs/01-install-windows.md` step 2.

### `The requested operation requires elevation`

You ran something that changes Windows (the engine install) from a normal window. Start menu → type
`powershell` → right-click → **Run as administrator**.

### `running scripts is disabled on this system`

You ran a `.ps1` by right-clicking it. Use the `.cmd` wrappers instead (`Install.cmd`, `scripts\doctor.cmd`) —
they already pass `-ExecutionPolicy Bypass`. Or run, in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### The download fails: `unauthorized` / `manifest unknown` / `denied`

- `unauthorized` — the machine is offline, or a proxy is intercepting GitHub. Check `doctor`'s `NET` row.
- `manifest unknown` — the `.env` asks for an image tag that does not exist. Check `EMPI_IMAGE_TAG` in `.env`;
  the released tag is `v1.0.0`.

### The first start takes very long, or `Install.cmd` says "did not answer within 15 minutes"

The first start really is 5–15 minutes on an 8 GB laptop: the database initialises, then the site is created,
then the two apps are installed into it. Watch it:

```powershell
scripts\logs.cmd create-site
```

You want to see `[create-site] DONE — site … , database …`. If you see it, the site exists and the containers
are just still booting — `scripts\status.cmd` will show them turning `running`.

If `create-site` exited with an error (its state is `exited` and the log has no `DONE`), the machine was
probably short of memory. Close everything else (browser, Teams, games), then:

```powershell
scripts\stop.cmd
scripts\start.cmd
```

### The laptop becomes very slow, or Docker commands hang / say `Wsl/Service/WSAETIMEDOUT`

The machine is out of RAM. The whole stack needs about 2.5 GB; Windows needs the rest of the 8 GB. Measured
symptom: Windows reports ~0.1 GB free, WSL stops answering, and every `docker` command times out.

1. Close everything you are not using (browser tabs are the usual culprit).
2. Free the WSL memory: `wsl --shutdown` in PowerShell (this stops the containers; **data is kept**).
3. `scripts\start.cmd` — the stack comes back, and containers with the `unless-stopped` policy restart by
   themselves once the engine is up.

You can also tell Docker Desktop to use less memory (Settings → Resources), but with the WSL engine the memory
is managed automatically and released when the stack stops.

### `port 8080 is used by another program` (or 3000)

Something else is listening. Either close it, or edit `.env` and change `HTTP_PORT` / `METABASE_PORT`, then run
`scripts\restart.cmd`. `doctor` tells you which port is blocked.

### Metabase returns `503` forever, or the page never loads

Metabase is a Java application and needs **60–120 seconds** after the other services are up. `status.cmd` shows
it as `running` before it can answer. Wait two minutes and reload.

If it is still 503 with the logs repeating `Metabase Initialization FAILED`:

```powershell
scripts\logs.cmd metabase
```

- `Database has migration lock` — the very first Metabase start was interrupted (power loss, `wsl --shutdown`,
  closed laptop). The half-written migration blocks every later start. Fix (loses Metabase's own saved
  questions, **not** your ERPNext data):

  ```powershell
  scripts\stop.cmd
  docker compose --env-file .env -f compose.yml rm -sf metabase
  docker volume rm empiflow_metabase-data
  scripts\start.cmd
  ```

- Out-of-memory during startup — close other programs and `scripts\restart.cmd`.

### The setup wizard fails: `Standard Template` / `Could not find Warehouse Type: Transit` / `Failed to install presets`

Three different messages, one family of causes:

| message | cause | fix |
|---|---|---|
| a chart-of-accounts error, or the Chart field is empty | ERPNext ships no chart for some countries; `Standard Template` is not a valid chart name | pick **`Standard`** (or `Standard with Numbers`) from the list |
| `Could not find Warehouse Type: Transit` | you tried to create a **Company through the API** before the setup wizard ran. ERPNext's Company needs the fixtures (warehouse types, taxes) that the wizard creates | run the setup wizard first — it is the intended first step |
| `Failed to install presets` | the site was created without the ERPNext fixtures, usually a `create-site` that never reached `DONE` | check `scripts\logs.cmd create-site`, and reset if needed |

The wizard is not decoration: until it completes, ERPNext has no fiscal year and no chart of accounts, and
`/app/company/new` cannot succeed. This was measured on the current pin
(ERPNext 15.125.0 / Frappe 15.126.1 / HRMS 15.64.8).

### Frappe HR pages load but look unstyled, or the HR workspace is empty

The site was created against an image whose assets did not include HRMS. Check what the image really contains:

```powershell
docker run --rm --entrypoint bench ghcr.io/empiflow/empiflow-kit-erpnext:v1.0.0 version
docker run --rm --entrypoint bash ghcr.io/empiflow/empiflow-kit-erpnext:v1.0.0 -c "ls /home/frappe/frappe-bench/assets"
```

`bench version` must list `hrms 15.64.8`, and `assets` must contain an `hrms` directory. If not, the image is
not the released one — check `EMPI_IMAGE_TAG` in `.env`.

### `docker compose ... down -v` and nothing works any more

You deleted the volumes: the site, the database and Metabase's metadata are gone. That is the reset. Run
`Install.cmd` again and wait through the first start (5–15 minutes).

### Everything is running but ERPNext shows `502 Bad Gateway`

The backend is restarting (usually memory). `scripts\status.cmd` → if all containers are `running` but the page
is 502, wait 30 seconds, then:

```powershell
scripts\logs.cmd backend
```

A `Traceback` there is a real error — collect it (below) and send it on.

---

## Collecting a support bundle

When you need to ask for help, send these four files:

```powershell
cd C:\EmpiFlow
scripts\doctor.cmd      > $env:TEMP\empi-doctor.txt     2>&1
scripts\status.cmd      > $env:TEMP\empi-status.txt     2>&1
scripts\logs.cmd backend  > $env:TEMP\empi-backend.txt  2>&1
scripts\logs.cmd create-site > $env:TEMP\empi-create.txt 2>&1
```

`.env` contains your passwords — **do not** send `.env`; send the four files above.

---

## Last resort: a clean reinstall

This deletes all data (back up from ERPNext first: *Home → Tools → Backup*):

```powershell
cd C:\EmpiFlow
docker compose --env-file .env -f compose.yml down -v
Install.cmd
```

If a pull is failing because of a broken local image, remove it first:

```powershell
docker rmi ghcr.io/empiflow/empiflow-kit-erpnext:v1.0.0
```
