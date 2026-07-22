# DR Validation Pipeline

Automated daily validation of your Amazon Connect DR instance. Confirms the DR
instance matches the production backup every day, publishes a CloudWatch metric,
and alerts you immediately when drift is detected.

## Why This Matters

DR plans rot silently. Someone changes a flow on production, the DR instance
doesn't get updated, and you discover the gap during an actual outage — the worst
possible time to learn your DR is broken.

This pipeline catches drift within 24 hours:

- **Daily backup** of the production instance (fresh snapshot)
- **Full validation** against the DR instance (18-layer comparison)
- **CloudWatch metric** — `1` = DR ready, `0` = DR broken
- **SNS alert** on failure with specific broken resources listed
- **CloudWatch alarm** — fires if no successful validation in 36 hours
- **S3 audit trail** — timestamped validation results for compliance

If the metric stays at `1`, your DR instance is always ready for failover.
If it drops to `0`, you know exactly what broke and can fix it before an outage.

## Idle Cost

With a warm-standby DR instance and this pipeline running daily:

| Component | Monthly cost | Notes |
|-----------|-------------|-------|
| Connect instance (idle) | $0 | Pay-per-use; no contacts = no charge |
| Phone numbers | $0 | Not provisioned until failover |
| CodeBuild (daily run) | $1-2 | ~2-3 min/day at $0.005/min |
| S3 (backups + results) | $0.50-1 | < 1 GB with 7-day lifecycle |
| CloudWatch (metric + alarm) | $0.30-0.50 | 1 custom metric, 1 alarm |
| SNS (alerts) | $0 | Negligible for daily emails |
| CloudWatch Logs | $0.50-1 | Log retention for build output |
| Lambda functions (idle) | $0 | No invocations |
| Lex V2 bots (idle) | $0 | No requests |
| KMS key (if used) | $1 | $1/month per customer-managed key |

**Total: approximately $3-5/month ($0.10-0.17/day)**

The Connect instance and all its configured resources cost nothing when idle.
You're paying only for the pipeline infrastructure that validates it daily.

## What Gets Deployed

The CloudFormation template (`template.yaml`) creates:

| Resource | Purpose |
|----------|---------|
| S3 bucket | Stores daily backups (`backups/YYYY-MM-DD/`) and validation JSON (`validations/`) |
| SNS topic | Sends email alerts on validation failure or alarm state change |
| CodeBuild project | Runs the validation pipeline (sources from this GitHub repo) |
| EventBridge rule | Triggers CodeBuild daily at 06:00 UTC (configurable) |
| CloudWatch alarm | Fires if no successful validation in 36 hours |
| IAM roles | Least-privilege roles for CodeBuild and EventBridge |

## Setup

### Prerequisites

1. Production Connect instance (the source you're protecting)
2. DR Connect instance (warm standby, already restored at least once)
3. AWS CLI access to deploy CloudFormation

### Deploy

```bash
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name connect-dr-pipeline \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    SourceInstance=<production-instance-alias> \
    TargetInstance=<dr-instance-id> \
    AlertEmail=oncall@example.com \
    ScheduleExpression="cron(0 6 * * ? *)"
```

### Cross-Account DR

If your DR instance is in a different AWS account:

```bash
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name connect-dr-pipeline \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    SourceInstance=<production-alias> \
    TargetInstance=<dr-instance-id> \
    TargetProfile=dr-account-profile \
    AlertEmail=oncall@example.com \
    LambdaPrefixA=prod- \
    LambdaPrefixB=dr-
```

For cross-account, the CodeBuild role needs to assume a role in the target
account. Add a trust policy on the target account role and configure the
`TARGET_PROFILE` accordingly.

### Verify It Works

```bash
# Trigger manually
aws codebuild start-build --project-name connect-dr-validation

# Watch the build
aws codebuild batch-get-builds --ids <build-id> --query 'builds[0].buildStatus'

# Check the metric
aws cloudwatch get-metric-data \
  --metric-data-queries '[{"Id":"dr","MetricStat":{"Metric":{"Namespace":"ConnectDR","MetricName":"ValidationResult","Dimensions":[{"Name":"SourceInstance","Value":"<alias>"},{"Name":"TargetInstance","Value":"<id>"}]},"Period":86400,"Stat":"Minimum"}}]' \
  --start-time $(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

## Pipeline Flow

```
06:00 UTC — EventBridge triggers CodeBuild
    │
    ├─ 1. Back up production instance (fresh snapshot)
    │     └─ Upload to S3: backups/YYYY-MM-DD/ + backups/latest/
    │
    ├─ 2. Preflight check (DR instance reachable?)
    │
    ├─ 3. Full 18-layer validation (backup vs DR instance)
    │     └─ Save JSON result: validations/YYYY-MM-DD/validation.json
    │
    ├─ 4. Publish CloudWatch metric
    │     └─ ConnectDR/ValidationResult = 1 (PASS) or 0 (FAIL)
    │
    └─ 5. If FAIL: send SNS alert with failure details
          └─ Email lists exact broken resources + remediation
```

## Monitoring

### CloudWatch Dashboard (optional)

Add the `ConnectDR/ValidationResult` metric to a dashboard. A sustained `1`
means your DR is healthy. Any `0` needs investigation.

### Alarm States

| Alarm state | Meaning | Action |
|-------------|---------|--------|
| OK | Last validation passed | None — DR is ready |
| ALARM | No pass in 36 hours | Investigate: pipeline failure or DR drift |
| INSUFFICIENT_DATA | Pipeline hasn't run yet | Wait for first scheduled run |

### Integration with Route 53 Health Checks

To gate automated DNS failover on DR readiness:

1. Create a Route 53 health check that monitors the CloudWatch alarm
2. Associate the health check with your failover DNS record
3. If the alarm is in ALARM state, Route 53 won't route to the DR endpoint

This prevents automated failover to a broken DR instance.

## S3 Bucket Structure

```
connect-dr-<account-id>-<region>/
├── backups/
│   ├── 2026-07-21/          ← daily snapshot (expires after 7 days)
│   │   ├── instance.json
│   │   ├── flows.json
│   │   ├── flow_*.json
│   │   └── ...
│   └── latest/              ← always points to most recent successful backup
│       └── ...
└── validations/
    ├── 2026-07-21/
    │   └── validation.json  ← full JSON result (expires after 30 days)
    └── latest.json          ← most recent result (always current)
```

## Customisation

### Change the schedule

```bash
aws cloudformation update-stack \
  --stack-name connect-dr-pipeline \
  --use-previous-template \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ScheduleExpression="cron(0 2,14 * * ? *)"  # twice daily
```

### Add Slack notifications

Subscribe a Lambda function to the SNS topic that posts to a Slack webhook.
The SNS message body contains structured failure details.

### Skip specific validation layers

Modify the `buildspec.yml` validate command to add `--skip` flags:

```yaml
bin/connect_validate -m full -j --skip 18 --target "$TARGET_INSTANCE" ...
```

Layer 18 (smoke tests) requires live call capability and may not be appropriate
for a standby instance with no phone numbers.

### Retention policy

The default lifecycle rules are:
- Backups: 7 days (one week of daily snapshots)
- Validation results: 30 days (one month of audit history)

Adjust in `template.yaml` under `LifecycleConfiguration` if your compliance
requirements differ.

## Teardown

```bash
# Empty the S3 bucket first (required before stack deletion)
aws s3 rm s3://connect-dr-<account-id>-<region> --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name connect-dr-pipeline
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Build fails on preflight | DR instance not reachable | Check instance is ACTIVE, credentials work |
| Build fails on validate | Source backup structure changed | Run a manual backup + restore cycle first |
| Alarm fires but build succeeded | Metric dimension mismatch | Check SourceInstance/TargetInstance values match between stack and buildspec |
| No metric data | Build not running | Check EventBridge rule is ENABLED, CodeBuild role has permissions |
| SNS email not received | Subscription not confirmed | Check email inbox for confirmation link from AWS |
