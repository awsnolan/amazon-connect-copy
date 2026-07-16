# DR Validation Test Suite — Specification

**Version:** 0.1.0 (Draft)
**Last updated:** 2026-07-16
**Status:** Ready for implementation — expect changes as code is developed

---

## Change Log

| Version | Date | Change |
|---------|------|--------|
| 0.1.0 | 2026-07-16 | Initial draft. 19 layers, 104 tests, companion tool spec, full runbook |

---

## Purpose

This document defines the acceptance criteria for a fully restored Amazon Connect
instance in a Disaster Recovery scenario. A restored instance passes validation
when every test in this suite returns PASS or SKIP (where SKIP means the resource
type was intentionally not present in the source instance).

The suite answers one question: **can this instance serve live traffic identically
to the instance that was backed up?**

---

## Tool Landscape

A restored Amazon Connect instance cannot function without its external dependencies.
Contact flows invoke Lambda functions. IVR menus use Lex bots. Callers hear prompts.
If any of these are missing, the instance is technically restored but operationally dead.

The tooling is therefore two adjacent tools with a shared validation layer:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DR Backup + Restore                          │
├──────────────────────────────┬──────────────────────────────────────┤
│  connect_backup / connect_restore │  connect_deps_backup / connect_deps_  │
│  (Amazon Connect resources)  │  restore (external dependencies)    │
│                              │                                      │
│  Hours, Queues, Routing      │  Lambda functions (code + config)    │
│  Profiles, Flows, Modules,   │  Lex V2 bots (definition + builds)  │
│  Users, Security Profiles,   │  Lex Classic bots (definition)       │
│  Quick Connects, Phone Nums, │  Prompts (audio files)               │
│  Rules, Views, Eval Forms,   │  Wisdom/Q knowledge bases            │
│  Task Templates, Cases,      │                                      │
│  Campaigns, Email, etc.      │                                      │
├──────────────────────────────┴──────────────────────────────────────┤
│                       connect_validate -m full                       │
│           (validates BOTH Connect resources AND dependencies)        │
└─────────────────────────────────────────────────────────────────────┘
```

**Why separate tools:**
- Different IAM permissions (Lambda admin vs. Connect admin)
- Different backup cadences (Lambda code changes on a different schedule than flows)
- Different restore targets (Lambdas deploy via SAM/CDK/Terraform in many orgs)
- Different failure modes (a missing Lambda is a deploy fix, a missing queue is a Connect API fix)

**Why they must be adjacent:**
- The validation suite gates on BOTH. A Connect-only restore that passes Layer 1–16
  but fails Layer 12 (integrations reachable) and Layer 17 (reference integrity)
  is NOT ready for live traffic.
- The dependency manifest (`external_dependencies.json`) produced by `connect_backup`
  is the input to `connect_deps_backup` — it tells the deps tool exactly what to back up.
- Restore order matters: dependencies must be deployed BEFORE `connect_restore` runs,
  because `connect_restore` does preflight checks and remaps ARNs.

---

## Principles

1. **Completeness over speed.** Every configurable resource is validated. The suite
   may take minutes to run — that's acceptable for DR verification.

2. **Config comparison, not just existence.** Knowing a queue exists is not enough.
   Its hours of operation, caller ID, max contacts, and description must match.

3. **Reference integrity is mandatory.** A contact flow that references a deleted
   queue will fail at runtime. Every internal ARN/ID reference must resolve.

4. **External dependencies are verified.** Lambda functions and Lex bots are not
   Amazon Connect resources, but they must be reachable from the restored instance.

5. **Order follows dependency chain.** Validate foundation resources before the
   resources that reference them. If Layer 2 fails, Layer 10 results are unreliable.

6. **No mutations.** The validation suite is strictly read-only. It never creates,
   updates, or deletes anything.

7. **Deterministic output.** Same instance state produces same results. No flaky
   tests. Transient API errors are retried (3 attempts) before reporting FAIL.

---

## Modes

| Mode | Description |
|------|-------------|
| `local` | Validate saved directory structure and JSON integrity only. No AWS calls. |
| `live` | Compare saved backup against the live restored instance via AWS APIs. |
| `full` | Run both local and live. This is the DR acceptance mode. |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests PASS (warnings are acceptable) |
| 1 | One or more tests FAIL |
| 2 | Usage error or missing prerequisites |

---

## Test Layers

### Layer 1: Instance Foundation

The instance itself must be reachable, active, and configured identically.

| ID | Test | Pass criteria |
|----|------|---------------|
| 1.1 | Instance reachable | `describe-instance` succeeds, returns `InstanceStatus: ACTIVE` |
| 1.2 | Instance alias matches | Alias equals the backed-up alias |
| 1.3 | Instance attributes match | Every attribute in `instance_attributes.json` matches live. Attributes: INBOUND_CALLS, OUTBOUND_CALLS, CONTACTFLOW_LOGS, CONTACT_LENS, AUTO_RESOLVE_BEST_VOICES, USE_CUSTOM_TTS_VOICES, EARLY_MEDIA, MULTI_PARTY_CONFERENCE, HIGH_VOLUME_OUTBOUND, ENHANCED_CONTACT_MONITORING, ENHANCED_CHAT_MONITORING |
| 1.4 | Storage configs match | For each storage type, the StorageType, S3 bucket/prefix, KMS key ARN, and Kinesis stream ARN are identical. Types: CALL_RECORDINGS, CHAT_TRANSCRIPTS, SCHEDULED_REPORTS, MEDIA_STREAMS, CONTACT_TRACE_RECORDS, AGENT_EVENTS, REAL_TIME_CONTACT_ANALYSIS_SEGMENTS, REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS, ATTACHMENTS, CONTACT_EVALUATIONS, SCREEN_RECORDINGS |
| 1.5 | Approved origins match | Set of CORS origins is identical (order-independent) |
| 1.6 | Security keys present | Count of active security keys matches. WARN if keys differ (re-association is manual) |

---

### Layer 2: Hours of Operations + Scheduling

| ID | Test | Pass criteria |
|----|------|---------------|
| 2.1 | All hours of operations exist | Every name in `hours.json` exists live |
| 2.2 | Hour configs match | For each hours-of-operation: TimeZone is identical; Config array (Day, StartTime, EndTime) is identical (order-independent per day) |
| 2.3 | Hour overrides restored | For each hours-of-operation: `list-hours-of-operation-overrides` returns the same set of overrides (matched by EffectiveFrom + EffectiveTill + day config). Recurring overrides included |

---

### Layer 3: Queues

| ID | Test | Pass criteria |
|----|------|---------------|
| 3.1 | All standard queues exist | Every name in `queues.json` exists live |
| 3.2 | Queue HoursOfOperation correct | `HoursOfOperationId` on live queue resolves to an hours-of-operation with the same name as the source |
| 3.3 | Queue outbound caller config | `OutboundCallerConfig` matches: OutboundCallerIdName, OutboundCallerIdNumberId (resolves to same phone number), OutboundFlowId (resolves to same flow name) |
| 3.4 | Queue status ENABLED | Live status is ENABLED |
| 3.5 | Queue quick connect associations | `list-queue-quick-connects` returns same set of quick connect names as saved `queueQCs_*.json` |
| 3.6 | Queue max contacts | `MaxContacts` value matches |
| 3.7 | Queue description | Description field matches (null == null is PASS) |
| 3.8 | Queue tags match | Tags on live queue match saved tags |

---

### Layer 4: Routing Profiles

| ID | Test | Pass criteria |
|----|------|---------------|
| 4.1 | All routing profiles exist | Every name in `routings.json` exists live |
| 4.2 | DefaultOutboundQueue correct | `DefaultOutboundQueueId` resolves to a queue with the same name as the source |
| 4.3 | MediaConcurrencies match | For each channel (VOICE, CHAT, TASK, EMAIL): Concurrency value, CrossChannelBehavior identical |
| 4.4 | Associated queues match | `list-routing-profile-queues` returns same set of (QueueName, Priority, Delay) tuples as saved `routingQs_*.json` |
| 4.5 | Description matches | Description field matches |
| 4.6 | Tags match | Tags on live routing profile match saved tags |

---

### Layer 5: Security Profiles

| ID | Test | Pass criteria |
|----|------|---------------|
| 5.1 | All security profiles exist | Every name in `securityprofiles.json` exists live |
| 5.2 | Permissions match | `list-security-profile-permissions` returns identical permission set (order-independent) |
| 5.3 | Access control tags match | `AllowedAccessControlTags` and `AllowedAccessControlHierarchyGroupId` match |
| 5.4 | Tag restrictions match | `TagRestrictedResources` list matches |
| 5.5 | Description matches | Description field matches |

---

### Layer 6: User Hierarchy

| ID | Test | Pass criteria |
|----|------|---------------|
| 6.1 | Hierarchy structure matches | `describe-user-hierarchy-structure` returns same levels (LevelOne through LevelFive) with same names |
| 6.2 | All hierarchy groups exist | Every group in `hierarchy_groups.json` exists live with same name |
| 6.3 | Group parent relationships correct | Each group's `HierarchyPath` matches (LevelOne through parent chain identical) |
| 6.4 | Group tags match | Tags on hierarchy groups match |

---

### Layer 7: Users

| ID | Test | Pass criteria |
|----|------|---------------|
| 7.1 | All users exist | Every username in `users.json` exists live |
| 7.2 | User routing profile correct | `RoutingProfileId` resolves to a routing profile with the same name |
| 7.3 | User security profile(s) correct | `SecurityProfileIds` resolve to security profiles with same names |
| 7.4 | User hierarchy group correct | `HierarchyGroupId` resolves to group with same name (or both null) |
| 7.5 | User identity info matches | FirstName, LastName, Email, Mobile, SecondaryEmail match |
| 7.6 | User phone config matches | PhoneType, AutoAccept, AfterContactWorkTimeLimit, DeskPhoneNumber match |
| 7.7 | User tags match | Tags match |
| 7.8 | User proficiencies match | `list-user-proficiencies` returns same set of (AttributeName, AttributeValue, Level) tuples |

---

### Layer 8: Quick Connects

| ID | Test | Pass criteria |
|----|------|---------------|
| 8.1 | All quick connects exist | Every name in `quickconnects.json` exists live |
| 8.2 | Quick connect type correct | `QuickConnectType` (USER, QUEUE, PHONE_NUMBER) matches |
| 8.3 | Quick connect config correct | Target resolves correctly: UserConfig.UserId → same username; QueueConfig.QueueId → same queue name + ContactFlowId → same flow name; PhoneConfig.PhoneNumber matches |
| 8.4 | Description matches | Description field matches |
| 8.5 | Tags match | Tags match |

---

### Layer 9: Contact Flow Modules

| ID | Test | Pass criteria |
|----|------|---------------|
| 9.1 | All modules exist | Every name in `modules.json` exists live |
| 9.2 | Module status published | Status == "published" |
| 9.3 | Module content matches | Content field (parsed as JSON) is structurally equivalent after ID remapping. Comparison uses normalized form: actions sorted by Identifier, parameters sorted by key |
| 9.4 | Module description matches | Description field matches |
| 9.5 | Module internal references resolve | Every ARN in the module's Actions resolves to a resource that exists in the live instance |
| 9.6 | Module tags match | Tags match |

---

### Layer 10: Contact Flows

| ID | Test | Pass criteria |
|----|------|---------------|
| 10.1 | All flows exist | Every name in `flows.json` exists live |
| 10.2 | Flow state ACTIVE | `State` == ACTIVE |
| 10.3 | Flow type correct | `ContactFlowType` matches (CONTACT_FLOW, CUSTOMER_HOLD, CUSTOMER_QUEUE, CUSTOMER_WHISPER, AGENT_HOLD, AGENT_WHISPER, OUTBOUND_WHISPER, AGENT_TRANSFER, QUEUE_TRANSFER) |
| 10.4 | Flow content matches | Content structurally equivalent after ID remapping (same normalization as 9.3) |
| 10.5 | Flow description matches | Description field matches |
| 10.6 | Flow references resolve | Every queue, prompt, flow, module, Lambda, Lex ARN referenced in Actions resolves to an existing resource |
| 10.7 | Flow tags match | Tags match |

---

### Layer 11: Phone Numbers

| ID | Test | Pass criteria |
|----|------|---------------|
| 11.1 | All phone numbers claimed | Every number in `phonenumbers.json` exists with Status=CLAIMED |
| 11.2 | Phone type correct | PhoneNumberType (DID, TOLL_FREE, UIFN, SHARED) matches |
| 11.3 | Phone → flow association correct | `TargetArn` on live number resolves to a contact flow with the same name as the source |
| 11.4 | Phone country code correct | PhoneNumberCountryCode matches |

---

### Layer 12: Integration Associations

| ID | Test | Pass criteria |
|----|------|---------------|
| 12.1 | All integrations exist | Every integration in `integrations.json` exists live (matched by IntegrationType + IntegrationArn/SourceApplicationName) |
| 12.2 | Lex V2 bots reachable | Each Lex V2 bot alias ARN is accessible via `lexv2-models describe-bot-alias`. Bot status is Available |
| 12.3 | Lambda functions reachable | Each Lambda ARN referenced in flows returns successfully from `lambda get-function`. State is Active |
| 12.4 | Lambda permissions correct | Each Lambda has `connect.amazonaws.com` invoke permission for this instance (via `lambda get-policy`) |

---

### Layer 13: Email Channel

| ID | Test | Pass criteria |
|----|------|---------------|
| 13.1 | Email addresses exist | Every address in `email_addresses.json` exists live |
| 13.2 | Email domain verified | Domain verification status is not PENDING (address is usable) |
| 13.3 | Email display name matches | DisplayName field matches |
| 13.4 | Email description matches | Description field matches |

---

### Layer 14: Supporting Resources

#### 14A: Agent Statuses

| ID | Test | Pass criteria |
|----|------|---------------|
| 14A.1 | All custom statuses exist | Every status in `agentstatuses.json` exists live |
| 14A.2 | Status state correct | `State` (ENABLED/DISABLED) matches |
| 14A.3 | Status order preserved | `DisplayOrder` matches |
| 14A.4 | Status tags match | Tags match |

#### 14B: Predefined Attributes

| ID | Test | Pass criteria |
|----|------|---------------|
| 14B.1 | All attributes exist | Every attribute name exists live |
| 14B.2 | Attribute values match | `Values.StringList` contains same entries (order-independent) |

#### 14C: Task Templates

| ID | Test | Pass criteria |
|----|------|---------------|
| 14C.1 | All task templates exist | Every template in `tasktemplates.json` exists live |
| 14C.2 | Template status ACTIVE | Status == ACTIVE |
| 14C.3 | Template fields match | Field definitions (Id, Name, Type, Required, Description) are identical |
| 14C.4 | Template defaults match | Default field values are identical |
| 14C.5 | Template contact flow correct | ContactFlowId resolves to flow with same name |

#### 14D: Evaluation Forms

| ID | Test | Pass criteria |
|----|------|---------------|
| 14D.1 | All evaluation forms exist | Every form in `evaluationforms.json` exists live |
| 14D.2 | Form status ACTIVE | Status == ACTIVE |
| 14D.3 | Form items match | Sections and questions structure is identical (question text, type, options, scoring) |
| 14D.4 | Form scoring strategy matches | ScoringStrategy field matches |

#### 14E: Rules

| ID | Test | Pass criteria |
|----|------|---------------|
| 14E.1 | All rules exist | Every rule in `rules.json` exists live |
| 14E.2 | Rule publish status | PublishStatus == PUBLISHED |
| 14E.3 | Rule trigger matches | `TriggerEventSource` (EventSourceName + IntegrationAssociationId) matches |
| 14E.4 | Rule conditions match | `Function` (condition tree) is structurally equivalent |
| 14E.5 | Rule actions match | `Actions` list (AssignContactCategory, SendNotification, CreateTask, etc.) is equivalent |

#### 14F: Views

| ID | Test | Pass criteria |
|----|------|---------------|
| 14F.1 | All views exist | Every view in `views.json` exists live |
| 14F.2 | View status PUBLISHED | Status == PUBLISHED |
| 14F.3 | View content matches | Content (Template + Actions) structurally equivalent |
| 14F.4 | View tags match | Tags match |

#### 14G: Vocabularies

| ID | Test | Pass criteria |
|----|------|---------------|
| 14G.1 | All vocabularies exist | Every vocabulary in `vocabularies.json` exists live |
| 14G.2 | Vocabulary state ACTIVE | State == ACTIVE (not PENDING or FAILED) |
| 14G.3 | Vocabulary content matches | Phrases/content match |
| 14G.4 | Vocabulary language matches | LanguageCode matches |

#### 14H: Data Tables

| ID | Test | Pass criteria |
|----|------|---------------|
| 14H.1 | All data tables exist | Every table in `datatables.json` exists live |
| 14H.2 | Table schema matches | Column definitions (name, type) identical |
| 14H.3 | Table data present | Row count > 0 if source had rows (WARN if empty) |

---

### Layer 15: Cases Domain

| ID | Test | Pass criteria |
|----|------|---------------|
| 15.1 | Cases domain exists | Domain accessible via `connectcases list-domains` |
| 15.2 | Custom fields match | All custom fields exist with correct Type (Text, Number, Boolean, DateTime, SingleSelect, Url) and options |
| 15.3 | Layouts match | All layouts exist with correct fieldGroup definitions |
| 15.4 | Templates match | All case templates exist with correct required fields and default values |

---

### Layer 16: Outbound Campaigns

| ID | Test | Pass criteria |
|----|------|---------------|
| 16.1 | All campaigns exist | Every campaign in `campaigns.json` exists live |
| 16.2 | Campaign channel config correct | ChannelSubtypeConfig matches (telephony, sms, email settings) |
| 16.3 | Campaign Connect queue correct | ConnectQueueId resolves to queue with same name |
| 16.4 | Campaign schedule config | Schedule and communication time/limits config matches |

---

### Layer 17: Cross-Reference Integrity

These tests verify the graph of references between resources is intact.

| ID | Test | Pass criteria |
|----|------|---------------|
| 17.1 | Flow → queue references | Every queue ARN in flows resolves to a live queue |
| 17.2 | Flow → prompt references | Every prompt ARN in flows resolves to a live prompt |
| 17.3 | Flow → flow references | Every transfer-to-flow ARN resolves to a live flow |
| 17.4 | Flow → module references | Every InvokeFlowModule ARN resolves to a live module |
| 17.5 | Flow → Lambda references | Every InvokeLambdaFunction ARN resolves to an accessible Lambda |
| 17.6 | Flow → Lex references | Every Lex bot ARN resolves to an accessible bot |
| 17.7 | Routing profile → queue references | Every queue in routing profile queue associations exists live |
| 17.8 | Queue → hours references | Every HoursOfOperationId on a queue resolves live |
| 17.9 | User → routing profile references | Every user's RoutingProfileId resolves live |
| 17.10 | User → security profile references | Every user's SecurityProfileIds resolve live |
| 17.11 | User → hierarchy group references | Every user's HierarchyGroupId resolves live |
| 17.12 | Quick connect → target references | Every quick connect target (user/queue/flow) resolves live |
| 17.13 | Phone → flow references | Every phone number's TargetArn resolves to a live flow |
| 17.14 | Task template → flow references | Every task template ContactFlowId resolves live |
| 17.15 | Rule → resource references | Every rule's queue/flow/contact-attribute references resolve |

---

### Layer 18: Functional Smoke Tests

These are optional, higher-cost tests that verify the instance can actually
process contacts. Run with `-m smoke` or `-m full+smoke`.

| ID | Test | Pass criteria |
|----|------|---------------|
| 18.1 | Instance access URL reachable | HTTP GET to InstanceAccessUrl returns 200/302 (login page) |
| 18.2 | Chat flow invocable | `StartChatContact` with the primary IVR flow succeeds (creates a ContactId). Contact is immediately disconnected after verification |
| 18.3 | Outbound capability | If OUTBOUND_CALLS enabled: `StartOutboundVoiceContact` to a test number does not return InvalidParameterException (verifying the flow + queue + caller ID chain is valid). Immediately cancel via `StopContact` |
| 18.4 | Test contact flow API | If available (Jan 2026 API): Use the Connect testing API to simulate a voice interaction through the primary flow |

---

## Comparison Rules

When comparing saved vs. live values:

1. **IDs are remapped.** Source instance IDs will differ from target. Compare by
   **name** (or the logical identifier), not by UUID.
2. **ARNs are reconstructed.** Source ARNs contain source account/region/instance.
   Target will have different ARNs. Resolution is by extracting the resource name.
3. **Null == missing == empty string** for optional fields like Description.
4. **Order-independent comparison** for: permissions lists, tag sets, queue
   associations, override lists, Config day entries, vocabulary phrases.
5. **Timestamps are excluded** from comparison (CreatedTime, LastModifiedTime, etc.).
6. **IsDefault fields are excluded** — system-generated defaults may differ.
7. **Whitespace normalization** on description fields (trim, collapse internal whitespace).

---

## Output Format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  connect_validate 2.0.0
  Source   : source-instance (from backup)
  Target   : target-instance (live)
  Mode     : full
  Profile  : dr-restore-profile
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━ Layer 1: Instance Foundation ━━━
  [1.1] PASS  Instance reachable: ACTIVE
  [1.2] PASS  Instance alias matches: my-instance
  [1.3] PASS  Instance attributes match (11/11)
  [1.4] PASS  Storage configs match (8/8)
  [1.5] PASS  Approved origins match (3/3)
  [1.6] WARN  Security keys: saved=1 live=0 (manual re-association needed)

━━━ Layer 2: Hours of Operations ━━━
  [2.1] PASS  All hours exist (5/5)
  [2.2] PASS  Hour configs match (5/5)
  [2.3] PASS  Hour overrides match (12/12)

...

━━━ Layer 17: Cross-Reference Integrity ━━━
  [17.1] PASS  Flow → queue references (23/23)
  [17.2] PASS  Flow → prompt references (8/8)
  [17.3] PASS  Flow → flow references (15/15)
  [17.4] PASS  Flow → module references (4/4)
  [17.5] FAIL  Flow → Lambda references (11/12)
         → Missing: arn:aws:lambda:us-east-1:123456789012:function:my-lookup-fn
           Referenced by: flow_MainIVR.json (Action: InvokeLambda_abc123)
  [17.6] PASS  Flow → Lex references (2/2)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Layers    : 17 passed, 0 failed, 1 with warnings
  Tests     : 89 passed, 1 failed, 1 warning, 0 skipped
  Duration  : 2m 34s

  RESULT: FAIL (1 test failed)
  Action required: Deploy missing Lambda function before enabling live traffic.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Machine-Readable Output

With `--json` flag, emit results as JSON for CI/CD integration:

```json
{
  "version": "2.0.0",
  "mode": "full",
  "source_instance": "source-alias",
  "target_instance": "target-alias",
  "timestamp": "2026-07-16T10:30:00Z",
  "duration_seconds": 154,
  "summary": {
    "total": 90,
    "pass": 89,
    "fail": 1,
    "warn": 1,
    "skip": 0
  },
  "result": "FAIL",
  "layers": [
    {
      "id": 1,
      "name": "Instance Foundation",
      "result": "WARN",
      "tests": [
        {"id": "1.1", "result": "PASS", "label": "Instance reachable"},
        {"id": "1.6", "result": "WARN", "label": "Security keys", "detail": "saved=1 live=0"}
      ]
    }
  ],
  "failures": [
    {
      "id": "17.5",
      "layer": "Cross-Reference Integrity",
      "label": "Flow → Lambda references",
      "detail": "Missing: arn:aws:lambda:us-east-1:123456789012:function:my-lookup-fn",
      "referenced_by": "flow_MainIVR.json",
      "remediation": "Deploy the Lambda function to the target account/region"
    }
  ]
}
```

---

## Remediation Guidance

Each FAIL result should include actionable guidance:

| Failure type | Remediation |
|-------------|-------------|
| Resource missing | Indicates restore step was skipped or failed. Re-run `connect_restore` for that resource type |
| Config mismatch | Restore wrote stale data, or a manual change was made post-restore. Re-run save + diff + copy for that resource |
| Reference broken | Dependency not restored or not yet deployed. Check the dependency chain and restore in correct order |
| External dep missing | Lambda/Lex/Q not deployed to target account. Deploy external dependencies before re-validating |
| Permission denied | AWS profile lacks access. Check IAM permissions for the validate role |
| Timeout/throttle | API rate limit hit. Re-run with `--retry-delay` or run during off-peak |

---

## Prerequisites for Running

1. AWS CLI 2.9.4+ installed
2. jq 1.6+ installed
3. AWS profile with **read-only** access to both source backup directory and live target instance
4. Required IAM permissions on target:
   - `connect:Describe*`, `connect:List*`, `connect:Search*`
   - `connect:GetContactFlow`, `connect:GetTaskTemplate`
   - `lambda:GetFunction`, `lambda:GetPolicy`
   - `lex:DescribeBot`, `lex:DescribeBotAlias`
   - `connectcases:ListDomains`, `connectcases:ListFields`, `connectcases:ListLayouts`, `connectcases:ListTemplates`
   - `connect-campaigns-v2:DescribeCampaign`
5. Source backup directory produced by `connect_backup`
6. **Target instance must already exist and be ACTIVE.** Instance creation is not
   automated. The target must be a pre-provisioned Amazon Connect instance (empty or
   warm standby). `connect_restore` will verify the instance is reachable before
   proceeding — if it's not ACTIVE, the restore aborts immediately.

   Things that must be set up manually on the target instance before restore:
   - Instance creation (via console or `create-instance` API)
   - Identity provider / SSO configuration
   - Telephony options (claim phone numbers or use Global Resiliency)
   - Domain verification for email channel (if used)
   - KMS key configuration for encryption at rest (if using CMKs)

---

## What "Done" Looks Like

The DR validation suite is complete when:

1. Running `connect_validate -m full` against a freshly restored instance
   produces a clear PASS/FAIL for every resource that was backed up.

2. Every FAIL includes enough context to identify and fix the problem without
   re-reading source code.

3. The exit code can gate a DNS failover or traffic shift in an automated
   DR runbook.

4. The JSON output can be consumed by monitoring/alerting systems to track
   DR readiness over time (scheduled validation runs against warm standby).

5. A human operator with no knowledge of the tool's internals can read the
   output and understand exactly what is and isn't working.


---

## Companion Tool: `connect_deps_backup` / `connect_deps_restore`

### Why This Exists

A contact flow with an "Invoke Lambda" action and no Lambda behind it produces a
hard failure — the caller hears an error treatment or gets disconnected. A "Get
Customer Input" action pointing to a deleted Lex bot produces silence. A "Play
Prompt" action with a missing prompt produces dead air.

The Connect instance is the orchestrator. The dependencies are the workers. Without
the workers, the orchestrator has nothing to orchestrate.

### What It Backs Up

| Dependency | What's saved | How |
|-----------|-------------|-----|
| **Lambda functions** | Deployment package (zip), environment variables (encrypted), layers (ARN + version), aliases, concurrency config, timeout, memory, runtime, VPC config, dead-letter config, tags | `lambda get-function` (presigned URL → download zip), `get-function-configuration`, `list-aliases`, `list-versions-by-function`, `get-policy` (resource policy) |
| **Lambda layers** | Layer version zip (only layers referenced by backed-up functions) | `lambda get-layer-version` (presigned URL → download) |
| **Lex V2 bots** | Bot definition, all locales, all intents + slot types per locale, bot alias config, conversation logs config | `lexv2-models describe-bot`, `list-bot-locales`, `list-intents`, `describe-intent` (per intent), `list-slot-types`, `describe-slot-type`, `describe-bot-alias` |
| **Lex Classic bots** | Bot definition, intents, slot types, utterances | `lex-models get-bot`, `get-intent` (per intent), `get-slot-type` (per slot type) |
| **Prompts (audio)** | Audio file (wav/mp3), prompt name, description, tags | `connect get-prompt` (presigned S3 URL → download audio file) |
| **Wisdom / Amazon Q** | Assistant config, knowledge base config, content source URIs | `wisdom get-assistant`, `list-knowledge-bases`, `get-knowledge-base` |

### Input

The `external_dependencies.json` manifest produced by `connect_backup`:

```json
{
  "LambdaFunctions": [{"Arn": "...", "FunctionName": "...", ...}],
  "LexV2Bots": [{"Arn": "...", "BotId": "...", "BotName": "...", ...}],
  "LexClassicBots": [{"Name": "...", "Region": "...", ...}]
}
```

Plus prompts from `prompts.json` (which has Name + Id but no audio content today).

### Output Directory Structure

```
deps/
├── lambda/
│   ├── my-lookup-fn/
│   │   ├── code.zip                    # Deployment package
│   │   ├── config.json                 # Full function configuration
│   │   ├── aliases.json                # Alias definitions
│   │   ├── policy.json                 # Resource policy (invoke permissions)
│   │   └── tags.json                   # Tags
│   └── my-other-fn/
│       └── ...
├── lambda_layers/
│   ├── my-shared-layer/
│   │   ├── layer_v3.zip               # Layer content
│   │   └── config.json                # Layer version metadata
│   └── ...
├── lex_v2/
│   ├── my-bot/
│   │   ├── bot.json                   # Bot definition
│   │   ├── alias_LiveAlias.json       # Alias config
│   │   ├── locale_en_US/
│   │   │   ├── locale.json            # Locale settings
│   │   │   ├── intents.json           # All intents
│   │   │   ├── intent_BookFlight.json  # Full intent detail
│   │   │   └── slot_types.json        # Slot type definitions
│   │   └── locale_es_ES/
│   │       └── ...
│   └── ...
├── lex_classic/
│   ├── my-legacy-bot/
│   │   ├── bot.json
│   │   ├── intents/
│   │   │   └── *.json
│   │   └── slot_types/
│   │       └── *.json
│   └── ...
├── prompts/
│   ├── Welcome%20Greeting.wav         # Audio file
│   ├── Welcome%20Greeting.json        # Metadata (name, description, tags)
│   ├── Hold%20Music.wav
│   ├── Hold%20Music.json
│   └── ...
└── manifest.json                       # Full dependency manifest with restore order
```

### CLI Interface

```
Usage: connect_deps_backup [-?fv] [-p aws_profile] [-d deps_dir] instance_alias
    Back up all external dependencies referenced by a saved Amazon Connect instance.

    instance_alias  Path to the directory saved by connect_backup
    -d deps_dir     Output directory for dependency backups (default: <instance_alias>_deps)
    -f              Force removal of existing deps directory
    -p profile      AWS Profile to use
    -v              Show version
    -?              Help

    Prerequisites: connect_backup must have been run first (needs external_dependencies.json
    and prompts.json).
```

```
Usage: connect_deps_restore [-?dv] [-p aws_profile] [-P prefix_map] deps_dir
    Restore external dependencies to the target account/region.

    deps_dir        Path to the dependency backup directory
    -d              Dry run
    -p profile      AWS Profile for target account
    -P old=new      Lambda/Lex name prefix mapping (for cross-environment restore)
    -v              Show version
    -?              Help

    This deploys Lambda functions, builds Lex bots, and uploads prompts to the
    target account. Run BEFORE connect_restore.
```

### Restore Behaviour

| Dependency | Restore action | Idempotent? |
|-----------|---------------|-------------|
| Lambda function | `create-function` if missing, `update-function-code` + `update-function-configuration` if exists | Yes — overwrites to match backup |
| Lambda alias | `create-alias` or `update-alias` pointing to $LATEST after code update | Yes |
| Lambda resource policy | `add-permission` for Connect invoke (uses source instance ID, must be updated to target instance ID) | Yes — removes + re-adds |
| Lambda layer | `publish-layer-version` (layers are immutable — publishes new version if content differs) | Yes |
| Lex V2 bot | `create-bot` + `create-bot-locale` + `create-intent` + `create-slot-type` + `build-bot-locale` + `create-bot-alias` | Yes — updates if exists |
| Lex Classic bot | `put-bot` + `put-intent` + `put-slot-type` | Yes |
| Prompt | `create-prompt` with audio file upload (Connect API supports this since May 2023) | Yes — updates if name matches |

### Prefix Remapping

In cross-environment DR (e.g., source in us-east-1, DR target in us-west-2),
Lambda and Lex names often have environment prefixes:

```
connect_deps_restore -P "prod-east-=prod-west-" deps/
```

This renames `prod-east-lookup-fn` to `prod-west-lookup-fn` during restore. The
Connect copy step's `-l` flag handles the corresponding ARN remapping in flows.

### Security Considerations

- Lambda environment variables may contain secrets. `connect_deps_backup` saves
  them encrypted (as returned by `get-function-configuration`). The restore step
  re-creates them as-is. Operator must verify KMS key availability in target region.
- Lambda VPC config references specific subnet IDs and security group IDs. These
  will differ in the DR region. Restore must accept a VPC mapping file or flag
  VPC-attached functions for manual intervention.
- Lex bot conversation logs reference CloudWatch log groups and S3 buckets that
  may not exist in the DR region. Restore skips log config or accepts a mapping.

### What This Does NOT Back Up

| Resource | Why excluded |
|---------|-------------|
| Lambda event source mappings (SQS, Kinesis triggers) | Not Connect-related; managed by the triggering service's IaC |
| Lambda CloudWatch alarms | Operational tooling, not functional dependency |
| DynamoDB/RDS/S3 data that Lambdas read | Data-layer DR is a separate domain (backups, replication, etc.) |
| Lex bot conversation history | Runtime data, not configuration |
| Amazon Q/Wisdom content files | Large datasets; typically replicated via S3 cross-region replication |

The boundary is: **back up everything needed to make the Connect instance's flows
execute without error.** Data that flows *read at runtime* (DynamoDB lookups, S3
objects, etc.) is out of scope — that's the application team's DR responsibility.

---

## DR Restore Sequence (Full Runbook)

The complete DR restore is:

```
# 1. Restore external dependencies first
connect_deps_restore -p dr-profile deps/

# 2. Save the fresh target instance (empty or warm standby)
connect_backup -p dr-profile target-instance

# 3. Diff source backup against target
connect_plan source-instance target-instance helper \
    -l "prod-east-=prod-west-" \
    -b "prod-east-=prod-west-"

# 4. Restore Connect resources
connect_restore helper

# 5. Validate everything
connect_validate -m full -p dr-profile source-instance target-instance
```

Step 5 is the gate. If it passes, cut DNS/traffic over. If it fails, the output
tells you exactly what to fix before retrying.

---

## Validation Layer 0: External Dependencies

This is the layer that bridges the two tools. It runs as part of `connect_validate -m full`.

| ID | Test | Pass criteria |
|----|------|---------------|
| 0.1 | All Lambda functions exist | Every ARN in `external_dependencies.json` → `lambda get-function` succeeds |
| 0.2 | Lambda functions are Active | State == Active (not Pending or Failed) |
| 0.3 | Lambda runtime matches | Runtime matches saved config (e.g., not accidentally on an EOL runtime) |
| 0.4 | Lambda code hash matches | CodeSha256 matches saved value (confirms correct code deployed) |
| 0.5 | Lambda Connect permission exists | Resource policy includes `connect.amazonaws.com` as principal with `lambda:InvokeFunction` action |
| 0.6 | Lambda environment variables present | All expected env var keys exist (values not compared — may be secrets) |
| 0.7 | Lambda timeout adequate | Timeout >= saved timeout (a lower timeout could cause flow failures) |
| 0.8 | All Lex V2 bots exist | Each bot ID + alias accessible via `describe-bot-alias` |
| 0.9 | Lex V2 bot status Available | BotStatus == Available (not Building, Failed, or Deleting) |
| 0.10 | Lex V2 bot locales built | Each locale referenced in flows has BotLocaleStatus == Built |
| 0.11 | All Lex Classic bots exist | Each bot name accessible via `get-bot` |
| 0.12 | Lex Classic bot status READY | Status == READY (not BUILDING or FAILED) |
| 0.13 | All prompts exist | Every prompt name in `prompts.json` exists in target instance |
| 0.14 | Prompt count matches | Total prompt count >= saved count (no missing prompts) |

**A failure in Layer 0 is a blocker.** It means the Connect instance will encounter
runtime errors on live calls. No amount of correct Connect configuration can
compensate for a missing Lambda.

---

## Living Document Notes

This spec is a target for implementation, not a frozen contract. The following
areas are expected to evolve during development:

1. **Test IDs and groupings** — Tests may merge or split as implementation reveals
   what's natural to check in a single API call vs. what needs separate assertions.

2. **Field-level pass criteria** — Exact JSON field names come from real API responses.
   The spec uses documented names but the code is authoritative.

3. **New resource types** — AWS releases new Connect features regularly. Adding a
   new layer should follow the established pattern: list → describe → compare →
   cross-reference.

4. **Flow content normalization (9.3 / 10.4)** — This is the hardest comparison.
   Connect may add metadata fields between save and restore. The normalization
   rules will tighten or relax based on what we find.

5. **Layer 18 smoke tests** — The Connect testing API (Jan 2026) is new. Its
   exact interface and limitations will inform what's automatable.

6. **Retry and throttle handling** — API rate limits and eventual consistency
   windows may require tuning per-layer.

When a change is made, update the Change Log above with the version, date, and
a one-line description. Bump the minor version for additive changes (new tests,
new layers). Bump the major version if the structure or principles change.
