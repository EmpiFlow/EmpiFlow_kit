# 00 — Client guide: start here

*One page: what this kit is, how to install it, what you will see, and how to start it tomorrow.*

---

## 1. What you get

An ERPNext 15 site with the Frappe HR app, plus Metabase for reports, all running on this Windows laptop.
Nothing leaves the laptop: the two web pages answer only on `127.0.0.1`.

**Before you start:** Windows 10 (2004+) or 11, 64-bit, **8 GB of memory installed**, 15 GB free on the drive
that will hold the WSL disk (`C:` by default), and internet for the first download. It is a testing kit for one
person at a time, not a production server.

---

## 2. Install it

1. Download the repository as a ZIP (**Code → Download ZIP**) and extract it somewhere simple, for example
   `C:\EmpiFlow`. Do not use OneDrive or a USB stick.
2. Double-click **`Install.cmd`**.

   It checks the machine first. If something is wrong it tells you and **changes nothing**. If the machine is
   fine, it asks five questions (press Enter to accept each default), then does the rest by itself:
   installs WSL 2 + Docker if they are missing (Windows asks for administrator permission **once**), downloads
   the image, and starts the stack.

   A **progress window** stays open the whole time and prints each step plus a `still working` line every few
   seconds. You do not need to understand the steps; you just need to see that it is alive.
3. If it says Windows must restart, restart and double-click `Install.cmd` again. It continues where it stopped.
4. The first start takes 5–15 minutes. When it is done the browser opens on ERPNext.

The progress window prints `== EmpiFlow installer - progress`, then one line per step:

```
[01:47:37] == Docker engine
[01:47:38]   [ OK ] docker 29.6.1 inside WSL (Ubuntu-24.04)
[01:47:43] == Starting the stack
   ... still working (00:10 elapsed)
```

---

## 3. The EmpiFlow_kit folder (shortcuts)

The installer creates a folder called **EmpiFlow_kit** on the Desktop and in the Start menu:

| item | what it does |
|---|---|
| **1 Start EmpiFlow** | starts WSL, Docker, ERPNext and Metabase |
| **2 Stop EmpiFlow** | stops everything and gives the memory back; **data is kept** |
| **3 ERPNext** | opens <http://127.0.0.1:8080> |
| **4 Metabase** | opens <http://127.0.0.1:3000> |

Use **1** at the start of the day and **2** at the end. After a reboot the stack does not start by itself
unless you ran `scripts\autostart.cmd`.

---

## 4. First 20 minutes

1. **Log in** to ERPNext as `Administrator` with the admin password you typed during the install.
2. **Run the setup wizard.** This is the empty state, not an error. For Malaysia choose the chart
   **`Standard`** (not `Standard Template`). The wizard creates the chart of accounts and warehouses.
3. **Connect Metabase** (`4 Metabase` shortcut):
   - create Metabase's own admin account (this is not the ERPNext account);
   - **Admin settings → Databases → Add database → MySQL**;
   - Host `db`, Port `3306`, Database name **`empiflow_local`**, user `metabase_ro`, password
     `MB_RO_PASSWORD` from `.env`.

   > **Exactly where is `empiflow_local` typed?** In the **Database name** field of that Add-database form.
   > It is your site name `empiflow.local` with the dots replaced by underscores — not the Host field, and not
   > a SQL command.

The full detail is in [02 — First steps](02-first-steps.md).

---

## 5. What to watch while installing

| you see | what it means |
|---|---|
| `[ OK ]` | the check passed |
| `[WARN]` | it will work; the note says what to watch |
| `[FAIL]` | this is a real problem; the `fix:` line says what to do. Nothing has been changed, so you can stop and come back. |
| `no Docker engine yet` | normal on a new laptop — `Install.cmd` sets it up |
| `Windows has to restart once` | normal on a new laptop — restart, then run `Install.cmd` again |
| a progress window with a `still working` line | normal — long steps are running |
| the progress window closed but the work continues | the work is in a hidden worker; the log is `install-log.txt`. Reopen the progress view with `Get-Content -Wait .\install-log.txt` |

If the install stops, read the last `[FAIL]` line. [03 — Troubleshooting](03-troubleshooting.md) lists every
symptom this kit has actually produced.

---

## 6. Limits

- **8 GB installed** is the floor. Windows reports about 7.7 GB usable on an 8 GB machine; the check uses the
  installed modules.
- **One person at a time.** A few concurrent browsers may work, but this kit is for testing, not production.
- **WSL gets 3 GB.** The installer writes `%USERPROFILE%\.wslconfig` (`memory=3GB`, `swap=6GB`,
  `autoMemoryReclaim=dropCache`). Without that cap an 8 GB laptop can freeze.
- **The WSL disk is 2–4 GB on `C:`** by default. If `C:` is small, run `.\Install.cmd -WslRoot D:\EmpiFlow\wsl`
  from PowerShell on the first install.
- **Docker Desktop is optional.** If you use it, Docker's own licence terms apply; the kit's own engine needs no
  Docker Desktop.

---

## 7. If you need help

Run these three and send the files:

```powershell
cd C:\EmpiFlow
scripts\doctor.cmd      > $env:TEMP\empi-doctor.txt     2>&1
scripts\status.cmd      > $env:TEMP\empi-status.txt     2>&1
scripts\logs.cmd create-site > $env:TEMP\empi-create.txt 2>&1
```

Send the three files, not `.env` (it contains your passwords).
