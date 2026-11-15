# 01 — Install on Windows

*This is the detailed install document. It takes about 20 minutes, most of which is waiting. If you only want
the short version, read [`00-client-guide.md`](00-client-guide.md).*

---

## Before you start

| | |
|---|---|
| Windows | Windows 10 (version 2004 or newer) or Windows 11, 64-bit |
| Memory | **8 GB installed** minimum and recommended. Windows shows an 8 GB machine as about 7.7 GB usable; the installer checks the installed capacity. |
| Disk | 15 GB free (20 GB recommended) on the drive that will hold the WSL disk — `C:` by default |
| Internet | Needed for the download. After the install the kit works offline. |
| Time | ~20 minutes: 5 minutes of clicking, 5–15 minutes of the machine creating the site |

You do **not** need: an account anywhere, a server, a GitHub account, or the internet after the install.

> **This is a testing kit.** It is sized for one person at a time. A few people browsing at once may work,
> but concurrent users have not been tested. Do not use it as a production server.

---

## Step 1 — Check the machine

1. Unzip the kit into a normal folder, for example `C:\EmpiFlow`. **Do not** put it in OneDrive or on a USB
   stick — Docker needs a stable local path, and OneDrive locks files while it syncs.
2. Open the folder `scripts` and double-click **`doctor.cmd`**.

A black window opens and prints one line per check (the window stays open until you press a key):

```
EmpiFlow kit - machine check

  [ OK ] Windows 11 (build 26200)
  [ OK ] 64-bit Windows
  [ OK ] 8 GB of memory installed (7.7 GB usable)
  [ OK ] 42.3 GB free on C: (the WSL disk)
  [WARN] no Docker engine yet - Install.cmd sets one up (WSL 2 + Docker Engine)
  [ OK ] virtualisation available
  [ OK ] WSL memory cap set (memory=3GB)
  [ OK ] port 8080 is free (ERPNext)
  ...
12 checks: 9 OK, 3 warning(s), 0 problem(s)

This machine can run the EmpiFlow kit.
Next: double-click Install.cmd - it sets up WSL and Docker for you.
```

- **`[ OK ]`** — nothing to do.
- **`[WARN]`** — it will work; the note says what to watch. *No Docker engine yet* is the normal first-run
  warning; the installer fixes it.
- **`[FAIL]`** — the line says what is wrong and the `fix:` line says what to do. Nothing has been changed on
  your machine by this step, so you can stop and come back.

`doctor` checks **8 GB of memory installed**. It reads the physical modules, not the ~7.7 GB Windows reports,
so an 8 GB laptop passes. A 4 GB or 6 GB machine fails here, deliberately: below 8 GB the stack, WSL and Windows
compete and the laptop can freeze. The installer also caps WSL at 3 GB with 6 GB of swap in
`%USERPROFILE%\.wslconfig`, which is what keeps an 8 GB laptop usable.

> If the window closes instantly, open **Windows PowerShell** in the kit folder and run `scripts\doctor.cmd`
> instead. (Right-click the folder → *Open in Terminal*, or hold Shift and right-click the folder →
> *Open PowerShell window here*.) The `.cmd` wrappers pause when double-clicked so you can read the result.

---

## Step 2 — Install EmpiFlow

Double-click **`Install.cmd`** in the kit folder. That is the whole step.

It runs the machine check again, asks five questions (Step 3), and then **does the engine work itself**:

1. If Docker is already running (Docker Desktop or a previous install), it uses it and changes nothing.
2. If Docker is installed but stopped, it starts it.
3. If there is no engine at all, it enables WSL 2 and the Virtual Machine Platform, installs the WSL runtime,
   imports Ubuntu 24.04 (a 30 MB download) and installs the Docker engine inside it. **Windows asks for
   administrator permission once** — click **Yes**. If the UAC prompt is refused, no engine or stack is
   installed (the settings file may already exist).

The long work runs in a **hidden worker** while a **progress window** stays open and prints the log, plus a
`still working` line every few seconds. You do not need to know which step is running; you only need to see
that it is alive. Closing the progress window does not stop the install.

### If it says Windows must restart

On a machine that has never had WSL, Windows has to restart once after the two features are enabled. The
installer stops and says so. **Restart Windows, then double-click `Install.cmd` again** — it continues from
where it stopped, and that is the last restart.

> **Windows 11 24H2 / 25H2 may ask for a second restart.** On those builds WSL itself is a Microsoft Store
> package, and the built-in `wsl.exe` cannot install it. The installer notices this, runs
> `winget install Microsoft.WSL`, and asks for one more restart. Run `Install.cmd` again afterwards.
>
> **Why a restart?** WSL 2 is a small virtual machine; Windows can only start it after the feature is switched
> on at boot. There is no way around the reboot.

### If you already have Docker Desktop

Start **Docker Desktop** from the Start menu and wait until the whale icon stops animating. Then run
`Install.cmd`: the engine row passes and the kit uses Desktop. If Docker Desktop is installed but not running,
the installer starts it.

> **Docker Desktop licence.** Docker Desktop is **not required** by this kit and is not installed by it. If you
> choose to use it, Docker's own subscription terms apply — at the time of writing it is free for personal use,
> education, and businesses with fewer than 250 employees **and** less than $10M annual revenue; larger
> organisations need a paid Docker subscription. Check <https://www.docker.com/pricing/>. The kit's own
> WSL 2 + Docker Engine route needs no Docker Desktop account or licence.

---

## Step 3 — Answer five questions

Press **Enter** to accept the value in brackets — for a first install, accept all five.

```
  Site name                    [empiflow.local]
  ERPNext admin password       [admin]
  Database password            [admin]
  ERPNext port                 [8080]
  Metabase port                [3000]
```

| question | what to type | if you are unsure |
|---|---|---|
| Site name | the internal name of your ERPNext site, letters/digits/dots/dashes | press Enter |
| ERPNext admin password | the password you will log in with, user `Administrator` | press Enter, change it later in ERPNext |
| Database password | password of the stack's own database; never leaves the machine | press Enter |
| ERPNext port | the number in `http://127.0.0.1:8080` | press Enter |
| Metabase port | the number in `http://127.0.0.1:3000` | press Enter |

Then it downloads the image (~1.5 GB, once) and starts the eleven containers. **The first start takes 5–15
minutes** — the database is created, then the site, then ERPNext and Frappe HR are installed into it. The
progress window shows a line every few seconds:

```
  -> starting the containers
  [ OK ] image downloaded
  == Starting the stack
         waiting for ERPNext ... 180s elapsed
   ... still working (03:12 elapsed)
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

Your browser opens on ERPNext. The installer also creates the **EmpiFlow** folder on your Desktop and in the
Start menu.

**[Next: 02 — First steps](02-first-steps.md)** — the setup wizard is waiting for you there.

---

## The EmpiFlow folder

| item | what it does |
|---|---|
| **1 Start EmpiFlow** | starts WSL, Docker, ERPNext and Metabase (about a minute) |
| **2 Stop EmpiFlow** | stops the containers and the WSL engine; data is kept, memory is returned |
| **3 ERPNext** | opens <http://127.0.0.1:8080> |
| **4 Metabase** | opens <http://127.0.0.1:3000> |

Recreate it at any time with `scripts\shortcuts.cmd`; remove it with `scripts\shortcuts.cmd -Remove`.

## Everyday commands

All of them are double-clickable in `scripts\`.

| what | command |
|---|---|
| start the stack | `start.cmd` |
| stop the stack (data is kept) | `stop.cmd` |
| stop the containers but leave WSL/Docker running | `stop.cmd -KeepEngine` |
| what is running, and are the pages answering | `status.cmd` |
| apply changes you made to `.env` | `restart.cmd` |
| look at a service log | `logs.cmd create-site`, `logs.cmd backend`, … |
| start automatically when you log in | `autostart.cmd` (undo: `autostart.cmd -Remove`) |
| the machine check again | `doctor.cmd` |

After a reboot the stack does **not** start by itself unless you ran `autostart.cmd`. Use **1 Start EmpiFlow**
or `start.cmd`; it takes about a minute.

---

## Where the WSL disk lives

The Ubuntu distribution is a 2–4 GB disk image. By default it is created at:

```
C:\ProgramData\EmpiFlow\wsl\Ubuntu-24.04
```

If `C:` is small, set `WSL_ROOT` in `.env` **before the first install**:

```ini
WSL_ROOT=D:\EmpiFlow\wsl
```

`doctor` checks free space on that drive, and the installer imports the distribution there. The setting only
affects a **new** import; an existing distribution stays where it was created. For a machine with a large `D:`
and a small `C:`, set it before running `Install.cmd` — after the first run, edit `.env` and reinstall the
distribution to move it.

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
This is for a demo, not multi-user production: the kit has not been tested with concurrent users.

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

Then delete the `C:\EmpiFlow` folder. If you installed the engine with this kit and want it gone as well,
uninstall *Ubuntu 24.04* from Windows Settings → Apps, delete `C:\ProgramData\EmpiFlow\wsl`, and turn off the
two Windows features in *Turn Windows features on or off*.

---

## Where things are

| | |
|---|---|
| the kit's settings | `C:\EmpiFlow\.env` (created by `Install.cmd`) |
| the installer's progress log | `C:\EmpiFlow\install-log.txt` |
| ERPNext site files and database | Docker volumes `empiflow_sites`, `empiflow_db-data` |
| Metabase's own metadata | Docker volume `empiflow_metabase-data` |
| the WSL Linux disk | `C:\ProgramData\EmpiFlow\wsl\Ubuntu-24.04` (or `WSL_ROOT`) |
| container logs | `scripts\logs.cmd <service>` |
