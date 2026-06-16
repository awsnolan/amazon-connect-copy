# Amazon-Connect-Copy User Guide

Amazon-Connect-Copy (v1.5.0) copies components from a source Amazon Connect instance
to a target instance safely, remapping all internal IDs and ARN references automatically.

Use it to deploy an Amazon Connect instance across environments
(AWS accounts or regions), or to save a backup copy for restoration
when required — reducing an hours-long error-prone manual job to a few minutes of
automated and reliable processing.

## Tools in the Suite

| Tool | Purpose |
|------|---------|
| `connect_save` | Export an Amazon Connect instance to local JSON files |
| `connect_diff` | Compare source and target exports, produce helper files for copying |
| `connect_copy` | Apply changes from source to target using the helper files |
| `connect_validate` | Validate a saved instance directory (local JSON checks and/or live AWS comparison) |

## Components Handled

IDs and ARNs are re-mapped from source to target for all copied components.

### Saved, diffed, and copied

- Hours of Operations (including overrides)
- Queues (STANDARD type)
- Quick Connects
- Routing Profiles (including queue associations and concurrency)
- Contact Flow Modules
- Contact Flows
- Agent Statuses (CUSTOM type)
- Security Profiles (including permissions)
- Predefined Attributes
- Task Templates
- Evaluation Forms
- Rules (Contact Lens automation)
- Views (Agent Workspace)
- User Hierarchy Structure and Groups
- Users

### Saved and validated (not copied — informational)

- Instance Attributes (feature flags)
- Instance Storage Configs (S3/KMS destinations)
- Authentication Profiles
- Prompts (names only — audio files must be pre-uploaded)
- Phone Numbers (claimed numbers with flow associations)
- Vocabularies (custom vocabulary for Contact Lens)
- Data Tables (flow lookup tables)
- Integration Associations (Lex V2, Amazon Q, Voice ID, Cases)
- Approved Origins (CCP embed CORS)
- Security Keys
- Outbound Campaigns

### Pre-requisites (must exist on target before copying)

- Instance (pre-existing)
- Lambda functions (pre-deployed)
- Lex bots (pre-built)
- Prompts (pre-uploaded with matching names)

### Not affected by Amazon-Connect-Copy

- Phone number → Contact flow/IVR mappings
- Outbound caller ID number for queues
- Historical metrics and reports
- Contact Trace Records (CTRs)
- Amazon Connect service quotas

Amazon-Connect-Copy does not remove target instance components that are absent from
the source — it only creates or updates. This is by design for shared instances
hosting multiple contact centres.

## Installation

- Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  (version 2.15.0 or higher recommended).
- Install [jq](https://stedolan.github.io/jq/) version 1.6 or higher.
- Copy `bin/*` to your shell search path (e.g., `cp bin/* /usr/local/bin/`).

## Quick Start

**Replace names with your own instance aliases and AWS CLI profiles.**

```bash
# 1. Save the source instance (the one you want to copy FROM)
connect_save -p my-source-aws-profile -c CCC my-connect-dev

# 2. Save the target instance (the one you want to copy TO)
connect_save -p my-target-aws-profile -c CCC my-connect-prod

# 3. Diff: produces helper files for copying source → target
connect_diff my-connect-dev my-connect-prod helper

# 4. Validate saved data (optional)
connect_validate my-connect-dev
connect_validate -m live -p my-target-aws-profile my-connect-prod

# 5. Dry run (no changes made — review proposed actions)
connect_copy -d helper

# 6. Real run (applies changes to the target instance)
connect_copy helper
```

### What each argument means

- `my-connect-dev` / `my-connect-prod` — Amazon Connect instance aliases
  (the name shown in the Connect console). Also used as the directory name
  where `connect_save` stores exported data. You can pass a path instead
  (e.g., `./backups/my-connect-prod`) — the basename is used as the alias.
- `-p my-source-aws-profile` — an AWS CLI named profile (from `~/.aws/credentials`
  or `~/.aws/config`) that has permissions to access the Connect instance.
  Omit if your default profile already has access.
- `-c CCC` — limits the copy to contact flows and modules with names prefixed by
  `CCC` (your Contact Centre Code). Omit to copy all flows.
- `connect_diff` always takes the **source instance first** and the **target instance second**.
- `helper` — the directory where `connect_diff` stores its output, consumed by `connect_copy`.

## Detailed Process

Note: All names in Amazon Connect are case sensitive.

### Pre-steps

1. Ensure no one else is making changes to either instance during the process.
2. Deploy all Lambda functions required by the target instance.
3. Build all Lex bots required by the target instance.
4. Upload all required prompts to the target instance (names must match exactly).
5. For incremental updates with **name changes** to flows or modules:
   manually rename them in the target instance first. Otherwise, flows with new
   names are created and old-named flows are left untouched.

### Copying

1. Set up [named profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)
   for AWS CLI access (optional if your default profile has access to both instances).
2. `cd` to an empty working directory.
3. Run `connect_save` for both instances:
   ```
   connect_save -p <source_profile> -c <prefix> <source_instance>
   connect_save -p <target_profile> -c <prefix> <target_instance>
   ```
4. Run `connect_diff`:
   ```
   connect_diff <source_instance> <target_instance> <helper>
   ```
   Options: `-l source_lambda=target_lambda` and `-b source_bot=target_bot`
   for Lambda/Lex prefix substitution.
5. Review the helper directory:
   - `helper.new` — components to create (remove lines to skip)
   - `helper.old` — components to update (remove lines to skip)
   - `helper.sed` — SED script remapping source references to target
   - `helper.var` — variables identifying source and target instances
6. Dry run: `connect_copy -d <helper>` — review proposed changes.
7. Apply: `connect_copy <helper>`

### Validation (optional)

Run `connect_validate` to check saved data integrity before or after copying:
```
# Local only — validates JSON structure and cross-references
connect_validate <instance_dir>

# Live — compares saved files against the live AWS instance
connect_validate -m live -p <profile> <instance_dir>

# Both local and live checks
connect_validate -m full -p <profile> <instance_dir>
```

### Post-steps

- In the target instance console:
  - Check Phone Numbers → re-map to new Inbound Contact Flows if required.
  - Check Queues → set Outbound caller ID name/number and whisper flow for new queues.

## Backup and Restore

You can restore an Amazon Connect instance from a previous backup saved by `connect_save`.

```bash
# Backup — save a point-in-time snapshot
connect_save -p <profile> <backup_dir>/<instance_alias>

# Later — restore from backup:

# 1. Save the current (live) state
connect_save -p <profile> <current_dir>/<instance_alias>

# 2. Diff: backup = source (desired state), current = target (to be overwritten)
connect_diff <backup_dir>/<instance_alias> <current_dir>/<instance_alias> <helper_dir>

# 3. Dry run to verify
connect_copy -d <helper_dir>

# 4. Apply the restore
connect_copy <helper_dir>
```

## Tips

- **Don't reuse directories.** Remove the target instance directory and helper
  directory after copying. Re-run `connect_save` if you want a fresh backup.
- **Freeze both instances** during the entire save → diff → copy process.
- **`connect_diff` is read-only** — it only creates the helper directory.
- **`connect_copy` is not idempotent** — it modifies the helper directory and
  (in non-dry-run mode) the target instance.
- **Source is preserved** — `connect_diff` and `connect_copy` never modify the
  source directory, so it can serve as backup or be copied to multiple targets.
- **Relative paths** — run `connect_diff` and `connect_copy` from the same
  directory so relative paths resolve correctly.
- **Description field** — for Hours of Operations, flows, and modules, Description
  is required in the target. If missing in the source, the component name is used.

## Required IAM Permissions

Configure your AWS profile with a role authorised for these actions:

```
connect:AssociateBot
connect:AssociateLambdaFunction
connect:AssociateLexBot
connect:AssociatePhoneNumberContactFlow
connect:AssociateQueueQuickConnects
connect:AssociateRoutingProfileQueues
connect:CreateAgentStatus
connect:CreateContactFlow
connect:CreateContactFlowModule
connect:CreateEvaluationForm
connect:CreateHoursOfOperation
connect:CreateHoursOfOperationOverride
connect:CreatePredefinedAttribute
connect:CreateQueue
connect:CreateQuickConnect
connect:CreateRoutingProfile
connect:CreateRule
connect:CreateSecurityProfile
connect:CreateTaskTemplate
connect:CreateUser
connect:CreateUserHierarchyGroup
connect:CreateView
connect:DeleteContactFlow
connect:DeleteContactFlowModule
connect:DeleteHoursOfOperation
connect:DeleteQuickConnect
connect:DescribeAgentStatus
connect:DescribeAuthenticationProfile
connect:DescribeContactFlow
connect:DescribeContactFlowModule
connect:DescribeEvaluationForm
connect:DescribeHoursOfOperation
connect:DescribeInstance
connect:DescribeInstanceAttribute
connect:DescribePhoneNumber
connect:DescribePredefinedAttribute
connect:DescribeQueue
connect:DescribeQuickConnect
connect:DescribeRoutingProfile
connect:DescribeRule
connect:DescribeSecurityProfile
connect:DescribeUser
connect:DescribeUserHierarchyGroup
connect:DescribeUserHierarchyStructure
connect:DescribeView
connect:DescribeVocabulary
connect:DisassociateRoutingProfileQueues
connect:GetTaskTemplate
connect:ListAgentStatuses
connect:ListApprovedOrigins
connect:ListAuthenticationProfiles
connect:ListContactFlowModules
connect:ListContactFlows
connect:ListEvaluationForms
connect:ListHoursOfOperationOverrides
connect:ListHoursOfOperations
connect:ListInstanceStorageConfigs
connect:ListInstances
connect:ListIntegrationAssociations
connect:ListPhoneNumbersV2
connect:ListPredefinedAttributes
connect:ListPrompts
connect:ListQueueQuickConnects
connect:ListQueues
connect:ListQuickConnects
connect:ListRoutingProfileQueues
connect:ListRoutingProfiles
connect:ListRules
connect:ListSecurityProfilePermissions
connect:ListSecurityProfiles
connect:ListTaskTemplates
connect:ListUserHierarchyGroups
connect:ListUsers
connect:ListViews
connect:UpdateAgentStatus
connect:UpdateAuthenticationProfile
connect:UpdateContactFlowContent
connect:UpdateContactFlowMetadata
connect:UpdateContactFlowModuleContent
connect:UpdateContactFlowModuleMetadata
connect:UpdateHoursOfOperation
connect:UpdateInstanceAttribute
connect:UpdatePredefinedAttribute
connect:UpdateQuickConnectConfig
connect:UpdateRoutingProfileConcurrency
connect:UpdateRoutingProfileDefaultOutboundQueue
connect:UpdateRule
connect:UpdateTaskTemplate
connect:UpdateUserHierarchyStructure
connect:UpdateViewContent
```
