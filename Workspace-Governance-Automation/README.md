# Workspace Governance Automation

An automated governance system for Microsoft Fabric workspaces. It scans workspace items,
enriches them with ownership and genuine usage data (not just last-modified dates), scores
each item for cleanup risk, and tracks candidates through a 3-strike email warning lifecycle
before optionally auto-deleting — all behind multiple safety gates and off by default.

## What it does

1. **Scans** every item in one or more Fabric workspaces.
2. **Enriches** each item with ownership and usage signals (who actually viewed/ran it, not
   just when it was last edited).
3. **Scores** each item for cleanup risk using six governance signals.
4. **Tracks** cleanup candidates through a 3-strike warning lifecycle.
5. **Notifies** item owners via escalating emails.
6. **Deletes** items automatically only after 3 warnings with no owner action, behind multiple
   safety gates — disabled by default.
7. **Reports** the overall picture to a governance admin each run.

## Folder structure

```
Workspace-Governance-Automation/
├── Analysis/     ad-hoc SQL queries for exploring the inventory data
├── Archive/      superseded prototype versions, kept for history
├── Governance/   the automation engine (table setup, tracker, email generator, auto-delete, mark-sent)
├── Inventory/    the current multi-workspace scanner notebook
└── Pipeline/     orchestration pipeline definition
```

## Key design principle

An item's *last modified* date and its *last used* date are tracked independently — a report
can be viewed constantly and never edited. An item is only flagged for cleanup when it's
inactive on both signals (where usage data is available).

## Safety

Deletion is guarded by multiple independent gates (master switch, dry-run mode, protected
types/items, active-item re-checks) and starts fully disabled. Every action is logged.
