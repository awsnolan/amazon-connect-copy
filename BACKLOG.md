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
