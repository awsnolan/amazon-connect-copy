# Backlog

Items for future consideration. Not prioritised.

---

## Considered — Not Planned

Items evaluated and intentionally excluded from the roadmap.

### Scheduled Backup with S3 Storage (standalone)

**Status:** Superseded by CI/CD pipeline (`examples/codebuild/dr-validate-pipeline/`).
The pipeline backs up daily to S3 with 7-day lifecycle retention. A standalone
backup-only wrapper adds no value beyond what the pipeline already provides.

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

---

## Cases & Customer Profiles Config Restore Automation

**Problem:** Cases and Customer Profiles config (schemas, field definitions,
object types, layouts, templates, calculated attributes) are backed up but
restore is manual. Operators must recreate domain structures by hand on the DR
instance.

**What's in scope (config only):**

| Feature | Config to restore |
|---------|-------------------|
| Cases | CreateDomain → BatchCreateField → CreateLayout → CreateTemplate (with ID remapping) |
| Customer Profiles | CreateDomain → PutProfileObjectType → CreateCalculatedAttributeDefinition |

**What's permanently out of scope (data):**
- Case records (individual cases filed by agents)
- Profile records (customer data, merged profiles, interaction history)
- Identity resolution ML state (instance-specific merge graphs)

**Rationale for excluding data:**
- Volume: millions of records, not a "minutes to failover" operation
- Freshness: stale immediately after backup
- Source of truth is elsewhere: profiles come from CRM via AppFlow, cases resume on failback
- Design principle: toolkit optimises for RTO, not data completeness

**Operational expectation during DR:**
- Cases: agents take notes, file cases on failback
- Customer Profiles: flows reference profiles via error paths; data re-ingests
  once AppFlow integrations are reconnected on DR instance

**Implementation:**
1. Add Customer Profiles backup (ListDomains, GetDomain, ListProfileObjectTypes,
   GetProfileObjectType, ListCalculatedAttributes, GetCalculatedAttributeDefinition)
2. Add Cases + Customer Profiles config restore logic
3. Update README/DR_OPERATOR_GUIDE with Customer Profiles in feature tables
4. Add validation layer (domain exists, object types match, calculated attributes match)
5. Add profile:* permissions to backup IAM profile

**Note:** External integrations (AppFlow OAuth connections) require manual
reconnection even with config automation — OAuth tokens are not portable.

See `.kiro/steering/customer-profiles-decision.md` for full rationale.
