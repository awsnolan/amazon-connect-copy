# Release Notes

- Version 1.5.0
  - **New components saved and copied:**
    - Quick Connects
    - Agent Statuses (CUSTOM type)
    - Security Profiles (with permissions)
    - Predefined Attributes
    - Task Templates
    - Evaluation Forms
    - Rules (Contact Lens automation)
    - Views (Agent Workspace)
    - User Hierarchy Structure and Groups
    - Users
    - Hours of Operation Overrides
  - **New components saved (informational):**
    - Phone Numbers (claimed, with flow associations)
    - Vocabularies
    - Data Tables
    - Instance Attributes (feature flags)
    - Instance Storage Configs
    - Authentication Profiles
    - Integration Associations (Lex V2, Amazon Q, Voice ID, Cases)
    - Approved Origins (CCP embed CORS)
    - Security Keys
    - Outbound Campaigns
  - **New tool: `connect_validate`** — validates saved instance directories
    (local JSON integrity, cross-reference checks, and live AWS comparison)
  - **Shared library refactor** — common helpers extracted to `connect_lib.sh`,
    sourced by all scripts (eliminates code duplication)
  - **Terminology clarity** — usage text and runtime output now use
    "source instance" / "target instance" instead of "A" / "B"
  - Updated README with complete component list and IAM permissions

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
