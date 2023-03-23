# Release Notes

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
