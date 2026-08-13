# Fabric Workspace Governance Automation — Project README

**Project:** Fabric-Monitoring-POC
**Owner:** Suryadev Rathore
**Workspace:** MS Fabric Demo (`<WORKSPACE_ID>`)
**Governance admin (report recipient):** <ADMIN_EMAIL>
**Status:** In testing (notification-only; auto-delete disabled)

---

## 1. What this project does

This is an automated governance system for Microsoft Fabric workspaces. It answers a simple
question that gets harder to answer as a workspace grows: **what's in here, what's actually being
used, and what can safely be cleaned up?**

The system runs on a schedule and:

1. **Scans** every item in one or more Fabric workspaces (notebooks, semantic models, reports,
   pipelines, lakehouses, warehouses, dashboards, and 20+ other types).
2. **Enriches** each item with ownership, creation/modification dates, and — critically —
   *genuine usage data* (who actually viewed or ran it), not just when it was last edited.
3. **Scores** each item for cleanup risk using six governance signals.
4. **Tracks** cleanup candidates through a 3-strike warning lifecycle.
5. **Notifies** item owners with professional Xebia-branded HTML emails, escalating in tone
   across three warnings.
6. **Deletes** items automatically only after 3 warnings with no owner action — behind multiple
   safety gates.
7. **Reports** the whole picture to a governance admin in a dashboard email each run.

Everything is auditable, configurable without code changes, and safe by default (deletion is
off until explicitly enabled).

---

## 2. The core principle: "Last Modified ≠ Last Used"

This distinction is the reason the project exists and shapes its whole design.

- **Last Modified** — when an item's definition was last edited. Easy to get from the API, but
  misleading: a report can be viewed 500 times a day and never modified.
- **Last Used** — when someone actually accessed, viewed, or ran the item. This is the real
  signal of value, and it only comes from the Power BI Activity Events API.

The system captures both independently and never treats one as a proxy for the other. An item is
only flagged "stale" when it's inactive on *both* signals (where usage data exists).

---

## 3. Folder structure

```
Fabric-Monitoring-POC/
├── README                          (this document, as a markdown notebook)
│
├── Analysis/
│   └── Fabric_Inventory_Analysis_Queries    15 ad-hoc SQL queries for exploring the data
│
├── Archive/                        (superseded versions — kept for history, not run)
│   ├── 01_Fabric_Workspace_Inventory_CoreAdminAPI       first attempt: REST API only
│   ├── 02_Fabric_Workspace_Inventory_SemanticLinkLabs   first attempt: Scanner API only
│   ├── Fabric_Workspace_Inventory_v3                     merged approach, early
│   ├── Fabric_Workspace_Inventory_v3.1                   + activity events fixes
│   ├── Fabric_Workspace_Inventory_v3.2                   + all field/serialization fixes
│   ├── Governance_Mark_Emails_Sent                       replaced by a Script activity in the pipeline
│   └── Test_Outlook                                      throwaway email-delivery test
│
├── Governance/                     (the automation engine — 5 notebooks)
│   ├── Governance_Table_Setup            creates the Governance schema + tables in DW_Fabric (run once)
│   ├── Governance_Tracker_Update         escalation logic (the brain)
│   ├── Governance_Email_Generator        builds HTML emails
│   ├── Governance_Auto_Delete            deletes items past 3 warnings
│   └── Governance_Failure_Notifier       builds a pipeline-failure alert email (called on activity failure)
│
├── Inventory/
│   └── Fabric_Workspace_Inventory_v4     CURRENT scanner (multi-workspace)
│
└── Pipeline/
    ├── PL_Inventory_Governance            main pipeline — orchestrates everything, on a schedule
    └── PL_Send_Failure_Alert              child pipeline — delivers one failure alert email, called by PL_Inventory_Governance
```

---

## 4. Notebooks — what each one does

### 4.1 Current / active notebooks

#### `Fabric_Workspace_Inventory_v4` (Inventory/)
**The scanner.** Reads the live workspace(s) and produces the raw inventory.

- **Reads from:** 5 live APIs
  - Core Items API (`/v1/workspaces/{id}/items`) — item list
  - Admin Items API (`/v1/admin/items`) — owner, last-modified, state, capacity
  - Scanner API (`semantic-link-labs scan_workspaces()`) — created date, modified-by
  - Activity Events API (`api.powerbi.com/.../admin/activityevents`) — genuine usage
  - Unused Artifacts (`semantic-link-labs list_unused_artifacts()`) — Power BI unused flag + dates
- **Writes to:** `workspace_inventory_snapshot`
- **Permission:** **Fabric Admin** (the only notebook that needs it)
- **Multi-workspace:** reads `workspace_ids` from `governance_config` (comma-separated),
  loops each one, computes governance flags *per workspace* so items in one workspace aren't
  matched against another.
- **Output:** 27 columns per item, one `snapshot_id` per run.
- **Runtime:** ~2 min per workspace (most of it the 30-day Activity Events walk).

#### `Governance_Table_Setup` (Governance/)
**Run once.** Creates the `Governance` schema and all governance tables in the `DW_Fabric`
Warehouse, and seeds default config.

- **Reads from:** nothing (except the Xebia logo PNG, read from the attached Lakehouse's Files
  area — Warehouses have no Files area, so a Lakehouse still needs to be attached for that one
  read)
- **Writes to:** `Governance.cleanup_tracker`, `Governance.cleanup_audit_log`,
  `Governance.email_outbox`, `Governance.governance_config`,
  `Governance.workspace_inventory_snapshot`, `Governance.deleted_items_archive`
- **Permission:** Contributor on `DW_Fabric`
- **Note:** don't re-run to reset data — it drops and recreates every table, wiping
  `governance_config` (logo, test-mode setting) and all tracked history. Use targeted
  `DELETE`/`UPDATE` statements instead.

#### `Governance_Tracker_Update` (Governance/)
**The brain.** Decides what happens to each item this run.

- **Reads from:** `workspace_inventory_snapshot` (latest), `cleanup_tracker`, `governance_config`
- **Writes to:** `cleanup_tracker`, `cleanup_audit_log`
- **Permission:** Contributor (pure Warehouse SQL operations, no APIs)
- **Logic, each run:**
  - **New candidates** — items scoring ≥ threshold, not yet tracked → added as `new`
  - **Resolved** — tracked items the owner acted on (modified, used, deleted, or score dropped)
    → marked `resolved`
  - **Escalations** — tracked items past the warning interval → bumped `new` → `warning_1` →
    `warning_2` → `warning_3`
  - **Deletion-ready** — items past `warning_3` → marked `deletion_ready`
  - **Protected / active-guard skips** — protected types and recently-active items are excluded

#### `Governance_Email_Generator` (Governance/)
**Builds the emails.** Generates Xebia-branded HTML and queues it.

- **Reads from:** `workspace_inventory_snapshot`, `cleanup_tracker`, `governance_config`
- **Writes to:** `email_outbox`
- **Permission:** Contributor
- **Produces:**
  - 1 **admin dashboard** email (KPIs, usage bar, warning pipeline, top candidates, owner table)
  - N **owner warning** emails (grouped by owner, tone escalates by warning level)
  - **Orphan** emails — ownerless items routed to the admin so nothing is deleted silently
  - **Deletion confirmation** emails (when items were deleted)
- **Test mode:** if `test_mode_recipient` is set, ALL emails redirect there with a
  `[TEST -> original@addr]` subject prefix.

#### `Governance_Auto_Delete` (Governance/)
**The enforcer.** Deletes items that completed the warning cycle.

- **Reads from:** `cleanup_tracker`, `governance_config`, `workspace_inventory_snapshot`
- **Calls:** `DELETE /v1/workspaces/{id}/items/{id}`
- **Writes to:** `cleanup_tracker`, `cleanup_audit_log`, `email_outbox` (confirmations)
- **Permission:** Contributor/Admin **on each target workspace** (separate from Fabric Admin)
- **8 safety gates** (all must pass): auto-delete enabled, dry-run off, not first run,
  status = deletion_ready, type not protected, id not protected, item still exists,
  active-item guard re-check.

#### `Governance_Failure_Notifier` (Governance/)
**Called on failure, not on a schedule.** The pipeline attaches this notebook to 8 critical
activities (5 governance notebooks + the 3 owner/admin/deletion email send-loops) via a
`dependsOn: [Failed]` branch, so it only ever runs when something breaks.

- **Reads from:** `governance_config` (for the recipient + logo)
- **Writes to:** `email_outbox` (`email_type="pipeline_failure_alert"`)
- **Permission:** Contributor
- **Parameters (injected by the pipeline):** `activity_name`, `error_message`, `pipeline_name`,
  `run_id`, `workspace_id`
- **One alert per failed activity per run.** For a failed `ForEach` send-loop, this reports the
  loop failing as a whole — not which specific recipient's send failed. Check `email_outbox` for
  `status='pending'` rows from the same `pipeline_run_id` to see who didn't get sent.

#### `Fabric_Inventory_Analysis_Queries` (Analysis/)
**Ad-hoc exploration.** 15 standalone SQL queries — not part of the pipeline.

- Workspace overview, ownership, usage categories, most-accessed items, stale age bands,
  top cleanup candidates, orphans, unused artifacts, duplicates, no-owner items, safe-to-keep
  list, creation timeline, modifier activity, governance scorecard, lakehouse ecosystem.
- Run any cell independently against the latest snapshot.

**Where did `Governance_Mark_Emails_Sent` go?** It's archived — see 4.2. Once its logic was
simplified down to a single `UPDATE` + `DELETE` (no Python left at all), running it as a
`TridentNotebook` pipeline activity meant paying Spark session start-up cost for two SQL
statements, and it inherited the same notebook-execution-identity issues affecting every other
`TridentNotebook` activity in the pipeline (see `PL_Inventory_Governance`'s `Mark Emails Sent`
activity, now a native **Script** activity running directly against `DW_Fabric`, no notebook
involved).

### 4.2 Archived notebooks (history — not run)

| Notebook | What it was | Why archived |
|---|---|---|
| `01_..._CoreAdminAPI` | First scanner, REST API only | Missing created_date, modified_by, usage |
| `02_..._SemanticLinkLabs` | First scanner, Scanner API only | Inconsistent type names, null IDs, noise |
| `Fabric_Workspace_Inventory_v3` | Merged both approaches | Activity Events returned 0 (wrong endpoint) |
| `Fabric_Workspace_Inventory_v3.1` | Fixed the endpoint | Bool→NaN serialization, Scanner dict issues |
| `Fabric_Workspace_Inventory_v3.2` | All single-workspace fixes working | Superseded by v4 (multi-workspace) |
| `Governance_Mark_Emails_Sent` | Flipped outbox rows `pending`→`sent`, purged 30-day-old rows | Down to 2 SQL statements — replaced by a native pipeline `Script` activity, no Spark session needed |
| `Test_Outlook` | One-activity email test | Purpose served (confirmed Outlook works) |

**The evolution in one line:** two separate proof-of-concepts → merged (v3) → endpoint fixes
(v3.1) → serialization + field fixes (v3.2) → multi-workspace (v4).

---

## 5. Governance tables — what each one holds

All tables live in the `Governance` schema of the `DW_Fabric` Warehouse (migrated from the
original `LK_Fabric` Lakehouse/Delta implementation — every notebook now connects via raw
`pyodbc` + an AAD token instead of `spark.sql`, and every column is `VARCHAR` to match the
original string-everywhere convention — Fabric Data Warehouse does not support `NVARCHAR`/`NCHAR`
at all; it stores Unicode text in `VARCHAR` columns under a UTF-8 collation instead).

### `workspace_inventory_snapshot`
The raw inventory. One row per item per scan. Appended each run (history preserved via
`snapshot_id`). **27 columns:**

| Group | Columns |
|---|---|
| Identity | id, name, type, description, web_url |
| Workspace | workspace_id, workspace_name, capacity_id |
| Ownership | created_by, modified_by |
| Dates | created_date, last_modified |
| Usage | last_used_date, access_count_30d, unique_users_30d, is_unused_artifact |
| Computed | days_since_modified, days_since_last_used |
| Governance | state, is_stale, has_missing_owner, is_duplicate_name, is_orphaned_model, is_orphaned_endpoint, cleanup_candidate_score |
| Snapshot | snapshot_id, snapshot_time_utc |

### `cleanup_tracker`
The warning lifecycle state — one row per item ever flagged. This is the memory that persists
between runs.

Key columns: item_id, item_name, item_type, owner_email, cleanup_score, warning_count,
warning_1_date / warning_2_date / warning_3_date, **status**, first_flagged_date,
resolved_date, deleted_date, workspace_id, **deletion_notified**.

**status values:** `new` → `warning_1` → `warning_2` → `warning_3` → `deletion_ready` →
`deleted`, plus `resolved` (owner acted) and `exempted` (protected).

**deletion_notified:** `"true"` once `Governance_Email_Generator` has sent the deletion
confirmation for this item — `Governance_Auto_Delete` no longer sends that email itself (it used
to, via a separate inline template; that duplication was removed). Without this flag, every
future run would re-notify the owner about deletions from runs ago, since this table holds every
item ever tracked, not just this run's.

### `cleanup_audit_log`
Immutable append-only log of every action. Never overwritten.

Columns: audit_id, timestamp, pipeline_run_id, item_id, item_name, item_type, owner_email,
**action**, detail, workspace_id.

**action values:** candidate_flagged, warning_1_sent, warning_2_sent, warning_3_sent,
owner_resolved, deletion_ready, auto_deleted, deletion_skipped, deletion_failed, exempted.

### `email_outbox`
The queue between notebooks (which generate emails) and the pipeline (which sends them).

Columns: email_id, pipeline_run_id, email_type, recipient, subject, body_html, **status**,
created_at, workspace_id.

**email_type values:** admin_report, owner_warning_1/2/3, orphan_warning_1/2/3,
deletion_confirmation, **pipeline_failure_alert**.
**status values:** pending → sent (or failed). `pipeline_failure_alert` rows are fire-and-forget —
they're never run through the `Mark Emails Sent` Script activity, since that step only runs at
the end of a *successful* main chain, which may not be reached if something failed.

### `deleted_items_archive`
Full metadata snapshot of every item, written by `Governance_Auto_Delete` **immediately before**
the actual DELETE API call — the technical backing for the "contact the administrator within 48
hours" recovery window promised in the deletion-confirmation email. Append-only, one row per item
per deletion.

Columns: item_id, item_name, item_type, workspace_id, workspace_name, owner_email, description,
web_url, created_date, last_modified, last_used_date, cleanup_candidate_score, and all governance
flags (is_stale, is_unused_artifact, has_missing_owner, is_duplicate_name, is_orphaned_model,
is_orphaned_endpoint), plus warning_1/2/3_date, deleted_by_pipeline_run_id, archived_at.

### `governance_config`
Key-value configuration. Change behaviour here, never in code.

| Key | Default | Meaning |
|---|---|---|
| cleanup_score_threshold | 30 | Min score to enter the cleanup workflow |
| stale_cutoff_days | 90 | Days of inactivity to flag as stale |
| warnings_before_delete | 3 | Warnings before deletion |
| days_between_warnings | 1 | Min days between warnings (1=testing, 7=production) |
| admin_email | <ADMIN_EMAIL> | Dashboard recipient |
| protected_types | Lakehouse,Warehouse,Environment,SQLEndpoint | Never auto-deleted |
| protected_items | (empty) | Specific item IDs never deleted |
| enable_auto_delete | false | Master delete switch |
| dry_run | true | Simulate deletes without executing |
| workspace_ids | <WORKSPACE_ID> | Comma-separated workspaces to scan |
| test_mode_recipient | (empty) | Redirect ALL emails here for testing (blank to disable) |
| logo_url | (base64) | Xebia logo embedded in emails |
| pipeline_failure_notify_email | (empty) | Recipient for pipeline activity-failure alerts (blank = falls back to admin_email) |

---

## 6. The cleanup candidate score (0–100)

Each item accumulates points from six signals. Higher = stronger deletion candidate.

| Signal | Points | Source |
|---|---|---|
| is_stale | +30 | Computed (inactive on both modification and usage) |
| is_unused_artifact | +25 | Power BI usage telemetry (confirmed, not inferred) |
| has_missing_owner | +15 | No creator on record |
| is_duplicate_name | +10 | Same name+type appears >1 time in the workspace |
| is_orphaned (model or endpoint) | +10 | Model with no report / endpoint with no parent |
| very old (>180 days modified) | +10 | Computed |

- **≥ 50 = high risk**, **30–49 = medium risk**, **< 30 = not tracked.**
- An item flagged **both stale and unused** starts at 55 — the strongest signal, since it's both
  untouched and confirmed unopened.

---

## 7. The pipeline — `PL_Inventory_Governance`

Orchestrates the notebooks and sends emails on a schedule.

```
Run Inventory Scan          [DEACTIVATED during testing — needs Fabric Admin]
  └→ Run Tracker Update
       └→ Generate Emails
            ├→ Lookup Admin Emails    (targeted SQL: email_type='admin_report' AND status='pending')
            │     └→ For Each Admin → Send Admin Report
            └→ Lookup Owner Emails    (targeted SQL: owner_warning*/orphan_warning* AND status='pending')
                  └→ For Each Owner → Send Owner Email
                        (both branches above run in parallel — no dependency between them)
                             └→ Lookup Auto Delete Flag   (targeted SQL: config_key='enable_auto_delete')
                                  └→ Check Auto Delete Enabled
                                       ├ True: Run Auto Delete
                                       └ False: (empty)
                                       └→ Lookup Deletion Emails  (targeted SQL: email_type IN (deletion_confirmation,
                                                                    deletion_manual_action_required, deletion_summary_admin) AND status='pending')
                                            └→ For Each Deletion → Send Deletion Email
                                                 └→ Mark Emails Sent  (Script activity — UPDATE + DELETE against DW_Fabric,
                                                                        no longer a notebook)
```

**Warehouse Lookups, not Lakehouse + Filter.** Since the backend moved to `DW_Fabric`, every
Lookup now runs a targeted `DataWarehouseSource` SQL query directly against
`Governance.email_outbox` / `Governance.governance_config`, instead of reading the whole table
and narrowing it in memory with a separate `Filter` activity. This collapsed 4 `Lookup + Filter`
pairs down to 4 plain Lookups, and let `Lookup Admin Emails`/`Lookup Owner Emails` run in
parallel (previously the single shared `Lookup Outbox` forced the admin and owner branches to
run one after another). `Check Auto Delete Enabled` now waits on **both** parallel branches
completing before it runs, since it used to depend only on `For Each Owner` back when Owner ran
strictly after Admin.

> ⚠️ **Run Inventory Scan starts deactivated** (`"state": "Inactive"`) since it needs Fabric
> Admin. Activating it is a deliberate decision, not a config step you're expected to flip during
> setup — leave it off until you're ready to scan the real workspace.

**Failure alerts:** every governance activity, plus the 3 owner/admin/deletion email send-loops,
has a parallel failure branch: `[Activity] --(Failed)--> Send Failure Alert (Invoke pipeline)`.
Unlike an earlier design, there is **no per-activity notebook** in the main pipeline anymore —
each branch is a single `InvokePipeline` call straight off the source activity's `Failed`
condition, passing `activity_name`/`error_message`/`pipeline_name`/`run_id`/`workspace_id` as
parameters. All the actual notebook work happens **once**, inside the child pipeline itself:
`PL_Send_Failure_Alert` runs `Notify Failure` (→ `Governance_Failure_Notifier`, which builds the
branded HTML and writes one row to `email_outbox`, then exits with that row's `email_id`) →
`Lookup Outbox` (targeted Warehouse query for `status='pending'`) → `Filter Alert` → `For Each
Alert` → `Send Office365Email`. `Filter Alert` is the one remaining `Lookup + Filter` pair in the
project — it narrows to the exact dynamic `email_id` returned by `Notify Failure`, which needs
the pipeline's own expression engine, not a static SQL `WHERE` clause, so it wasn't folded into
the Lookup like the others. Collapsing the per-activity notebook into the child pipeline (instead
of duplicating it 8 times across the main canvas) also means every `TridentNotebook` activity's
parameters into `Notify Failure` must use Fabric's double-nested `{"value": {"value":
"@pipeline().parameters.X", "type": "Expression"}, "type": "string"}` form for dynamic content —
a single-wrapped form silently stringifies the raw parameter object instead of evaluating it,
which showed up as a `String or binary data would be truncated` error on the `workspace_id`
column the first time this was wired up.

**A note on `TridentNotebook` execution identity:** a notebook run interactively (by opening it
and clicking Run) authenticates as *you*. The same notebook run as a pipeline activity does
**not** — it authenticates as whatever's bound to that activity's connection, which for a
`Notebook`-type Fabric connection can only ever be **Service principal** or **Workspace
identity**, never a real delegated user session, regardless of what the connection's own
properties page shows. This is why `Governance_Auto_Delete` can succeed manually and still fail
with 401/403 on `Dataflow`/RTI items when triggered by the pipeline — confirmed by decoding the
acquired token's JWT claims (`idtyp: app` vs `idtyp: user`, different `oid`/`appid` entirely) in
both execution contexts. The durable fix is a properly-scoped Service Principal added to the
target workspace(s) with real membership, not chasing this as a code bug.

**A note on why `Mark Emails Sent` is a `Script` activity, not a notebook:** once its logic was
down to a single `UPDATE` + `DELETE`, running it as a `TridentNotebook` meant paying Spark
session start-up cost for two SQL statements *and* inheriting the identity issue above. A native
`Script` activity runs the same SQL directly against `DW_Fabric` via the pipeline's own Warehouse
connection — no Spark session, no notebook-identity ambiguity. Worth considering for any other
notebook step that's shrunk down to pure SQL with no real Python logic left.

This whole failure-alert flow lives in its own child pipeline rather than inline in the main one
so the same delivery logic isn't duplicated 8 times across the main canvas. It fires
independently of the main success chain, so one activity's failure never blocks another's alert,
and it works no matter where in the pipeline the failure happened. Filtering on the specific
`email_id` (not just the run ID) matters because if two activities fail in the same run,
`Notify Failure` writes a separate outbox row each time it's invoked — without matching on the
exact `email_id`, the child pipeline would re-match every alert from that run and send
duplicates. One email per failure event — see `Governance/Governance_Failure_Notifier.ipynb` for
what it contains and its limitations (a failed `ForEach` reports the loop failing as a whole, not
which specific recipient's send failed). Recipient is `pipeline_failure_notify_email` in
`governance_config` (falls back to `admin_email` if blank).

**Key design decisions:**
- **Notebooks generate, pipeline delivers.** Emails are built by notebooks and written to
  `email_outbox`; the pipeline reads them and sends via the Office 365 Outlook activity. No email
  credentials live in notebooks.
- **Targeted SQL Lookups, not Table mode + Filter.** The Warehouse connector supports Query mode,
  so each Lookup runs its own `WHERE`-scoped `sqlReaderQuery` directly against
  `Governance.email_outbox` instead of pulling the whole table and slicing it in memory.
- **ForEach can't nest in If.** The deletion-email chain sits at the top level after the If, gated
  implicitly (no deletions = empty Lookup result = no-op loop).
- **Deletion needs a second outbox read** — confirmation rows don't exist when the first read runs.

**Email delivery — two hard-won rules:**
1. The sending account needs a real Exchange Online mailbox. A `.onmicrosoft.com` demo account
   fails with `MailboxNotEnabledForRESTAPI`; a licensed `@xebia.com` mailbox works.
2. **Never set the Outlook Body field in the designer UI** — it corrupts expressions. Set all
   Outlook `to`/`subject`/`body` via **View → Edit JSON code**. The `body` must be a plain string
   starting with `@` (e.g. `@item().body_html`).

---

## 8. The warning lifecycle

```
Item scores ≥ 30
      │
      ▼
   Day 1: NEW ───────────── owner acts ──▶ RESOLVED (drops out)
      │ no action
      ▼
   Warning 1 (friendly) ─── owner acts ──▶ RESOLVED
      │ no action
      ▼
   Warning 2 (firm) ─────── owner acts ──▶ RESOLVED
      │ no action
      ▼
   Warning 3 (final) ────── owner acts ──▶ RESOLVED
      │ no action
      ▼
   AUTO-DELETE ──▶ item removed + confirmation email + audit entry
```

**Resolution is checked every run.** If an item was modified, used, deleted by the owner, or its
score dropped below threshold, it's marked `resolved` and leaves the cycle — even mid-warnings.

**Ownerless items** are routed to the admin instead of being silently escalated, so a human always
has a chance to intervene before deletion.

---

## 9. Safety mechanisms

Deletion is guarded by layers, all of which must clear:

1. `enable_auto_delete = true` (default false)
2. `dry_run = false` (default true — simulates without deleting)
3. Not the first/second pipeline run (needs audit history)
4. Item status = `deletion_ready` (survived all 3 warnings)
5. Item type not in `protected_types` (Lakehouses/Warehouses/etc. hold data)
6. Item id not in `protected_items`
7. Item still exists in the workspace (re-verified)
8. Active-item guard: not modified <14 days or used <30 days

Plus: every action is logged, deletion confirmation emails give a 48-hour recovery window, and the
whole system starts in notification-only mode.

---

## 10. How to operate it

### First-time setup
1. Run `Governance_Table_Setup` once.
2. Save the Xebia logo and `test_mode_recipient` into `governance_config`.
3. Build/import `PL_Send_Failure_Alert` first, then `PL_Inventory_Governance` (which calls it), signing in on the Outlook activities in both.

### Normal testing cycle
```sql
-- Before a run, ensure the outbox is clean:
DELETE FROM email_outbox;

-- To walk the full escalation quickly, set interval to 0:
UPDATE governance_config SET config_value = '0' WHERE config_key = 'days_between_warnings';
```
Run the pipeline. Emails land with the tester (via `test_mode_recipient`).

### Reset the tracker for a fresh test
```sql
DELETE FROM cleanup_tracker;
DELETE FROM cleanup_audit_log;
DELETE FROM email_outbox;
-- next run rebuilds all candidates as 'new'
```

### Add more workspaces
```sql
UPDATE governance_config SET config_value = 'guid1,guid2,guid3' WHERE config_key = 'workspace_ids';
```
(Scanning is tenant-wide with Fabric Admin; deletion still needs rights per workspace.)

### Go to production
```sql
UPDATE governance_config SET config_value = '7'     WHERE config_key = 'days_between_warnings';
UPDATE governance_config SET config_value = ''      WHERE config_key = 'test_mode_recipient';   -- real owners
```
Then activate `Run Inventory Scan` in the pipeline and set a daily schedule.
Only when fully confident:
```sql
UPDATE governance_config SET config_value = 'true'  WHERE config_key = 'enable_auto_delete';
UPDATE governance_config SET config_value = 'false' WHERE config_key = 'dry_run';
```

### Emergency stop
```sql
UPDATE governance_config SET config_value = 'false' WHERE config_key = 'enable_auto_delete';
UPDATE governance_config SET config_value = 'true'  WHERE config_key = 'dry_run';
```

---

## 11. Known constraints & gotchas

- **Activity Events retention is ~28 days.** The oldest 2–3 days of a 30-day scan return HTTP 400.
  This is expected (retention boundary), handled gracefully, not an error. Run daily and persist to
  build longer history than the API retains.
- **Usage data covers Power BI item types only.** Notebooks, pipelines, lakehouses etc. get no
  Activity Events — for those, "stale" (modification-based) is the only signal available.
- **Booleans stored as int 1/0.** Fabric's display/CSV export turns Python `False` into `NaN`.
  All governance flags are stored as integers to survive serialization.
- **Fabric Admin needed only for the scan.** Everything downstream runs on Contributor. During
  testing the scan is deactivated and the existing snapshot is reused.
- **Moving notebooks between folders may change their GUID.** The pipeline references notebooks by
  GUID. If you reorganize folders, verify the pipeline's notebook IDs still match.
- **Outlook connection is user-bound.** Deploying the pipeline to another workspace needs
  re-authentication there. For production, use a shared mailbox/service account.
- **A stale token in a long-running notebook session can cause phantom 401s on delete —
  restart the session if you see this.** During testing, `Governance_Auto_Delete` 401'd on
  Notebook/Report/SemanticModel/DataPipeline/SparkJobDefinition/Reflex deletes despite the
  identity having full Workspace Admin and being able to delete the same items fine through
  the UI. Switching to a Fabric-audience token (`getToken("https://api.fabric.microsoft.com")`)
  was tried first and did **not** fix it — a red herring. The actual fix was restarting the
  notebook's session: a completely fresh `getToken("pbi")` call succeeded on every one of
  those 6 types, confirmed via a follow-up GET (not just trusting the DELETE status code).
  `Governance_Auto_Delete` uses `"pbi"` for exactly this reason — it's the audience that's
  actually confirmed to work, not the newer Fabric-audience one.
- **Dataflow deletion needs the classic Power BI Dataflow API, not the Fabric Items API at
  all.** Confirmed: Dataflows don't even appear in a `GET .../items` listing, and the generic
  `/items/{id}` DELETE always 400s (`OperationNotSupportedForItem`) — Dataflows still live in
  the classic Power BI backend, not Fabric's unified item catalog. `Governance_Auto_Delete`
  routes Dataflow deletes to `https://api.powerbi.com/v1.0/myorg/groups/{workspaceId}/dataflows/{dataflowId}`
  instead, confirmed working via a real test (list count dropped, target ID confirmed absent).
- **Eventhouse, Eventstream, and KQLDatabase cannot currently be auto-deleted at all —
  confirmed, not a session/token issue.** Even after the session-restart fix above resolved 6
  other types, these 3 still 401 consistently, same Admin identity, same fresh token. These
  three are architecturally coupled (Eventstream routes into Eventhouse, which contains KQL
  Databases) and likely sit behind a separate Real-Time Intelligence permission layer (KQL
  Database Admin/User/Viewer) independent of Fabric workspace roles — Reflex, despite also
  being RTI-family, isn't gated the same way and deletes fine. No code fix addresses this;
  `Governance_Auto_Delete`'s existing failure handling (reset to `warning_3`, retry next run,
  plus the `deletion_manual_action_required` owner email and `deletion_summary_admin` report)
  already covers this gracefully — these 3 types are effectively manual-deletion-only for now.

---

## 12. Operational notes

- **Outlook/Fabric connections are currently bound to one person's account** (see §11 above).
  This works fine for testing but is a real continuity risk for production — if that account is
  disabled or offboarded, the pipeline breaks. Move to a shared mailbox/service principal before
  relying on this in production.
- **Sanitize before pushing to a public repo.** Real tenant data (emails, workspace GUIDs, owner
  names) lives in these notebooks' source and, if they've been run, their saved cell outputs.
  Before publishing a copy anywhere public, strip saved outputs and replace those values with
  placeholders — don't publish the notebooks as-is.

## 13. Current state (as of this README)

- Single workspace (MS Fabric Demo), 461 items, 27 types.
- 60% stale, 30 high-risk, 38 confirmed-unused, 25 orphaned, 8 ownerless.
- Pipeline built and tested in notification-only mode; emails deliver correctly with Xebia
  branding; test-mode redirect active (all mail → Suryadev).
- Auto-delete built but disabled (both gates closed).
- v4 multi-workspace scanner uploaded, not yet activated in the pipeline.

**Next steps:** activate v4 scan → validate multi-workspace → run notification-only for a couple
of weeks → enable auto-delete → move to weekly production schedule.
