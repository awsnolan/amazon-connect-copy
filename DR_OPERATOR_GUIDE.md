# DR Operator Guide

## What This Toolkit Does and Does NOT Do

### What it handles (automated)

| Resource | Backup | Restore | Validate |
|----------|--------|---------|----------|
| Instance attributes | ✓ | ✓ | ✓ |
| Hours of operations + overrides | ✓ | ✓ | ✓ |
| Queues + quick connect associations | ✓ | ✓ | ✓ |
| Routing profiles + queue associations | ✓ | ✓ | ✓ |
| Contact flow modules | ✓ | ✓ | ✓ |
| Contact flows | ✓ | ✓ | ✓ |
| Quick connects | ✓ | ✓ | ✓ |
| Agent statuses | ✓ | ✓ | ✓ |
| Security profiles + permissions | ✓ | ✓ (new only) | ✓ |
| User configs (routing/security assignment) | ✓ | ✓ (update only) | ✓ |
| Views | ✓ | ✓ | ✓ |
| Lambda function code + config | ✓ (deps tool) | ✓ (deps tool) | ✓ (exists + permissions) |
| Lex V2 bot definitions | ✓ (deps tool) | Partial (association) | ✓ (exists + available) |
| Lambda ↔ Connect association | ✓ | ✓ | ✓ |
| Lex ↔ Connect association | ✓ | ✓ | ✓ |

### What it does NOT handle (operator responsibility)

These items must be set up manually in the DR account. The toolkit **cannot**
automate them because they involve identity systems, telephony provisioning,
or application-layer concerns that are outside the Amazon Connect API scope.

---

## Operator Checklist: Before Restore

### 1. Target Instance

- [ ] Amazon Connect instance created and ACTIVE
- [ ] Instance in same region as planned (or Global Resiliency configured)
- [ ] Identity provider configured (SSO/SAML/IAM Identity Center)

**How to verify:**
```bash
connect_validate -m preflight --target <instance-id> <backup-dir>
```
Check P.1 passes.

### 2. Users

- [ ] All users pre-provisioned on DR instance
- [ ] Usernames match source exactly (case-sensitive)
- [ ] Users have Connect instance access (appear in `list-users`, not just Identity Center)

**Why this can't be automated:** The `create-user` API requires a password or
directory user ID. Passwords aren't in backups. Directory IDs are instance-specific.

**How to set up:**
- For SSO instances: configure Identity Center group assignment to the DR instance
- For Connect-managed instances: create users manually with temporary passwords
- Recommended: automate with SCIM provisioning from Identity Center

**How to verify:**
```bash
connect_validate -m preflight --target <instance-id> <backup-dir>
```
Check P.4 passes.

**AWS Documentation:**
- https://docs.aws.amazon.com/singlesignon/latest/userguide/
- https://docs.aws.amazon.com/connect/latest/adminguide/user-management.html

### 3. External Dependencies (Lambda)

- [ ] Lambda execution roles created (same names as source account)
- [ ] Lambda functions deployed (use `connect_deps_restore` or your IaC)
- [ ] Connect invoke permissions granted
- [ ] Lambda functions associated with Connect instance

**How to deploy:**
```bash
connect_deps_restore -p dr-profile -i <instance-id> <deps-dir>
```

**How to verify:**
```bash
connect_validate -m preflight --target <instance-id> <backup-dir>
```
Check P.3 passes.

### 4. External Dependencies (Lex V2 Bots)

- [ ] Lex V2 bots created (same names as source)
- [ ] Bot locales built and Available
- [ ] Bot aliases created (same alias names as source — typically "live")
- [ ] Bots associated with Connect instance

**Why this may need manual intervention:** Lex bot creation is complex (locales,
intents, slot types, builds). The deps tool saves the full definition but may
not auto-create complex bots. Use SAM/CloudFormation for deployment.

**AWS Documentation:**
- https://docs.aws.amazon.com/lexv2/latest/dg/what-is.html

### 5. Phone Numbers

- [ ] Phone numbers claimed in DR account/region
- [ ] Numbers associated with correct contact flows

**Why this can't be automated:** Phone numbers are provisioned per-instance and
cannot be transferred between accounts via API. In a DR scenario, you either:
- Pre-claim numbers in the DR region (warm standby)
- Use Amazon Connect Global Resiliency (automatic failover)
- Port numbers from source (takes days — not suitable for DR)

**How to set up:**
1. Go to Amazon Connect console → Phone numbers → Claim a number
2. Assign each to its contact flow:
   - Check backup `phonenumber_*.json` files for the TargetArn → flow name mapping
3. Update queue outbound caller config to reference new numbers

**AWS Documentation:**
- https://docs.aws.amazon.com/connect/latest/adminguide/claim-phone-number.html
- https://docs.aws.amazon.com/connect/latest/adminguide/setup-connect-global-resiliency.html

### 6. Storage Configuration

- [ ] S3 buckets created for call recordings, chat transcripts, etc.
- [ ] KMS keys available (if using customer-managed encryption)
- [ ] Storage configs applied to the Connect instance

**How to set up:** Reference `storage_configs.json` from the backup for the
required S3 buckets, prefixes, and KMS key ARNs. Create equivalent resources
in the DR account and apply via Connect console or API.

**AWS Documentation:**
- https://docs.aws.amazon.com/connect/latest/adminguide/update-instance-settings.html

---

## Operator Checklist: After Restore

### 7. Security Profile Permissions

- [ ] Review security profile permission differences
- [ ] Apply updates if source permissions should override target defaults

**Why this is manual:** Default security profiles (Admin, Agent, CallCenterManager)
have per-instance defaults that intentionally differ. The restore flags these for
review rather than overwriting, because incorrect security profile changes could
lock operators out of the console.

**AWS Documentation:**
- https://docs.aws.amazon.com/connect/latest/adminguide/security-profiles.html

### 8. Lambda Runtime Dependencies

- [ ] DynamoDB tables exist with required data
- [ ] Secrets Manager secrets populated (API keys, credentials)
- [ ] S3 buckets with config files/templates
- [ ] VPC/networking configured (if Lambdas are VPC-attached)
- [ ] External API connectivity verified (CRM, payment gateways, etc.)
- [ ] Bedrock/AgentCore model access enabled (if using AI features)

**Why this can't be automated:** These are application-layer concerns. Each
Lambda function has its own runtime dependencies that the backup tool cannot
introspect or replicate. The `connect_deps_backup` tool produces a
`runtime_dependencies.json` file listing environment variables for each
function — use this as your checklist.

**How to check:**
```bash
cat <deps-dir>/runtime_dependencies.json | jq .
```

### 9. Email Channel

- [ ] Domain verified in Amazon SES for the DR region
- [ ] Email addresses created on the Connect instance

**AWS Documentation:**
- https://docs.aws.amazon.com/connect/latest/adminguide/email-capabilities.html

### 10. Cases & Campaigns

- [ ] Connect Cases domain created (if used)
- [ ] Outbound campaigns recreated (if used)

**Why this is manual:** These require external service setup (Cases domain
registration, campaign dialer configuration) that involves more than just
Connect API calls.

---

## Validation: Confirming Everything Works

After completing all manual actions:

```bash
# Full cross-account validation
connect_validate -m full --target <instance-id> <backup-dir>
```

**Target state:** All tests PASS (warnings acceptable for alias name difference
and pre-existing dead flow references).

The validate output will show you exactly what's still missing or misconfigured.
Re-run after each batch of manual fixes until you reach PASS.

---

## What "Ready for Traffic" Means

The instance is ready for live traffic when:

1. `connect_validate -m full` returns **PASS** (0 failures)
2. All manual actions from this checklist are complete
3. Phone numbers are claimed and assigned to flows
4. A test call/chat through the primary IVR flow completes successfully
5. Agents can log in and receive contacts

Items 4 and 5 are manual verification — the toolkit's `smoke` mode can
partially automate item 4:

```bash
connect_validate -m smoke --target <instance-id> <backup-dir>
```
