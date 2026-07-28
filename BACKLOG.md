# Backlog

No outstanding items. All backlog items have been implemented or explicitly excluded.

---

## Completed

| Item | Implemented in |
|------|----------------|
| User Provisioning Helper | `--create-users` flag on `connect_restore` (Phase 2) |
| Smart Validate Messaging | Auto-detect pre/post restore context in results (Phase 1) |
| Consistent Output Styling | Numbered headers + summaries across all scripts (Phase 3) |
| Lex Bot Preflight Contradiction | Process substitution fix + name-based fallback (Phase 1) |
| Predefined Attributes: WARN not FAIL | `connect:*` prefix → WARN (Phase 1) |
| Dry-Run View Content Dump | Show name + size, not full JSON (Phase 2) |
| Cases & Customer Profiles Config Restore | Full config backup/plan/restore/validate (Phase 4) |

---

## Considered — Not Planned

Items evaluated and intentionally excluded from the roadmap.

### Scheduled Backup with S3 Storage (standalone)

**Status:** Superseded by CI/CD pipeline (`examples/codebuild/dr-validate-pipeline/`).
The pipeline backs up daily to S3 with 7-day lifecycle retention. A standalone
backup-only wrapper adds no value beyond what the pipeline already provides.

### Case Record / Profile Data Migration

**Status:** Permanently out of scope. Case records and customer profile data are
operational data (millions of records, immediately stale, sourced from external
CRMs). See `.kiro/steering/customer-profiles-decision.md` for full rationale.
