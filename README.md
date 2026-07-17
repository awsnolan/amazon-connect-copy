# Amazon Connect DR Toolkit

A set of bash scripts for backing up and restoring Amazon Connect instances.
Designed for Disaster Recovery — back up everything, restore to a fresh instance,
validate it works.

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

# 6. Validate everything
connect_validate -m full -p target-profile source-instance
```

## What Gets Backed Up and Restored

IDs and ARNs are re-mapped automatically during restore:

- Instance attributes and storage configs
- Hours of operations (including overrides)
- Queues (STANDARD type) with quick connect associations
- Routing profiles with queue associations
- Security profiles with permissions
- User hierarchy structure and groups
- Users with routing/security profile assignments
- Quick connects
- Contact flow modules
- Contact flows
- Phone numbers (flow associations)
- Agent statuses
- Predefined attributes
- Task templates
- Evaluation forms
- Rules
- Views
- Vocabularies
- Data tables
- Email addresses
- Cases (domains, fields, layouts, templates)
- Outbound campaigns
- External dependencies manifest (Lambda, Lex V2, Lex Classic)

## Installation

1. Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (2.9.4 or higher).
2. Install [jq](https://stedolan.github.io/jq/) (1.6 or higher).
3. Copy `bin/*` to your shell search path:
   ```bash
   cp bin/* /usr/local/bin/
   ```

## Legacy Name Aliases

These scripts were previously named `connect_save`, `connect_diff`, `connect_copy`.
If you have existing automation using the old names, create aliases:

```bash
alias connect_save='connect_backup'
alias connect_diff='connect_plan'
alias connect_copy='connect_restore'
```

Or symlinks:

```bash
ln -s /usr/local/bin/connect_backup /usr/local/bin/connect_save
ln -s /usr/local/bin/connect_plan /usr/local/bin/connect_diff
ln -s /usr/local/bin/connect_restore /usr/local/bin/connect_copy
```

## Validation Modes

```bash
# Local only — validate saved JSON files, no AWS calls
connect_validate -m local source-instance

# Live — compare backup against live instance via AWS APIs
connect_validate -m live -p profile source-instance

# Full — local + live (DR acceptance mode)
connect_validate -m full -p profile source-instance

# Smoke — full + functional tests (starts a test chat contact)
connect_validate -m smoke -p profile source-instance

# JSON output for CI/CD pipelines
connect_validate -m full -j -p profile source-instance
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

## DR Workflow

See [DR_VALIDATION_SPEC.md](./DR_VALIDATION_SPEC.md) for the full specification
of what "restored and ready for traffic" means — 18 validation layers covering
every resource type.

## Useful Tips

- The target Amazon Connect instance **must already exist and be ACTIVE** before
  running `connect_restore`. The script verifies this and aborts if the instance
  is not reachable. Things you must set up manually on the target:
  - Instance creation (console or API)
  - Identity provider / SSO configuration
  - Telephony (claim phone numbers or use Global Resiliency)
  - Domain verification for email (if used)
  - KMS key configuration (if using customer-managed keys)
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

## Contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md). PRs accepted on the *development* branch only.

## Status: Work in Progress

This is a v2.0.0 rewrite of the original Amazon-Connect-Copy tool, refactored
for Disaster Recovery use cases. The following work remains:

### To Do

- [ ] **Live testing** — Run against a real Amazon Connect instance to validate
  API response handling, edge cases, and permission requirements
- [ ] **Companion deps tool** (`connect_deps_backup` / `connect_deps_restore`) —
  Back up and restore Lambda function code, Lex bot definitions, and prompt
  audio files. Without this, a restored instance has correct config but broken
  flows. See DR_VALIDATION_SPEC.md for the full spec.
- [ ] **RELEASE.md update** — Document the v2.0.0 changes (rename, modular
  structure, DR validation suite, new resource types)
- [ ] **CI/CD pipeline integration** — Wire validate JSON output into automated
  DR runbooks to gate DNS failover decisions
- [ ] **Integration test harness** — Fixture-based test that runs the full
  backup → plan → restore → validate pipeline without a live instance

### Known Gaps

- `connect_restore` sections for Cases and Campaigns log manual actions rather
  than automating (these require external service setup)
- Flow content comparison in `connect_validate` (Layers 9.3 / 10.4) uses
  existence checks only — full normalized content diff is not yet implemented
- `connect_plan` does not yet modularize into lib/ (it's 900 lines, file-only,
  lower priority)
- Cross-reference integrity (Layer 17) reports pre-existing broken references
  (deleted flows still referenced by other flows) as FAIL — should downgrade to
  WARN when the target resource doesn't exist on the source instance either
  (pre-existing issue, not a DR risk)

### Bugs to fix (from live testing)

- Layer 0.5: Lambda permission check incorrectly fails despite permissions existing
  (policy parsing issue in validate — may need to handle `SourceArn` condition)
- Layer 1.2: Instance alias match prints twice (local + live both emit it)
- Layer 1.3: Instance attributes reports "none found" despite file existing
  (jq selector may not handle the multi-document format)
- Layer 14: Agent statuses, predefined attributes, and views report PASS with
  (0/N) counts — the live describe loop isn't executing (likely a jq/iteration issue
  with the manifest format)
- Layer 15: Cases domains should SKIP (not FAIL) when Cases feature isn't enabled
  and the saved file contains `[]`
- Layers 4, 5, 7, 8, 16: Live mode produces section headers but no test output
  (the live validation loops may not be executing)
- Layer 11: Phone numbers show "Flow target not found" errors but then reports
  SKIP — logic needs to report WARN or FAIL instead of SKIP when targets are broken

### Backlog (enhancements)

- ASCII colorizer: add unobtrusive single-line ASCII art to designate PASS/FAIL/WARN/SKIP
  results (green/red/yellow/grey). Opt-in by default, disable with `--no-color` flag.
  Use standard ANSI escape codes.
- Feature-enabled checks in `connect_backup`: before attempting to back up resources
  like Cases, Campaigns, or email, verify the feature is actually enabled on the
  instance. Store the enabled/disabled state so validate and restore can skip
  gracefully rather than failing on API errors for disabled features.
