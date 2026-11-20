# DR Resilience Assessment Guide

`connect_assess` performs static analysis on contact flow JSON to identify blocks
that will **not degrade gracefully** if their external dependencies (Lambda, Lex,
modules, prompts) are unavailable on the DR instance.

No AWS credentials required. Runs against local backup files.

---

## Quick Start

```bash
# Assess all flows in a backup directory
connect_assess -d <backup-dir>

# Assess a single flow
connect_assess flow_Main%20IVR.json

# JSON output for CI/CD
connect_assess -j -d <backup-dir>
```

---

## What It Checks

For every block that references an external dependency, the tool asks:

> "If this dependency fails, does the contact reach an agent or get disconnected?"

It traces two paths per block:

1. **Error path** — where does the `Errors[]` transition lead?
2. **Default path** — if a Lambda returns empty data, where does the downstream
   Compare/Branch block route when no conditions match?

---

## Classifications

| Symbol | Classification | Meaning |
|--------|---------------|---------|
| `✓` | GRACEFUL | Error/default path reaches a queue. Caller gets an agent. |
| `✗` | NOT GRACEFUL | Error/default path reaches disconnect or dead end. Caller dropped. |
| `⚠` | DEGRADED | Resource missing won't crash the flow, but experience is reduced (e.g., silence instead of audio). |

---

## Example Output

Running against a real backup directory:

```
$ connect_assess -d dr-solution-target

Flow: "DR Test IVR"
  ✓ start-check-hours (InvokeLambdaFunction)
    Dependency: arn:aws:lambda:ap-southeast-2:***:function:dr-test-after-hours-check
    Error path: graceful → set-queue-basic
    Default path: graceful (NoMatchingCondition→set-queue-basic)
    Classification: GRACEFUL
  ✓ lookup-customer (InvokeLambdaFunction)
    Dependency: arn:aws:lambda:ap-southeast-2:***:function:dr-test-customer-lookup
    Error path: graceful → lex-main-menu
    Classification: GRACEFUL
  ✓ lex-main-menu (ConnectParticipantWithLexBot)
    Dependency: arn:aws:lex:ap-southeast-2:***:bot-alias/ZZQJMDILEH/SN7XRCMP2H
    Error path: graceful → set-queue-basic
    Classification: GRACEFUL

Flow: "Default customer whisper"
  ⚠ 8614b74d-...-0e47df651838 (MessageParticipant)
    Dependency: .../prompt/c02416c5-...-27b6027bf77c
    Error path: no_error_handler
    Classification: DEGRADED

Flow: "Sample Lambda integration"
  ✗ 7eefafd6-...-b017ef5f3969 (InvokeLambdaFunction)
    Dependency: arn:aws:lambda:us-east-1:***:function:state-lookup
    Error path: not_graceful → 431f29e2-...
    Default path: not_graceful (NoMatchingCondition→35c77601-...)
    Classification: NOT_GRACEFUL

━━━ Assessment Summary ━━━
  Flows assessed  : 3
  Blocks assessed : 5
  Graceful        : 3
  Not graceful    : 1
  Degraded        : 1

  ⚠ 1 block(s) will NOT degrade gracefully.
    These paths lead to disconnect or dead-end on dependency failure.
```

---

## Reading the Output

### Graceful: "DR Test IVR"

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flow: DR Test IVR                                                  │
│                                                                     │
│  ┌──────────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │ start-check-hours│───▶│ branch-hours │───▶│ lookup-customer  │  │
│  │ (Lambda)         │    │ (Compare)    │    │ (Lambda)         │  │
│  └──────┬───────────┘    └──────┬───────┘    └──────┬───────────┘  │
│         │ error                 │ NoMatch           │ error        │
│         ▼                       ▼                   ▼              │
│  ┌──────────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │ set-queue-basic  │    │set-queue-basic│    │ lex-main-menu    │  │
│  │ (SetQueue)       │    │(SetQueue)    │    │ (Lex Bot)        │  │
│  └──────┬───────────┘    └──────┬───────┘    └──────┬───────────┘  │
│         │                       │                   │ error        │
│         ▼                       ▼                   ▼              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    transfer-to-queue                          │  │
│  │                    ✓ Caller reaches agent                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

  Result: ALL error paths and default paths lead to a queue.
          This flow degrades gracefully in DR.
```

**Why it's safe:** Every dependency block has an error transition that eventually
reaches `TransferContactToQueue`. Even if all three dependencies (both Lambdas and
the Lex bot) are completely missing, every caller path leads to an agent.

---

### Not Graceful: "Sample Lambda integration"

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flow: Sample Lambda integration                                    │
│                                                                     │
│  ┌──────────────────┐         ┌──────────────────┐                 │
│  │ Invoke Lambda    │────────▶│ Check Result     │                 │
│  │ (state-lookup)   │ success │ (Compare)        │                 │
│  └──────┬───────────┘         └──────┬───────────┘                 │
│         │ error                      │ NoMatch                     │
│         ▼                            ▼                             │
│  ┌──────────────────┐         ┌──────────────────┐                 │
│  │ Play Error Msg   │         │ Play Error Msg   │                 │
│  └──────┬───────────┘         └──────┬───────────┘                 │
│         ▼                            ▼                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    DisconnectParticipant                      │  │
│  │                    ✗ Caller DROPPED                           │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

  Result: BOTH error path AND default path lead to disconnect.
          This flow will DROP CALLERS if the Lambda is unavailable.
```

**Why it's dangerous:** The `state-lookup` Lambda is in a different account
(`us-east-1`). If that account/region is unavailable:
- Lambda invocation fails → error path → disconnect
- Even if the Lambda somehow returns empty → Compare has no match → disconnect

**Remediation options:**
1. Deploy the Lambda to the DR account (full restore)
2. Rewire the error path to a queue (flow modification)
3. Deploy a stub Lambda that returns a safe default
4. Accept the risk (document that this flow drops callers in DR)

---

### Degraded: "Default customer whisper"

```
┌─────────────────────────────────────────────────────────────────────┐
│  Flow: Default customer whisper                                     │
│                                                                     │
│  ┌──────────────────┐                                               │
│  │ Play Prompt      │─── (no error handler) ───▶ ???               │
│  │ (Beep.wav)       │                                               │
│  └──────┬───────────┘                                               │
│         │ success                                                   │
│         ▼                                                           │
│  ┌──────────────────┐                                               │
│  │ (next block)     │                                               │
│  └──────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────┘

  Result: Prompt reference may not resolve. Caller hears silence
          instead of the whisper tone. Flow continues — no crash.
```

**Why it's degraded, not broken:** Missing prompts typically result in silence
rather than a hard error. The flow continues, the agent connection completes,
but the caller/agent doesn't hear the expected audio cue.

---

## JSON Output Schema

```json
{
  "flows_assessed": 3,
  "blocks_assessed": 5,
  "graceful": 3,
  "not_graceful": 1,
  "degraded": 1,
  "details": [
    {
      "flow": "DR Test IVR",
      "file": "dr-solution-target/flow_DR%20Test%20IVR.json",
      "findings": [
        {
          "block": "start-check-hours",
          "type": "InvokeLambdaFunction",
          "dependency": "arn:aws:lambda:...:function:dr-test-after-hours-check",
          "error_path": "graceful",
          "error_target": "set-queue-basic",
          "default_path": "graceful",
          "default_detail": "NoMatchingCondition→set-queue-basic",
          "classification": "graceful"
        }
      ],
      "graceful": 3,
      "not_graceful": 0,
      "degraded": 0
    }
  ]
}
```

---

## CI/CD Integration

Add to the daily DR validation pipeline:

```yaml
phases:
  build:
    commands:
      # Back up production
      - connect_backup -p source-profile $SOURCE_INSTANCE
      # Assess resilience
      - connect_assess -j -d $SOURCE_INSTANCE > assess_report.json
      # Fail pipeline if any flow won't degrade gracefully
      - connect_assess -d $SOURCE_INSTANCE
```

Exit code 1 fails the pipeline, flagging flows that need error handling
before the next DR event.

---

## Interpreting Results for DR Planning

| Assessment result | Operator action |
|-------------------|-----------------|
| All GRACEFUL | Instance is resilient. Deps can be missing and callers still reach agents. |
| Some DEGRADED | Acceptable. Callers won't hear prompts or see enhanced features, but calls route. |
| Any NOT GRACEFUL | **Action required.** Fix the flow's error handling, deploy the dependency to DR, or deploy a stub. |

### Priority order for fixing NOT GRACEFUL flows:

1. **Flows assigned to phone numbers** (reachable by callers) — fix first
2. **Flows referenced by other flows** (transfer targets) — fix second
3. **Flows not in active use** (development, testing) — document and accept

---

## Limitations

- **Static analysis only.** Cannot determine runtime behaviour (e.g., what a
  Lambda actually returns, or whether a queue has available agents).
- **Does not trace cross-flow transfers.** If a flow transfers to another flow,
  the assessment covers each flow independently.
- **Assumes all dependencies are unavailable.** In practice, some may be deployed.
  Use with `external_dependencies.json` to narrow to actually-missing deps.
- **Compare block heuristic.** The "empty response" check only looks at the
  immediate next block after a Lambda. Deeply separated logic (Lambda → 5 blocks
  → Compare) is not traced for the default-path scenario.
