#!/bin/bash
############################################################
#
# probe_api_idempotency — are these two Connect APIs idempotent?
#
# Answers one question, to unblock backlog item B5:
#
#   If connect_restore calls associate-queue-quick-connects or
#   create-hours-of-operation-override a second time, does the API
#   succeed quietly, or does it return an error?
#
# This matters because both calls in bin/lib/restore/hours.sh end with
# "2>/dev/null || true". Removing that suppression is only safe if a
# re-run does NOT error — otherwise the documented "re-run connect_restore"
# remediation loop would abort the restore (run_section sources each
# section, and `test $? -eq 0 || error` calls exit 1).
#
# PROBE A  associate-queue-quick-connects  (non-destructive)
#          Re-associates quick connects that are ALREADY associated.
#          Cannot change the association set; verified before and after.
#
# PROBE B  create-hours-of-operation-override  (creates then deletes)
#          Creates a scratch hours-of-operation and override, then
#          creates the SAME override again. Cleans up on every exit path.
#
# SAFETY
#   - Read-only by default. Writes require --live.
#   - Probe B additionally requires --include-writes.
#   - Refuses to run against an instance whose alias looks like
#     production unless --force is given.
#   - All scratch resources are named zz-idempotency-probe-<epoch>.
#   - EXIT trap removes scratch resources and reports any orphans.
#
# Requires: aws CLI 2.32+, jq 1.6+, bash 3.2+
#
############################################################

VERSION=1.0.0
SCRIPT=$(basename "$0")

usage() {
    cat <<EOD
Usage: $SCRIPT --instance-id <id> [--profile <name>] [--live] [--include-writes] [--force]

    Determine whether associate-queue-quick-connects and
    create-hours-of-operation-override are idempotent on re-invocation.

    --instance-id <id>   Target Amazon Connect instance (required)
    --profile <name>     AWS CLI profile
    --region <name>      AWS region (defaults to profile/env)
    --live               Actually call the APIs. Without this, prints the
                         plan and makes read-only calls only.
    --include-writes     Also run Probe B, which creates and deletes a
                         scratch hours-of-operation and override.
    --force              Proceed even if the instance alias looks like
                         production. Not recommended.
    -v                   Version
    -?, --help           This help

    Use a scratch or DR instance. Do not run with --live against
    production.

Examples:
    # Safe: plan only, no writes
    $SCRIPT --instance-id <id> --profile dr-profile

    # Probe A only (non-destructive re-association)
    $SCRIPT --instance-id <id> --profile dr-profile --live

    # Both probes (Probe B creates + deletes scratch resources)
    $SCRIPT --instance-id <id> --profile dr-profile --live --include-writes
EOD
}

############################################################
# Arguments
############################################################

instance_id=""
profile=""
region=""
live=""
include_writes=""
force=""

while [ $# -gt 0 ]; do
    case "$1" in
        --instance-id)    instance_id="$2"; shift 2;;
        --profile)        profile="$2"; shift 2;;
        --region)         region="$2"; shift 2;;
        --live)           live=1; shift;;
        --include-writes) include_writes=1; shift;;
        --force)          force=1; shift;;
        -v)               echo "$SCRIPT $VERSION"; exit 0;;
        -\?|--help)       usage; exit 0;;
        *)                echo "Unknown option: $1" >&2; usage; exit 1;;
    esac
done

[ -z "$instance_id" ] && { echo "Error: --instance-id is required" >&2; usage; exit 1; }

profile_flag=""
[ -n "$profile" ] && profile_flag="--profile $profile"
[ -n "$region" ]  && profile_flag="$profile_flag --region $region"

for dep in aws jq; do
    command -v "$dep" >/dev/null 2>&1 || { echo "Error: $dep not found" >&2; exit 1; }
done

############################################################
# Output helpers
############################################################

if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
    C_BOLD=$'\033[1m'; C_PASS=$'\033[32m'; C_FAIL=$'\033[31m'
    C_WARN=$'\033[33m'; C_DIM=$'\033[90m'; C_RESET=$'\033[0m'
else
    C_BOLD=""; C_PASS=""; C_FAIL=""; C_WARN=""; C_DIM=""; C_RESET=""
fi

hdr()  { echo; echo "${C_BOLD}━━━ $* ━━━${C_RESET}"; }
info() { echo "  $*"; }
dim()  { echo "  ${C_DIM}$*${C_RESET}"; }
ok()   { echo "  ${C_PASS}✓${C_RESET} $*"; }
bad()  { echo "  ${C_FAIL}✗${C_RESET} $*"; }
warn() { echo "  ${C_WARN}⚠${C_RESET} $*"; }

RESULTS=$(mktemp)
SCRATCH=$(mktemp -d)

# api|scenario|exit_code|error_code|verdict
record() { printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >> "$RESULTS"; }

# Extract ExceptionName from an AWS CLI error string
err_code() {
    printf '%s' "$1" | sed -n 's/.*An error occurred (\([A-Za-z]*\)).*/\1/p' | head -1
}

############################################################
# Scratch resource tracking + cleanup
############################################################

STAMP=$(date +%s)
SCRATCH_PREFIX="zz-idempotency-probe-$STAMP"
CREATED_HOO=""
CREATED_OVERRIDES=""

cleanup() {
    local rc=$?
    if [ -n "$CREATED_OVERRIDES" ] || [ -n "$CREATED_HOO" ]; then
        hdr "Cleanup"
        for ov in $CREATED_OVERRIDES; do
            if aws connect delete-hours-of-operation-override \
                 --instance-id "$instance_id" \
                 --hours-of-operation-id "$CREATED_HOO" \
                 --hours-of-operation-override-id "$ov" \
                 $profile_flag >/dev/null 2>&1; then
                ok "Deleted override $ov"
            else
                bad "Could NOT delete override $ov — remove manually"
            fi
        done
        if [ -n "$CREATED_HOO" ]; then
            if aws connect delete-hours-of-operation \
                 --instance-id "$instance_id" \
                 --hours-of-operation-id "$CREATED_HOO" \
                 $profile_flag >/dev/null 2>&1; then
                ok "Deleted hours-of-operation $CREATED_HOO"
            else
                bad "Could NOT delete hours-of-operation $CREATED_HOO — remove manually"
            fi
        fi
        # Orphan sweep
        local leftover
        leftover=$(aws connect list-hours-of-operations \
                     --instance-id "$instance_id" $profile_flag 2>/dev/null \
                   | jq -r --arg p "zz-idempotency-probe-" \
                       '.HoursOfOperationSummaryList[]? | select(.Name | startswith($p)) | .Name' 2>/dev/null)
        if [ -n "$leftover" ]; then
            warn "Scratch resources still present:"
            echo "$leftover" | sed 's/^/      /'
        fi
    fi
    rm -rf "$SCRATCH"
    rm -f "$RESULTS"
    exit $rc
}
trap cleanup EXIT INT TERM

############################################################
# Banner
############################################################

cat <<EOD
${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}
  $SCRIPT $VERSION
  Instance : $instance_id
  Profile  : ${profile:-${AWS_PROFILE:-(default)}}
  Mode     : $([ -n "$live" ] && echo "LIVE" || echo "plan only (read-only)")
  Probe B  : $([ -n "$include_writes" ] && echo "enabled" || echo "skipped (needs --include-writes)")
${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}
EOD

############################################################
# Preflight
############################################################

hdr "Preflight"

caller=$(aws sts get-caller-identity $profile_flag --output json 2>/dev/null)
if [ -z "$caller" ]; then
    bad "Cannot authenticate. Check credentials/profile."
    exit 1
fi
ok "Authenticated as $(printf '%s' "$caller" | jq -r '.Arn' | sed 's/:[0-9]\{12\}:/:<account>:/')"

inst=$(aws connect describe-instance --instance-id "$instance_id" $profile_flag --output json 2>/dev/null)
if [ -z "$inst" ]; then
    bad "Cannot describe instance $instance_id"
    exit 1
fi
alias=$(printf '%s' "$inst" | jq -r '.Instance.InstanceAlias // "(none)"')
status=$(printf '%s' "$inst" | jq -r '.Instance.InstanceStatus // "UNKNOWN"')
ok "Instance alias '$alias', status $status"
[ "$status" != "ACTIVE" ] && { bad "Instance is not ACTIVE"; exit 1; }

# Production heuristic.
# Tokens are matched only when delimited by start/end or -_. so that
# substrings do not produce false matches (e.g. "hydra-prod" must not be
# treated as a DR instance because "hydra" contains "dr").
PROD_TOKENS='prod|production|prd|live'
SAFE_TOKENS='dev|test|tst|beta|stag|staging|sandbox|sbx|dr|scratch|uat|poc|nonprod|non-prod|demo'
DELIM='(^|[-_.])'
DELIM_END='([-_.]|$)'

looks_prod=""
looks_safe=""
printf '%s' "$alias" | grep -qiE "${DELIM}(${PROD_TOKENS})${DELIM_END}" && looks_prod=1
printf '%s' "$alias" | grep -qiE "${DELIM}(${SAFE_TOKENS})${DELIM_END}" && looks_safe=1

# An alias carrying both (e.g. "prod-dr-sydney") is the DR copy of prod.
if [ -n "$looks_prod" ] && [ -n "$looks_safe" ]; then
    looks_prod=""
    dim "Alias contains both production and non-production tokens; treating as non-production."
fi

if [ -n "$looks_prod" ] && [ -n "$live" ] && [ -z "$force" ]; then
    echo
    bad "Instance alias '$alias' looks like PRODUCTION."
    info "Probe A is non-destructive, but this script will not run live"
    info "against a production-looking instance without --force."
    info "Use a DR or scratch instance instead."
    exit 1
fi
[ -n "$looks_prod" ] && [ -n "$force" ] && warn "Proceeding against production-looking alias due to --force"

# Assume production when uncertain — gate the WRITE path only, so Probe A
# stays frictionless on instances with an ambiguous alias.
if [ -z "$looks_safe" ] && [ -n "$include_writes" ] && [ -n "$live" ] && [ -z "$force" ]; then
    echo
    bad "Cannot confirm '$alias' is a non-production instance."
    info "Probe B creates and deletes resources, so it needs a clearly"
    info "non-production target. Recognised safe tokens:"
    info "  $(printf '%s' "$SAFE_TOKENS" | tr '|' ' ')"
    info "Either use such an instance, or pass --force if you are certain."
    info "Probe A alone is non-destructive and needs no extra flag."
    exit 1
fi

############################################################
# PROBE A — associate-queue-quick-connects (non-destructive)
############################################################

hdr "Probe A — associate-queue-quick-connects (re-associate existing)"

info "Finding a queue that already has quick connects associated..."

probe_queue_id=""
probe_queue_name=""
probe_qc_ids=""

queues=$(aws connect list-queues --instance-id "$instance_id" \
           --queue-types STANDARD $profile_flag --output json 2>/dev/null \
         | jq -r '.QueueSummaryList[]? | .Id + "\t" + .Name')

while IFS=$'\t' read -r qid qname; do
    [ -z "$qid" ] && continue
    ids=$(aws connect list-queue-quick-connects \
            --instance-id "$instance_id" --queue-id "$qid" \
            $profile_flag --output json 2>/dev/null \
          | jq -r '[.QuickConnectSummaryList[]?.Id] | join(" ")')
    if [ -n "$ids" ]; then
        probe_queue_id="$qid"; probe_queue_name="$qname"; probe_qc_ids="$ids"
        break
    fi
done <<< "$queues"

if [ -z "$probe_queue_id" ]; then
    warn "No queue with existing quick connect associations found."
    info "Probe A needs one. Associate a quick connect to any queue, then re-run."
    record "associate-queue-quick-connects" "duplicate associate" "-" "-" "SKIPPED (no fixture)"
else
    qc_n=$(printf '%s' "$probe_qc_ids" | wc -w | tr -d ' ')
    ok "Using queue '$probe_queue_name' with $qc_n associated quick connect(s)"

    before=$(aws connect list-queue-quick-connects \
               --instance-id "$instance_id" --queue-id "$probe_queue_id" \
               $profile_flag --output json 2>/dev/null \
             | jq -r '[.QuickConnectSummaryList[]?.Id] | sort | join(",")')

    ids_json=$(printf '%s' "$probe_qc_ids" | tr ' ' '\n' | jq -Rs 'split("\n") | map(select(. != ""))')

    if [ -z "$live" ]; then
        dim "[plan] aws connect associate-queue-quick-connects \\"
        dim "         --instance-id $instance_id \\"
        dim "         --queue-id $probe_queue_id \\"
        dim "         --quick-connect-ids <$qc_n already-associated id(s)>"
        record "associate-queue-quick-connects" "duplicate associate" "-" "-" "NOT RUN (plan only)"
    else
        info "Calling associate-queue-quick-connects with the SAME ids..."
        out=$(aws connect associate-queue-quick-connects \
                --instance-id "$instance_id" \
                --queue-id "$probe_queue_id" \
                --quick-connect-ids "$ids_json" \
                $profile_flag 2>&1)
        rc=$?
        ec=$(err_code "$out")

        if [ $rc -eq 0 ]; then
            ok "Returned exit 0 — IDEMPOTENT"
            record "associate-queue-quick-connects" "duplicate associate" "$rc" "none" "IDEMPOTENT"
        else
            bad "Returned exit $rc${ec:+ ($ec)}"
            dim "$(printf '%s' "$out" | head -2)"
            record "associate-queue-quick-connects" "duplicate associate" "$rc" "${ec:-unknown}" "NOT IDEMPOTENT"
        fi

        after=$(aws connect list-queue-quick-connects \
                  --instance-id "$instance_id" --queue-id "$probe_queue_id" \
                  $profile_flag --output json 2>/dev/null \
                | jq -r '[.QuickConnectSummaryList[]?.Id] | sort | join(",")')
        if [ "$before" = "$after" ]; then
            ok "Association set unchanged (no side effect)"
        else
            bad "Association set CHANGED — investigate before relying on this probe"
            dim "before: $before"
            dim "after : $after"
        fi
    fi
fi

############################################################
# PROBE B — create-hours-of-operation-override
############################################################

hdr "Probe B — create-hours-of-operation-override (duplicate create)"

if [ -z "$include_writes" ]; then
    info "Skipped. Re-run with --live --include-writes to execute."
    info "Probe B creates a scratch hours-of-operation and override, then deletes both."
    record "create-hours-of-operation-override" "duplicate create" "-" "-" "SKIPPED (no --include-writes)"
elif [ -z "$live" ]; then
    dim "[plan] create-hours-of-operation  $SCRATCH_PREFIX"
    dim "[plan] create-hours-of-operation-override  $SCRATCH_PREFIX-ov   (first call)"
    dim "[plan] create-hours-of-operation-override  $SCRATCH_PREFIX-ov   (same payload again)"
    dim "[plan] delete override, delete hours-of-operation"
    record "create-hours-of-operation-override" "duplicate create" "-" "-" "NOT RUN (plan only)"
else
    cat > "$SCRATCH/hoo.json" <<EOD
{
  "InstanceId": "$instance_id",
  "Name": "$SCRATCH_PREFIX",
  "Description": "Temporary resource created by probe_api_idempotency.sh. Safe to delete.",
  "TimeZone": "UTC",
  "Config": [
    {"Day": "MONDAY", "StartTime": {"Hours": 9, "Minutes": 0}, "EndTime": {"Hours": 17, "Minutes": 0}}
  ]
}
EOD

    info "Creating scratch hours-of-operation '$SCRATCH_PREFIX'..."
    out=$(aws connect create-hours-of-operation \
            --cli-input-json "file://$SCRATCH/hoo.json" \
            $profile_flag --output json 2>&1)
    if [ $? -ne 0 ]; then
        bad "Could not create scratch hours-of-operation"
        dim "$(printf '%s' "$out" | head -2)"
        record "create-hours-of-operation-override" "duplicate create" "-" "-" "SETUP FAILED"
    else
        CREATED_HOO=$(printf '%s' "$out" | jq -r '.HoursOfOperationId')
        ok "Created $CREATED_HOO"

        from=$(date -u -v+1d +%Y-%m-%d 2>/dev/null || date -u -d '+1 day' +%Y-%m-%d)
        till=$(date -u -v+2d +%Y-%m-%d 2>/dev/null || date -u -d '+2 days' +%Y-%m-%d)

        cat > "$SCRATCH/ov.json" <<EOD
{
  "InstanceId": "$instance_id",
  "HoursOfOperationId": "$CREATED_HOO",
  "Name": "$SCRATCH_PREFIX-ov",
  "Description": "Temporary override created by probe_api_idempotency.sh.",
  "EffectiveFrom": "$from",
  "EffectiveTill": "$till",
  "Config": [
    {"Day": "MONDAY", "StartTime": {"Hours": 10, "Minutes": 0}, "EndTime": {"Hours": 12, "Minutes": 0}}
  ]
}
EOD

        info "First create-hours-of-operation-override..."
        out1=$(aws connect create-hours-of-operation-override \
                 --cli-input-json "file://$SCRATCH/ov.json" \
                 $profile_flag --output json 2>&1)
        rc1=$?
        if [ $rc1 -ne 0 ]; then
            bad "First override create failed — cannot test duplicate"
            dim "$(printf '%s' "$out1" | head -2)"
            record "create-hours-of-operation-override" "duplicate create" "-" "$(err_code "$out1")" "SETUP FAILED"
        else
            ov1=$(printf '%s' "$out1" | jq -r '.HoursOfOperationOverrideId')
            CREATED_OVERRIDES="$ov1"
            ok "Created override $ov1"

            info "Second create with the SAME payload..."
            out2=$(aws connect create-hours-of-operation-override \
                     --cli-input-json "file://$SCRATCH/ov.json" \
                     $profile_flag --output json 2>&1)
            rc2=$?
            ec2=$(err_code "$out2")

            if [ $rc2 -eq 0 ]; then
                ov2=$(printf '%s' "$out2" | jq -r '.HoursOfOperationOverrideId')
                if [ "$ov2" = "$ov1" ]; then
                    ok "Returned exit 0 with the same id — IDEMPOTENT"
                    record "create-hours-of-operation-override" "duplicate create" "$rc2" "none" "IDEMPOTENT"
                else
                    CREATED_OVERRIDES="$CREATED_OVERRIDES $ov2"
                    warn "Returned exit 0 but created a SECOND override ($ov2)"
                    info "Re-running restore would silently duplicate overrides."
                    record "create-hours-of-operation-override" "duplicate create" "$rc2" "none" "DUPLICATES SILENTLY"
                fi
            else
                bad "Returned exit $rc2${ec2:+ ($ec2)}"
                dim "$(printf '%s' "$out2" | head -2)"
                record "create-hours-of-operation-override" "duplicate create" "$rc2" "${ec2:-unknown}" "NOT IDEMPOTENT"
            fi

            count=$(aws connect list-hours-of-operation-overrides \
                      --instance-id "$instance_id" \
                      --hours-of-operation-id "$CREATED_HOO" \
                      $profile_flag --output json 2>/dev/null \
                    | jq '[.HoursOfOperationOverrideList[]?] | length')
            info "Overrides now on scratch hours-of-operation: ${count:-?}"
        fi
    fi
fi

############################################################
# Report
############################################################

hdr "Results"

printf '  %-38s %-20s %-6s %-26s %s\n' "API" "SCENARIO" "EXIT" "ERROR CODE" "VERDICT"
printf '  %-38s %-20s %-6s %-26s %s\n' "--------------------------------------" "--------------------" "------" "--------------------------" "-------"
while IFS='|' read -r api scen rc ec verdict; do
    printf '  %-38s %-20s %-6s %-26s %s\n' "$api" "$scen" "$rc" "$ec" "$verdict"
done < "$RESULTS"

hdr "What this means for B5"

if grep -q 'NOT IDEMPOTENT\|DUPLICATES SILENTLY' "$RESULTS" 2>/dev/null; then
    cat <<EOD
  ${C_FAIL}Do NOT simply remove "2>/dev/null || true" in hours.sh.${C_RESET}

  At least one API is not safely repeatable. Because run_section sources
  each section and "test \$? -eq 0 || error" calls exit 1, an unsuppressed
  failure would abort the whole restore — breaking the documented
  "re-run connect_restore" remediation loop.

  Use the alternative: capture the call's status, print a WARN naming the
  resource, and continue. Keep the failure away from the "test \$?" guard.
EOD
elif grep -q 'IDEMPOTENT' "$RESULTS" 2>/dev/null && ! grep -q 'SKIPPED\|NOT RUN\|SETUP FAILED' "$RESULTS" 2>/dev/null; then
    cat <<EOD
  ${C_PASS}Both APIs are safely repeatable.${C_RESET}

  Relaxing error suppression is lower risk than feared. Even so, prefer
  explicit capture-and-report over bare unsuppressed calls, so a genuine
  failure does not reach "test \$? -eq 0 || error" and abort the restore.
EOD
else
    cat <<EOD
  ${C_WARN}Inconclusive.${C_RESET} One or more probes did not run.

  Re-run with --live --include-writes against a scratch or DR instance
  to get a definitive answer. Note that Probe A also needs at least one
  queue with a quick connect already associated.
EOD
fi

echo
