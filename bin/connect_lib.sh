#!/bin/bash
###############################################################################
#
# connect_lib.sh — shared helpers for the Amazon-Connect-Copy tool suite
#                  (connect_save / connect_copy / connect_diff / connect_validate)
#
# DRAFT — proposed by refactor. NOT yet wired into any script.
# Source it near the top of each script:   . "$(dirname "$0")/connect_lib.sh"
#
# Design notes
# ------------
# * The 5 helpers below (dos2unix, usage, version, hex_code, path_encode) were
#   verified byte-identical across the scripts that define them, so they are
#   lifted verbatim.
# * aws_connect() and error() were FORKED across scripts (different behaviour).
#   They are reconciled here into ONE implementation each, parameterised by
#   environment variables / optional hook functions so every caller keeps its
#   current behaviour. See the per-script "wiring" comments at the bottom.
# * Nothing here changes behaviour on its own — a script only gets the new
#   behaviour once it sources this file AND removes its local copies.
#
###############################################################################

# Guard against double-sourcing
[ -n "${_CONNECT_LIB_SOURCED:-}" ] && return 0
_CONNECT_LIB_SOURCED=1

# ---------------------------------------------------------------------------
# Suite version (single source of truth)
# ---------------------------------------------------------------------------
# NOTE: connect_save/copy/diff currently report 1.5.0 but connect_validate
# reports 1.1.0 — they are independently versioned today. Adopting a single
# constant is a deliberate decision, not a freebie. Scripts that want the
# shared version should set:  SCRIPT_VERSION="$(basename "$0") $CONNECT_TOOLS_VERSION"
# A script may keep its own version simply by setting SCRIPT_VERSION itself.
CONNECT_TOOLS_VERSION="1.5.0"

# ---------------------------------------------------------------------------
# usage() / version()  — identical across all 4 scripts.
# They rely on the SOURCING script having set $USAGE and $SCRIPT_VERSION.
# ---------------------------------------------------------------------------
usage()   { echo -e "$USAGE" >&2; exit 2; }
version() { echo -e "$SCRIPT_VERSION"; exit; }

# ---------------------------------------------------------------------------
# dos2unix() — identical across all 4 scripts.
# ---------------------------------------------------------------------------
dos2unix() { tr -d '\r'; }

# ---------------------------------------------------------------------------
# Hex conversion + hex_code() — identical in save/copy/diff (absent in validate).
# Detects an available hex tool once at source time.
# ---------------------------------------------------------------------------
hex_cmd=
if [ -x "$(command -v xxd)" ]; then
  hex_cmd="xxd -u -p -c1"
elif [ -x "$(command -v hexdump)" ]; then
  hex_cmd="hexdump -v -e '/1 \"%02X\n\"'"
elif [ -x "$(command -v od)" ]; then
  hex_cmd="od -An -vtx1 | tr [:lower:] [:upper:] | for i in \$(cat); do echo \$i; done"
fi
# Callers that need hex_code MUST verify $hex_cmd is non-empty (as the
# scripts do today) — left to the caller so this file stays side-effect free.
hex_code() { printf '%s' "$1" | eval "$hex_cmd" | while read x; do printf "%%%s" "$x"; done }

# ---------------------------------------------------------------------------
# path_encode() — identical in save/copy/diff (absent in validate).
# URL/percent-encodes a component name for safe use as a filename.
# ---------------------------------------------------------------------------
path_encode() {
    old_lc_collate=$LC_COLLATE
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

# ---------------------------------------------------------------------------
# aws_cli_out_filter() — DEFAULT passthrough.
# connect_save overrides this AFTER sourcing to add its codepage/iconv filter:
#
#     aws_cli_out_filter() {
#         if [ -n "$codepage" ] && [ "$codepage" != "$aws_cli_encoding" ]; then
#             cat > "$TEMPOF"
#             iconv -f "$codepage" -t "$aws_cli_encoding" "$TEMPOF" 2>/dev/null \
#                 || cat "$TEMPOF"
#         else
#             cat
#         fi
#     }
# ---------------------------------------------------------------------------
aws_cli_out_filter() { cat; }

# ---------------------------------------------------------------------------
# aws_connect() — RECONCILED.
# Reproduces save/copy/validate behaviour via these knobs:
#   $aws_cli_log        : if set & non-empty -> append each command + errors to it
#                         (save & copy set this; validate does not -> no logging)
#   aws_cli_out_filter  : function hook; default passthrough, save overrides
#                         (gives save its codepage filtering; copy/validate get cat)
#   $AWS_CONNECT_QUIET  : if set -> discard stderr (validate's "2>/dev/null")
#   $TEMPERR            : if set (non-quiet) -> capture stderr there, tee to log
# Arg quoting uses the SUPERSET rule (space, '(' and ')') from connect_copy —
# strictly safer than save's space-only rule, harmless where unneeded.
# ---------------------------------------------------------------------------
aws_connect() {
    local cmd="" ii
    for ii; do
        if [[ "$ii" == *[" ()"]* ]]; then
            cmd="$cmd \"$ii\""
        else
            cmd="$cmd $ii"
        fi
    done

    [ -n "${aws_cli_log:-}" ] && echo "aws connect$profile_flag$cmd" >> "$aws_cli_log"

    if [ -n "${AWS_CONNECT_QUIET:-}" ]; then
        # validate-style: silent stderr, still passes through the (default) filter
        eval "aws connect$profile_flag$cmd" 2>/dev/null | aws_cli_out_filter
        return "${PIPESTATUS[0]}"
    fi

    # save/copy-style: capture stderr, surface + log it, return pipeline status
    eval "aws connect$profile_flag$cmd | aws_cli_out_filter" 2> "${TEMPERR:-/dev/null}"
    local ret=$?
    if [ -n "${TEMPERR:-}" ] && [ -s "$TEMPERR" ]; then
        if [ -n "${aws_cli_log:-}" ]; then
            cat "$TEMPERR" | tee -a "$aws_cli_log" >&2
        else
            cat "$TEMPERR" >&2
        fi
    fi
    return $ret
}

# ---------------------------------------------------------------------------
# error() — RECONCILED.
# Behaviour by argument shape (matches diff/save/copy today):
#   * no args                       -> exit 1 (save's bare `error`)
#   * non-numeric $1                -> "Error: $*" to stderr, exit 1
#                                      (diff's one-liner; save/copy non-CLI branch)
#   * numeric $1 (a line number)    -> AWS CLI error path:
#       - if $ERROR_SKIP_ENABLED set AND $2 (cf) AND $3 (manifest) given:
#           remove cf from the manifest, print a skip notice, RETURN 0
#           (connect_save -s behaviour; needs $TEMPCF set by caller)
#       - else: print recommended-actions hint and exit 1.
#           The hint text differs per script -> define an optional hook:
#               error_cli_hint() { ... uses $1 (line number) ... }
#           save/copy each define their own after sourcing; a default is used
#           if no hook is defined.
# ---------------------------------------------------------------------------
error() {
    [ "$#" -eq 0 ] && exit 1

    if [[ ! "$1" =~ ^[[:digit:]]+$ ]]; then
        printf 'Error: %s\n' "$*" >&2
        exit 1
    fi

    local line_no=$1; shift
    local cf="${1:-}" manifest="${2:-}"

    if [ -n "${ERROR_SKIP_ENABLED:-}" ] && [ -n "$cf" ] && [ -n "$manifest" ]; then
        cat "$manifest" | jq -r "select(.Name != \"$cf\")" > "$TEMPCF"
        cat "$TEMPCF" > "$manifest"
        printf '"%s" skipped and removed from %s.\n\n' "$cf" "$manifest"
        > "$TEMPCF"
        return 0
    fi

    if declare -F error_cli_hint >/dev/null 2>&1; then
        error_cli_hint "$line_no" >&2
    else
        cat >&2 <<EOD
Error at line ${line_no}. Recommended actions:
Install the latest AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
EOD
    fi
    exit 1
}

###############################################################################
# PER-SCRIPT WIRING (reference — what each script sets AFTER sourcing this lib
# so its current behaviour is preserved). Not executed here.
#
# connect_save:
#   SCRIPT_VERSION="$(basename "$0") $CONNECT_TOOLS_VERSION"
#   aws_cli_log="${instance_alias_dir%/}.log"        # enables logging
#   ERROR_SKIP_ENABLED=$skip_cf_errors               # -s flag
#   aws_cli_out_filter() { ...codepage/iconv... }    # override (see above)
#   error_cli_hint() {
#       cat <<H
# Error at line ${1}. Recommended actions:
# 1. Create all required prompts on the target instance
# 2. Publish all in-scope contact flows and contact flow modules (or use -s to skip them)
# 3. Install the latest AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# H
#   }
#
# connect_copy:
#   SCRIPT_VERSION="$(basename "$0") $CONNECT_TOOLS_VERSION"
#   aws_cli_log="${helper%/}.log"                    # enables logging
#   # no aws_cli_out_filter override -> passthrough (matches copy today)
#   error_cli_hint() {
#       cat <<H
# Error at line ${1}. Recommended actions:
# Make sure all required prompts exist in the target instance, and
# Install the latest AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html .
# H
#   }
#
# connect_diff:   (no AWS calls)
#   SCRIPT_VERSION="$(basename "$0") $CONNECT_TOOLS_VERSION"
#   # only uses usage/version/dos2unix/hex_code/path_encode + the non-numeric
#   # branch of error(). Nothing else to set.
#
# connect_validate:
#   SCRIPT_VERSION="$(basename "$0") 1.1.0"          # keeps its own version
#   AWS_CONNECT_QUIET=on                             # matches its 2>/dev/null
#   # keeps its own pass/fail/warn/skip test framework; uses lib only for
#   # usage/version/dos2unix (+ aws_connect in quiet mode).
###############################################################################
