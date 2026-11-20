# Amazon Connect Catastrophic-Recovery Data Scope

## Executive conclusion

The next version should evolve from a **Connect configuration copier** into a **recovery-orchestration and data-protection system**.

The present solution can rebuild much of the Connect control plane, but catastrophic recovery also requires:

1. Immutable, point-in-time Connect configuration snapshots.
2. Replication of customer-owned S3 and streaming data.
3. Exports of service-managed records such as Cases and Customer Profiles.
4. Native protection for DynamoDB, databases, secrets, queues, and integration stores.
5. Rebuildable Lambda, Lex, Amazon Q, SES, identity, and networking dependencies.
6. Explicit handling of data that can be retained but **cannot be faithfully re-imported into Connect**.

The critical design principle is:

> “Retained,” “queryable after a disaster,” and “restorable into a replacement Connect instance” are three different recovery outcomes.

## Current solution position

The repository is primarily a **cold-recovery configuration replication toolkit**:

- `connect_backup`, `connect_plan`, and `connect_restore` recreate routing, flows, users, security configuration, data tables, Cases schemas, Customer Profiles schemas, and related Connect resources.
- Connect storage configurations are copied as references. The S3 buckets, KMS keys, streams, and their contents are not copied.
- `connect_deps_backup` partially captures Lambda and Lex invocation dependencies, but explicitly excludes runtime stores such as DynamoDB, S3 configuration buckets, databases, secrets, networking, and third-party services.
- Historical contact records, case records, profile records, recordings, evaluation results, campaigns, and analytics are not migrated.

There is also documentation drift:

- Cases and Customer Profiles configuration restore now exists in `bin/lib/restore/supporting.sh`, despite older limitation text saying Cases is manual.
- Lambda/Lex/prompt restore claims are broader than the current implementation.
- Generated workspace manifests contain non-placeholder account/resource identifiers. Those directories should be treated as sensitive recovery artifacts and must not be committed or published without sanitization.

## Complete data-store scope

### 1. Connect configuration and control-plane state

This includes:

- Instance attributes and storage associations
- Flows, flow modules, versions, aliases, and prompts
- Queues, routing profiles, quick connects, hours and overrides
- Users, hierarchy, security profiles, statuses, proficiencies
- Phone-number-to-flow and queue associations
- Rules, views, workspaces, task templates
- Evaluation forms, vocabularies, predefined attributes
- Data-table definitions and rows
- Cases and Customer Profiles schemas
- Saved reports, custom metrics, test cases, notifications
- Email addresses, campaign definitions, integration associations
- Authentication profiles, approved origins, attachment settings

**Protection:** Periodic API snapshots, IaC where supported, checksums, versioning, and an immutable cross-account copy.

**Recovery:** Mostly reconstructable, but some resources require name/ID remapping or manual action.

Where eligible, [Amazon Connect Global Resiliency](https://docs.aws.amazon.com/connect/latest/adminguide/create-replica-connect-instance.html) should be the first regional-continuity layer. It continuously mirrors a documented set of Connect resources and associations.

However:

- It is limited to supported Region pairs.
- The replica is in the same AWS account.
- Synchronization is bidirectional.
- Lambda, Lex, and third-party integrations are explicitly excluded.
- It is not a cyber-recovery backup: an erroneous or malicious configuration change can also synchronize.

Therefore, Global Resiliency and immutable point-in-time backups are complementary, not substitutes.

### 2. Customer-owned Connect storage

The current [`ListInstanceStorageConfigs`](https://docs.aws.amazon.com/connect/latest/APIReference/API_ListInstanceStorageConfigs.html) API identifies these storage domains:

- `CALL_RECORDINGS`
- `CHAT_TRANSCRIPTS`
- `SCREEN_RECORDINGS`
- `EMAIL_MESSAGES`
- `ATTACHMENTS`
- `CONTACT_EVALUATIONS`
- `SCHEDULED_REPORTS`
- `CONTACT_TRACE_RECORDS`
- `AGENT_EVENTS`
- `MEDIA_STREAMS`
- `REAL_TIME_CONTACT_ANALYSIS_SEGMENTS`
- `REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS`
- `REAL_TIME_CONTACT_ANALYSIS_VOICE_SEGMENTS`

Destinations can be S3, Kinesis Data Streams, Firehose, or Kinesis Video Streams.

#### S3 objects

Potential S3 content includes:

- Voice and IVR recordings
- Screen recordings
- Chat transcripts
- Email bodies and attachments
- Chat/task/case attachments
- Contact Lens output files and transcripts
- Contact evaluation exports
- Scheduled/exported reports
- Prompt audio stored outside Connect
- Customer Profiles exports
- Analytics data-lake exports

**Protection:**

- S3 versioning
- Cross-Region and preferably cross-account replication
- Independent destination-region KMS keys
- Lifecycle policies
- CloudTrail S3 data events
- Object checksums and replication-status monitoring
- Object Lock where legal and retention requirements justify immutability

AWS specifically documents [S3 Object Lock for immutable Connect call recordings](https://docs.aws.amazon.com/connect/latest/adminguide/s3-object-lock-call-recordings.html).

**Recovery:**

- Exact object recovery is normally feasible.
- Restoring objects does not automatically reconstruct contact search, thread metadata, Cases links, or Connect analytics in a new instance.
- Preserve both the object and its metadata index: contact ID, instance ID, channel, timestamp, bucket key, encryption key, content type, checksum, and related contact/case/profile IDs.

### 3. Contact records and analytics

Contact records underpin most historical metrics and contain:

- Contact lifecycle and channel
- Queues, agents, transfers, and routing
- Contact attributes
- Email metadata and thread relationships
- Recording and attachment locations
- Campaign and task context
- Related-contact chains

Connect retains contact records in the instance for [24 months](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-metrics.html). They should be streamed continuously through Kinesis or Firehose into organization-controlled storage.

The Connect analytics data lake has a fixed [rolling 25-month retention window](https://docs.aws.amazon.com/connect/latest/adminguide/data-lake-data-retention.html). Its tables include:

- Contact records and contact statistics
- Agent and queue statistics
- Flow events
- Contact Lens conversational analytics
- Contact evaluations
- Workforce shifts and time off
- Forecasts and schedule metrics
- Outbound campaign events
- Bot conversations, intents, and slots
- Cases events and related-item events

**Protection:** Scheduled CTAS/UNLOAD jobs into a protected S3 data lake, partitioned by data type and event date.

**Recovery reality:** These exports preserve evidence and analytics, but generally cannot be attached to a replacement instance so that native Connect dashboards behave as if the records originated there. The recovery product should provide Athena/Glue or an archive portal rather than promise native rehydration.

### 4. Kinesis, Firehose, and real-time streams

Consider:

- Contact records
- Agent events
- Real-time Contact Lens segments
- Chat message streams
- Live audio through Kinesis Video Streams
- Application-specific streams consumed by Lambda
- Firehose delivery streams, error buckets, and transformation functions

Kinesis is a transport with finite retention, not a long-term backup.

**Protection:**

- Archive every required stream to S3.
- Back up stream configuration, consumers, enhanced fan-out registrations, retention settings, encryption, and Firehose transformations.
- Monitor delivery delay, failed records, S3 freshness, and consumer lag.
- Preserve raw events before transformation where possible.

**Recovery:** Recreate streams and consumers from IaC. Historical events usually remain in the archive rather than being replayed into Connect unless an application-specific replay contract exists.

### 5. Email

[Connect email](https://docs.aws.amazon.com/connect/latest/adminguide/email-capabilities.html) divides persistence across systems:

- Message bodies and attachments: customer-owned SES S3 bucket
- To, CC, subject, state, related contact, and thread linkage: Connect contact records
- Domain identities, DKIM, receipt rules, configuration sets: SES
- Bounce and complaint events: SES/SNS/EventBridge, depending on configuration
- DNS records: external DNS provider or Route 53

**Protection:** Replicate S3 content and independently capture contact records, SES configuration, DNS configuration, suppression-list requirements, and bounce/complaint events.

**Recovery:** S3 recovery alone does not reconstruct a functioning Connect email thread. SES identities and domains must be verified in the recovery Region, and historical metadata should be presented through an archive if it cannot be imported.

### 6. Cases

Cases data comprises:

- Domains, fields, layouts, templates, SLA definitions
- Case records and custom fields
- Comments
- Contact links
- Files
- Related cases and custom related items
- Audit events and lifecycle history

The current tool restores configuration but not records. Connect now exposes [Cases event and related-item tables](https://docs.aws.amazon.com/connect/latest/adminguide/data-lake-cases-data.html) in the analytics data lake. Search/Get APIs can also enumerate current records.

**Protection:**

- Export current case state through the Cases APIs.
- Export lifecycle and related-item events from the data lake.
- Copy file attachments from their underlying storage.
- Preserve mappings between case, profile, contact, user, queue, template, field, and attachment IDs.

**Recovery fidelity:**

- Cases may be recreated through APIs.
- Original service-generated case IDs, timestamps, audit actors, event IDs, and complete lifecycle semantics generally cannot be assumed preservable.
- Links to old contacts and profile ARNs may not be valid in the target.

The product should offer two explicit outcomes:

1. **Cases archive:** exact historical evidence remains queryable.
2. **Operational case reconstruction:** selected open cases are recreated with provenance fields and original identifiers stored as custom metadata.

### 7. Customer Profiles

The scope includes:

- Standard profile records
- Custom profile objects
- Identity-resolution and merge state
- Object types and mappings
- Calculated attributes
- Segments
- AppFlow/AppIntegrations workflows
- Event streams and integration sources

AWS supports [bulk export of Customer Profiles object types to S3](https://docs.aws.amazon.com/connect/latest/adminguide/set-up-bulk-export.html). A separate export is required per object type, and data ingested during approximately the final 30 minutes may be absent.

**Protection:**

- Periodic full exports plus incremental exports based on last-update time
- Export every standard and custom object type
- Capture definitions, integrations, mappings, calculated attributes, segments, and matching configuration
- Retain source-system identifiers so profiles can be rebuilt from authoritative sources

**Recovery fidelity:** Profiles and objects can be re-ingested, but original profile IDs, merge outcomes, identity-resolution decisions, and calculated values may change. A restore proof-of-concept should establish whether the business requires:

- Exact identity continuity
- Functionally equivalent profiles
- Or reconstruction from the CRM/master customer system

For many organizations, the CRM should remain the authoritative source and Customer Profiles should be treated as a rebuildable projection.

### 8. Contact Lens and quality management

Include:

- Audio, chat, and email transcripts
- Redacted and unredacted variants
- Sentiment, categories, issues, summaries, and analytics
- Evaluation forms
- Draft and completed evaluations
- Automated evaluation results
- Coaching records
- Vocabularies and rule definitions
- Screen recordings

[Connect evaluations](https://docs.aws.amazon.com/connect/latest/adminguide/evaluations.html) can be stored/exported to S3. Contact Lens output is also available in S3 and in data-lake tables.

**Recovery:** Raw output, recordings, and evaluations can be retained exactly. Reconstructing their native Connect UI context is more limited. Generated models and some AI-derived state should be classified as **recompute/retrain**, not conventional restore.

### 9. Tasks, chat, attachments, and files

Tasks and chat span several systems:

- Contact records and attributes
- Chat transcripts
- Participant messages
- Task templates and integration associations
- Attached files in S3
- SNS/Kinesis/SQS if message streaming is enabled
- External ticket or CRM records that initiated tasks

A restored task template does not restore historical or pending tasks.

For active work at disaster time, define whether the business needs:

- Pending tasks replayed into the recovery instance
- Open tasks recreated from the originating system
- Or historical tasks available only in an archive

The originating CRM/ticketing platform is usually the safest source for rebuilding pending work.

### 10. Outbound campaigns

Include:

- Campaign definitions and schedules
- Dial requests and recipient lists
- Customer Profiles segments
- End User Messaging configuration
- SES/SMS channel configuration
- Contact dispositions
- Suppression and consent records
- Campaign events and analytics

Campaign events are exposed in the analytics data lake, but historical campaigns and in-flight work should not be assumed replayable. Consent, suppression, and regulatory calling state must be recovered from their authoritative system before campaigns resume.

### 11. Workforce management

Include:

- Forecast groups and staffing groups
- Short-, long-, and intraday forecasts
- Schedules and schedule goals
- Agent shifts
- Time off and time-off intervals
- Adherence and schedule metrics
- External HR/workforce integrations

Some of this state can be retained from the data lake, but managed forecasting models may need to be recreated or retrained. Historical exports can accelerate rebuilding but are not a native model backup.

### 12. Amazon Q, Lex, Voice ID, and AI state

#### Amazon Q in Connect / Wisdom

Back up:

- Knowledge base and assistant configuration
- Quick responses and message templates
- Source documents
- S3/CRM/SharePoint/Salesforce connectors
- AppIntegrations/AppFlow state
- Secrets and OAuth configuration
- Guardrails, prompts, AI-agent configuration, and associations

The most important backup is often the authoritative knowledge source plus reproducible ingestion configuration.

#### Amazon Lex

Back up:

- Bot, locales, intents, slots, slot types
- Versions and aliases
- Lambda hooks
- Bot resource policies
- Conversation logs in S3/CloudWatch
- Build settings and test artifacts

The current dependency tool captures only part of this.

#### Voice ID

Treat speaker enrollments, watchlists, fraudster data, consent state, and domain configuration as a separate service-managed security domain. Unless current service APIs explicitly support export/import for the required objects, classify them as re-enrollment/reconstruction rather than promising recovery.

### 13. Lambda and execution-layer dependencies

A usable backup must include more than Lambda ZIP files:

- Code or container image digest
- Runtime, architecture, handler, memory, timeout
- Environment variables
- KMS configuration
- Layers
- Versions and aliases
- Reserved/provisioned concurrency
- Execution role and permissions boundary
- Resource policy
- VPC, subnet, and security-group configuration
- Event-source mappings
- Destinations and dead-letter queues
- Tags, tracing, signing configuration
- CloudWatch alarms and log retention

Code should preferably be rebuilt from source and immutable artifacts rather than recovered from a downloaded deployment ZIP.

### 14. Runtime application stores

These are not Connect-owned, but often determine whether restored flows function.

| Store | Typical Connect use | Recovery treatment |
|---|---|---|
| DynamoDB | Customer lookup, routing, state, idempotency | Global tables for low RPO, or PITR/AWS Backup with cross-Region and cross-account copies |
| S3 | Configuration, templates, prompts, documents | Versioning, replication, Object Lock where required |
| RDS/Aurora | CRM or transactional state | PITR, cross-Region replicas/global database, cross-Region backup copies |
| OpenSearch | Search and interaction analytics | Snapshots to protected S3 or cross-cluster strategy |
| EFS/FSx/EBS | Integration application state | Native replication/AWS Backup |
| SQS | Work queues and dead letters | Recreate configuration; design producers for replay because queue contents are not a durable backup |
| SNS/EventBridge | Events and routing | IaC plus archives/replay where supported |
| Kinesis/Firehose | Contact and application streams | Archive to S3; recreate transport from IaC |
| Secrets Manager | Credentials and tokens | Multi-Region secret replication and independently recoverable KMS keys |
| Parameter Store/AppConfig | Runtime configuration | IaC/export, version history, replicated configuration |
| External CRM/ticketing/payment systems | Authoritative customer and case state | Vendor-specific backup and continuity contract |

A future solution should discover these dependencies from:

- Lambda environment variables and configuration
- IAM resource ARNs
- Flow definitions
- Event-source mappings
- AppFlow/AppIntegrations
- Tags and an operator-supplied dependency manifest

Automatic discovery should produce recommendations, not automatically copy every discovered resource.

### 15. Identity, keys, telephony, and operational evidence

Also include:

- SAML/OIDC/Identity Center applications and assignments
- SCIM provisioning
- IAM roles, resource policies, and service-linked roles
- KMS keys, aliases, policies, and grants
- Certificates, SES identities, and DNS records
- Claimed telephone numbers and traffic distribution groups
- CloudTrail, AWS Config, CloudWatch Logs/metrics/alarms
- EventBridge rules and archives
- X-Ray traces where operationally needed
- Build artifacts, container images, deployment pipelines, and source repositories

KMS is especially important: copied encrypted data is not recoverable if the recovery environment cannot use a surviving key. Destination copies should use destination-controlled keys and explicit, least-privilege key policies.

## Recommended next-version architecture

### 1. Recovery manifest

Generate a versioned manifest for every backup:

```text
resource/data domain
system of record
source account and Region
sensitivity and retention class
native identifiers and logical name
storage location and KMS key
dependencies
export watermark
object/record counts and checksums
recovery method
expected recovery fidelity
target RPO/RTO class
validation procedure
```

Never store real production manifests in the source repository.

### 2. Six protection planes

1. **Configuration plane:** Connect API snapshots and IaC.
2. **Object plane:** S3 replication, versioning, lifecycle, and optional Object Lock.
3. **Streaming plane:** Kinesis/Firehose archives to S3.
4. **Managed-record plane:** Profiles exports, Cases/data-lake exports, evaluation exports.
5. **Application plane:** DynamoDB, databases, secrets, queues, source artifacts, and external systems.
6. **Recovery plane:** Dependency-aware restore orchestration, ID remapping, validation, and evidence reporting.

### 3. Recovery modes

Support separate declared modes:

- **Regional continuity:** Global Resiliency plus multi-Region dependencies.
- **Cross-account cyber recovery:** Restore from immutable, isolated backups.
- **Point-in-time configuration rollback:** Recover before accidental or malicious change.
- **Historical evidence access:** Query recordings, Cases, contact records, and analytics without pretending they are rehydrated into Connect.
- **Permanent migration:** Rebuild service-managed records where supported and document changed IDs/provenance.

### 4. Fidelity status per data type

Every restore report should label each domain:

- **Native failover**
- **Exact native restore**
- **Functionally reconstructed**
- **Archive/query access only**
- **Retrain/re-enroll**
- **Unavailable/manual**

This prevents an overall “restore succeeded” result when only configuration was restored.

## Prioritized roadmap

### Priority 0 — recovery foundation

1. Fix current documentation/implementation drift and restore ordering issues.
2. Extend the backup manifest to cover every current Connect storage resource type, including email messages and channel-specific analysis streams.
3. Store configuration backups in a central recovery account with versioning, immutable retention where appropriate, cross-Region copies, and independent KMS keys.
4. Add S3 replication validation for recordings, transcripts, email, attachments, evaluations, reports, and Contact Lens files.
5. Continuously archive contact records, agent events, and analysis streams.
6. Expand Lambda/Lex capture to full reproducible deployment configuration.
7. Add recovery-fidelity reporting and dependency-graph validation.

### Priority 1 — customer and operational data

1. Automate Customer Profiles full and incremental exports.
2. Export every analytics data-lake table before its 25-month expiry.
3. Build Cases snapshots from APIs plus Cases event exports from the data lake.
4. Add native protection adapters for DynamoDB, RDS/Aurora, Secrets Manager, S3, and OpenSearch.
5. Provide an archive index linking contact, case, profile, recording, transcript, evaluation, and attachment records.
6. Validate backup freshness, counts, checksums, replication status, and encryption-key usability.

### Priority 2 — selective reconstruction

1. Recreate open Cases with provenance metadata.
2. Test Customer Profiles reconstruction and identity-resolution behavior.
3. Offer recording ingestion only as an explicitly lossy migration path. AWS documents that [recording ingestion](https://docs.aws.amazon.com/connect/latest/adminguide/recording-ingestion.html) creates imported contacts with new Connect timestamps and cannot attach recordings to normal existing contacts.
4. Rebuild campaign, workforce, Amazon Q, and Voice ID capabilities through service-specific adapters.
5. Add scheduled isolated restore drills and synthetic voice/chat/task/email acceptance tests.

## Suggested business recovery tiers

These are starting points; the organization should set the actual values.

| Tier | Data/capability | Typical objective |
|---|---|---|
| T0 | Telephony, identity, flows, queues, routing, security, Lambda/Lex reachability | Near-current configuration; restore first |
| T1 | DynamoDB/databases, secrets, pending work, Profiles needed for routing | Seconds-to-minutes RPO where justified |
| T2 | Recordings, transcripts, email, Cases, evaluations, consent records | Immutable retention; hours-level operational access |
| T3 | Historical analytics, forecasts, campaign history, AI outputs | Daily export; recovery may take days |

## Final recommendation

The next version should not attempt to make every data set “look native” in a replacement Connect instance. Instead, promise three measurable outcomes:

1. **Resume customer service:** routing, agents, channels, and dependencies function. Called Minimally Reachable Service
2. **Preserve organizational records:** recordings, messages, Cases, Profiles, evaluations, and analytics remain secure and queryable.
3. **Reconstruct selected operational state:** only where APIs permit a safe, supportable replay, with changed IDs and fidelity limitations clearly reported.

Global Resiliency should handle eligible regional failover. This solution should become the complementary **cross-account, point-in-time, cyber-recovery, and historical-data preservation layer**.

## Research note

The Recommendation Engine could not be checked because its MCP operations were unavailable in the research session; the official public AWS documentation and repository implementation were reviewed instead.

Content sourced from public documentation was rephrased for compliance with licensing restrictions.
