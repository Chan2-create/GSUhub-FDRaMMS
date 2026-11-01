# Final presentation walkthrough

Objective 7.C. One damage report followed from the phone to the console
to the technician and back, with each role's own screens shown along the
way. It takes about 20 minutes; the timings are a guide.

Every button and page named here is the one in the app. The local demo
data (`supabase/seed.sql`) supplies the accounts, rooms, materials and
tools quoted below.

## Choose where to run it

| | Local, seeded | Live |
|---|---|---|
| What it is | The whole system on the presenting laptop (`tool\run_local.cmd`) | The deployed console and the installed APK |
| Data | Six months of history, duplicates, low stock, a pending sign-up: everything has something to show | Only what the team has entered; the demo seed never goes on live |
| Needs | Docker Desktop; internet only for the map tiles | Internet; phones with the APK |
| Shows | Every feature | The deployment itself |

Run the walkthrough locally. If the panel wants the deployment, open the
live console and the APK afterwards to show they are the same system.
On live you would have to enter every room, material, tool and account
first (see "Live: the day before").

## Local: the day before and the morning of

1. Start Docker Desktop, then run `tool\run_local.cmd -Server -Reseed`.
   `-Reseed` loads the demo data again; its times are relative to now, so
   load it on the morning itself. `-Server` serves the app at
   `http://localhost:5556` for any browser.
2. Open three browser windows that do not share a session (one browser
   holds one sign-in):
   - **Console**: Edge, `http://localhost:5556`, as `admin@dorsu.edu.ph`.
   - **Faculty**: an Edge InPrivate window,
     `http://localhost:5556/#/staff/login`, as `faculty@dorsu.edu.ph`.
   - **Technician**: Chrome or a second Edge profile, the same address, as
     `personnel@dorsu.edu.ph` (Marcus Wright, electrician).

   The password for every seeded account is `password123`. Narrow the
   faculty and technician windows to phone width, side by side with the
   console.
3. Have these codes ready on a second screen or printed, from any QR
   generator (or print them from the console's labels):
   - `FAC-FAC-ENGINEERING-203` (a room)
   - `INV-INV-SOCKET-PLATE` (a material)
   - `TOOL-TL-0824` (DeWalt Impact Driver)

   A laptop without a camera can open a scan by address instead:
   `http://localhost:5556/#/personnel/scan?code=TOOL-TL-0824`.
4. Have a photo of a damaged outlet on the laptop for the report.
5. Rehearse once, then run `tool\run_local.cmd -Reseed` again so the
   panel sees clean data.

The orange **EMULATOR** ribbon marks the local system; say so if asked.

## Live: the day before

Only if you present on live as well.

1. **Wake the database.** A free Supabase project pauses after a week
   without use: open the Supabase dashboard and restore it if it says
   *Paused*.
2. **Check the site is the new build** (docs/manual_deploy.md): the
   sidebar's Notifications opens its page. The old build greys it out.
3. **Accounts.** User Accounts → **Add Personnel** → **Create maintenance
   account** for each technician in the demo, with their trade. Each gets
   an email to set their password, so use addresses the team can open.
   A faculty member signs up from the app's **CREATE ACCOUNT**; approve
   it in User Accounts (⋮ → **Approve**).
4. **Rooms, materials, tools.** Facilities & Equipment → **Add Room** for
   the rooms you will report from; Inventory Management → **Add
   Material** (one below its minimum, to show the alert) and a tool.
   Print their labels.
5. **Settings.** Press **Save keywords**, **Save priority scoring** and
   **Save duplicate detection** once, so the stored settings are the
   ones shown. Until then the manuscript's defaults apply.
6. Install the APK (`scripts/build_apk.ps1`) on the faculty and
   technician phones; sign in on each.

## The walkthrough

### 1. A faculty member reports damage (3 min, Faculty window)

1. Home → the gold **+** (Report Damage).
2. Title: *Sparking outlet in Room 203*. Description: *The faulty outlet
   beside the whiteboard sparks when a plug goes in, and there is an
   exposed wire behind the cover.*
3. **Scan facility QR code** → show `FAC-FAC-ENGINEERING-203`: the
   building and room fill in. Switch on **Auto-capture GPS location**
   (allow the browser or phone to share it); **Tap to adjust location on
   map** moves the pin.
4. Add the photo. **Urgency level**: High. **Submit Report**.
5. My Reports shows it, with its status.

*Point out:* the description's "faulty outlet" and "exposed wire" are
Table 3.3 keywords; the report is already classified Electrical.

### 2. The administrator reviews it (4 min, Console)

1. The bell has a new count. **Notifications** → *New urgent report
   submitted* (urgent because the requestor chose High) → it opens the
   report.
2. **Start review**. In the Faculty window, the report's status changes
   to Under review without a reload.
3. **Classification and priority**: **Keywords found** shows the two
   keywords and Electrical. Frequency is filled in from similar reports.
   Rate **Severity**, **Safety risk** and **Location importance**; the
   **Priority score** and the **Recommended** priority follow. Set the
   **Official priority** and **Confirm classification and priority**.
4. **Approve**. The faculty member gets *Report approved*, and the
   report's timeline gains the step.

*Point out:* the weights and score bands are in **Settings → Priority
scoring**. The manuscript gives two sets (Table 3.2's integer weights
and §3.4's formula); both are there, and the formula's is in use.

### 3. Duplicates (1 min, Console)

Reports → `#REP-0001` is marked: Ana reported the same fan in Room 101.
Open it: **Possible duplicates** gives the reasons and offers **Merge**
or **Keep separate**. Leave it, or merge to show the requestor is told.

### 4. Assignment (2 min, Console)

1. **Task Assignment** → select the report under UNASSIGNED REPORTS.
2. Personnel Availability lists electricians first, then the least busy.
   **Assign** on Marcus Wright's row → **Set date** for the target
   completion → **Assign**. Marcus is told, and so is the faculty member.
3. **Work Orders**: the new work order is in Pending on the board.

### 5. The technician does the work (4 min, Technician window)

1. Home shows the new work order; its alert is in the bell.
2. Open it → **Start work**. In the Console, Notifications shows *Work
   started*; on the Faculty side the report is In Progress.
3. The gold **+** → scan `INV-INV-SOCKET-PLATE` → **Record use on a work
   order** → pick this work order, quantity 1 → **Record**.
4. Scan `TOOL-TL-0824` → **Borrow** it for this work order.
5. Optional: **Request Materials** asks GSU for more; the Console's
   Notifications shows *Materials requested*, and Inventory Management →
   Material Requests approves it.
6. Scan `TOOL-TL-0824` again → **Return**.
7. **Mark Complete**: completion notes and a photo of the finished work.
   The confirmation lists what comes off stock. **Submit**.

### 6. Sign-off (2 min, Console)

1. Notifications → *Work ready for sign-off* → the work order.
2. **Accomplishment report**: the notes, the photo, the materials.
   **Approve and sign off**. (Or **Send back for rework** with a note:
   the technician sees it at the top of the work order.)
3. On the board, try dragging a For Review card to Completed: it opens
   the accomplishment report instead. Only the sign-off completes work.
4. **Reassign** on another open work order's page hands it to another
   technician; both are told.
5. Inventory Management: the socket plate's stock went down when the
   report was filed. A LOW STOCK material → **ORDER** records a delivery
   and the alert clears. A tool's QR icon downloads its label.

### 7. The faculty member rates the work (1 min, Faculty window)

The report shows Completed, with a *Work completed* alert. **Rate this
Service**: three ratings, Poor to Excellent. Submit: the report is
Closed.

### 8. Oversight (3 min, Console)

- **Dashboard**: the counts, the urgent reports, Recent Activity (the
  audit trail).
- **Analytics**: the charts for the period, Most Used Materials; **Export
  Data** downloads the period's reports as a CSV.
- **User Accounts**: `liza.tan@` signed up and waits; ⋮ → **Approve**.
- **Settings**: **Try a description** shows the classification as you
  type; Priority scoring and Duplicate detection are editable, and the
  database refuses settings outside the manuscript's ranges.

## If something goes wrong

- **"Your session has expired"**: sign in again; nothing is lost.
- **A screen does not update**: reload the page. Locally, on
  `localhost`, a reload keeps you signed in.
- **Live is down or paused**: switch to the local system.
- **A scan will not read**: type the scan address (above), or pick the
  building and room by hand.

## Questions the panel may ask

| Question | Answer, and where it is written |
|---|---|
| Does a phone get a notification when the app is closed? | Not yet: that needs a server to send it (Cloud Functions, on Firebase's paid Blaze plan). In-app alerts and notifications while the app is open work. docs/architecture_decisions.md §16 |
| Which priority weights are used? | The §3.4 formula's (0.40, 0.30, 0.20, 0.10). Table 3.2's are stored too, and GSU can switch in Settings. The manuscript says the criteria are subject to GSU's endorsement. |
| Who rates severity and safety risk? | The administrator, when reviewing the report; the requestor only chooses an urgency. docs/architecture_decisions.md §18 |
| Can someone give themselves admin rights? | No. Only an administrator assigns roles, and the database checks every change. `supabase/tests/permission_matrix.test.sql` |
| How do you know stock is right? | Stock changes only through the ledger, when the accomplishment report is filed or a delivery or count is recorded. `stock_ledger.test.sql` |
| How was it tested? | docs/testing.md: every requirement and the tests that prove it. |
