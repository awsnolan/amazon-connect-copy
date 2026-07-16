# Release Notes

- Version 2.0.0 (2026-07-16)
  - **Breaking: Scripts renamed for DR clarity**
    - `connect_save` → `connect_backup`
    - `connect_diff` → `connect_plan`
    - `connect_copy` → `connect_restore`
    - `connect_validate` (unchanged name, rewritten)
  - **Modular architecture** — thin orchestrators + `bin/lib/` section files
    - `--only` and `--skip` flags on backup, restore, and validate
    - Shared helpers in `bin/lib/common.sh`
  - **New: connect_validate v2.0.0** — 18-layer DR validation suite
    - Local, live, full, and smoke modes
    - JSON output (`-j`) for CI/CD pipeline integration
    - Retry logic for transient AWS API errors
    - `--only`/`--skip` for iterating on specific layers
  - **New resource types backed up**
    - User proficiencies (skill levels per user)
    - Lambda function associations
    - Prompt details (describe-prompt per prompt)
    - Attachment configuration (file type/size settings)
    - CodeSha256 in external dependencies manifest
  - **Restore improvements**
    - Pre-flight: target instance reachability check (aborts if not ACTIVE)
    - Consolidated manual actions summary at end of restore
    - Removed scattered NOTE/WARNING interruptions from restore flow
  - **connect_plan expanded** to diff vocabularies, phone numbers, Lambda associations, attachment config (32 resource types total)
  - **Resilient API handling**
    - `describe_or_skip` helper for AWS-managed resources that can't be described
    - Null-safe jq iteration (`// []`) across all backup sections
  - **DR_VALIDATION_SPEC.md** — full specification document
  - **test-fixtures/** — SAM template deploying DynamoDB + Lambdas + Lex V2 bot + contact flow for integration testing
  - Legacy name aliases documented in README

- Version 1.3.5
  - Handle null component descriptions by setting the corresponding target description to the component name

- Version 1.3.4
  - Copy contact flow/module description
  - Amend README.md

- Version 1.3.3
  - Add `check_contact_flow()` to find broken references (missing components) in contact flows
  - Fix QueueConfigs limit issue when creating new routing profiles

- Version 1.3.2
  - Fix AWS CLI max 10 queue-configs in `aws connect associate-routing-profile-queues`
  - Fix QueueName select in RoutingProfileQueueConfigSummaryList
  - Remove routing_profile_to_ignore from connect_diff
  - Explicit with `.` in `jq -s '.'` (instead of just `jq -s`) in connect_copy

- Version 1.3.1
  - Fix unpublished contact flow error
  - Limit queue copying to STANDARD type only
  - Update doc

- Version 1.3
  - Fix an error when a routing profile has no queues
  - Fix reference cross-reference between contact flows and modules

- Version 1.2.2
  - Delete NumberOfAssociatedQueues and NumberOfAssociatedUsers from AWS CLI describe-routing-profile output
  - Error handle iconv in connect_save
  - Add IAM role permission to README.md
