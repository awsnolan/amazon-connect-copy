############################################################
#
# Pre-flight: Target Instance Reachability
#

section_header "Pre-flight: Target Instance"

instance_id_b=$(jq -r '.Id // empty' "$instance_alias_dir_b/instance.json" 2>/dev/null | tr -d '\r')
if [ -z "$instance_id_b" ]; then
    error "Cannot determine target instance ID from $instance_alias_dir_b/instance.json"
fi

live_status=$(aws_connect describe-instance --instance-id "$instance_id_b" 2>/dev/null | \
    jq -r '.Instance.InstanceStatus // empty' | tr -d '\r')

if [ "$live_status" = "ACTIVE" ]; then
    echo "  ✓ Target instance $instance_alias_b is ACTIVE (id=$instance_id_b)"
elif [ -n "$dryrun" ]; then
    echo "  - Target instance not reachable (dry-run mode, continuing)"
else
    echo "  ✗ Target instance $instance_alias_b is NOT reachable or not ACTIVE (status=$live_status)" >&2
    echo "" >&2
    echo "The target Amazon Connect instance must exist and be in ACTIVE state before" >&2
    echo "running connect_restore. Instance creation is not automated — provision the" >&2
    echo "instance manually or use a warm standby." >&2
    error "Target instance not available. Cannot proceed with restore."
fi

echo

############################################################
#
# Prompts
#

cat <<EOD

Prompts
-------
EOD

egrep -q "^prompt_" "$helper_new"
if [ $? -eq 1 ]; then
    echo "All prompts in the source instance exist in the target instance."
else
    echo "Missing prompts detected — recording for manual action."
    egrep "^prompt_" "$helper_new" | sort |
    while read prompt_entry; do
        prompt_name=${prompt_entry#prompt_}
        prompt_name=${prompt_name%.json}
        manual_action "Prompts" "Upload prompt '$prompt_name' to target instance"
    done
fi


############################################################
#
# Pre-flight: External Dependencies Check
#

cat <<EOD

Pre-flight Check: External Dependencies
----------------------------------------
EOD

manifest_file="$instance_alias_dir_a/external_dependencies.json"
preflight_warnings=0
preflight_missing=0

if [ ! -f "$manifest_file" ]; then
    echo "WARNING: external_dependencies.json not found in $instance_alias_dir_a"
    echo "         Run connect_save >= 1.5.0 to generate it."
    echo "         Skipping pre-flight check - continuing anyway."
else
    echo "Checking dependencies from: $manifest_file"
    echo

    # --- Lambda functions ---
    lambda_count=$(jq ".LambdaFunctions | length" "$manifest_file" 2>/dev/null || echo 0)
    if [ "$lambda_count" -gt 0 ]; then
        echo "Lambda Functions ($lambda_count):"
        jq -r ".LambdaFunctions[] | .Arn" "$manifest_file" | dos2unix |
        while read lambda_arn; do
            # Remap ARN prefix for target account/region
            lambda_arn_b=$(echo "$lambda_arn" | sed -f "$helper_sed")
            func_name="${lambda_arn_b##*:function:}"
            func_name="${func_name%%:*}"
            exists=$(aws lambda get-function \
                $profile_flag \
                --function-name "$lambda_arn_b" \
                2>/dev/null | jq -r '.Configuration.FunctionName // empty')
            if [ -n "$exists" ]; then
                echo "  ✓ $func_name"
            else
                echo "  ✗ MISSING: $func_name"
                echo "    Source ARN : $lambda_arn"
                echo "    Target ARN : $lambda_arn_b"
                preflight_missing=$((preflight_missing + 1))
            fi
        done
        echo
    fi

    # --- Lex V2 bots ---
    lexv2_count=$(jq ".LexV2Bots | length" "$manifest_file" 2>/dev/null || echo 0)
    if [ "$lexv2_count" -gt 0 ]; then
        echo "Lex V2 Bots ($lexv2_count):"
        jq -r ".LexV2Bots[] | .BotId + \" \" + .BotName + \" \" + .AliasId" "$manifest_file" | dos2unix |
        while read bot_id bot_name alias_id; do
            # Remap bot ARN
            bot_arn_a="arn:aws:lex:$region_a:$aws_ac_a:bot-alias/$bot_id/$alias_id"
            bot_arn_b=$(echo "$bot_arn_a" | sed -f "$helper_sed")
            bot_id_b=$(echo "$bot_arn_b" | sed 's|.*bot-alias/\([^/]*\)/.*|\1|')
            alias_id_b=$(echo "$bot_arn_b" | sed 's|.*bot-alias/[^/]*/\(.*\)|\1|')
            exists=$(aws lexv2-models describe-bot \
                $profile_flag \
                --bot-id "$bot_id_b" \
                2>/dev/null | jq -r '.botName // empty')
            if [ -n "$exists" ]; then
                echo "  ✓ $bot_name (id=$bot_id_b)"
            else
                echo "  ✗ MISSING: $bot_name"
                echo "    Source bot-id : $bot_id / alias: $alias_id"
                echo "    Target bot-id : $bot_id_b / alias: $alias_id_b"
                preflight_missing=$((preflight_missing + 1))
            fi
        done
        echo
    fi

    # --- Lex Classic bots ---
    lex_classic_count=$(jq ".LexClassicBots | length" "$manifest_file" 2>/dev/null || echo 0)
    if [ "$lex_classic_count" -gt 0 ]; then
        echo "Lex Classic Bots ($lex_classic_count):"
        jq -r ".LexClassicBots[] | .Name + \" \" + .Region" "$manifest_file" | dos2unix |
        while read bot_name bot_region; do
            # Remap region if cross-region copy
            bot_region_b="${bot_region/$region_a/$region_b}"
            # Apply lex bot prefix remapping if set
            bot_name_b="$bot_name"
            if [ -n "$lex_bot_prefix_a" ] && [ -n "$lex_bot_prefix_b" ]; then
                bot_name_b="${bot_name/#$lex_bot_prefix_a/$lex_bot_prefix_b}"
            fi
            exists=$(aws lex-models get-bot \
                $profile_flag \
                --name "$bot_name_b" \
                --version-or-alias '$LATEST' \
                2>/dev/null | jq -r '.name // empty')
            if [ -n "$exists" ]; then
                echo "  ✓ $bot_name_b (region=$bot_region_b)"
            else
                echo "  ✗ MISSING: $bot_name_b (region=$bot_region_b)"
                preflight_missing=$((preflight_missing + 1))
            fi
        done
        echo
    fi

    if [ "$preflight_missing" -gt 0 ]; then
        echo "WARNING: $preflight_missing external dependency(s) not found on target account."
        echo "         Continuing with restore — manual actions will be listed at end."
        manual_action "External Dependencies" "Deploy $preflight_missing missing Lambda/Lex resource(s) to target account. Flows referencing them will fail until deployed."
    else
        echo "All external dependencies verified on target account."
    fi
fi

