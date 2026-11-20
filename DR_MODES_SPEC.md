# DR Modes Specification

**Version:** 0.1.0
**Date:** 2026-08-03
**Status:** DRAFT — NOT IMPLEMENTED

> **Nothing in this document exists in the codebase.**
>
> `connect_restore` has no `--mode` flag. There is no stub deployment, no
> selective feature disablement, and no mode-dependent validation threshold.
> Verified against `bin/` as at November 2026.
>
> This is a design proposal retained for reference. Treat the scripts under
> `bin/` as the only description of current behaviour.
>
> Before implementing, reconcile this spec against the three-layer recovery
> model in [DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md). The `--layer`
> selector proposed there overlaps substantially with `--mode` here, and the
> two should not both be built.

---

## Overview

The toolkit gains a `--mode` flag that declares operator intent and governs
behaviour at every decision point where out-of-scope or unavailable resources
could cause blocking failures on the target instance.

Two modes:

| Mode | Flag | Intent | Acceptance criteria |
|------|------|--------|---------------------|
| **Emergency** | `--mode dr` | Get agents answering calls in minutes. Accept degradation. Fix later or fail back. | Core routing works. Degraded features are stubbed or disabled. |
| **Migration** | `--mode migrate` | Permanent move. Full feature parity required before traffic. | Zero degradation. All features configured and validated. |

**Default behaviour (no flag):** Current behaviour. Equivalent to `--mode dr`
with warnings — does not auto-stub, does not block on missing deps. This
preserves backward compatibility.

---

## Design Principles

1. **The mode is the operator's declaration of intent.** Everything downstream
   (stubs, validation thresholds, attribute handling) derives from this single
   flag rather than per-resource decisions.

2. **No flow content modification.** Neither mode alters contact flow JSON. The
   backup remains source of truth. Degradation is handled at the resource layer
   (stubs, attribute disablement) not the flow layer.

3. **Progressive promotion.** An instance restored with `--mode dr` can later be
   promoted to `--mode migrate` by re-running restore/validate. The gap report
   shows exactly what's still missing.

4. **Auditable.** The mode is recorded in the helper.var file and in restore/
   validate output so there's a record of what was accepted at restore time.

---

## Affected Tools

| Tool | Mode awareness | Behaviour change |
|------|----------------|------------------|
| `connect_backup` | None | Backup is mode-agnostic — always captures everything |
| `connect_plan` | Reads mode, records in helper.var | Adds stub deployment plan for `--mode dr` |
| `connect_restore` | `--mode dr` or `--mode migrate` | Controls preflight strictness, stub deployment, attribute handling |
| `connect_validate` | `--mode dr` or `--mode migrate` | Controls pass/fail threshold per layer |
| `connect_deps_restore` | Unchanged | Deploys real deps (called before restore regardless of mode) |

---

## Specification: `--mode dr` (Emergency)

### Goal

The instance can handle live calls within minutes. Features that can't be
restored are stubbed or disabled so flows proceed through their fallback/error
paths gracefully rather than hitting blocking failures.

### Preflight Behaviour (`bin/lib/restore/preflight.sh`)

| Check | Current behaviour | `--mode dr` behaviour |
|-------|-------------------|----------------------|
| Target instance not ACTIVE | ABORT | ABORT (unchanged — can't do anything without an instance) |
| Missing users | WARN, continue | WARN, continue (unchanged — users route to "not found" gracefully) |
| Missing Lambda functions | WARN, manual action | NOTE: "Will deploy stub." Continue. |
| Missing Lex V2 bots | WARN, manual action | NOTE: "Will deploy fallback bot." Continue. |
| Missing prompts | WARN, manual action | NOTE: "Will use TTS placeholder." Continue. |

### Stub Deployment (new section: `bin/lib/restore/stubs.sh`)

Runs after preflight, before flows restore. Deploys lightweight replacements for
dependencies that weren't deployed by `connect_deps_restore`.

#### Lambda Stubs

For each Lambda in `external_dependencies.json` that does NOT exist on the
target account:

1. **Create a stub function** named identically to the source function.
2. **Runtime:** `python3.12` (smallest cold start).
3. **Code:** A generic handler that:
   - Logs the invocation (function name, contact ID, parameters) to CloudWatch
   - Returns a configurable response (default: `{}`)
   - Sets a `X-DR-Stub: true` header in the response for traceability
4. **Timeout:** Match the source function's timeout (from manifest).
5. **Memory:** 128MB (minimum).
6. **IAM role:** Use a shared `dr-stub-execution-role` (must pre-exist; permissions: CloudWatch Logs only).
7. **Tag:** `dr-mode: stub` — identifies it for later replacement.
8. **Connect permission:** Grant `lambda:InvokeFunction` to connect.amazonaws.com.
9. **Associate with Connect instance.**

**Stub response configuration:**

A file `stub_responses.json` can optionally exist in the backup directory:

```json
{
  "dr-test-after-hours-check": {
    "response": {"isOpen": "true"},
    "comment": "Default to open — route calls to queue rather than after-hours disconnect"
  },
  "dr-test-customer-lookup": {
    "response": {"found": false, "CustomerName": "Customer", "AccountTier": "standard"},
    "comment": "Return generic customer — flow proceeds with default routing"
  }
}
```

If no entry exists for a function, the stub returns `{}`.

**Why this works:** Contact flows handle Lambda responses through branches
(`Compare` blocks). A response of `{}` causes branch conditions to not match,
which routes to the `NoMatchingCondition` error path. For most flows, this
path leads to a queue (safe). For flows where the default path is dangerous
(disconnect), the operator configures a specific stub response in
`stub_responses.json`.

#### Lex V2 Bot Stubs

For each Lex V2 bot in `external_dependencies.json` that does NOT exist on
the target account:

1. **Create a minimal bot** with the same name.
2. **Single locale** matching the source (e.g., `en_AU`, `en_US`).
3. **Single intent:** `FallbackIntent` — always triggers.
4. **Build the locale** (wait for status = `Built`).
5. **Create alias** matching the source alias name (typically "live").
6. **Associate with Connect instance.**
7. **Tag:** `dr-mode: stub`.

**Effect:** When a flow sends a caller to the bot, the bot immediately returns
`FallbackIntent`. The flow's "no match" or "error" transition fires,
typically routing to a queue or DTMF fallback.

**Limitation:** If the flow only has intent-specific branches (no fallback
handling), the contact may hit a dead end. The degradation risk report (see
below) flags these cases.

#### Prompt Stubs

For each prompt in the source backup that does NOT exist on the target:

1. **Generate a TTS audio file** using Amazon Polly: "Please hold while we
   connect you." (or configurable text in `stub_responses.json`).
2. **Upload as a prompt** to the target instance with the same name.
3. **Tag:** `dr-mode: stub` (via description field — prompts don't support tags).

**Fallback if Polly unavailable:** Upload a 1-second silence WAV. Better than
a missing prompt error.

### Instance Attributes (feature gates)

In `--mode dr`, the restore of instance attributes becomes selective:

| Attribute | Source value | `--mode dr` action |
|-----------|-------------|-------------------|
| `CONTACTFLOW_LOGS` | true/false | Restore as-is |
| `CONTACT_LENS` | true | Set to `false` — prevents flows from attempting analytics calls that will fail |
| `ENHANCED_CONTACT_MONITORING` | true | Set to `false` — same reason |
| `AUTO_RESOLVE_BEST_VOICES` | any | Restore as-is |
| `USE_CUSTOM_TTS_VOICES` | any | Restore as-is |
| `EARLY_MEDIA` | any | Restore as-is |
| `MULTI_PARTY_CONFERENCE` | any | Restore as-is |
| All others | any | Restore as-is |

**Rationale:** Attributes like `CONTACT_LENS` are checked by flows (via
`Check contact attributes` blocks). If enabled but the backing service isn't
configured, the flow may take a branch that assumes analytics data exists —
leading to confusing behaviour. Disabling the attribute causes flows to take
the "feature off" branch, which is always safe (it's the path that existed
before the feature was enabled).

**Recorded as manual action:** "Instance attribute CONTACT_LENS was set to
false for emergency DR. Re-enable after configuring Contact Lens on target."

### Restore Summary Output

The summary section (`bin/lib/restore/summary.sh`) gains:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Restore Mode: EMERGENCY DR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Stubs deployed:
    Lambda: 3 functions (tagged dr-mode:stub)
    Lex V2: 1 bot (tagged dr-mode:stub)
    Prompts: 2 TTS placeholders

  Attributes disabled for DR:
    CONTACT_LENS (was: true)

  Instance is ready for EMERGENCY traffic.
  Degraded features will route via fallback paths.

  To promote to full migration:
    connect_restore --mode migrate helper
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Validation Behaviour (`connect_validate --mode dr`)

| Layer | Current: FAIL on | `--mode dr`: downgraded to |
|-------|------------------|---------------------------|
| 0 (External deps) | Missing Lambda | WARN if stub exists and is tagged `dr-mode:stub` |
| 0 (External deps) | Missing Lex bot | WARN if stub bot exists |
| 0 (External deps) | Code hash mismatch | SKIP (stubs won't match) |
| 0 (External deps) | Missing prompt | WARN if TTS placeholder exists |
| 1 (Instance attrs) | Attribute mismatch | WARN for intentionally-disabled attributes (CONTACT_LENS etc.) |
| 12 (Integrations) | Lambda not reachable | WARN if stub exists |
| 12 (Integrations) | Lex bot not reachable | WARN if stub bot exists |
| 15 (Cases/Profiles) | Domain missing | WARN (feature is non-critical for call routing) |
| 16 (Campaigns) | Campaign missing | WARN (feature is non-critical for inbound) |
| 17 (Integrity) | Flow references unresolved resource | WARN if that resource is a known stub |
| All other layers | Unchanged | Unchanged (core routing must still PASS) |

**Pass criteria for `--mode dr`:**
- Layers 2-10 (hours, queues, routing, flows, users, security): All PASS
- Layer 0, 12, 15, 16: WARNs acceptable for stubbed/disabled features
- Layer 17 (integrity): WARNs acceptable for references to stubs
- Layer 18 (smoke): If run, test call must reach a queue (may not get AI/analytics)

---

## Specification: `--mode migrate` (Permanent Migration)

### Goal

Full feature parity. The target instance is production-ready with zero
degradation. No stubs, no disabled features, no accepted WARNs.

### Preflight Behaviour

| Check | `--mode migrate` behaviour |
|-------|---------------------------|
| Target instance not ACTIVE | ABORT |
| Missing users | ABORT — "Pre-create all users before migration restore" |
| Missing Lambda functions | ABORT — "Deploy all Lambda functions before migration restore" |
| Missing Lex V2 bots | ABORT — "Deploy all Lex V2 bots before migration restore" |
| Missing prompts | ABORT — "Upload all prompt audio before migration restore" |
| Existing stubs detected (tagged `dr-mode:stub`) | ABORT — "Replace stubs with real implementations before migration restore" |

**Key difference:** `--mode migrate` refuses to proceed if anything is missing.
It is a blocking gate that forces the operator to set up everything first. This
is appropriate because migration is not time-pressured — it happens days or
weeks after the initial DR event.

### Stub Detection and Removal

Before restore begins in `--mode migrate`:

1. **Scan for stub-tagged resources:**
   - Lambda functions with tag `dr-mode: stub`
   - Lex V2 bots with tag `dr-mode: stub`
   - Prompts with "(DR stub)" in description

2. **Report:**
   ```
   ✗ BLOCKING: 3 stub resources detected on target instance.
     Lambda: dr-test-after-hours-check (stub)
     Lambda: dr-test-customer-lookup (stub)
     Lex V2: MainMenuBot (stub)

     Replace stubs with real implementations, then re-run.
   ```

3. **Do not auto-delete stubs.** The operator replaces them manually (via
   `connect_deps_restore` or their IaC pipeline), which overwrites the stubs
   in place. The tag is removed when the real code deploys.

### Instance Attributes

All attributes restored exactly as source. No selective disablement.

If a feature attribute is enabled (e.g., `CONTACT_LENS = true`), `--mode migrate`
preflight additionally checks that the backing service is configured:

| Attribute | Additional preflight check |
|-----------|--------------------------|
| `CONTACT_LENS` | At least one Contact Lens rule exists on target |
| `CASES` (if applicable) | Cases domain exists and has fields |
| `ENHANCED_CONTACT_MONITORING` | Instance has recording config |

If the backing service isn't configured but the attribute would be enabled,
preflight reports:

```
⚠ CONTACT_LENS is enabled in source but no Contact Lens rules exist on target.
  This will cause flows checking analytics data to behave unexpectedly.
  Options:
    1. Configure Contact Lens on target before proceeding
    2. Manually set CONTACT_LENS=false if feature is being dropped
```

### Restore Behaviour

No stubs deployed. No attributes modified. Strict restore — identical to
current behaviour but with the preflight gate ensuring everything is in place
first.

### Validation Behaviour (`connect_validate --mode migrate`)

**No downgrades.** Every layer must PASS:

| Layer | Criteria |
|-------|----------|
| 0 (External deps) | All Lambdas exist, Active, correct code hash, Connect permissions |
| 0 (External deps) | All Lex bots exist, Available, alias accessible |
| 0 (External deps) | All prompts exist by name (count and names match) |
| 1 (Instance attrs) | All attributes match source exactly |
| 2-10 | All PASS (unchanged) |
| 12 (Integrations) | All integrations reachable and functional |
| 15 (Cases/Profiles) | Domain exists, fields match, object types match |
| 16 (Campaigns) | If source had campaigns, target has campaigns |
| 17 (Integrity) | Zero unresolved references |
| 18 (Smoke) | Full test call with all features exercised |

**Pass criteria for `--mode migrate`:** Zero FAILs, zero WARNs on any layer.
Only SKIPs acceptable (for features genuinely not present in source).

---

## Degradation Risk Report (`connect_validate -m degradation`)

A new validation mode (or `--report degradation` flag) that runs at planning
time (before restore) and identifies exactly what will break in `--mode dr`.

### What It Produces

For each contact flow, trace every block that references an external or
out-of-scope resource:

```
━━━ Degradation Risk Report ━━━

Flow: "Main IVR" (3647ed7e-...)
  Block: start-check-hours (InvokeLambdaFunction)
    Dependency: dr-test-after-hours-check
    Status: NOT DEPLOYED on target
    Error path: → set-queue-basic (routes to BasicQueue)
    Risk: LOW — caller proceeds to queue on failure
    Stub response needed: {"isOpen": "true"} (otherwise default path = disconnect)

  Block: lookup-customer (InvokeLambdaFunction)
    Dependency: dr-test-customer-lookup
    Status: NOT DEPLOYED on target
    Error path: → lex-main-menu (routes to Lex bot)
    Risk: LOW — caller proceeds without customer context

  Block: lex-main-menu (ConnectParticipantWithLexBot)
    Dependency: Lex bot ZZQJMDILEH
    Status: NOT DEPLOYED on target
    Error path: → set-queue-basic (routes to BasicQueue)
    Risk: LOW — caller proceeds to queue without intent classification

Flow: "After Hours Handler" (6f69cfd9-...)
  Block: check-schedule (InvokeLambdaFunction)
    Dependency: schedule-lookup
    Status: NOT DEPLOYED on target
    Error path: → disconnect
    Risk: HIGH — caller disconnected on failure
    ⚠ Recommend stub response: {"isOpen": "true"} or full deploy

━━━ Summary ━━━
  Flows analyzed: 14
  Blocks with missing deps: 8
  HIGH risk (disconnect on failure): 1
  MEDIUM risk (no error path defined): 0
  LOW risk (routes to queue/flow): 7

  Auto-generated stub_responses.json written to: helper/stub_responses.json
```

### Risk Classification Logic

| Error path destination | Risk level |
|-----------------------|-----------|
| Routes to a queue (TransferContactToQueue, UpdateContactTargetQueue) | LOW |
| Routes to another flow block that eventually reaches a queue | LOW |
| Routes to PlayPrompt → queue | LOW |
| Routes to DisconnectParticipant | HIGH |
| No error path defined (block has no Errors array) | HIGH |
| Error path references another missing resource | MEDIUM |
| Error path loops back to same block | MEDIUM |

### Auto-Generated stub_responses.json

For HIGH risk blocks, the report generates a suggested `stub_responses.json`
entry based on the flow's branch logic:

- If the flow branches on `$.External.isOpen == "true"` and the "true" branch
  goes to a queue while the default goes to disconnect → suggest
  `{"isOpen": "true"}`
- If the flow branches on `$.External.found == "true"` and both paths eventually
  route to a queue → suggest `{}` (either path is safe)
- If the branch logic is too complex to auto-determine → flag for operator
  review with explanation

---

## Implementation: File Changes

### New files

| File | Purpose |
|------|---------|
| `bin/lib/restore/stubs.sh` | Stub deployment logic (Lambda, Lex, Prompts) |
| `bin/lib/restore/stubs_lambda.py` | Generic Lambda stub handler code |
| `bin/lib/validate/degradation.sh` | Degradation risk report (flow tracing) |

### Modified files

| File | Change |
|------|--------|
| `bin/connect_restore` | Accept `--mode dr\|migrate` flag, set `DR_MODE` variable, source `stubs.sh` |
| `bin/connect_validate` | Accept `--mode dr\|migrate` flag (orthogonal to existing `-m` mode), adjust thresholds |
| `bin/connect_plan` | Record mode in `helper.var` if provided |
| `bin/lib/restore/preflight.sh` | Branch on `DR_MODE` for blocking vs. warning behaviour |
| `bin/lib/restore/instance.sh` | Branch on `DR_MODE` for selective attribute disablement |
| `bin/lib/restore/summary.sh` | Report stubs deployed and features disabled |
| `bin/lib/validate/layer_0_deps.sh` | Check for stub tags, downgrade FAIL → WARN in dr mode |
| `bin/lib/validate/layer_12_integrations.sh` | Same stub-aware logic |
| `bin/lib/validate/layer_17_integrity.sh` | Same stub-aware logic |
| `bin/lib/common.sh` | Add `DR_MODE` variable, `is_stub()` helper function |

### helper.var additions

```bash
dr_mode="dr"            # or "migrate" or "" (legacy/default)
stubs_deployed="3"      # count of stub resources created
stubs_lambda="dr-test-after-hours-check,dr-test-customer-lookup"
stubs_lex="MainMenuBot"
attrs_disabled="CONTACT_LENS"
```

---

## Interaction With Existing `--only` / `--skip` Flags

The mode flag is orthogonal to `--only` and `--skip`:

- `connect_restore --mode dr --only flows,hours` — emergency mode but only
  restore flows and hours sections
- `connect_validate --mode migrate --skip 18` — migration mode validation
  but skip smoke test layer

---

## Interaction With `connect_deps_restore`

`connect_deps_restore` remains mode-unaware. It always deploys real
dependencies. The stub logic only activates for dependencies that `connect_deps_restore`
did NOT deploy (i.e., they don't exist on target at restore time).

Workflow:

```bash
# Deploy what you can
connect_deps_restore -p dr-profile -i <instance-id> deps_dir

# Restore with stubs for anything still missing
connect_restore --mode dr helper

# Later, when ready to promote:
connect_deps_restore -p dr-profile -i <instance-id> deps_dir   # deploy remaining
connect_restore --mode migrate helper                           # strict validation
```

---

## Interaction With CI/CD Pipeline

The CodeBuild pipeline (`examples/codebuild/dr-validate-pipeline/`) gains a
`DR_MODE` environment variable:

- **Daily validation (warm standby):** `--mode migrate` — full parity check,
  alert on any drift
- **During active DR event:** `--mode dr` — reduced alerting, stubs acceptable,
  only alert if core routing breaks

---

## Stub Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        Stub Lifecycle                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Emergency Restore                                           │
│     connect_restore --mode dr                                   │
│     → stubs deployed, tagged dr-mode:stub                       │
│     → CloudWatch logs capture every invocation                  │
│                                                                 │
│  2. Operating in DR (hours/days)                                │
│     → Stubs handle traffic gracefully                           │
│     → Operator works on deploying real services                 │
│     → connect_validate --mode dr reports "3 stubs active"       │
│                                                                 │
│  3a. Fail Back to Source Region                                 │
│      → Traffic moves back, DR instance goes idle                │
│      → Stubs can be left (no harm) or cleaned up               │
│                                                                 │
│  3b. Promote to Production                                      │
│      → Deploy real deps: connect_deps_restore                   │
│      → This overwrites stubs (same function name)              │
│      → Re-enable attributes: CONTACT_LENS=true etc.            │
│      → Validate: connect_validate --mode migrate               │
│      → Must reach zero FAILs, zero WARNs                       │
│                                                                 │
│  4. Stub Cleanup (optional, for 3a path)                        │
│     → Delete resources tagged dr-mode:stub                      │
│     → Or leave in place as warm standby for next DR event       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Generic Lambda Stub Handler

```python
"""
DR Stub Lambda — deployed by connect_restore --mode dr.
Returns a configurable response to prevent blocking failures in contact flows.
Logs all invocations for audit trail.
"""
import json
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Response is set via environment variable at deploy time
STUB_RESPONSE = json.loads(os.environ.get('STUB_RESPONSE', '{}'))
FUNCTION_NAME = os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')

def handler(event, context):
    logger.info(json.dumps({
        'stub': True,
        'function': FUNCTION_NAME,
        'event': event,
        'note': 'DR stub — real function not deployed'
    }))
    return STUB_RESPONSE
```

The `STUB_RESPONSE` environment variable is set from `stub_responses.json`
at deploy time:
- If entry exists in `stub_responses.json`: use that response
- If no entry: `STUB_RESPONSE='{}'`

---

## Edge Cases

### 1. Lambda exists but is broken (runtime deps missing)

If `connect_deps_restore` deployed a real Lambda but it will crash at runtime
(DynamoDB table doesn't exist, Secrets Manager secret missing), the preflight
can't detect this without invoking the function.

**`--mode dr` approach:** The degradation risk report flags functions whose
`runtime_dependencies.json` entries reference resources not verified on target.
The operator can choose to replace with a stub or fix the runtime deps.

**`--mode migrate` approach:** Layer 0 validation could optionally invoke each
Lambda with a test event and verify it doesn't error. This is opt-in (new flag
`--test-invoke`) because it has side effects.

### 2. Stub already exists from previous DR event

If `--mode dr` is re-run and stubs already exist:
- Check if tagged `dr-mode:stub` → skip (already a stub, no action needed)
- Check if NOT tagged → it's a real function that was deployed since last time → don't overwrite

### 3. Cross-region stub deployment

Stubs deploy to `region_b` (target region) regardless of where the source
function ran. The SED remapping already handles ARN prefix changes, so flows
will reference the correct target-region ARN.

### 4. Lex bot build time

Lex V2 bot locale builds can take 30-120 seconds. In emergency mode, the
restore script waits up to 120 seconds for the build to complete. If it
doesn't complete in time:
- Associate the bot anyway (Connect will retry)
- Report in summary: "Lex bot X build in progress — may take up to 2 minutes"

### 5. Operator has no Polly access

If TTS prompt generation fails (no Polly permissions), fall back to:
1. Skip prompt stub (report as manual action)
2. Prompt blocks that reference missing prompts will play silence or error —
   same as today, no regression

---

## IAM Requirements

### Stub deployment (additional permissions for restore profile)

```
# Lambda stub creation
lambda:CreateFunction
lambda:TagResource
lambda:AddPermission
iam:PassRole    (scoped to dr-stub-execution-role ARN only)

# Lex V2 stub bot creation
lex:CreateBot
lex:CreateBotLocale
lex:CreateIntent
lex:BuildBotLocale
lex:CreateBotAlias
lex:TagResource
iam:PassRole    (scoped to dr-stub-lex-role ARN only)

# Prompt stub (if using Polly)
polly:SynthesizeSpeech
connect:CreatePrompt

# Stub detection (for --mode migrate preflight)
lambda:ListTags
lex:ListTagsForResource
```

### Pre-requisite roles (must exist on target account)

| Role | Purpose | Permissions |
|------|---------|-------------|
| `dr-stub-execution-role` | Lambda stub execution | `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` |
| `dr-stub-lex-role` | Lex V2 stub bot | `polly:SynthesizeSpeech`, `comprehend:DetectSentiment` (Lex minimum) |

These are one-time setup. Document in DR Operator Guide under "Before First DR
Event" section.

---

## Validation Mode Summary

```
connect_validate -m full --mode dr --target <id> backup-dir
                 │        │
                 │        └── acceptance threshold (dr=lenient, migrate=strict)
                 └── execution scope (preflight/local/full/smoke — unchanged)
```

The two flags are orthogonal:
- `-m` controls WHAT gets checked (preflight vs full vs smoke)
- `--mode` controls HOW STRICTLY results are judged

---

## Success Criteria

### `--mode dr` is successful when:

1. A call entering the main IVR flow reaches a queue and is offered to an agent
2. No calls are silently dropped due to missing resources
3. Features that aren't available degrade to "feature off" behaviour (no
   analytics, no AI suggestions, no case creation) rather than error states
4. Total time from "start restore" to "first call answered" is under 10 minutes
   for a typical instance (<50 flows, <10 Lambda deps)

### `--mode migrate` is successful when:

1. `connect_validate --mode migrate` returns PASS with zero WARNs
2. All features from the source instance work identically on target
3. No stub resources remain
4. Smoke test exercises full call path including Lambda responses and Lex intents

---

## Not In Scope (for this feature)

- **Automatic failback orchestration** — detecting when source region recovers
  and routing traffic back. This is a Route 53 / Global Resiliency concern.
- **Data migration** (case records, profile records, CTRs) — permanently out of
  scope per existing design decision.
- **Warm standby automation** — keeping stubs updated as source instance evolves.
  The CI/CD pipeline already validates drift; stubs are re-deployed on next DR event.
- **Multi-region active-active** — this toolkit is cold recovery, not active-active.
  Use Amazon Connect Global Resiliency for that.
