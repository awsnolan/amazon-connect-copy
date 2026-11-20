#!/bin/bash
###############################################################################
#
# Test Suite: connect_assess — DR Resilience Assessment
#
# Runs all test cases against fixture flows. No AWS credentials needed.
#
# Exit codes:
#   0 — all tests pass
#   1 — one or more tests failed
#
###############################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSESS="$REPO_ROOT/bin/connect_assess"
FIXTURES="$SCRIPT_DIR/fixtures/assess"

# Counters
TESTS_RUN=0
TESTS_PASS=0
TESTS_FAIL=0
FAILURES=""

# Options
VERBOSE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --verbose|-v) VERBOSE=true; shift;;
        --help|-h) echo "Usage: $0 [--verbose]"; exit 0;;
        *) echo "Unknown option: $1"; exit 2;;
    esac
done

###############################################################################
# Test framework
###############################################################################

_test_name=""

test_start() {
    _test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$VERBOSE" = "true" ]; then
        printf "  %-70s " "$_test_name"
    fi
}

test_pass() {
    TESTS_PASS=$((TESTS_PASS + 1))
    if [ "$VERBOSE" = "true" ]; then
        echo "PASS"
    fi
}

test_fail() {
    local reason="${1:-}"
    TESTS_FAIL=$((TESTS_FAIL + 1))
    FAILURES="${FAILURES}\n  FAIL: ${_test_name}${reason:+ — $reason}"
    if [ "$VERBOSE" = "true" ]; then
        echo "FAIL${reason:+ ($reason)}"
    fi
}

# Helper: run assess on a fixture and extract JSON counts
assess_json() {
    local fixture="$1"
    "$ASSESS" -j "$FIXTURES/$fixture" 2>/dev/null
}

# Helper: check specific field from JSON output
check_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local actual
    actual=$(echo "$json" | jq -r ".$field" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        return 1
    fi
}

# Helper: check a specific finding's classification
check_finding() {
    local json="$1"
    local block="$2"
    local expected_class="$3"
    local actual
    actual=$(echo "$json" | jq -r ".details[0].findings[] | select(.block == \"$block\") | .classification" 2>/dev/null | head -1)
    if [ "$actual" = "$expected_class" ]; then
        return 0
    else
        return 1
    fi
}

###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  connect_assess Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
# Suite 1: Error Path Classification
###############################################################################

echo ""
echo "  Suite 1: Error Path Classification"

test_start "1.1 Lambda error path reaches queue → GRACEFUL"
result=$(assess_json "1.1_lambda_error_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "1.2 Lambda error path reaches disconnect → NOT GRACEFUL"
result=$(assess_json "1.2_lambda_error_to_disconnect.json")
if check_field "$result" "not_graceful" "1" && check_field "$result" "graceful" "0"; then
    test_pass
else
    test_fail "expected not_graceful=1, graceful=0"
fi

test_start "1.3 Lambda no error handler → NOT GRACEFUL"
result=$(assess_json "1.3_lambda_no_error_handler.json")
if check_field "$result" "not_graceful" "1"; then
    test_pass
else
    test_fail "expected not_graceful=1"
fi

test_start "1.4 Lambda error multi-hop to queue → GRACEFUL"
result=$(assess_json "1.4_lambda_error_multi_hop_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "1.5 Lex bot error path to queue → GRACEFUL"
result=$(assess_json "1.5_lex_error_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "1.6 Lambda error to nonexistent block → NOT GRACEFUL"
result=$(assess_json "1.6_lambda_error_to_nonexistent_block.json")
if check_field "$result" "not_graceful" "1"; then
    test_pass
else
    test_fail "expected not_graceful=1"
fi

###############################################################################
# Suite 2: Default/No-Match Path
###############################################################################

echo ""
echo "  Suite 2: Default/No-Match Path (empty response)"

test_start "2.1 Compare default to disconnect → NOT GRACEFUL"
result=$(assess_json "2.1_compare_default_to_disconnect.json")
if check_field "$result" "not_graceful" "1" && check_field "$result" "graceful" "0"; then
    test_pass
else
    test_fail "expected not_graceful=1, graceful=0"
fi

test_start "2.2 Compare default to queue → GRACEFUL"
result=$(assess_json "2.2_compare_default_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "2.3 Compare NoMatchingCondition error to queue → GRACEFUL"
result=$(assess_json "2.3_compare_nomatch_error_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

###############################################################################
# Suite 3: Dependency Awareness
###############################################################################

echo ""
echo "  Suite 3: Dependency Awareness"

test_start "3.1 Flow with no external dependencies → 0 blocks assessed"
result=$(assess_json "3.3_no_external_deps.json")
if check_field "$result" "blocks_assessed" "0"; then
    test_pass
else
    test_fail "expected blocks_assessed=0"
fi

test_start "3.2 All dep blocks are assessed (multi-lambda)"
result=$(assess_json "5.2_multi_lambda_mixed.json")
if check_field "$result" "blocks_assessed" "3"; then
    test_pass
else
    test_fail "expected blocks_assessed=3"
fi

###############################################################################
# Suite 4: Cycle Detection
###############################################################################

echo ""
echo "  Suite 4: Cycle Detection"

test_start "4.1 Self-loop (error path → same block) → NOT GRACEFUL"
result=$(assess_json "4.1_cycle_self_loop.json")
if check_field "$result" "not_graceful" "1"; then
    # Also verify the error_path field says "cycle"
    err_path=$(echo "$result" | jq -r '.details[0].findings[0].error_path' 2>/dev/null)
    if [ "$err_path" = "cycle" ]; then
        test_pass
    else
        test_fail "not_graceful=1 but error_path=$err_path (expected 'cycle')"
    fi
else
    test_fail "expected not_graceful=1"
fi

test_start "4.2 Multi-block cycle → NOT GRACEFUL"
result=$(assess_json "4.2_cycle_multi_block.json")
if check_field "$result" "not_graceful" "1"; then
    err_path=$(echo "$result" | jq -r '.details[0].findings[0].error_path' 2>/dev/null)
    if [ "$err_path" = "cycle" ]; then
        test_pass
    else
        test_fail "not_graceful=1 but error_path=$err_path (expected 'cycle')"
    fi
else
    test_fail "expected not_graceful=1"
fi

###############################################################################
# Suite 5: Multi-Block Real-World Flows
###############################################################################

echo ""
echo "  Suite 5: Multi-Block Real-World Flows"

test_start "5.1 DR Test IVR (3 deps, all graceful)"
result=$(assess_json "5.1_dr_test_ivr.json")
if check_field "$result" "blocks_assessed" "3" && check_field "$result" "graceful" "3" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected 3 blocks, 3 graceful, 0 not_graceful"
fi

test_start "5.2 Multiple Lambdas, mixed results (2 graceful, 1 not)"
result=$(assess_json "5.2_multi_lambda_mixed.json")
if check_field "$result" "graceful" "2" && check_field "$result" "not_graceful" "1"; then
    test_pass
else
    test_fail "expected graceful=2, not_graceful=1"
fi

test_start "5.3 Chained Lambda error (error → another Lambda → disconnect)"
result=$(assess_json "5.3_chained_lambda_error.json")
if check_field "$result" "blocks_assessed" "2" && check_field "$result" "not_graceful" "1" && check_field "$result" "graceful" "1"; then
    test_pass
else
    test_fail "expected 2 blocks, 1 graceful, 1 not_graceful"
fi

###############################################################################
# Suite 6: Block Type Coverage
###############################################################################

echo ""
echo "  Suite 6: Block Type Coverage"

test_start "6.1 TransferContactToFlow with no error handler → NOT GRACEFUL"
result=$(assess_json "6.1_transfer_to_missing_flow.json")
if check_field "$result" "not_graceful" "1"; then
    test_pass
else
    test_fail "expected not_graceful=1"
fi

test_start "6.2 InvokeFlowModule error path to queue → GRACEFUL"
result=$(assess_json "6.2_invoke_module_error_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "6.3 MessageParticipant with PromptId → DEGRADED"
result=$(assess_json "6.3_play_prompt_missing.json")
if check_field "$result" "degraded" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected degraded=1, not_graceful=0"
fi

###############################################################################
# Suite 7: Output Format
###############################################################################

echo ""
echo "  Suite 7: Output Format"

test_start "7.1 JSON output is valid JSON with required fields"
result=$(assess_json "5.1_dr_test_ivr.json")
valid=$(echo "$result" | jq -e '.flows_assessed and .blocks_assessed and .graceful != null and .not_graceful != null and .degraded != null and .details' >/dev/null 2>&1 && echo "yes" || echo "no")
if [ "$valid" = "yes" ]; then
    test_pass
else
    test_fail "JSON output missing required fields"
fi

test_start "7.2 Human-readable output contains classification markers"
human_out=$("$ASSESS" "$FIXTURES/5.2_multi_lambda_mixed.json" 2>&1)
if echo "$human_out" | grep -q "GRACEFUL" && echo "$human_out" | grep -q "NOT_GRACEFUL" && echo "$human_out" | grep -q "Assessment Summary"; then
    test_pass
else
    test_fail "missing GRACEFUL/NOT_GRACEFUL markers or summary"
fi

test_start "7.3 Exit code 0 when all graceful"
"$ASSESS" "$FIXTURES/1.1_lambda_error_to_queue.json" >/dev/null 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    test_pass
else
    test_fail "exit code=$rc (expected 0)"
fi

test_start "7.4 Exit code 1 when any not_graceful"
"$ASSESS" "$FIXTURES/1.2_lambda_error_to_disconnect.json" >/dev/null 2>&1
rc=$?
if [ $rc -eq 1 ]; then
    test_pass
else
    test_fail "exit code=$rc (expected 1)"
fi

test_start "7.5 Exit code 0 when only degraded (no not_graceful)"
"$ASSESS" "$FIXTURES/6.3_play_prompt_missing.json" >/dev/null 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    test_pass
else
    test_fail "exit code=$rc (expected 0)"
fi

###############################################################################
# Suite 8: Edge Cases
###############################################################################

echo ""
echo "  Suite 8: Edge Cases"

test_start "8.1 Empty flow (no actions) → 0 blocks"
result=$(assess_json "8.1_empty_flow.json")
if check_field "$result" "blocks_assessed" "0"; then
    test_pass
else
    test_fail "expected blocks_assessed=0"
fi

test_start "8.2 Single queue transfer (no deps) → 0 blocks"
result=$(assess_json "8.2_single_queue_transfer.json")
if check_field "$result" "blocks_assessed" "0"; then
    test_pass
else
    test_fail "expected blocks_assessed=0"
fi

test_start "8.3 Same Lambda twice (independent assessment per block)"
result=$(assess_json "8.3_same_lambda_twice.json")
if check_field "$result" "blocks_assessed" "2" && check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "1"; then
    test_pass
else
    test_fail "expected 2 blocks, 1 graceful, 1 not_graceful"
fi

test_start "8.4 Deep chain (12 hops) to queue → GRACEFUL"
result=$(assess_json "8.4_deep_chain_to_queue.json")
if check_field "$result" "graceful" "1" && check_field "$result" "not_graceful" "0"; then
    test_pass
else
    test_fail "expected graceful=1, not_graceful=0"
fi

test_start "8.5 Content stored as string field (double-parse)"
result=$(assess_json "8.5_content_as_string.json")
if check_field "$result" "blocks_assessed" "1" && check_field "$result" "graceful" "1"; then
    test_pass
else
    test_fail "expected 1 block, graceful=1"
fi

test_start "8.6 Directory mode (-d flag)"
result=$("$ASSESS" -j -d "$REPO_ROOT/dr-solution-target" 2>/dev/null)
total_blocks=$(echo "$result" | jq '.blocks_assessed' 2>/dev/null)
if [ -n "$total_blocks" ] && [ "$total_blocks" -gt 0 ]; then
    test_pass
else
    test_fail "directory mode produced blocks_assessed=$total_blocks (expected >0)"
fi

test_start "8.7 Version flag"
ver_out=$("$ASSESS" -v 2>&1)
if echo "$ver_out" | grep -q "1.0.0"; then
    test_pass
else
    test_fail "version output: $ver_out"
fi

###############################################################################
# Results
###############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $TESTS_PASS passed, $TESTS_FAIL failed (of $TESTS_RUN)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$TESTS_FAIL" -gt 0 ]; then
    echo ""
    echo "  Failures:"
    echo -e "$FAILURES"
    echo ""
    exit 1
fi

exit 0
