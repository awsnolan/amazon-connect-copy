# DR Drill Runbook

A single sitting that answers three questions:

1. **Does the restore path work?** Including the B5 fix, verified against real instances rather than fixtures.
2. **What is our actual RTO?** A measured number from your own environment, not an industry figure.
3. **What is still manual?** The list that determines whether the number above is achievable under pressure.

Companion documents: [DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md) ·
[DR_TIER_WORKSHOP_PACK.md](./DR_TIER_WORKSHOP_PACK.md) ·
[DR_OPERATOR_GUIDE.md](./DR_OPERATOR_GUIDE.md)

---

## Contents

1. [Non-negotiable safety rules](#1-non-negotiable-safety-rules)
2. [What this drill does and does not measure](#2-what-this-drill-does-and-does-not-measure)
3. [Prerequisites — complete before drill day](#3-prerequisites--complete-before-drill-day)
4. [Setup](#4-setup)
5. [Phase 1 — Capture (read-only)](#5-phase-1--capture-read-only)
6. [Phase 2 — Assess and plan](#6-phase-2--assess-and-plan)
7. [Phase 3 — Preflight](#7-phase-3--preflight)
8. [Phase 4 — Restore (clock starts)](#8-phase-4--restore-clock-starts)
9. [Phase 5 — Validate](#9-phase-5--validate)
10. [Phase 6 — Manual actions](#10-phase-6--manual-actions)
11. [Phase 7 — Live contact test (clock stops)](#11-phase-7--live-contact-test-clock-stops)
12. [Phase 8 — B5 verification](#12-phase-8--b5-verification)
13. [Phase 9 — Idempotency probe](#13-phase-9--idempotency-probe)
14. [Phase 10 — Results](#14-phase-10--results)
15. [Abort procedure](#15-abort-procedure)
16. [Results template](#16-results-template)

---

## 1. Non-negotiable safety rules

| # | Rule |
|---|------|
| 1 | **`connect_restore` is never pointed at production.** It only ever writes to the DR instance. |
| 2 | Production is touched by `connect_backup` and `connect_validate` only. Both are read-only. |
| 3 | All output goes under `output/`, which is gitignored. Backup directories contain real account IDs, instance IDs and ARNs. |
| 4 | Use a read-only credential profile for production. Write credentials are needed only for the DR target. |
| 5 | If any command targets an instance you did not expect, stop and re-check before continuing. |
| 6 | Do not commit anything produced by this drill. |

Rule 1 matters most. The restore target is derived from the `helper` directory built by `connect_plan`, so the ordering of the two aliases passed to `connect_plan` determines what gets written. Getting them the wrong way round would attempt to overwrite production with DR configuration.

---

## 2. What this drill does and does not measure

Recovery time divides into two parts, and conflating them produces a meaningless number.

**Pre-staged** — work that must already be done when the event happens:

- DR instance exists and is ACTIVE
- Identity provider configured, users provisioned and holding instance access
- Phone numbers claimed on the DR instance (cannot be transferred cross-account by API)
- Lambda functions and Lex bots deployed in the DR account
- Storage buckets and KMS access reachable from the DR account

**In-event** — the actual recovery, which is what the clock measures:

- Capture, plan, restore, validate, complete manual actions, test a contact

If something in the first list is not actually pre-staged, your real RTO is however long that item takes — potentially days for phone numbers or SES domain verification. **Record anything you have to do on the day that should have been pre-staged.** That gap is the single most important output of this drill, because it is the difference between a Pilot Light posture and a Backup-and-Restore one.

This drill measures a **configuration** recovery. It does not measure records recovery (Layer 2) or reconstruction (Layer 3). Those are separate exercises.

---

## 3. Prerequisites — complete before drill day

Work through this list in advance. Arriving without it turns a two-hour drill into a day of provisioning.

| # | Item | How to confirm |
|---|------|----------------|
| 1 | DR instance exists and is ACTIVE | `aws connect describe-instance --instance-id <dr-id> --profile <dr>` |
| 2 | Source and DR AWS profiles both work | `aws sts get-caller-identity --profile <each>` |
| 3 | Production profile is read-only | Review attached policies; prefer an explicit ReadOnly role |
| 4 | Users provisioned on DR with instance access | They must appear in `list-users`, not merely exist in Identity Center |
| 5 | Phone numbers claimed on DR | `aws connect list-phone-numbers-v2 --profile <dr>` |
| 6 | Lambda and Lex deployed in DR account | `connect_deps_restore -d` (dry run) reports no gaps |
| 7 | AWS CLI 2.32+ and jq 1.6+ | `aws --version` · `jq --version` |
| 8 | Toolkit on PATH | `connect_backup -v` |
| 9 | A booked window and a named person to answer the test call | — |
| 10 | Agreement that DR instance config will be overwritten | It will be. Confirm nobody else is using it. |

Item 4 is the most common cause of a failed drill. `connect_restore` cannot create users cross-account, because `create-user` requires either a password or a `DirectoryUserId`, and neither is available from a backup.

---

## 4. Setup

Run everything from the repository root. Paths below assume that.

```bash
# --- Edit these five values -------------------------------------------
export SRC_PROFILE=prod-readonly          # read-only credentials
export DR_PROFILE=dr-admin                # write credentials for DR only
export SRC_ALIAS=prod-cc                  # production instance alias
export DR_ALIAS=dr-cc                     # DR instance alias
export DR_INSTANCE_ID="REPLACE-WITH-DR-INSTANCE-ID"
# ----------------------------------------------------------------------

mkdir -p output/drill
export DRILL=output/drill
export LOG="$DRILL/drill-$(date +%Y%m%d-%H%M).log"
export NO_COLOR=1      # clean, greppable logs

# Phase tracking. phases.tsv holds completed phases; phases.running holds
# the one in flight. connect_report reads both to build the dashboard.
export PHASES="$DRILL/phases.tsv"
export RUNNING="$DRILL/phases.running"
: > "$PHASES"; : > "$RUNNING"
printf '# num\tname\tstate\tstart\tend\texit\n' >> "$PHASES"

# Call phase() at the start of every phase. It closes the previous one.
phase() {
  local name="$*" now; now=$(date -u +%s)
  if [ -s "$RUNNING" ]; then
    local pn pnum pstart
    IFS=$'\t' read -r pnum pn pstart < "$RUNNING"
    printf '%s\t%s\tdone\t%s\t%s\t0\n' "$pnum" "$pn" "$pstart" "$now" >> "$PHASES"
  fi
  _PH=$(( ${_PH:-0} + 1 ))
  printf '%s\t%s\t%s\n' "$_PH" "$name" "$now" > "$RUNNING"
  printf '\n=== %s | %s ===\n' "$(date -u +%H:%M:%S)" "$name" | tee -a "$LOG"
}

# Call on failure to mark the current phase red instead of green.
phase_fail() {
  local now; now=$(date -u +%s)
  if [ -s "$RUNNING" ]; then
    local pn pnum pstart
    IFS=$'\t' read -r pnum pn pstart < "$RUNNING"
    printf '%s\t%s\tdone\t%s\t%s\t1\n' "$pnum" "$pn" "$pstart" "$now" >> "$PHASES"
    : > "$RUNNING"
  fi
  printf 'PHASE FAILED: %s\n' "$*" | tee -a "$LOG"
}

# Call once at the very end to close the final phase.
phase_done() {
  local now; now=$(date -u +%s)
  if [ -s "$RUNNING" ]; then
    local pn pnum pstart
    IFS=$'\t' read -r pnum pn pstart < "$RUNNING"
    printf '%s\t%s\tdone\t%s\t%s\t0\n' "$pnum" "$pn" "$pstart" "$now" >> "$PHASES"
    : > "$RUNNING"
  fi
}

# Merge completed + in-flight for the dashboard
phases_now() {
  cat "$PHASES"
  [ -s "$RUNNING" ] && awk -F'\t' '{printf "%s\t%s\trunning\t%s\t\t\n",$1,$2,$3}' "$RUNNING"
  return 0
}

echo "Drill log: $LOG"
```

Confirm you are pointed where you think you are before going further:

```bash
phase "Identity check"
for p in "$SRC_PROFILE" "$DR_PROFILE"; do
  printf '%-18s ' "$p"
  aws sts get-caller-identity --profile "$p" --query Arn --output text
done | tee -a "$LOG"
```

**Stop if either line is not the account you expect.**

---

## 5. Phase 1 — Capture (read-only)

Nothing here writes to any Connect instance.

```bash
phase "Phase 1: capture source"
time connect_backup -p "$SRC_PROFILE" -s "$DRILL/$SRC_ALIAS" 2>&1 | tee -a "$LOG"

phase "Phase 1: capture DR (pre-restore state)"
time connect_backup -p "$DR_PROFILE" -s "$DRILL/$DR_ALIAS" 2>&1 | tee -a "$LOG"

phase "Phase 1: capture external dependencies"
connect_deps_backup -p "$SRC_PROFILE" "$DRILL/$SRC_ALIAS" 2>&1 | tee -a "$LOG"
```

`-s` skips unpublished flows and flows with errors rather than failing the whole run. Drop it if you want the backup to fail loudly instead.

**Capture:** wall-clock duration of each backup, and the file count in each directory.

**Pass criteria**

- Both backups exit 0
- `$DRILL/$SRC_ALIAS/external_dependencies.json` exists and lists your Lambda and Lex references
- No warnings about resources being skipped that you care about

---

## 6. Phase 2 — Assess and plan

```bash
phase "Phase 2: flow resilience assessment"
connect_assess -d "$DRILL/$SRC_ALIAS" 2>&1 | tee -a "$LOG"
echo "assess exit: $?" | tee -a "$LOG"
```

Exit 0 means every assessed block degrades gracefully. Exit 1 means at least one flow disconnects or dead-ends when a dependency is missing. **Record the exit code and the list of non-graceful flows** — this predicts how the instance behaves if a Lambda or Lex bot is unavailable after failover.

```bash
phase "Phase 2: plan"
connect_plan -f "$DRILL/$SRC_ALIAS" "$DRILL/$DR_ALIAS" "$DRILL/helper" 2>&1 | tee -a "$LOG"
```

Note the argument order: **source first, DR second.** Reversing them plans a restore in the wrong direction.

```bash
phase "Phase 2: dry run"
connect_restore -d -e "$DRILL/helper" 2>&1 | tee -a "$DRILL/dryrun.log"
tail -30 "$DRILL/dryrun.log"
```

**Pass criteria**

- Plan reports a sensible number of resources to create and update
- Dry run completes with step headers running `1/9` through `9/9`
- Dry run shows no unexpected deletions (there is no delete phase, so any surprise here means a misread plan)

Review `$DRILL/dryrun.log` before proceeding. This is the last checkpoint before writes.

---

## 7. Phase 3 — Preflight

```bash
phase "Phase 3: preflight"
connect_validate -m preflight \
  --target "$DR_INSTANCE_ID" --target-profile "$DR_PROFILE" \
  -p "$SRC_PROFILE" --no-color "$DRILL/$SRC_ALIAS" 2>&1 | tee -a "$LOG"
```

**Pass criteria**

- DR instance reachable and ACTIVE
- External dependencies resolvable in the DR account
- Every source username present on the DR instance

If usernames are missing, stop and provision them. Continuing produces a restore that completes but leaves agents unable to log in, which invalidates the RTO measurement.

---

## 8. Phase 4 — Restore (clock starts)

**Start the clock now.** This is the moment that corresponds to "we have declared a disaster and begun recovery."

```bash
phase "Phase 4: RESTORE START — clock running"
date -u +%s > "$DRILL/rto_start"

time connect_restore -e "$DRILL/helper" 2>&1 | tee -a "$DRILL/restore.log"
echo "restore exit: $?" | tee -a "$LOG"

phase "Phase 4: restore finished"
```

Do **not** re-run the restore yet, even if something looks wrong. A central purpose of this drill is establishing whether **one** run is sufficient. Re-running masks exactly the defect B5 fixed.

**Capture:** script duration, exit code, and the full `restore.log`.

```bash
# Manual actions the restore recorded for you
phase "Phase 4: manual actions raised"
grep -iE '^\[|manual' "$DRILL/restore.log" | sort -u | tee "$DRILL/manual_actions.txt"
wc -l < "$DRILL/manual_actions.txt"
```

**Pass criteria**

- Exit 0
- Step headers `1/9` to `9/9`
- Any failures are reported with a visible `✗` line rather than passing silently

---

## 9. Phase 5 — Validate

```bash
phase "Phase 5: full validation"
connect_validate -m full \
  --target "$DR_INSTANCE_ID" --target-profile "$DR_PROFILE" \
  -p "$SRC_PROFILE" --no-color "$DRILL/$SRC_ALIAS" 2>&1 | tee "$DRILL/validate_1.log"

# Machine-readable copy for the record
connect_validate -m full -j \
  --target "$DR_INSTANCE_ID" --target-profile "$DR_PROFILE" \
  -p "$SRC_PROFILE" "$DRILL/$SRC_ALIAS" > "$DRILL/validate_1.json" 2>/dev/null
```

**Capture:** pass/fail per layer, and the total count of failures.

```bash
grep -cE '✗|FAIL' "$DRILL/validate_1.log"
```

**Pass criteria**

Expect some failures on the first pass. The question is *which*. Sort them into two groups:

| Group | Meaning | Examples |
|---|---|---|
| Expected manual | Known constraints the toolkit cannot automate | Security keys, default security profile differences, SES/email, campaigns, integration associations |
| Unexpected | A genuine defect or gap | Anything in flows, queues, routing, hours, phone mappings |

**Record every unexpected failure.** Those are backlog items.

---

## 10. Phase 6 — Manual actions

Work through `$DRILL/manual_actions.txt` plus any unexpected validation failures. Consult [DR_OPERATOR_GUIDE.md](./DR_OPERATOR_GUIDE.md) for the per-category steps.

**Time each item separately.** This is where real recovery time hides.

```bash
phase "Phase 6: manual actions start"
# ... perform the manual steps ...
phase "Phase 6: manual actions complete"
```

Then re-validate:

```bash
phase "Phase 6: re-validate"
connect_validate -m full \
  --target "$DR_INSTANCE_ID" --target-profile "$DR_PROFILE" \
  -p "$SRC_PROFILE" --no-color "$DRILL/$SRC_ALIAS" 2>&1 | tee "$DRILL/validate_2.log"
```

**Capture:** which failures cleared, which persisted, and how long each manual item took.

---

## 11. Phase 7 — Live contact test (clock stops)

This is the only criterion that genuinely matters. Everything above is a proxy for it.

```bash
phase "Phase 7: live contact test"
```

1. Have an agent log in to the DR instance and go Available.
2. Place a real call to a DR phone number.
3. Confirm the contact routes through the expected flow to the expected queue and connects to the agent.
4. Confirm the recording appears in the configured S3 bucket.
5. If chat is in scope, repeat using the DR communication widget.
6. Attempt a **warm transfer** using a quick connect. This exercises the B5 fix directly.

```bash
phase "Phase 7: RTO STOP"
echo "$(( $(date -u +%s) - $(cat "$DRILL/rto_start") ))" > "$DRILL/rto_seconds"
printf 'Measured RTO: %s seconds (%s minutes)\n' \
  "$(cat "$DRILL/rto_seconds")" \
  "$(( $(cat "$DRILL/rto_seconds") / 60 ))" | tee -a "$LOG"
```

**Pass criteria**

- Call answered by a live agent
- Flow and queue behaved as designed
- Recording written to S3
- Warm transfer offered the expected destinations and completed

If recording failed, note it prominently. In a regulated environment a connected call that is not recorded is a compliance incident, not a success.

---

## 12. Phase 8 — B5 verification

The specific purpose of this phase is to confirm that **one** restore run produced the associations. Before the fix, these required a second pass.

```bash
phase "Phase 8: B5 verification"

# Layer 2 = hours (incl. overrides), Layer 3 = queues (incl. quick connect associations)
connect_validate -m full --only 2,3 \
  --target "$DR_INSTANCE_ID" --target-profile "$DR_PROFILE" \
  -p "$SRC_PROFILE" --no-color "$DRILL/$SRC_ALIAS" 2>&1 | tee "$DRILL/validate_b5.log"
```

Direct inspection, independent of the validator:

```bash
# Quick connects actually attached to each queue on DR
aws connect list-queues --instance-id "$DR_INSTANCE_ID" \
  --queue-types STANDARD --profile "$DR_PROFILE" --output json \
| jq -r '.QueueSummaryList[] | .Id + "\t" + .Name' \
| while IFS=$'\t' read -r qid qname; do
    n=$(aws connect list-queue-quick-connects --instance-id "$DR_INSTANCE_ID" \
          --queue-id "$qid" --profile "$DR_PROFILE" --output json 2>/dev/null \
        | jq '[.QuickConnectSummaryList[]?] | length')
    printf '%-40s %s\n' "$qname" "${n:-0}"
  done | tee "$DRILL/b5_queue_qc.txt"

# Compare against source expectations
ls "$DRILL/$SRC_ALIAS"/queueQCs_*.json 2>/dev/null | while read -r f; do
  printf '%-50s %s\n' "$(basename "$f")" "$(jq '.QuickConnectSummaryList | length' "$f")"
done | tee "$DRILL/b5_source_qc.txt"
```

**Pass criteria**

- Layers 2 and 3 pass after a **single** restore run
- Queue quick connect counts on DR match the source
- Hours overrides present on DR for every hours-of-operation that has them on source
- No `⚠ Queue '<name>' not found on target` warnings in `restore.log`

```bash
grep -c 'not found on target' "$DRILL/restore.log" || echo 0
```

If that count is non-zero, the ordering fix worked but some queues genuinely failed to resolve — capture the names, that is a new finding.

---

## 13. Phase 9 — Idempotency probe

Answers whether re-running a restore is safe, which determines whether the documented "re-run `connect_restore`" guidance can stand.

```bash
phase "Phase 9: idempotency probe"
./tests/probe_api_idempotency.sh \
  --instance-id "$DR_INSTANCE_ID" --profile "$DR_PROFILE" \
  --live --include-writes 2>&1 | tee "$DRILL/idempotency.log"
```

**Capture:** the verdict table. The outcome that matters most is whether `create-hours-of-operation-override` **silently duplicates**, because that would mean repeated restores quietly accumulate overrides and eventually fail Layer 2 for a reason that looks unrelated.

---

## 13a. Live dashboard

Optional, but useful if anyone is watching the drill rather than running it.

Open a second terminal, re-export the same variables from Section 4, then:

```bash
# Refresh the phase snapshot and rebuild the page every 20 seconds
while :; do
  phases_now > "$DRILL/phases_snapshot.tsv"
  connect_report \
    --validate "$DRILL/validate_1.json" \
    --assess   "$DRILL/assess.json" \
    --phases   "$DRILL/phases_snapshot.tsv" \
    --rto      "$DRILL/rto_seconds" \
    --manual   "$DRILL/manual_actions.txt" \
    --target-rto 30 --refresh 20 \
    --out "$DRILL/dashboard.html" >/dev/null
  sleep 20
done
```

Then open `output/drill/dashboard.html` in a browser. The page carries a
`meta refresh`, so it reloads on the same interval and picks up each rebuild.
It also reports its own age and turns the indicator amber if it goes stale,
so a dead loop is visible rather than silently showing frozen data.

Optional inputs can be absent — the corresponding tiles render grey as
"not actioned" rather than failing.

**Before sharing the screen**, regenerate with redaction:

```bash
connect_report --validate "$DRILL/validate_1.json" \
  --assess "$DRILL/assess.json" --phases "$DRILL/phases_snapshot.tsv" \
  --rto "$DRILL/rto_seconds" --manual "$DRILL/manual_actions.txt" \
  --redact --refresh 0 --out "$DRILL/dashboard_shared.html"
```

That masks account ids, resource ids, phone numbers and email addresses.
Instance aliases are kept, so the page still identifies its subject.

---

## 14. Phase 10 — Results

```bash
phase "Phase 10: collect results"

cat <<EOD | tee "$DRILL/SUMMARY.txt"
DR DRILL SUMMARY
================
Date              : $(date -u +%Y-%m-%dT%H:%MZ)
Source instance   : $SRC_ALIAS
DR instance       : $DR_ALIAS ($DR_INSTANCE_ID)

Measured RTO      : $(cat "$DRILL/rto_seconds" 2>/dev/null) seconds
                    ($(( $(cat "$DRILL/rto_seconds" 2>/dev/null || echo 0) / 60 )) minutes)

Restore exit      : see restore.log
Assess exit       : see drill log (0 = all flows degrade gracefully)
Validation fails  : first pass  $(grep -cE '✗|FAIL' "$DRILL/validate_1.log" 2>/dev/null)
                    after manual $(grep -cE '✗|FAIL' "$DRILL/validate_2.log" 2>/dev/null)
Manual actions    : $(wc -l < "$DRILL/manual_actions.txt" 2>/dev/null)
Queues missing QC : $(grep -c 'not found on target' "$DRILL/restore.log" 2>/dev/null || echo 0)
EOD

ls -la "$DRILL"/*.log "$DRILL"/*.txt "$DRILL"/*.json 2>/dev/null
```

Keep the whole `$DRILL` directory. It is gitignored, so it will not be committed, but it is the evidence base for the workshop.

**Do not commit it.** If you need to share results, copy them into the template below and redact account IDs, instance IDs and phone numbers first.

---

## 15. Abort procedure

If something goes wrong mid-restore:

1. **Stop.** Do not re-run blindly.
2. The restore is additive — it creates and updates, and never deletes. A partial restore leaves extra or half-configured resources on DR, not missing production data.
3. Production is unaffected. Nothing in this runbook writes to it.
4. Capture `restore.log` and the validation output before changing anything.
5. To reset the DR instance to a known state, restore again from the DR backup taken in Phase 1 — that is why it was captured.

If you discover the aliases were passed to `connect_plan` in the wrong order and a restore has already run against production: stop immediately, do not run further commands, and treat it as a production change incident. The backup of production from Phase 1 is your reference for what the configuration was.

---

## 16. Results template

Fill this in and bring it to the senior leader workshop. It replaces every industry figure in [DR_TIER_WORKSHOP_PACK.md](./DR_TIER_WORKSHOP_PACK.md) with your own evidence.

```text
DR DRILL RESULT — <date>

MEASURED RTO
  Tooling time (capture -> restore -> validate) : ______ min
  Manual actions                                 : ______ min
  Total to first answered call                   : ______ min

PRE-STAGED vs IN-EVENT
  Items we had to do on the day that should
  have been pre-staged:
    1. ______________________  took ______
    2. ______________________  took ______
  => If these cannot be pre-staged, real RTO is: ______

CONTACT TEST
  Voice call answered by live agent      Y / N
  Routed via correct flow and queue      Y / N
  Recording written to S3                Y / N
  Warm transfer worked (B5)              Y / N
  Chat answered (if in scope)            Y / N

B5 VERIFICATION
  Layers 2 and 3 passed after ONE run    Y / N
  Queue quick connect counts matched     Y / N
  Hours overrides applied                Y / N

FLOW RESILIENCE (connect_assess)
  Exit code                              0 / 1
  Flows that do NOT degrade gracefully : ______

RESIDUAL GAPS
  Validation failures still open after manual work:
    1. ______________________
    2. ______________________

IDEMPOTENCY
  associate-queue-quick-connects       : idempotent / errors / n/a
  create-hours-of-operation-override   : idempotent / duplicates / errors
  Is "re-run connect_restore" safe?      Y / N

RECOMMENDED LAYER 1 TARGET
  Based on the above, the achievable Layer 1 RTO is ______,
  which corresponds to: Backup-and-Restore / Pilot Light / Warm Standby

SIGN-OFF
  Drill run by : ____________   Date : ________
  Witnessed by : ____________
```

---

## Notes

The drill deliberately does **not** cover Layer 2 (records) or Layer 3 (reconstruction). Attempting all three in one sitting produces a long day and no clear conclusions. Run this one first, because Layer 1 is the only layer where minutes matter.

Because Sydney is not a Global Resiliency Region, this toolkit is the recovery path rather than a complement to a managed replica. That makes the measured number here your actual recovery capability, not a fallback estimate.
