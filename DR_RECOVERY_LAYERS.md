# Recovery Layers, Backlog Reconciliation, and Platform Change Review

Status date: November 2026
Last repository commit: 2026-07-28 (`6389683`)
Elapsed: approximately four months

Companion documents:
- [CONNECT_CATASTROPHIC_RECOVERY_DATA_SCOPE.md](./CONNECT_CATASTROPHIC_RECOVERY_DATA_SCOPE.md) — full data-store inventory
- [DR_TIER_WORKSHOP_PACK.md](./DR_TIER_WORKSHOP_PACK.md) — tier models and leader workshop
- [BACKLOG.md](./BACKLOG.md) — now stale, see Section 2

---

## Contents

1. [Executive summary](#1-executive-summary)
2. [Backlog reconciliation](#2-backlog-reconciliation)
3. [Immediate safety finding](#3-immediate-safety-finding)
4. [Platform changes since the last commit](#4-platform-changes-since-the-last-commit)
5. [New backup surface — gap table](#5-new-backup-surface--gap-table)
6. [The strategic shift](#6-the-strategic-shift)
7. [The three recovery layers](#7-the-three-recovery-layers)
8. [Layer 1 — Reachability](#8-layer-1--reachability)
9. [Layer 2 — Records](#9-layer-2--records)
10. [Layer 3 — Reconstruction](#10-layer-3--reconstruction)
11. [Full domain allocation](#11-full-domain-allocation)
12. [Revised priority order](#12-revised-priority-order)

---

## 1. Executive summary

Three findings matter most.

**The backlog is not empty.** `BACKLOG.md` states no outstanding items, which was true on 2026-07-28. Since then an entire unreleased capability (`connect_assess`) plus two specification documents were written in August and never committed. They are still sitting untracked in the working tree.

**`.gitignore` does not do what its comment says.** It contains a comment instructing that backup output directories must never be committed, but no matching pattern. Three such directories currently sit untracked and contain real AWS account identifiers and resource IDs. See Section 3.

**Amazon Connect Global Resiliency now mirrors more configuration than this toolkit backs up.** Since July, Global Resiliency has gained quick responses, the knowledge base behind them, and chat support. Its mirrored-resource list already included workspaces, flow module versions and aliases, custom metrics, test cases, notifications, and saved reports — none of which this toolkit captures. Breadth of configuration coverage is no longer the toolkit's differentiator. Cross-account isolation, point-in-time rollback, and cyber recovery are. This should change how the next version is positioned and built.

---

## 2. Backlog reconciliation

### Uncommitted work sitting in the working tree

| Artefact | Date | State |
|---|---|---|
| `bin/connect_assess` | Aug 4 | v1.0.0, functional, untracked |
| `DR_ASSESS_GUIDE.md` | Aug 4 | Complete, untracked |
| `tests/run_assess_tests.sh` + `tests/fixtures/assess/` | Aug 4 | Untracked |
| `DR_MODES_SPEC.md` | Aug 3 | **Draft, never implemented** |
| `.kiro/steering/customer-profiles-decision.md` | Jul 28 | Untracked, referenced by `BACKLOG.md` |
| `CONNECT_CATASTROPHIC_RECOVERY_DATA_SCOPE.md` | Nov | Untracked |
| `DR_TIER_WORKSHOP_PACK.md` | Nov | Untracked |

`connect_assess` performs static analysis of flow JSON to identify blocks with external dependencies and trace their error paths, classifying flows as graceful or not. It requires no AWS credentials. It is directly relevant to Layer 1 below, and is the most valuable uncommitted asset here.

`DR_MODES_SPEC.md` specifies `--mode dr` versus `--mode migrate`, dependency stubs, and selective feature disablement. **None of it exists under `bin/`.** The current `connect_restore` has no `--mode` flag. Anyone reading that spec as current will be misled.

### Reopened items

| # | Item | Why reopened |
|---|---|---|
| B1 | Fix `.gitignore` to actually exclude backup output directories | Safety — Section 3 |
| B2 | Commit or discard the August `connect_assess` work | Four months of unversioned work at risk |
| B3 | Mark `DR_MODES_SPEC.md` as unimplemented, or implement it | Spec/implementation divergence |
| B4 | Terminology refresh across all docs | Platform renames, Section 4 |
| B5 | Restore ordering defects | Queue-to-quick-connect associations replay before the quick connects are created; hours overrides replay before new hours are created. Both can require a second run. |
| B6 | Stale limitation text | README "Known Limitations" still says Cases restore is manual; it was automated in Phase 4. Prompt audio and Lex restore claims remain broader than the implementation. |
| B7 | New resource coverage | Section 5 |

---

## 3. Immediate safety finding

`.gitignore` currently reads, in part:

```
# Backup output directories (contain real instance data)
# These are produced by connect_backup runs — never commit
*.log
```

The comment describes an intent that the file does not implement. Only `*.log` is excluded, which catches `dr-solution-target.log` but not the directories themselves.

Currently untracked and **not ignored**:

- `dr-solution-target/` (128 entries)
- `qs-builder-in-sydney/` (109 entries)
- `helper/`

These contain real 12-digit AWS account IDs, real instance and resource IDs, and real ARNs. A single `git add -A` would stage all of them. If pushed to a public remote, scrubbing requires history rewrite, not a follow-up deletion.

Recommended patterns:

```
# Backup output directories (contain real instance data)
# These are produced by connect_backup runs — never commit
dr-solution-target/
qs-builder-in-sydney/
helper/
helper.*/
*.log
```

A durable alternative is to require all backup output under a single ignored parent, for example `output/`, and have `connect_backup` default there. That removes the need to add a new pattern each time an instance alias changes.

---

## 4. Platform changes since the last commit

### Terminology renames — 4 August 2026

Amazon Connect renamed several things. Current documentation uses the new names throughout, so the repository's vocabulary is now inconsistent with AWS documentation.

| Previously | Now |
|---|---|
| Amazon Connect | **Amazon Connect Customer** |
| Contact Lens | **conversational analytics** |
| Amazon Q in Connect | **agent assist** |

This affects `README.md`, `DR_VALIDATION_SPEC.md`, `DR_OPERATOR_GUIDE.md`, validation layer names, and user-facing script output. It is cosmetic but it degrades credibility with anyone cross-referencing AWS docs.

### Feature timeline, August to November 2026

Drawn from the [Connect Customer document history](https://docs.aws.amazon.com/connect/latest/adminguide/doc-history.html) and [release notes](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-release-notes.html).

| Date | Change | Recovery relevance |
|---|---|---|
| Aug 4 | Feature name changes | Documentation only |
| Aug 11 | Email loop handling guidance | Flow logic, no new resource |
| Aug 12 | Manager assist (**preview**) | Defer until GA |
| Sep 16 | **Custom metrics APIs GA** | New backup surface |
| Sep 21 | Data tables create/configure guidance | Already covered |
| Sep 23 | Service level on intraday forecast dashboard | Layer 3 |
| Sep 24 | Connection information when starting chat | Layer 1 context |
| Sep 29 | Contact attributes and contact ID in campaign voice dials | Campaign config |
| Sep | **Live Sync and Touchpoint** | New entry point, Layer 1 |
| Sep 30 | Attachment preview in agent workspace | No new store |
| Oct 6 | Agent-to-agent collaboration | New contact behaviour |
| Oct | **Shift bidding** | Layer 3 workforce data |
| Oct | **Segment membership events in Customer Profiles** | Layer 2/3 |
| Oct | Import evaluation form PDFs with AI | Evaluation form authoring |
| Oct 12 | Step-by-step guides reorganised, after-contact-work prefill | Guides as a resource |
| Oct 20 | **Global Resiliency for chat** | Changes Layer 1 options |
| Oct 21 | Modern and Classic agent workspace layouts | Workspace config |
| Oct 22 | Profile Explorer layout in agent workspace | Profiles domain layouts |
| Oct 26 | **Email draft auto-save** | New mutable record |
| Oct 28 | **`evaluation_review_record` data lake table** | Layer 3 export target |
| Nov 13 | **Global Resiliency for quick responses** | Changes Layer 1/3 boundary |
| Nov 13 | agent assist interactive responses, MCP tools | New AI configuration |
| Nov 16 | **Resolutions** (Work plans) | Significant, see below |
| Nov 16 | Cases enablement at instance creation, Cases event streams, Cases integrations | New Cases config |
| Nov | Batch actions on up to 100 Cases | Record operations |
| Nov | Cases **Phases** | New Cases config concept |
| Nov | Rules can end associated email contacts from a case | Rule action type |

### Global Resiliency expansion

Two additions materially change the recovery conversation.

**Quick responses** (13 Nov) now replicate, including the `QUICK_RESPONSES` knowledge base and the `WISDOM_QUICK_RESPONSES` integration association. Quick responses keep the same IDs in both Regions. Changes to quick responses replicate bidirectionally; knowledge base changes replicate one way, source to replica only. If the knowledge base uses a customer managed key, nothing replicates until a key is registered in the replica Region. Quick responses grouped by routing profile only replicate if those routing profiles exist in the replica.

**Chat** (20 Oct) is supported, but with an important caveat: communication widgets are **not** replicated. You must create a second widget in the replica instance and switch the embedded script on your website to move chat traffic. AWS suggests holding the active Region in an external store such as a DynamoDB global table and updating it alongside `UpdateTrafficDistribution`.

### Resolutions — the most architecturally significant addition

[Resolutions](https://docs.aws.amazon.com/connect/latest/adminguide/resolutions.html) turns standard operating procedures into Work plans that AI agents execute, with human specialists handling approvals and exceptions.

Why it matters for recovery: **publishing a Work plan generates Connect resources.** Resolutions creates the flows, Case template, Case fields, and Task templates the plan requires, and optionally a dedicated outbound queue and outbound whisper flow, plus an information extraction flow.

This inverts the usual backup assumption. If you back up only the generated artefacts — flows, case templates, fields, task templates — you restore a set of orphaned resources with no governing Work plan. The **Work plan definition is the system of record**, and the generated Connect resources are derived output.

Also note that Resolutions does not automatically modify existing inbound contact flows, because those flows may serve other purposes. The wiring from inbound flow to information extraction flow is a manual step, which means it is a manual step during recovery too.

Resolutions introduces a new `ResolutionsUser` security profile, and Cases now support Phases.

---

## 5. New backup surface — gap table

Verified against the toolkit's actual API calls. The toolkit currently invokes 60+ Connect operations plus Cases, Customer Profiles, and `connect-campaigns-v2`.

| Resource | API | In toolkit? | Mirrored by Global Resiliency? | Layer |
|---|---|---|---|---|
| Custom metrics | `ListMetrics`, `DescribeMetric`, `CreateMetric`, `SearchMetrics` | **No** | Yes | 3 |
| Quick responses | qconnect / Wisdom quick responses | **No** | Yes (since Nov 13) | 3 |
| `QUICK_RESPONSES` knowledge base | qconnect | **No** | Yes, one-way | 3 |
| Test cases | `ListTestCases`, `SearchTestCases` | **No** | Yes | 3 |
| Workspaces | Workspace APIs | **No** | Yes | 3 |
| Flow module versions and aliases | Module version APIs | **No** | Yes | 1 |
| Contact flow versions | Flow version APIs | **No** | Partial | 1 |
| Notifications | Notification APIs | **No** | Yes | 3 |
| Saved reports | Saved report APIs | **No** | Yes, **schedules excluded** | 3 |
| Saved report schedules | — | **No** | **No** | 3 |
| Communication widgets | Widget config | **No** | **No** | 1 |
| Cases event configuration | `GetCaseEventConfiguration` | **No** | n/a | 2 |
| Cases case rules | `BatchGetCaseRule` | **No** | n/a | 2 |
| Cases Phases | Cases config | **No** | n/a | 2 |
| Cases SLA configuration | Cases config | **No** | n/a | 2 |
| Profiles domain layouts | `ListDomainLayouts` | **No** | n/a | 2 |
| Profiles segment definitions | `ListSegmentDefinitions` | **No** | n/a | 2/3 |
| Resolutions Work plans | Resolutions | **No** | Unknown | 1/2 |
| agent assist AI agent config, MCP tools | agent assist | **No** | Partial | 3 |
| Live Sync scripts, Touchpoint, ACXD apps | ACXD | **No** | Unknown | 1 |
| Email drafts | Draft storage | **No** | n/a | 2 |
| Shift bidding | WFM | **No** | n/a | 3 |
| Evaluation review records | Data lake table | **No** | n/a | 3 |

Already covered and still current: instance attributes, storage configs, approved origins, authentication profiles, security keys, flows and modules, queues, routing profiles, quick connects, hours and overrides, users, hierarchy, security profiles and permissions, agent statuses, predefined attributes, proficiencies, task templates, evaluation forms, rules, views, vocabularies, data tables including row data, prompts metadata, phone numbers, email addresses, Cases domain/fields/layouts/templates, Profiles domain/object types/calculated attributes, campaigns via `connect-campaigns-v2`, Lambda and Lex associations.

---

## 6. The strategic shift

In July, the toolkit's value was broad Connect configuration capture. That is no longer the gap.

Global Resiliency, where available, now continuously mirrors flows, modules and their versions and aliases, queues, routing profiles, users, security profiles, hours, quick connects, predefined attributes, prompts, hierarchies, agent statuses, saved reports, views, data tables, workspaces, custom metrics, test cases, notifications, quick responses and their knowledge base, plus the key associations.

What Global Resiliency does **not** give you:

1. **Cross-account isolation.** The replica is in the same AWS account. Account compromise or insider action affects both.
2. **Point-in-time rollback.** Synchronisation is bidirectional and near real time. A destructive or malicious change propagates, with a 30-minute catch-up window if the immediate sync fails.
3. **Region freedom.** Supported Region pairs only. Osaka is replica-only. Sydney is not in the list.
4. **Execution-layer coverage.** Lambda, Lex, and third-party integrations are explicitly excluded.
5. **Records.** No recordings, transcripts, contact records, case records, or profile records.
6. **Saved report schedules** and **communication widgets**, even though the parent resources replicate.

The next version should therefore stop competing with Global Resiliency on configuration breadth and position explicitly as the **cross-account, point-in-time, cyber-recovery and records-preservation layer** — complementing Global Resiliency where it is available, and substituting for it where it is not.

---

## 7. The three recovery layers

Replacing the earlier flat tier framing with three layers, each with its own goal, owner, exit criteria, and failure mode.

| | Layer 1 — Reachability | Layer 2 — Records | Layer 3 — Reconstruction |
|---|---|---|---|
| **Goal** | A contact can reach the business and be served | The organisation can produce and continue customer records | Rebuild everything else |
| **Question answered** | Can customers get through? | Can we honour and evidence our obligations? | Can we operate at full capability? |
| **Primary method** | Failover or rebuild of configuration | **Attach** surviving stores, or restore records | Re-ingest, recompute, retrain, recreate |
| **Target horizon** | Minutes to hours | Hours to days | Days to weeks |
| **Owner** | Contact centre operations plus platform engineering | Data, records, risk and compliance | Capability owners per feature |
| **Fails when** | Nobody can call in | Auditors or customers cannot be served evidence | Reporting and AI features stay degraded |
| **Accept partial?** | No | No, for regulated records | Yes, explicitly |

The layers are **sequential in execution but independent in design**. Layer 1 must not depend on Layer 2 or 3 completing. Layer 2 must not require Layer 1 to be finished, because attaching storage can proceed in parallel.

The most common planning error is to treat these as one restore with one completion state. A run that restores configuration and reports success while recordings remain unreachable and Cases are absent has completed Layer 1 only. Report per layer.

---

## 8. Layer 1 — Reachability

**Definition:** the minimum set of resources required for an inbound contact to arrive, route, and be answered or deliberately deflected.

### Minimum viable set

| Requirement | Notes |
|---|---|
| Active instance, correct alias, instance attributes | Must pre-exist; cannot be created by restore |
| Identity and sign-in | SAML or Identity Center. Users must have instance access, not merely exist |
| Claimed phone numbers | Cannot be claimed cross-account by API. Must be pre-provisioned |
| Number-to-flow associations | Restorable |
| At least one inbound flow per entry point | Plus referenced modules |
| Flow module versions and aliases | **Gap.** If flows reference a module alias, restoring content alone is insufficient |
| Queues, routing profiles, hours of operation | Restorable |
| Security profiles, agent statuses | Restorable |
| Data tables including row data | **Layer 1, not Layer 3.** Flows perform routing lookups against them |
| Storage configuration associations | Prevents recording and transcript write failures at contact time |
| Lambda and Lex reachable, or gracefully bypassed | This is what `connect_assess` evaluates |
| Communication widget, if chat is an entry point | **Gap.** Not replicated by Global Resiliency either |
| Touchpoint and Live Sync configuration, if used as an entry point | **Gap.** New since July |
| Resolutions inbound flow wiring, if email intake drives Work plans | Manual by design |

### Explicitly out of scope for Layer 1

Cases, Customer Profiles, conversational analytics, evaluations, agent assist, campaigns, forecasting, scheduling, historical dashboards, custom metrics, test cases, saved reports.

Agents can work without all of these. Stating this explicitly is what keeps Layer 1 fast.

### Exit criteria

1. A test voice call reaches a live agent through the production entry point.
2. A test chat reaches a live agent, if chat is in scope.
3. `connect_assess` reports graceful degradation for every entry flow.
4. `connect_validate` passes the layers covering instance, flows, routing, queues, hours, users, security, and phone mappings.
5. Recording and transcript writes succeed for the test contacts.

Criterion 5 matters: a contact that connects but fails to record is a compliance incident in regulated environments, not a success.

### Design rule

Layer 1 must be executable **without any dependency on record restoration**. If the toolkit cannot complete Layer 1 while Layer 2 is still running, the layering is not real.

---

## 9. Layer 2 — Records

**Definition:** the organisation can continue to produce, serve, and evidence customer records.

The central insight is that Layer 2 has two distinct modes, and choosing correctly determines whether recovery takes hours or weeks.

### Attach versus restore

**Attach** — point the recovered instance at stores that survived.

Most Connect payload data already lives in customer-owned S3. If those buckets survive, or have been replicated, you do not move data. You re-associate storage configuration and ensure cross-account and KMS access works. This applies to call and screen recordings, chat transcripts, email bodies and attachments, evaluations, scheduled reports, and conversational analytics output.

Attach is dramatically faster and should always be the default. The toolkit already re-associates storage configuration, though it currently points at original buckets and continues past some association failures.

**Restore** — copy records into a service that owns them.

Required where data lives inside a managed service rather than your bucket: Cases records, Customer Profiles records, and data tables. These cannot be attached; they must be re-ingested, with the fidelity caveats documented in the scope assessment.

### Coverage

| Domain | Mode | Current state |
|---|---|---|
| Storage configuration associations | Attach | Covered, needs failure-handling hardening |
| S3 payloads (recordings, transcripts, email, attachments, evaluations, reports, analytics output) | Attach | **Not validated by the toolkit.** Needs replication and key-usability checks |
| Contact records | Stream and archive | **Gap.** 24-month in-instance retention; must be streamed out |
| Cases configuration, including Phases, event configuration, case rules, SLA | Restore | **Gap** for the newer config types |
| Cases records, comments, related items, attachments | Restore or archive | Out of scope by decision; archive path still needed |
| Customer Profiles configuration, including domain layouts and segments | Restore | **Gap** for layouts and segments |
| Customer Profiles records | Restore or rebuild from CRM | Out of scope by decision |
| Email drafts | Restore | **Gap.** New since October |
| Consent and suppression records | Restore from authoritative source | Not modelled |
| Data table row data | Restore | Covered |

### Exit criteria

1. A named historical contact can be retrieved with its recording and transcript playable.
2. Encryption keys in the recovery environment can decrypt the attached objects.
3. Replication lag and object counts reconcile against source.
4. Regulated retention periods remain satisfied, with immutability intact where required.
5. Cases and Profiles configuration exists so that **new** records can be created correctly, even where historical records are archive-only.

Criterion 5 is the pragmatic separation: you may accept that historical cases are query-only while still requiring that agents can open new cases correctly on day one.

### Design rule

Layer 2 must distinguish, in its output, between *attached*, *restored*, *archive-only*, and *absent*. A single success flag here is actively misleading.

---

## 10. Layer 3 — Reconstruction

**Definition:** rebuild capability that can neither be failed over nor attached, accepting that some of it changes identity or must be recomputed.

### Coverage

| Domain | Method | Notes |
|---|---|---|
| Historical analytics and data lake | Re-export, query via Athena | Fixed rolling 25-month window; export before expiry |
| Evaluation review records | Data lake export | New October table |
| Custom metrics definitions | Recreate via `CreateMetric` | **Gap.** Mirrored by Global Resiliency |
| Saved reports and schedules | Recreate | **Gap.** Schedules excluded from Global Resiliency |
| Test cases | Recreate | **Gap** |
| Workspaces and agent workspace layouts | Recreate | **Gap** |
| Notifications | Recreate | **Gap** |
| agent assist: knowledge bases, quick responses, AI agent config, MCP tools | Re-ingest from authoritative sources | Quick responses now mirrored by Global Resiliency; otherwise rebuild |
| Conversational analytics models and categories | Re-enable, recreate rules and vocabularies | Models are service-managed |
| Forecasting, scheduling, shift bidding | Recreate, retrain | No export and import path |
| Outbound campaigns | Recreate | Definitions captured; runtime setup manual |
| Voice ID | Re-enrol | Treat as re-enrolment, not restore |
| Resolutions Work plans | Republish from Work plan definition | **Work plan is the system of record**; generated resources are derived |
| Live Sync scripts, Touchpoint, ACXD applications | Recreate | New since September |

### Exit criteria

Per capability, not in aggregate. For each: either the capability is restored, or its absence is a recorded and accepted gap with an owner and a target date.

### Design rule

Layer 3 should be explicitly **partial and prioritised**. Attempting completeness here is what causes recovery programmes to overrun. The correct output is a ranked list with named owners, not a single progress bar.

---

## 11. Full domain allocation

Every domain from the scope assessment, assigned to exactly one layer.

| Domain | Layer |
|---|---|
| Instance, attributes, alias | 1 |
| Identity, SSO, users, instance access | 1 |
| Phone numbers and number-to-flow mapping | 1 |
| Flows, modules, versions, aliases | 1 |
| Queues, routing profiles, quick connects, hours | 1 |
| Security profiles, permissions, hierarchy, agent statuses | 1 |
| Predefined attributes, proficiencies | 1 |
| Data tables (schema and rows) | 1 |
| Storage configuration associations | 1 |
| Lambda and Lex invocation reachability | 1 |
| Communication widgets, Touchpoint, Live Sync | 1 |
| Runtime stores needed for routing decisions (DynamoDB, secrets) | 1 |
| Prompts and prompt audio | 1 |
| Resolutions inbound wiring | 1 |
| S3 payloads: recordings, screen recordings, transcripts | 2 |
| Email bodies, attachments, drafts | 2 |
| Attachments and attached files | 2 |
| Contact records and agent events | 2 |
| Evaluations and evaluation exports | 2 |
| Cases configuration, Phases, event config, rules, SLA | 2 |
| Cases records and related items | 2 |
| Customer Profiles configuration, layouts, segments | 2 |
| Customer Profiles records | 2 |
| Consent and suppression records | 2 |
| Historical analytics and data lake tables | 3 |
| Custom metrics, saved reports and schedules, test cases, workspaces, notifications | 3 |
| agent assist, knowledge bases, quick responses, MCP tools | 3 |
| Conversational analytics models, categories, vocabularies | 3 |
| Forecasting, scheduling, shift bidding | 3 |
| Outbound campaigns | 3 |
| Voice ID enrolments | 3 |
| Resolutions Work plan definitions | 3 for rebuild, 1 for generated artefacts |

---

## 12. Revised priority order

### P0 — Hygiene and safety

1. Fix `.gitignore` so backup output directories are genuinely excluded. **Do this before any `git add`.**
2. Commit the August `connect_assess` work, its guide, and its tests.
3. Mark `DR_MODES_SPEC.md` as an unimplemented draft, or delete it.
4. Correct stale limitation text in `README.md` and `DR_OPERATOR_GUIDE.md`.
5. Refresh terminology to Amazon Connect Customer, conversational analytics, and agent assist.

### P1 — Make the three layers real in the tooling

6. Add a `--layer 1|2|3` selector to backup, restore, and validate so each layer runs and reports independently.
7. Report outcomes per layer, with the fidelity labels: attached, restored, reconstructed, archive-only, absent.
8. Fix the restore ordering defects (B5) so a single run completes Layer 1 deterministically.
9. Promote `connect_assess` into the Layer 1 exit criteria, and gate Layer 1 completion on it.
10. Add Layer 1 coverage for the current gaps: flow and module versions and aliases, communication widgets, Touchpoint and Live Sync.

### P2 — Records layer

11. Add storage attach validation: replication status, object counts, and decryption checks in the recovery environment.
12. Add contact record streaming and archive verification.
13. Extend Cases backup to event configuration, case rules, Phases, and SLA configuration.
14. Extend Customer Profiles backup to domain layouts and segment definitions.
15. Add email draft handling.
16. Build the archive index linking contact, case, profile, recording, transcript, and attachment records.

### P3 — Reconstruction layer

17. Add custom metrics backup and restore via `ListMetrics`, `DescribeMetric`, and `CreateMetric`.
18. Add saved reports and, critically, their schedules, which Global Resiliency omits.
19. Add test cases, workspaces, and notifications.
20. Add quick responses and the `QUICK_RESPONSES` knowledge base, for environments without Global Resiliency.
21. Add Resolutions Work plan capture, treating the Work plan as the system of record for its generated flows, case templates, fields, and task templates.
22. Reassess Manager assist once it leaves preview.

### P4 — Positioning

23. Rewrite the README scope section around the three layers and the Global Resiliency complement, per Section 6.
24. Document the Region eligibility constraint prominently, including that Sydney is not currently a supported Global Resiliency Region.

---

## Sources

- [Connect Customer document history](https://docs.aws.amazon.com/connect/latest/adminguide/doc-history.html)
- [Release notes for Connect Customer](https://docs.aws.amazon.com/connect/latest/adminguide/amazon-connect-release-notes.html)
- [Create a replica of your existing instance](https://docs.aws.amazon.com/connect/latest/adminguide/create-replica-connect-instance.html)
- [Global Resiliency for quick responses](https://docs.aws.amazon.com/connect/latest/adminguide/global-resiliency-quick-responses.html) and [mirrored resources](https://docs.aws.amazon.com/connect/latest/adminguide/global-resiliency-quick-responses-resources.html)
- [Manage chat across Regions](https://docs.aws.amazon.com/connect/latest/adminguide/manage-chat-across-regions.html)
- [Resolutions](https://docs.aws.amazon.com/connect/latest/adminguide/resolutions.html)
- [Custom metrics APIs announcement](https://aws.amazon.com/about-aws/whats-new/2026/09/connect-customer-custom-metrics-apis/), [CreateMetric](https://docs.aws.amazon.com/connect/latest/APIReference/API_CreateMetric.html), [ListMetrics](https://docs.aws.amazon.com/connect/latest/APIReference/API_ListMetrics.html), [DescribeMetric](https://docs.aws.amazon.com/connect/latest/APIReference/API_DescribeMetric.html), [SearchMetrics](https://docs.aws.amazon.com/connect/latest/APIReference/API_SearchMetrics.html)
- [Live Sync and Touchpoint](https://docs.aws.amazon.com/connect/latest/devguide/touchpoint.html)
- [ListInstanceStorageConfigs](https://docs.aws.amazon.com/connect/latest/APIReference/API_ListInstanceStorageConfigs.html)
- [Data retention in the analytics data lake](https://docs.aws.amazon.com/connect/latest/adminguide/data-lake-data-retention.html)

Repository state established from `git log`, working-tree inspection, and static analysis of the API calls in `bin/lib/backup/`.

Content drawn from public AWS documentation was rephrased and summarised for compliance with licensing restrictions. Refer to the linked originals as authoritative.
