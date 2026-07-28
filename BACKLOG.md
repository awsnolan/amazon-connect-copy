# Backlog

Items for future consideration. Not prioritised.

---

## Scheduled Backup with S3 Storage

**Problem:** Operators running DR for production Connect instances need automated,
recurring backups stored durably — not just ad-hoc runs from a laptop.

**Scope:**
- Wrapper script or updated CodeBuild buildspec that runs `connect_backup` on a
  schedule (daily), uploads to S3 with date-stamped paths, and maintains a
  `latest/` pointer.
- S3 lifecycle rules for retention (e.g., 7 daily / 4 weekly / 3 monthly).
- Only overwrite `latest/` on successful backup (check exit code).
- Optional: run `connect_validate -m full -j` post-backup, publish result to
  CloudWatch custom metric or SNS for alerting on drift.

**Notes:**
- The scripts already work with plain directory paths — no code changes needed
  to the tools themselves. This is purely an orchestration/infrastructure item.
- Existing `examples/codebuild/buildspec.yml` uses the old CLI interface and
  needs updating to v2.0.0 conventions (--only/--skip, --target, --target-profile).
- CloudShell is viable for manual runs (all deps present) but not for scheduled
  automation — CodeBuild or Fargate scheduled task is the better fit.
- RPO consideration: daily backup means up to 24h of config changes could be lost.
  Operators with tighter RPO requirements would need more frequent runs.

**Not in scope:** Incremental/diff-based backups. Connect config is small enough
that full snapshots are fine.

---

## User Provisioning Helper

**Problem:** Operators must manually create users on the DR instance before restore
can assign their configurations. During a DR event this adds friction and RTO.

**Scope:**
- `--create-users` flag on `connect_restore` (or standalone `connect_provision_users`)
- Reads backed-up user list, creates missing users with temporary password + identity
  info from backup, then restore updates routing/security as normal
- For Connect-managed identity instances only (SSO instances use Identity Center)
- Clear warning: "These users have temporary passwords — change after failback"

---

## Smart Validate Messaging (pre-restore vs post-restore)

**Problem:** `connect_validate -m full` outputs "NOT ready for live traffic" regardless
of whether you've run restore yet. Before restore this is obvious and unhelpful; after
restore it's actionable.

**Scope:**
- Auto-detect context: if majority of failures are restorable (flow content, user configs,
  descriptions), message as "Run connect_restore to resolve X differences"
- If majority are manual (phone numbers, security profiles), message as "X items require
  operator action before live traffic"
- No new flags needed — detect from failure pattern

---

## Consistent Output Styling Across All Scripts

**Problem:** `connect_validate` has colour-coded ✓/✗, layer numbers, timestamps, and
a results summary. `connect_backup`, `connect_plan`, and `connect_restore` are
visually inconsistent — plain text, no progress indicators, no summary counts.

**Scope:**
- `connect_backup`: add section numbering (1/7, 2/7...), colour ✓ on exports,
  completion summary (resources exported, time, any skipped)
- `connect_plan`: add resource counts per type (X matched, Y new, Z to update),
  completion summary (total new/update/manual)
- `connect_restore`: apply colour consistently to all sections (not just users),
  suppress verbose JSON dumps in dry-run (show resource name + "changed" instead)
- All scripts: consistent use of `section_header()` with numbering

---

## Lex Bot Preflight Contradiction

**Problem:** Preflight reports `✗ MISSING: dr-test-MainMenu` for a Lex bot but then
prints "All external dependencies verified" — contradictory messaging.

**Scope:**
- Fix: if any dependency is MISSING, the summary line should say "X of Y dependencies
  missing" not "All verified"
- Check: the bot may actually exist but the lookup logic is using source IDs instead
  of name-based search

---

## Predefined Attributes: System-Managed Should Be WARN Not FAIL

**Problem:** Validate Layer 14B.2 reports FAIL for `connect:*` system-managed predefined
attribute value mismatches. These are AWS-managed and differ per instance by design —
operators cannot fix them.

**Scope:**
- Change from FAIL to WARN for attributes with `connect:` prefix
- Or skip them entirely in the comparison (they're already skipped in restore)

---

## Dry-Run View Content Dump

**Problem:** `connect_restore -d` dumps the entire view JSON content (including massive
dropdown option lists) into the terminal output. Unreadable and noisy.

**Scope:**
- In dry-run mode, show only: view name, "changed", content size
- Full content available in helper.log for debugging, not stdout
