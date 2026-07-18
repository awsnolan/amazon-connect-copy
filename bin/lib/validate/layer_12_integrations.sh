validate_layer_12() {
    layer_start 12 "Integration Associations"

    if [ ! -f "$instance_alias_dir/integrations.json" ]; then
        skip "12.1" "Integrations" "integrations.json not found"
        layer_end; return
    fi

    local int_count
    int_count=$(jq -s 'length' "$instance_alias_dir/integrations.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "12.1" "Integrations manifest ($int_count)"
        layer_end; return
    }

    # 12.1: Check that live instance has integration associations
    local live_integrations
    live_integrations=$(aws_connect list-integration-associations \
        --instance-id "$instance_id" \
        --max-items $maxitems 2>/dev/null)
    if [ -n "$live_integrations" ]; then
        local live_int_count
        live_int_count=$(echo "$live_integrations" | jq '.IntegrationAssociationSummaryList | length' 2>/dev/null)
        if [ "$live_int_count" -ge "$int_count" ]; then
            pass "12.1" "Integration associations present (live=$live_int_count saved=$int_count)"
        else
            warn "12.1" "Integration count" "live=$live_int_count < saved=$int_count"
        fi
    else
        fail "12.1" "Integrations" "Could not retrieve live integrations"
        layer_end; return
    fi

    # 12.2: Lex V2 bots reachable (from integration associations)
    local lex_pass=0 lex_fail=0 lex_total=0
    while IFS=$'\t' read -r ia_type ia_arn; do
        [ -z "$ia_type" ] && continue
        [ "$ia_type" != "LEX_BOT" ] && continue
        lex_total=$((lex_total + 1))

        # Extract bot ID and alias from the ARN (format: arn:aws:lex:region:account:bot-alias/BOT_ID/ALIAS_ID)
        local bot_id alias_id
        bot_id=$(echo "$ia_arn" | sed 's|.*bot-alias/\([^/]*\)/.*|\1|')
        alias_id=$(echo "$ia_arn" | sed 's|.*bot-alias/[^/]*/\(.*\)|\1|')

        # Try to describe the bot alias
        local alias_check
        alias_check=$(aws_lex_v2 describe-bot-alias --bot-id "$bot_id" --bot-alias-id "$alias_id" 2>/dev/null)
        if [ -n "$alias_check" ]; then
            local alias_status
            alias_status=$(echo "$alias_check" | jq -r '.botAliasStatus // empty' | dos2unix)
            if [ "$alias_status" = "Available" ]; then
                lex_pass=$((lex_pass + 1))
            else
                lex_fail=$((lex_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Lex bot alias not Available: bot=$bot_id alias=$alias_id (status=$alias_status)" >&2
            fi
        else
            lex_fail=$((lex_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Lex bot alias not reachable: bot=$bot_id alias=$alias_id" >&2
        fi
    done < <(jq -r '.IntegrationType + "\t" + .IntegrationArn' "$instance_alias_dir/integrations.json" 2>/dev/null | dos2unix)

    if [ "$lex_total" -gt 0 ]; then
        if [ "$lex_fail" -eq 0 ]; then
            pass "12.2" "Lex V2 bots reachable ($lex_pass/$lex_total)"
        else
            fail "12.2" "Lex V2 bots" "$lex_fail of $lex_total not reachable"
        fi
    else
        skip "12.2" "Lex V2 bots" "no Lex integrations"
    fi

    # 12.3 + 12.4: Lambda functions reachable + permissions
    # Get Lambda associations from the instance
    local lambda_assoc
    lambda_assoc=$(aws_connect list-lambda-functions \
        --instance-id "$instance_id" \
        --max-items $maxitems 2>/dev/null)
    local live_lambda_arns
    live_lambda_arns=$(echo "$lambda_assoc" | jq -r '.LambdaFunctions[]? // empty' 2>/dev/null | dos2unix)

    # Get saved Lambda associations
    local saved_lambda_file="$instance_alias_dir/lambda_associations.json"
    if [ -f "$saved_lambda_file" ]; then
        local lam_pass=0 lam_fail=0 lam_total=0
        local perm_pass=0 perm_fail=0

        while IFS= read -r saved_arn; do
            [ -z "$saved_arn" ] && continue
            lam_total=$((lam_total + 1))

            # Extract function name for cross-account lookup
            local func_name="${saved_arn##*:function:}"
            func_name="${func_name%%:*}"

            # 12.3: Function exists and is Active
            local lookup_name="$saved_arn"
            [ -n "$CROSS_ACCOUNT" ] && lookup_name="$func_name"
            local func_info
            func_info=$(aws_lambda get-function --function-name "$lookup_name" 2>/dev/null)
            if [ -z "$func_info" ]; then
                lam_fail=$((lam_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Lambda not found: $func_name" >&2
                continue
            fi
            local func_state
            func_state=$(echo "$func_info" | jq -r '.Configuration.State // "Active"' | dos2unix)
            if [ "$func_state" != "Active" ]; then
                lam_fail=$((lam_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Lambda not Active: $func_name (state=$func_state)" >&2
                continue
            fi
            lam_pass=$((lam_pass + 1))

            # 12.4: Connect invoke permission
            local policy
            policy=$(aws_lambda get-policy --function-name "$lookup_name" 2>/dev/null)
            if [ -n "$policy" ]; then
                local has_connect_perm
                has_connect_perm=$(echo "$policy" | jq -r '.Policy' 2>/dev/null | \
                    jq -r '.Statement[] | select(.Principal.Service == "connect.amazonaws.com" or .Principal == "connect.amazonaws.com") | .Effect' 2>/dev/null | head -1)
                if [ "$has_connect_perm" = "Allow" ]; then
                    perm_pass=$((perm_pass + 1))
                else
                    perm_fail=$((perm_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → No Connect invoke permission: $func_name" >&2
                fi
            else
                perm_fail=$((perm_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → No resource policy: $func_name" >&2
            fi
        done < <(jq -r '.FunctionArn // .Arn // .' "$saved_lambda_file" 2>/dev/null | dos2unix)

        if [ "$lam_total" -gt 0 ]; then
            if [ "$lam_fail" -eq 0 ]; then
                pass "12.3" "Lambda functions reachable ($lam_pass/$lam_total)"
            else
                fail "12.3" "Lambda functions" "$lam_fail of $lam_total not reachable"
            fi

            if [ "$perm_fail" -eq 0 ] && [ "$perm_pass" -gt 0 ]; then
                pass "12.4" "Lambda Connect permissions ($perm_pass/$lam_pass)"
            elif [ "$perm_fail" -gt 0 ]; then
                fail "12.4" "Lambda permissions" "$perm_fail missing Connect invoke permission"
            fi
        else
            skip "12.3" "Lambda functions" "no Lambda associations saved"
            skip "12.4" "Lambda permissions" "no Lambda associations saved"
        fi
    else
        skip "12.3" "Lambda functions" "lambda_associations.json not found"
        skip "12.4" "Lambda permissions" "lambda_associations.json not found"
    fi

    layer_end
}
