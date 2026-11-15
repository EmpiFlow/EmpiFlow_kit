# 02 — First steps

*After `Install.cmd` finishes, the browser opens on ERPNext. This document is the first 20 minutes: the setup
wizard, where HR lives, and connecting Metabase.*

> **Starting and stopping from now on.** Use the **EmpiFlow** folder on your Desktop: **1 Start EmpiFlow**
> starts WSL, Docker, ERPNext and Metabase; **2 Stop EmpiFlow** stops them and gives the memory back (data is
> kept). **3 ERPNext** and **4 Metabase** open the two pages. You do not need the installer again.

---

## 1. Log in

```
http://127.0.0.1:8080
user:      Administrator
password:  the ERPNext admin password you typed during Install.cmd  (default: admin)
```

If you accepted the defaults, change the password now: click the **A** avatar (top right) → **My Settings** →
**Change password**. The default is public knowledge and this laptop may leave your desk.

---

## 2. Run the setup wizard — this is the empty state

ERPNext opens **the setup wizard**, and that is correct: the kit ships an *empty* site, and the wizard is what
turns it into *your* company. Until it is done, ERPNext has no currency, no chart of accounts and no warehouse
types — creating a Company through the API even fails at that point (measured; see `03-troubleshooting.md`).

Fill it in:

| step | what to answer |
|---|---|
| Language | English |
| Country | Malaysia |
| Time zone | Asia/Kuala_Lumpur (or yours) |
| Currency | MYR |
| Company name | your real company name, e.g. `EmpiFlow Sdn Bhd` |
| Company abbreviation | 2–4 letters, e.g. `EFS` (it prefixes account names) |
| Chart of accounts | **`Standard`** — for Malaysia ERPNext ships no country chart, and the list offers `Standard` and `Standard with Numbers`. **Do not type `Standard Template`**; it does not exist and the wizard fails. |
| Fiscal year | the current year (1 Jan – 31 Dec is fine) |

Click **Complete Setup**. It takes 20–60 seconds and creates the chart of accounts, taxes, warehouses,
departments and the first fiscal year.

When it finishes you land on the **ERPNext desk** — the icon-based home screen. That is your ERP.

> Run the wizard **once**. Running it again on a site that already has a company only re-applies defaults.

---

## 3. Where Frappe HR is

Frappe HR is not a separate program — it adds HR pages *inside* ERPNext.

- The **HR** workspace: <http://127.0.0.1:8080/app/hr>
- Or type in the search bar (top): `Employee`, `Attendance`, `Leave Application`, `Expense Claim`,
  `Appraisal`, `Payroll Entry`.

The five records you will touch first:

| record | where | what it is |
|---|---|---|
| **Employee** | `/app/employee` | the person; `HR-EMP-00001`, … |
| **Attendance** | `/app/attendance` | one row per employee per day; must be **submitted** to count |
| **Leave Application** | `/app/leave-application` | requests, approved by a Leave Approver |
| **Shift Assignment** | `/app/shift-assignment` | which shift an employee works |
| **Payroll Entry** | `/app/payroll-entry` | monthly run over a Salary Structure |

**Create one employee to see the path work:** *Employee → New* → first name, last name, company (`EmpiFlow
Demo`), gender, date of birth, date of joining → **Save**. Then *Attendance → New* → that employee, a date,
status `Present` → **Save** → **Submit**.

An `Employee` is an **ERPNext** record; `Attendance` is a **Frappe HR** record. Submitting one against the other
is the cross-app path this kit exists to protect — if that works, the two apps are talking to each other.

---

## 4. Connect Metabase

Metabase is the reporting tool. It reads the ERPNext database **read-only** through a dedicated user
(`metabase_ro`); it cannot change or delete anything.

1. Open <http://127.0.0.1:3000>. On first run Metabase asks you to create **its own** admin account — this is
   *not* the ERPNext account. Use your work e-mail and a password you keep.
   - You can decline the "sample database" and the usage-tracking question.
2. **Admin settings (the gear, top right) → Databases → Add database → MySQL** (ERPNext runs MariaDB, which
   speaks the MySQL protocol):

   | field | value |
   |---|---|
   | Display name | `ERPNext` |
   | Host | `db` |
   | Port | `3306` |
   | **Database name** | **`empiflow_local`** — type it exactly like this, in this field |
   | Username | `metabase_ro` |
   | Password | `MB_RO_PASSWORD` from `.env` (default `metabase_ro`) |

   > **Where exactly do I type `empiflow_local`?** In the **Database name** field of the Add-database form.
   > It is **not** the Host field (that is `db`) and it is **not** a SQL command. It is the site name
   > `empiflow.local` with the dots replaced by underscores. All lowercase, one underscore.
   >
   > **Why not `127.0.0.1`?** Metabase runs in its own container; from there `db` is the database and
   > `127.0.0.1` is Metabase itself. Use the service name.
   >
   > **Why `empiflow_local` and not `empiflow.local`?** Frappe stores the database under a safe name. The
   > kit pins it to the site name with dots replaced by underscores so it is predictable. `create-site.sh`
   > prints it at install time (`database name: empiflow_local`), and it is in
   > `sites/empiflow.local/site_config.json` → `db_name`. If you changed `SITE_NAME`, use that name with
   > dots replaced by underscores.

3. Click **Save**. Metabase syncs the schema in the background: **5–15 minutes** on an 8 GB laptop. You can
   start asking questions before it finishes — table names appear as it discovers them.

**Your first question** (the one that proves the kit works end to end): *New → Question → Native query*, pick
`ERPNext`, and run

```sql
select e.employee_name, count(*) as days_present
from tabAttendance a
join tabEmployee e on e.name = a.employee
where a.docstatus = 1
group by e.employee_name
```

If it returns your test employee, Metabase is reading Frappe HR tables **through a join to an ERPNext table** —
the whole point of the kit.

---

## 5. Back up before you rely on it

ERPNext: *Home → Tools → Backup* (or `/app/backup`) → **Backup now** → download the database + files archive.
Keep it somewhere that is not this laptop.

The kit's own data lives in Docker volumes (`empiflow_sites`, `empiflow_db-data`, `empiflow_metabase-data`);
`scripts\stop.cmd` keeps them, `docker compose down -v` deletes them.

---

## 6. The daily rhythm

| when | what |
|---|---|
| start of day | **1 Start EmpiFlow** in the EmpiFlow folder (or `scripts\start.cmd`; or `autostart.cmd` once, and it starts at logon) |
| end of day | **2 Stop EmpiFlow** (or `scripts\stop.cmd`) — data is kept |
| open the pages | **3 ERPNext** · **4 Metabase** |
| something looks wrong | `scripts\status.cmd`, then `docs\03-troubleshooting.md` |
| you changed `.env` | `scripts\restart.cmd` |
