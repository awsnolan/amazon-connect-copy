# Backlog

Reconciled November 2026. Full analysis and rationale:
[DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md).

The previous version of this file read "no outstanding items". That was
accurate on 2026-07-28 and is no longer true — the platform moved, and work
written in August sat uncommitted for four months.

---

## P0 — Hygiene

| # | Item | State |
|---|------|-------|
| B1 | `.gitignore` must actually exclude backup output directories | **Done** (`5fbf86c`) |
| B2 | Commit the August `connect_assess` work | **Done** (`e7bd724`) |
| B3 | Mark `DR_MODES_SPEC.md` as unimplemented, or implement it | **Done** — marked DRAFT / NOT IMPLEMENTED |
| B4 | Terminology refresh for the August 2026 platform renames | Open |
| B5 | Restore ordering defects | Open |
| B6 | Stale limitation text in README and operator guide | Open |

**B4 — terminology.** Amazon Connect renamed features on 2026-08-04. Current
AWS documentation uses the new names throughout, so repository vocabulary is
now inconsistent with it.

| Previously | Now |
|---|---|
| Amazon Connect | Amazon Connect Customer |
| Contact Lens | conversational analytics |
| Amazon Q in Connect | agent assist |

Affects `README.md`, `DR_VALIDATION_SPEC.md`, `DR_OPERATOR_GUIDE.md`,
validation layer names, and script output.

**B5 — restore ordering.** Two sequences replay associations before their
dependencies exist, so a single run can leave references unset and require a
second pass:

- Queue-to-quick-connect associations replay at the start of the hours section,
  before missing queues and quick connects are created.
- Hours overrides replay before newly missing hours of operation are created.

**B6 — stale text.** README "Known Limitations" still states Cases restore is
manual; it was automated in Phase 4 (`81f7572`). Prompt audio and Lex restore
claims remain broader than the implementation — `connect_deps_backup` does not
download prompt audio, and Lex V2 bot creation is not implemented (existing
same-name bots are associated only).

---

## P1 — Make the three recovery layers real

The recovery model is now three layers: **Reachability**, **Records**,
**Reconstruction**. See [DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md)
sections 7 to 11.

| # | Item |
|---|------|
| L1 | Add `--layer 1\|2\|3` to backup, restore and validate so each layer runs and reports independently |
| L2 | Report per layer with explicit fidelity labels: attached, restored, reconstructed, archive-only, absent |
| L3 | Promote `connect_assess` into the Layer 1 exit criteria and gate Layer 1 completion on it |
| L4 | Close Layer 1 resource gaps: flow and module versions and aliases, communication widgets, Touchpoint and Live Sync config |

Note: `--layer` overlaps with the `--mode` proposal in `DR_MODES_SPEC.md`.
Pick one. The layer model is the more current framing.

---

## P2 — Records layer

| # | Item |
|---|------|
| R1 | Storage attach validation — replication status, object counts, and decryption checks in the recovery environment |
| R2 | Contact record streaming and archive verification (24-month in-instance retention) |
| R3 | Cases: event configuration, case rules, Phases, SLA configuration |
| R4 | Customer Profiles: domain layouts, segment definitions |
| R5 | Email drafts (new October 2026) |
| R6 | Archive index linking contact, case, profile, recording, transcript and attachment records |

---

## P3 — Reconstruction layer

New GA resource types the toolkit does not capture.

| # | Item | API |
|---|------|-----|
| C1 | Custom metrics | `ListMetrics`, `DescribeMetric`, `CreateMetric`, `SearchMetrics` (GA Sep 2026) |
| C2 | Saved reports **and their schedules** | Schedules are excluded from Global Resiliency, so this is a gap even with GR enabled |
| C3 | Test cases | `ListTestCases`, `SearchTestCases` |
| C4 | Workspaces and agent workspace layouts | — |
| C5 | Notifications | — |
| C6 | Quick responses and the `QUICK_RESPONSES` knowledge base | For environments without Global Resiliency |
| C7 | Resolutions Work plans | Work plan is the system of record; it generates flows, Case templates, Case fields and Task templates |
| C8 | Reassess Manager assist | Currently preview (Aug 2026) |

---

## P4 — Positioning

| # | Item |
|---|------|
| P1 | Rewrite the README scope section around the three layers and the Global Resiliency complement |
| P2 | Document Region eligibility prominently, including that Sydney is not a supported Global Resiliency Region |

**Why this matters.** Global Resiliency now mirrors more Connect configuration
than this toolkit backs up, including workspaces, flow module versions and
aliases, custom metrics, test cases, notifications, saved reports, and
quick responses. Configuration breadth is no longer the differentiator.

What Global Resiliency still does not provide, and this toolkit should own:

1. Cross-account isolation — the replica is in the same AWS account
2. Point-in-time rollback — sync is bidirectional, so destructive changes propagate
3. Region freedom — supported pairs only
4. Execution layer — Lambda, Lex and third-party integrations are excluded
5. Records — no recordings, transcripts, contact records, case or profile records
6. Saved report schedules and communication widgets, even where the parent resource replicates

---

## Considered — Not Planned

### Scheduled Backup with S3 Storage (standalone)

Superseded by the CI/CD pipeline (`examples/codebuild/dr-validate-pipeline/`),
which backs up daily to S3 with lifecycle retention. A standalone wrapper adds
nothing.

### Case Record / Profile Data Migration

Out of scope as *restore*. Volume, staleness, and non-portable identity
resolution state make record-level rehydration the wrong goal; see
`.kiro/steering/customer-profiles-decision.md`.

Still required as *archive*: records must remain queryable for audit and
customer-service continuity. That is Layer 2 work (R6), not a migration.

---

## Completed

| Item | Implemented in |
|------|----------------|
| `.gitignore` output exclusion | `5fbf86c` |
| `connect_assess` + guide + 31 tests | `e7bd724` |
| User Provisioning Helper | `--create-users` on `connect_restore` (Phase 2) |
| Smart Validate Messaging | Pre/post restore context detection (Phase 1) |
| Consistent Output Styling | Numbered headers and summaries (Phase 3) |
| Lex Bot Preflight Contradiction | Process substitution fix + name fallback (Phase 1) |
| Predefined Attributes: WARN not FAIL | `connect:*` prefix to WARN (Phase 1) |
| Dry-Run View Content Dump | Name and size instead of full JSON (Phase 2) |
| Cases & Customer Profiles Config Restore | Backup, plan, restore, validate (Phase 4, `81f7572`) |
