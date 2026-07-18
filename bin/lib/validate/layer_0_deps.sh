validate_layer_0() {
    layer_start 0 "External Dependencies"

    local deps_file="$instance_alias_dir/external_dependencies.json"
    if [ ! -f "$deps_file" ]; then
        skip "0.1" "Lambda functions" "external_dependencies.json not found"
        skip "0.8" "Lex V2 bots" "external_dependencies.json not found"
        skip "0.11" "Lex Classic bots" "external_dependencies.json not found"
        layer_end
        return
    fi

    # --- Lambda functions ---
    local lambda_count
    lambda_count=$(jq ".LambdaFunctions | length" "$deps_file" 2>/dev/null)
    if [ -z "$lambda_count" ] || [ "$lambda_count" -eq 0 ]; then
        skip "0.1" "Lambda functions" "none referenced"
    else
        local lambda_pass=0 lambda_fail=0
        local lambda_perm_pass=0 lambda_perm_fail=0

        while IFS= read -r arn; do
            [ -z "$arn" ] && continue
            local func_name="${arn##*:function:}"
            func_name="${func_name%%:*}"

            # 0.1 + 0.2: Existence and state
            local func_info
            # Cross-account: look up by function name, not source ARN
            local lookup_name="$arn"
            [ -n "$CROSS_ACCOUNT" ] && lookup_name="$func_name"
            func_info=$(aws_lambda get-function --function-name "$lookup_name" 2>/dev/null)
            if [ -z "$func_info" ]; then
                lambda_fail=$((lambda_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $func_name ($arn)" >&2
                continue
            fi
            local state
            state=$(echo "$func_info" | jq -r '.Configuration.State // "Active"' | dos2unix)
            if [ "$state" != "Active" ]; then
                lambda_fail=$((lambda_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Not Active: $func_name (state=$state)" >&2
                continue
            fi

            # 0.3: Runtime matches
            local saved_runtime live_runtime
            saved_runtime=$(jq -r ".LambdaFunctions[] | select(.Arn == \"$arn\") | .Runtime" "$deps_file" | dos2unix)
            live_runtime=$(echo "$func_info" | jq -r '.Configuration.Runtime // ""' | dos2unix)
            if [ -n "$saved_runtime" ] && [ "$saved_runtime" != "null" ] && [ "$saved_runtime" != "$live_runtime" ]; then
                [ -z "$JSON_OUTPUT" ] && echo "         → Runtime mismatch: $func_name (saved=$saved_runtime live=$live_runtime)" >&2
                # This is a warning, not a hard fail — function may still work
            fi

            # 0.4: Code hash matches
            local saved_hash live_hash
            saved_hash=$(jq -r ".LambdaFunctions[] | select(.Arn == \"$arn\") | .CodeSha256 // empty" "$deps_file" | dos2unix)
            live_hash=$(echo "$func_info" | jq -r '.Configuration.CodeSha256 // ""' | dos2unix)
            if [ -n "$saved_hash" ] && [ "$saved_hash" != "$live_hash" ]; then
                [ -z "$JSON_OUTPUT" ] && echo "         → Code hash mismatch: $func_name" >&2
                # Warning — code may have been updated intentionally
            fi

            # 0.5: Connect invoke permission
            local policy
            policy=$(aws_lambda get-policy --function-name "$lookup_name" 2>/dev/null)
            if [ -n "$policy" ]; then
                local has_connect_perm
                # Policy is a JSON string field; parse and check for connect.amazonaws.com principal
                has_connect_perm=$(echo "$policy" | jq -r '.Policy' 2>/dev/null | \
                    jq -r '.Statement[] | select(.Principal.Service == "connect.amazonaws.com" or .Principal == "connect.amazonaws.com") | .Effect' 2>/dev/null | head -1)
                if [ "$has_connect_perm" = "Allow" ]; then
                    lambda_perm_pass=$((lambda_perm_pass + 1))
                else
                    lambda_perm_fail=$((lambda_perm_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → No Connect invoke permission: $func_name" >&2
                fi
            else
                lambda_perm_fail=$((lambda_perm_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → No resource policy: $func_name" >&2
            fi

            # 0.7: Timeout adequate
            local saved_timeout live_timeout
            saved_timeout=$(jq -r ".LambdaFunctions[] | select(.Arn == \"$arn\") | .Timeout // 0" "$deps_file" | dos2unix)
            live_timeout=$(echo "$func_info" | jq -r '.Configuration.Timeout // 0' | dos2unix)
            if [ "$saved_timeout" != "null" ] && [ "$saved_timeout" -gt 0 ] && [ "$live_timeout" -lt "$saved_timeout" ]; then
                [ -z "$JSON_OUTPUT" ] && echo "         → Timeout reduced: $func_name (saved=${saved_timeout}s live=${live_timeout}s)" >&2
            fi

            lambda_pass=$((lambda_pass + 1))
        done < <(jq -r '.LambdaFunctions[].Arn' "$deps_file" 2>/dev/null)

        # Report Lambda results
        if [ "$lambda_fail" -eq 0 ]; then
            pass "0.1" "All Lambda functions exist and Active ($lambda_pass/$lambda_count)"
        else
            fail "0.1" "Lambda functions" "$lambda_fail of $lambda_count missing or not Active"
        fi

        if [ "$lambda_perm_fail" -eq 0 ] && [ "$lambda_perm_pass" -gt 0 ]; then
            pass "0.5" "Lambda Connect permissions ($lambda_perm_pass/$lambda_pass)"
        elif [ "$lambda_perm_fail" -gt 0 ]; then
            fail "0.5" "Lambda Connect permissions" "$lambda_perm_fail functions missing invoke permission"
        fi
    fi

    # --- Lex V2 bots ---
    local lex_v2_count
    lex_v2_count=$(jq ".LexV2Bots | length" "$deps_file" 2>/dev/null)
    if [ -z "$lex_v2_count" ] || [ "$lex_v2_count" -eq 0 ]; then
        skip "0.8" "Lex V2 bots" "none referenced"
    else
        local lex_pass=0 lex_fail=0
        while IFS= read -r arn; do
            [ -z "$arn" ] && continue
            local bot_id alias_id bot_name
            bot_id=$(echo "$arn" | sed 's|.*bot-alias/\([^/]*\)/.*|\1|')
            alias_id=$(echo "$arn" | sed 's|.*bot-alias/[^/]*/\(.*\)|\1|')
            bot_name=$(jq -r ".LexV2Bots[] | select(.Arn == \"$arn\") | .BotName // \"$bot_id\"" "$deps_file" | dos2unix)

            # 0.8 + 0.9: Existence and status
            local bot_info
            bot_info=$(aws_lex_v2 describe-bot --bot-id "$bot_id" 2>/dev/null)
            # Cross-account: bot ID differs, search by name
            if [ -z "$bot_info" ] && [ -n "$CROSS_ACCOUNT" ]; then
                local target_bot_id
                target_bot_id=$(aws_lex_v2 list-bots 2>/dev/null | \
                    jq -r ".botSummaries[] | select(.botName == \"$bot_name\") | .botId" 2>/dev/null | head -1)
                [ -n "$target_bot_id" ] && bot_info=$(aws_lex_v2 describe-bot --bot-id "$target_bot_id" 2>/dev/null)
            fi
            if [ -z "$bot_info" ]; then
                lex_fail=$((lex_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $bot_name (bot_id=$bot_id)" >&2
                continue
            fi
            local bot_status
            bot_status=$(echo "$bot_info" | jq -r '.botStatus // ""' | dos2unix)
            if [ "$bot_status" != "Available" ]; then
                lex_fail=$((lex_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Not Available: $bot_name (status=$bot_status)" >&2
                continue
            fi

            # 0.10: Alias accessible
            local alias_info
            local check_bot_id="$bot_id"
            # Cross-account: use the target bot ID if we resolved one
            if [ -n "$CROSS_ACCOUNT" ]; then
                local resolved_bot_id
                resolved_bot_id=$(echo "$bot_info" | jq -r '.botId // empty' | tr -d '\r')
                [ -n "$resolved_bot_id" ] && check_bot_id="$resolved_bot_id"
            fi
            # Try source alias ID first, then search by alias name
            alias_info=$(aws_lex_v2 describe-bot-alias --bot-id "$check_bot_id" --bot-alias-id "$alias_id" 2>/dev/null)
            if [ -z "$alias_info" ] && [ -n "$CROSS_ACCOUNT" ]; then
                # Source alias ID doesn't exist — find alias by name
                local src_alias_name
                src_alias_name=$(jq -r ".LexV2Bots[] | select(.Arn == \"$arn\") | .AliasName // empty" "$deps_file" | tr -d '\r')
                if [ -n "$src_alias_name" ]; then
                    local target_alias_id
                    target_alias_id=$(aws_lex_v2 list-bot-aliases --bot-id "$check_bot_id" 2>/dev/null | \
                        jq -r ".botAliasSummaries[] | select(.botAliasName == \"$src_alias_name\") | .botAliasId" 2>/dev/null | head -1)
                    [ -n "$target_alias_id" ] && \
                        alias_info=$(aws_lex_v2 describe-bot-alias --bot-id "$check_bot_id" --bot-alias-id "$target_alias_id" 2>/dev/null)
                fi
            fi
            if [ -z "$alias_info" ]; then
                lex_fail=$((lex_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Alias missing: $bot_name alias=$alias_id" >&2
                continue
            fi

            lex_pass=$((lex_pass + 1))
        done < <(jq -r '.LexV2Bots[].Arn' "$deps_file" 2>/dev/null)

        if [ "$lex_fail" -eq 0 ]; then
            pass "0.8" "All Lex V2 bots Available ($lex_pass/$lex_v2_count)"
        else
            fail "0.8" "Lex V2 bots" "$lex_fail of $lex_v2_count missing or not Available"
        fi
    fi

    # --- Lex Classic bots ---
    local lex_classic_count
    lex_classic_count=$(jq ".LexClassicBots | length" "$deps_file" 2>/dev/null)
    if [ -z "$lex_classic_count" ] || [ "$lex_classic_count" -eq 0 ]; then
        skip "0.11" "Lex Classic bots" "none referenced"
    else
        local lc_pass=0 lc_fail=0
        while IFS= read -r bot_name; do
            [ -z "$bot_name" ] && continue
            local bot_info
            bot_info=$(aws_lex_classic get-bot --name "$bot_name" --version-or-alias '$LATEST' 2>/dev/null)
            if [ -z "$bot_info" ]; then
                lc_fail=$((lc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $bot_name" >&2
                continue
            fi
            local bot_status
            bot_status=$(echo "$bot_info" | jq -r '.status // ""' | dos2unix)
            if [ "$bot_status" != "READY" ] && [ "$bot_status" != "NOT_BUILT" ]; then
                lc_fail=$((lc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Not READY: $bot_name (status=$bot_status)" >&2
                continue
            fi
            lc_pass=$((lc_pass + 1))
        done < <(jq -r '.LexClassicBots[].Name' "$deps_file" 2>/dev/null)

        if [ "$lc_fail" -eq 0 ]; then
            pass "0.11" "All Lex Classic bots READY ($lc_pass/$lex_classic_count)"
        else
            fail "0.11" "Lex Classic bots" "$lc_fail of $lex_classic_count missing or not READY"
        fi
    fi

    # --- Prompts ---
    local prompts_file="$instance_alias_dir/prompts.json"
    if [ -f "$prompts_file" ]; then
        local saved_prompt_count
        saved_prompt_count=$(jq -s "length" "$prompts_file" 2>/dev/null)
        local live_prompts live_prompt_count
        live_prompts=$(aws_connect list-prompts --instance-id "$instance_id" --max-items $maxitems 2>/dev/null)
        if [ -n "$live_prompts" ]; then
            live_prompt_count=$(echo "$live_prompts" | jq '.PromptSummaryList | length')
            if [ "$live_prompt_count" -ge "$saved_prompt_count" ]; then
                pass "0.13" "All prompts exist (live=$live_prompt_count saved=$saved_prompt_count)"
            else
                fail "0.13" "Prompts" "live=$live_prompt_count < saved=$saved_prompt_count"
            fi

            # Check each saved prompt exists by name
            local missing_prompts=0
            while IFS= read -r pname; do
                [ -z "$pname" ] && continue
                local exists
                exists=$(echo "$live_prompts" | jq -r ".PromptSummaryList[] | select(.Name == \"${pname//\"/\\\"}\") | .Id" | head -1)
                [ -z "$exists" ] && missing_prompts=$((missing_prompts + 1)) && \
                    [ -z "$JSON_OUTPUT" ] && echo "         → Missing prompt: $pname" >&2
            done < <(jq -r '.Name' "$prompts_file" 2>/dev/null | dos2unix)

            if [ "$missing_prompts" -gt 0 ]; then
                fail "0.14" "Prompt name match" "$missing_prompts prompt(s) missing by name"
            else
                pass "0.14" "All prompt names match"
            fi
        else
            fail "0.13" "Prompts" "Could not retrieve live prompts"
        fi
    else
        skip "0.13" "Prompts" "prompts.json not found"
    fi

    layer_end
}

############################################################
# Layer 1: Instance Foundation
############################################################

