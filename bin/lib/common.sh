#!/bin/bash
###############################################################################
#
# common.sh — shared helpers for the Amazon Connect DR tool suite
#             (connect_backup / connect_restore / connect_plan / connect_validate)
#
# Source this near the top of each script:
#   LIB_DIR="$(cd "$(dirname "$0")/lib" && pwd)"
#   . "$LIB_DIR/common.sh"
#
###############################################################################

# Guard against double-sourcing
[ -n "${_CONNECT_COMMON_SOURCED:-}" ] && return 0
_CONNECT_COMMON_SOURCED=1

CONNECT_TOOLS_VERSION="2.0.0"

###############################################################################
# Core utilities
###############################################################################

dos2unix() { tr -d '\r'; }

usage() { echo -e "$USAGE" >&2; exit 2; }

version() { echo -e "$SCRIPT_VERSION"; exit; }

# Timestamp for progress output
ts() { date '+%H:%M:%S'; }

###############################################################################
# ANSI Colour Support
# Respects NO_COLOR env var (https://no-color.org/) and --no-color flag.
# Set USE_COLOR=off to disable programmatically.
###############################################################################

USE_COLOR=on
[ -n "${NO_COLOR:-}" ] && USE_COLOR=off
# Terminal check: disable if stdout is not a terminal
[ ! -t 1 ] && USE_COLOR=off

if [ "$USE_COLOR" = "on" ]; then
    C_PASS='\033[32m'    # green
    C_FAIL='\033[31m'    # red
    C_WARN='\033[33m'    # yellow
    C_SKIP='\033[90m'    # grey
    C_BOLD='\033[1m'     # bold
    C_RESET='\033[0m'    # reset
else
    C_PASS=''
    C_FAIL=''
    C_WARN=''
    C_SKIP=''
    C_BOLD=''
    C_RESET=''
fi

###############################################################################
# Hex conversion + path encoding
###############################################################################

hex_cmd=
if [ -x "$(command -v xxd)" ]; then
    hex_cmd="xxd -u -p -c1"
elif [ -x "$(command -v hexdump)" ]; then
    hex_cmd="hexdump -v -e '/1 \"%02X\n\"'"
elif [ -x "$(command -v od)" ]; then
    hex_cmd="od -An -vtx1 | tr [:lower:] [:upper:] | for i in \$(cat); do echo \$i; done"
fi

hex_code() {
    printf '%s' "$1" | eval "$hex_cmd" | while read x; do printf "%%%s" "$x"; done
}

path_encode() {
    local old_lc_collate=$LC_COLLATE
    LC_COLLATE=C
    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:$i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf '%s' "$c";;
            *) x=$(hex_code "$c"); echo -n "${x//%0D/}";;
        esac
    done
    LC_COLLATE=$old_lc_collate
}

path_decode() {
    local path_encoded="${1//+/ }"
    printf '%b' "${path_encoded//%/\\x}"
}

###############################################################################
# Error handling
#
# Supports two modes:
#   error "message"                     — print message and exit
#   error LINENO "cf_name" "manifest"   — AWS CLI error with optional skip logic
#
# Set $skip_cf_errors=on and provide $TEMPCF to enable skip behaviour.
###############################################################################

error() {
    if [ "$#" -eq 0 ]; then
        exit 1
    fi
    if [[ ! "$1" =~ ^[[:digit:]]+$ ]]; then
        # Simple message
        cat <<EOD >&2
Error: $*
EOD
    else
        # AWS CLI error with line number
        local line_no=$1
        local cf="${2:-}"
        local manifest="${3:-}"
        if [ -n "$cf" ] && [ -n "$manifest" ] && [ -n "${skip_cf_errors:-}" ]; then
            # Skip this flow/module and remove from manifest
            cat "$manifest" |
            jq -r "select(.Name != \"$cf\")" > "${TEMPCF:-/dev/null}"
            if [ -n "${TEMPCF:-}" ]; then
                cat "$TEMPCF" > "$manifest"
                echo "\"$cf\" skipped and removed from $manifest."
                echo
                > "$TEMPCF"
                return 0
            fi
        fi
        cat <<EOD >&2
Error at line ${line_no}. Recommended actions:
1. Create all required prompts on the target instance
2. Publish all in-scope contact flows and contact flow modules (or use -s to skip them)
3. Install the latest AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
EOD
    fi
    exit 1
}

###############################################################################
# AWS CLI output filter
#
# Default: passthrough. connect_backup overrides this to add codepage/iconv
# filtering by redefining the function after sourcing common.sh.
###############################################################################

aws_cli_out_filter() { cat; }

###############################################################################
# AWS CLI wrapper — backup variant
#
# Used by connect_backup. Logs commands and filters output.
# Expects: $profile_flag, $aws_cli_log, $TEMPERR
###############################################################################

aws_connect_backup() {
    local cmd=""
    local ii
    for ii; do
        [[ "$ii" == *" "* ]] && cmd="$cmd \"$ii\"" || cmd="$cmd $ii"
    done
    echo "aws connect --output json$profile_flag$cmd" >> "${aws_cli_log:-/dev/null}"
    eval "aws connect --output json$profile_flag$cmd" 2> "${TEMPERR:-/dev/null}"
    local ret=$?
    if [ -s "${TEMPERR:-/dev/null}" ]; then
        cat "$TEMPERR" | tee -a "${aws_cli_log:-/dev/null}" >&2
    fi
    return $ret
}

###############################################################################
# AWS CLI wrapper — restore variant
#
# Used by connect_restore. Logs commands, captures stderr.
# Expects: $profile_flag, $aws_cli_log, $TEMPERR
###############################################################################

aws_connect_restore() {
    local cmd=""
    local ii
    for ii; do
        [[ "$ii" =~ " " || "$ii" =~ "(" || "$ii" =~ ")" ]] && cmd="$cmd \"$ii\"" || cmd="$cmd $ii"
    done
    echo "aws connect$profile_flag$cmd" >> "${aws_cli_log:-/dev/null}"
    eval "aws connect --output json$profile_flag$cmd" 2> "${TEMPERR:-/dev/null}"
    local ret=$?
    if [ -s "${TEMPERR:-/dev/null}" ]; then
        cat "$TEMPERR" | tee -a "${aws_cli_log:-/dev/null}" >&2
    fi
    return $ret
}

###############################################################################
# Extended ASCII encoding check
#
# Call check_encoding to warn/abort if the system can't handle accented chars.
# Set $ignore_improper_extended_ascii=on to bypass.
###############################################################################

check_encoding() {
    if [ "$(hex_code "é")" != "%C3%A9" ]; then
        echo "WARNING: This system may not encode Extended ASCII characters properly." >&2
        if [ -n "${ignore_improper_extended_ascii:-}" ]; then
            echo "Proceed regardless as the -e option is specified." >&2
        else
            cat <<EOD >&2

If your instance component names contain Extended ASCII characters, such as accented letters
like é, this system will encode those names differently from standard encoding.

If you are sure that your component names do not contain Extended ASCII characters,
you may proceed regardless by running the command again with the -e option.
EOD
            exit 1
        fi
    fi
}

###############################################################################
# JSON attribute helper (used by backup during flow/module export)
###############################################################################

add_json_attribute() {
    local attr_name=$1
    local attr_value=$2
    local key_id=$3
    local manifest=$4
    cat "$manifest" |
    jq -rs "map(if .Id == \"$key_id\" then . + {$attr_name: \"${attr_value//\"/\\\"}\"} else . end) | .[]" > "${TEMPCF:-/tmp/connect_tmp}"
    cat "${TEMPCF:-/tmp/connect_tmp}" > "$manifest"
    > "${TEMPCF:-/tmp/connect_tmp}"
}

###############################################################################
# Resilient describe wrapper (used by backup loops)
#
# Usage: describe_or_skip "label" output_file aws_connect describe-foo --args
#   - If the describe succeeds and output is non-empty: returns 0
#   - If the describe fails (ResourceNotFound, AccessDenied): prints skip, returns 1
#   - Caller decides whether to treat as fatal or continue
###############################################################################

describe_or_skip() {
    local label="$1"
    local output_file="$2"
    shift 2
    "$@" > "$output_file" 2>/dev/null
    if [ -s "$output_file" ]; then
        return 0
    else
        echo "  (skipped: $label — not describable or access denied)"
        rm -f "$output_file"
        return 1
    fi
}

###############################################################################
# Manual action tracker (used by restore)
#
# Appends items to $TEMPMANUAL. Call manual_action "Category" "Description"
###############################################################################

manual_action() {
    echo "[$1] $2" >> "${TEMPMANUAL:-/dev/null}"
}

###############################################################################
# Section runner utility
#
# Used by orchestrators to run sections with --only / --skip filtering.
# Usage: run_section "section_name" "/path/to/section.sh"
###############################################################################

run_section() {
    local name="$1"
    local script="$2"

    # Check --skip
    if [ -n "${SKIP_SECTIONS:-}" ]; then
        if echo "$SKIP_SECTIONS" | grep -qw "$name"; then
            echo "  [skip] $name"
            return 0
        fi
    fi

    # Check --only
    if [ -n "${ONLY_SECTIONS:-}" ]; then
        if ! echo "$ONLY_SECTIONS" | grep -qw "$name"; then
            return 0
        fi
    fi

    . "$script"
}

###############################################################################
# Section header for backup/restore output
###############################################################################

section_header() {
    echo ""
    echo -e "${C_BOLD}━━━ $1 ━━━ $(ts)${C_RESET}"
}
