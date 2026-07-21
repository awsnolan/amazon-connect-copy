# Amazon Connect DR Toolkit

Cold recovery scripts for Amazon Connect instances. Designed to get agents
answering calls in a DR region within minutes — not to replicate every managed
service feature.

## Scope: What This Toolkit Recovers

This toolkit restores **core telephony operations** — the components required for
agents to log in, receive contacts, and serve customers. It is designed for
**temporary failover** with the expectation that advanced features resume once the
source region recovers, or are manually configured if the DR instance becomes
permanent.

### Restored (agents can take calls)

- Contact flows, modules, and their internal references
- Queues, routing profiles, quick connects
- Hours of operations (including overrides)
- Security profiles and permissions
- User configurations (routing/security/hierarchy assignments)
- Agent statuses, views, evaluation forms, rules
- Lambda function code and associations
- Lex V2 bot associations
- Phone number → flow mappings (numbers must be pre-claimed)
- Instance attributes and storage configuration references

### NOT Restored (operate without during DR, or configure manually)

| Feature | Impact During DR | Path to Full Restoration |
|---------|-----------------|--------------------------|
| **Amazon Q in Connect / Wisdom** | Agents lose AI-suggested responses | Rebuild knowledge base from S3 sources + reassociate |
| **Contact Lens / Voice Analytics** | No real-time analytics, categories, or sentiment scoring | Re-enable instance attribute; rules and vocabulary backed up but models are AWS-managed |
| **Connect Forecasting** | No volume forecasts available | No export/import API; recreate forecasting groups manually |
| **Connect Scheduling** | No agent schedules generated | No export/import API; recreate scheduling config manually |
| **Outbound Campaigns** | No proactive outbound dialling | Campaign shell backed up; requires End User Messaging/SES + recipient source setup |
| **Connect Cases** | No case tracking for multi-touch issues | Domain/fields/layouts backed up; restore automation planned |
| **AI-powered Evaluations** | Manual evaluations still work; auto-evaluation paused | Evaluation forms restored; AI scoring models are AWS-managed |
| **Chat AI / Bot assistants** | Chat flows work; AI-enhanced features unavailable | Lex bots restored; Amazon Q assistants require separate setup |
| **Historical analytics / CTRs** | No historical data from source instance | Not portable; starts fresh on DR instance |
| **Forecasting/scheduling models** | Lose trained ML models | Models are AWS-managed; retrain from scratch on DR instance |

### Design Assumption

> **Fail over fast, fail back when ready.**
>
> This toolkit optimises for RTO (time to answer calls), not feature completeness.
> The DR instance handles live traffic with core routing while you either wait for
> the source region to recover or complete manual setup of advanced features.
>
> If a regional outage extends beyond your organisation's threshold, escalate from
> "temporary failover" to "permanent migration" using the manual steps in the
> [DR Operator Guide](./DR_OPERATOR_GUIDE.md).

---

## Scripts

| Script | Purpose |
|--------|---------|
| `connect_backup` | Export a live Amazon Connect instance to local files |
| `connect_plan` | Compare source backup vs target instance, produce a restore plan |
| `connect_restore` | Apply the plan — create/update components on the target instance |
| `connect_validate` | Verify the restored instance matches the backup (DR acceptance gate) |

## Quick Start

```bash
# 1. Back up the source instance
connect_backup -p source-profile source-instance

# 2. Back up the (empty/warm-standby) target instance
connect_backup -p target-profile target-instance

# 3. Plan the restore
connect_plan source-instance target-instance helper

# 4. Dry run (verify what will change)
connect_restore -d helper

# 5. Execute the restore
connect_restore helper

# 6. Validate the restore (cross-account)
connect_validate -m full --target <target-instance-id> source-instance
```

## What Gets Backed Up and Restored

IDs and ARNs are re-mapped automatically during restore. Resources are classified
by what the toolkit can fully automate versus what requires manual setup.

### Backed up and restored (automated)

| Resource | Restore behaviour |
|----------|-------------------|
| Instance attributes | Updated on target |
| Storage configs | Associated on target (pointing to original S3 buckets) |
| Hours of operations + overrides | Created/updated |
| Queues (STANDARD) + quick connect associations | Created/updated |
| Routing profiles + queue associations | Created/updated |
| Security profiles + permissions | New profiles created; updates flagged for manual review |
| User hierarchy structure + groups | Created |
| User configs (routing/security/hierarchy) | Updated on pre-existing users |
| Quick connects | Created/updated |
| Contact flow modules | Created/updated with ID remapping |
| Contact flows | Created/updated with ID remapping |
| Agent statuses | Created/updated |
| Predefined attributes | Created/updated (system-managed skipped) |
| Task templates | Created/updated |
| Evaluation forms | Created; updates flagged for manual review |
| Rules (Contact Lens, automation) | Created/updated |
| Views (agent workspace) | Created/updated |
| Vocabularies (Contact Lens) | Created on target |
| Data tables (structure + row data) | Created with full content |
| Phone number → flow mapping | Associated if number pre-claimed on target |
| Lambda function associations | Associated |
| Lex V2 bot associations | Associated |

### Backed up only (reference for validation and manual setup)

| Resource | Why not automated |
|----------|-------------------|
| Cases (domains, fields, layouts, templates) | Restore automation planned; currently operator must recreate |
| Outbound campaigns | Requires End User Messaging + recipient source configuration |
| Email addresses | Requires SES domain verification (days, not minutes) |
| External dependencies manifest | Informational; Lambda/Lex deployed via `connect_deps_restore` |

## Prerequisites

### Software
1. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (2.32 or higher)
2. [jq](https://stedolan.github.io/jq/) (1.6 or higher)
3. bash 4.0+ (macOS, Linux, CloudShell, WSL)

### Target Instance (before restore)
The target Amazon Connect instance **must already exist and be ACTIVE**. The
following must be set up manually before running `connect_restore`:

- Instance creation (console or `create-instance` API)
- Identity provider / SSO configuration
- Users pre-provisioned (see [User Identity Requirements](#user-identity-requirements))
- External dependencies deployed (Lambda, Lex bots) — use `connect_validate -m preflight` to verify
- Phone numbers claimed (cannot be transferred cross-account via API)
- Domain verification for email channel (if used)
- KMS key configuration (if using customer-managed keys)

### User Identity Requirements

**Users cannot be created cross-account by the restore script.** The `create-user`
API requires either a password (never available from backup) or a `DirectoryUserId`
(instance-specific, won't exist in the DR account).

Users must be pre-provisioned on the DR instance via:
- AWS IAM Identity Center sync (SCIM) — recommended for SSO instances
- Manual creation in the Connect console
- Separate identity automation

Once users exist on the target, `connect_restore` will update their configurations
(routing profile, security profile, hierarchy assignment). Username matching must
be exact, and the user must have instance access (appear in `list-users`, not just
exist in Identity Center).

Use `connect_validate -m preflight --target <id> <backup-dir>` to verify target
readiness before attempting restore.

## Installation

Copy `bin/*` to your shell search path:
```bash
cp -r bin/* /usr/local/bin/
```

## Validation Modes

```bash
# Preflight — check target readiness (instance active, deps available, credentials working)
connect_validate -m preflight --target <instance-id> source-backup-dir

# Local only — validate saved JSON files, no AWS calls
connect_validate -m local source-instance

# Full — compare backup against live instance (same-instance drift check)
connect_validate -m full -p profile source-instance

# Full cross-account — compare backup against a different target instance (DR acceptance)
connect_validate -m full --target <target-id> --target-profile dr-profile source-backup-dir

# JSON output for CI/CD pipelines
connect_validate -m full -j --target <target-id> source-backup-dir

# Selective — run only specific layers
connect_validate -m full --only 0,2,10 --target <target-id> source-backup-dir

# Skip layers
connect_validate -m full --skip 17 --target <target-id> source-backup-dir
```

## External Dependencies

Contact flows reference Lambda functions, Lex bots, and prompts. These are
**not Amazon Connect resources** — they must be deployed separately before
restoring the Connect instance.

`connect_backup` produces an `external_dependencies.json` manifest listing
every Lambda ARN, Lex V2 bot, and Lex Classic bot referenced by your flows.
Use this manifest to ensure dependencies exist in the target account before
running `connect_restore`.

`connect_validate` checks that all external dependencies are reachable
(Layer 0 of the validation suite). A missing Lambda means the instance
will fail on live calls.

## Cross-Account DR Workflow

```bash
# 1. Deploy external dependencies to DR account (Lambda, Lex, prompts)

# 2. Preflight check — verify target is ready
connect_validate -m preflight --target <target-id> source-backup-dir

# 3. Back up source and target
connect_backup -p source-profile source-instance
connect_backup -p target-profile target-instance

# 4. Plan and restore
connect_plan source-instance target-instance helper
connect_restore helper

# 5. Validate the restore
connect_validate -m full --target <target-id> source-backup-dir

# 6. Complete manual actions (phone numbers, users, security profiles)
# 7. Re-validate until PASS
```

See [DR_VALIDATION_SPEC.md](./DR_VALIDATION_SPEC.md) for the full specification
of what "restored and ready for traffic" means — 18 validation layers covering
every resource type.

## Useful Tips

- Do not reuse the target instance directory or helper directory between runs.
  Remove them after restoring.
- Both instances must remain unaltered during the entire process (backup, plan, restore).
- `connect_plan` only creates the helper directory — it never modifies instance files.
- `connect_restore` modifies the helper directory and (in non-dry-run mode) the target instance.
- If relative paths are used, run `connect_plan` and `connect_restore` from the same directory.
- All names in Amazon Connect are case sensitive.

## Required IAM Permissions

The restore profile needs these Connect actions:

```
connect:AssociateBot
connect:AssociateLambdaFunction
connect:AssociateLexBot
connect:AssociateQueueQuickConnects
connect:AssociateRoutingProfileQueues
connect:CreateContactFlow
connect:CreateContactFlowModule
connect:CreateHoursOfOperation
connect:CreateQueue
connect:CreateQuickConnect
connect:CreateRoutingProfile
connect:DeleteContactFlow
connect:DeleteContactFlowModule
connect:DeleteHoursOfOperation
connect:DeleteQuickConnect
connect:DescribeContactFlow
connect:DescribeContactFlowModule
connect:DescribeHoursOfOperation
connect:DescribeQueue
connect:DescribeQuickConnect
connect:DescribeRoutingProfile
connect:DisassociateRoutingProfileQueues
connect:ListContactFlowModules
connect:ListContactFlows
connect:ListHoursOfOperations
connect:ListInstances
connect:ListPhoneNumbers
connect:ListPrompts
connect:ListQueueQuickConnects
connect:ListQueues
connect:ListQuickConnects
connect:ListRoutingProfileQueues
connect:ListRoutingProfiles
connect:UpdateContactFlowContent
connect:UpdateContactFlowModuleContent
connect:UpdateHoursOfOperation
connect:UpdateQueueHoursOfOperation
connect:UpdateQueueOutboundCallerConfig
connect:UpdateQuickConnectConfig
connect:UpdateRoutingProfileConcurrency
connect:UpdateRoutingProfileDefaultOutboundQueue
```

The validate profile needs read-only access: `connect:Describe*`, `connect:List*`,
`connect:Search*`, plus `lambda:GetFunction`, `lambda:GetPolicy`,
`lex:DescribeBot`, `lex:DescribeBotAlias`.

## Legacy Name Aliases

These scripts were previously named `connect_save`, `connect_diff`, `connect_copy`.
If you have existing automation using the old names:

```bash
alias connect_save='connect_backup'
alias connect_diff='connect_plan'
alias connect_copy='connect_restore'
```

## Contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md). PRs accepted on the *development* branch only.

---

## Roadmap

### Next

- [ ] **CI/CD pipeline integration** — wire validate JSON output into automated DR
  runbooks to gate DNS failover.
- [ ] **Scheduled backup automation** — CodeBuild on a schedule with S3 storage and
  lifecycle retention. See [BACKLOG.md](./BACKLOG.md).

### Known Limitations

- **Advanced features not restored** — Amazon Q, Contact Lens, Forecasting,
  Scheduling, and Campaigns require manual setup. See the scope table above.
- Cases domain restore is backed up but currently requires manual recreation
  (automation planned).
- Default security profiles (Admin, Agent, CallCenterManager) have per-instance
  defaults that intentionally differ — flagged for manual review.
- Phone numbers cannot be claimed cross-account via API — must be provisioned
  manually on the DR instance.
- Historical metrics, CTRs, and trained ML models are not portable between
  instances.

### Done

- [x] **User restore improvements** — `update-user-*` for pre-provisioned users,
  preflight username verification, skip missing users gracefully.
- [x] **`--user-password-file` escape hatch** — for same-account restores where
  `create-user` is viable. CSV maps usernames to passwords.
- [x] **Flow content normalized diff** (Layers 9.3/10.4) — verify restored flow
  content matches source after ID/ARN normalization.
- [x] **`connect_plan` modularisation** — split into `bin/lib/plan/*.sh` modules.
  Main script is <100 lines. `--only`/`--skip` flags work.
- [x] **`connect_validate` modularisation** — split into orchestrator +
  `bin/lib/validate/*.sh` per-layer files. 18 layers, 90%+ of DR spec covered.
- [x] **Verbose restore output** — `--verbose` flag shows API call detail in dry-run.
- [x] **Colour-wire restore output** — `C_PASS`/`C_FAIL`/`C_WARN`/`C_SKIP` on
  individual operation lines.
- [x] **CodeBuild buildspec updated** — v2.0.0 CLI conventions, preflight check,
  cross-account support, validation gate.
- [x] **Companion deps tool** (`connect_deps_backup` / `connect_deps_restore`) —
  Back up and restore Lambda function code, Lex bot definitions, and prompt audio files.
- [x] **Feature-enabled checks in backup** — skip disabled features (Cases, Campaigns,
  email) gracefully rather than erroring on API calls.
- [x] **ANSI colour output** — colour-coded ✓/✗/⚠/- with `--no-color` flag and
  `NO_COLOR` env var support. Auto-disables when piped.
- [x] **Consistent layered output** — all scripts use `section_header()` from
  `common.sh` with `━━━` style and timestamps.
- [x] **Integration test harness** — 122 offline tests covering syntax, CLI interface,
  local validation, plan correctness, SED remapping, same-instance regression, JSON
  output schema, dry-run verification, and edge cases. Live integration suite (6 tests)
  available with `--live` flag. See [tests/README.md](./tests/README.md).

- [x] **Remediation guide in validate output** — per-layer fix instructions with AWS
  documentation links, shown only on FAIL. Covers all 18 layers including critical
  callouts for users, phone numbers, and external dependencies.
