# Test Fixtures

Sample AWS resources that wire into a Connect contact flow, giving the backup
script real external dependencies to capture.

## What Gets Created

- **DynamoDB table** (`dr-test-customers`) — customer lookup data
- **Lambda** (`dr-test-customer-lookup`) — reads DynamoDB, returns customer info
- **Lambda** (`dr-test-after-hours-check`) — returns open/closed based on time
- **Lex V2 bot** (`dr-test-MainMenu`) — en_AU locale, 3 intents
- **Contact flow** (`DR Test IVR`) — wires all the above together

## Deploy

```bash
# Get your instance ARN
aws connect list-instances --query 'InstanceSummaryList[].Arn' --output text

# Deploy (requires SAM CLI)
cd test-fixtures
./deploy.sh arn:aws:connect:ap-southeast-2:ACCOUNT:instance/INSTANCE-ID
```

Requires: AWS SAM CLI, Python 3.12, AWS credentials with admin access.

## Teardown

```bash
./teardown.sh arn:aws:connect:ap-southeast-2:ACCOUNT:instance/INSTANCE-ID
```

## What This Exercises in connect_backup

| Resource | Backup captures | Validate checks |
|----------|----------------|-----------------|
| 2 Lambda ARNs in flow | external_dependencies.json | Layer 0 |
| Lex V2 bot ARN in flow | external_dependencies.json | Layer 0 |
| Lambda associations | lambda_associations.json | Layer 12 |
| Lex bot integration | integrations.json | Layer 12 |
| Queue references in flow | flow content JSON | Layer 17 |
| Flow with real content | flow_DR%20Test%20IVR.json | Layers 9-10 |
