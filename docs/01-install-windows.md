# 01 — Install on Windows

*This is the only document you need to get EmpiFlow running. It takes about 20 minutes, most of which is waiting.*

---

## Before you start

| | |
|---|---|
| Windows | Windows 10 (version 2004 or newer) or Windows 11, 64-bit |
| Memory | 8 GB recommended; 6 GB works if you close other programs during the first start |
| Disk | 15 GB free (20 GB recommended) |
| Internet | Needed for the download. After the install the kit works offline. |
| Time | ~20 minutes: 5 minutes of clicking, 5–15 minutes of the machine creating the site |

You do **not** need: an account anywhere, a server, a GitHub account, or the internet after the install.

---

## Step 1 — Check the machine

1. Unzip the kit into a normal folder, for example `C:\EmpiFlow`. **Do not** put it in OneDrive or on a USB
   stick — Docker needs a stable local path, and OneDrive locks files while it syncs.
2. Open the folder `scripts` and double-click **`doctor.cmd`**.

A black window opens and prints one line per check:

```
EmpiFlow kit - machine check

  [ OK ] Windows 11 (build 26200)
  [ OK ] 64-bit Windows
  [WARN] 7.3 GB of memory — it works, but close other programs during the first start
  [ OK ] 51.6 GB free
  [ OK ] docker 29.6.1 inside WSL (Ubuntu-24.04)
  ...
9 checks: 7 OK, 2 warnings, 0 problems

This machine can run the EmpiFlow kit.
```

- **`[ OK ]`** — nothing to do.
- **`[WARN]`** — it will work; the note says what to watch.
- **`[FAIL]`** — the line says what is wrong and the `fix:` line says what to do. Nothing has been changed on
  your machine by this step, so you can stop and come back to it.

**The one FAIL everybody hits first is `no Docker engine answers`.** Step 2 fixes it.

> If the window closes instantly, open **Windows PowerShell** in the kit folder and run `scripts\doctor.cmd`
> instead — you will then see the output. (Right-click the folder → *Open in Terminal*, or hold Shift and
> right-click the folder → *Open PowerShell window here*.)

---

## Step 2 — Give Windows a Docker engine

Docker is what actually runs ERPNext. You have two routes; **B is the one this kit recommends**, because it
needs no account, no licence and no Docker Desktop.

### Route A — you already have Docker Desktop

Start **Docker Desktop** from the Start menu and wait until the whale icon stops animating. Then run
`scripts\doctor.cmd` again: the `DOCKER` row turns `[ OK ]`.

If Docker Desktop is installed but not running, `doctor` says so by name.

### Route B — let the kit install one (recommended)

1. Open **Windows PowerShell as administrator**:
   Start menu → type `powershell` → right-click **Windows PowerShell** → **Run as administrator** → **Yes**.
2. Go to the kit folder and start the installer as administrator:

   ```powershell
   cd C:\EmpiFlow
   Install.cmd -InstallEngine
   ```

3. It enables two Windows features (WSL 2 and the Virtual Machine Platform), then says it needs one restart:

   ```
   Windows has to restart once before WSL can run.
   After the restart, run Install.cmd again (it continues from here).
   ```

4. **Restart Windows.** Then run `Install.cmd -InstallEngine` again in an administrator window. It installs
   Ubuntu 24.04 inside WSL and the Docker engine in it (about 300 MB, a few minutes), and finishes with:

   ```
   [ OK ] Docker 29.x is running inside WSL (Ubuntu-24.04)
   [ OK ] docker compose v2.x
   ```

You only do this once per machine.

> **Windows 11 24H2 / 25H2 may ask for a second restart.** On those builds WSL itself is a Microsoft Store
> package, and the built-in `wsl.exe` cannot install it. The installer notices this, runs
> `winget install Microsoft.WSL`, and asks for one more restart. Run `Install.cmd -InstallEngine` again
> afterwards — that is the last one.
>
> **Why a restart?** WSL 2 is a small virtual machine; Windows can only start it after the feature is switched on
> at boot. There is no way around the reboot.

---

## Step 3 — Install EmpiFlow

Double-click **`Install.cmd`** in the kit folder (a normal, non-administrator window is enough from here on).

It asks five questions. Press **Enter** to accept the value in brackets — for a first install, accept all five.

```
  Site name                    [empiflow.local]
  ERPNext admin password       [admin]
  Database password            [admin]
  ERPNext port                 [8080]
  Metabase port                [3000]
```

What the answers mean:

| question | what to type | if you are unsure |
|---|---|---|
| Site name | the internal name of your ERPNext site, letters/digits/dots/dashes | press Enter |
| ERPNext admin password | the password you will log in with, user `Administrator` | press Enter, change it later in ERPNext |
| Database password | password of the stack's own database; never leaves the machine | press Enter |
| ERPNext port | the number in `http://127.0.0.1:8080` | press Enter |
| Metabase port | the number in `http://127.0.0.1:3000` | press Enter |

Then it downloads the image (~1.5 GB, once) and starts the eleven containers. **The first start takes 5–15
minutes** — the database is created, then the site, then ERPNext and Frappe HR are installed into it. The window
shows a progress line:

```
  waiting for ERPNext ...   180s elapsed,  720s left
```

When it is done:

```
  EmpiFlow is ready.

  ERPNext    http://127.0.0.1:8080
             user: Administrator   password: (ADMIN_PASSWORD in .env)
  Metabase   http://127.0.0.1:3000

  Stop it:   scripts\stop.cmd        Start it again: scripts\start.cmd
  Next:      docs\02-first-steps.md
```

Your browser opens on ERPNext. **Next: `docs/02-first-steps.md`** — the setup wizard is waiting for you there.

---

## Everyday commands

All of them are double-clickable in `scripts\`.

| what | command |
|---|---|
| start the stack | `start.cmd` |
| stop the stack (data is kept) | `stop.cmd` |
| what is running, and are the pages answering | `status.cmd` |
| apply changes you made to `.env` | `restart.cmd` |
| look at a service log | `logs.cmd create-site`, `logs.cmd backend`, … |
| start automatically when you log in | `autostart.cmd` (undo: `autostart.cmd -Remove`) |
| desktop and Start-menu shortcuts | `shortcuts.cmd` (undo: `shortcuts.cmd -Remove`) |
| the machine check again | `doctor.cmd` |

After a reboot the stack does **not** start by itself unless you ran `autostart.cmd`. Start it with
`start.cmd`; it takes about a minute.

---

## Optional — reach it from another device on the same Wi-Fi

By default both ports are bound to `127.0.0.1`, which means *this laptop only* — a deliberate security
default (anyone on the café Wi-Fi could otherwise open your ERPNext with the default password).

To demo from a phone or a second laptop on a trusted network, edit `compose.yml` and remove `127.0.0.1:` from
the two `ports:` lines:

```yaml
    ports:
      - "${HTTP_PORT:-8080}:8080"      # was 127.0.0.1:${HTTP_PORT:-8080}:8080
```

and the same for `"${METABASE_PORT:-3000}:3000"`. Then run `scripts\restart.cmd` and open
`http://<this-laptop-ip>:8080` from the other device. Change the admin password first. Undo it the same way.

---

## Reset, back up, remove

**Back up** — in ERPNext, *Home → Tools → Backup* downloads a database + files archive. Do this before any
reset.

**Start from an empty site again** (deletes everything):

```powershell
cd C:\EmpiFlow
docker compose --env-file .env -f compose.yml down -v
Install.cmd
```

`down -v` deletes the four Docker volumes (site files, database, Metabase metadata). It cannot be undone.

**Remove the kit from the machine:**

```powershell
scripts\autostart.cmd -Remove
scripts\shortcuts.cmd -Remove
docker compose --env-file .env -f compose.yml down -v
docker rmi ghcr.io/empiflow/empiflow-kit-erpnext:v1.0.0
```

Then delete the `C:\EmpiFlow` folder. If you installed the engine with Route B and want it gone as well,
uninstall *Ubuntu 24.04* from Windows Settings → Apps, and turn off the two Windows features in
*Turn Windows features on or off*.

---

## Where things are

| | |
|---|---|
| the kit's settings | `C:\EmpiFlow\.env` (created by `Install.cmd`) |
| ERPNext site files and database | Docker volumes `empiflow_sites`, `empiflow_db-data` |
| Metabase's own metadata | Docker volume `empiflow_metabase-data` |
| container logs | `scripts\logs.cmd <service>` |

Nothing is written anywhere else on the machine.
