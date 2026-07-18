validate_preflight() {
    layer_start 0 "Pre-Restore Readiness"

    # 1. Instance reachable
    local live_instance
    live_instance=$(aws_connect describe-instance --instance-id "$instance_id" 2>/dev/null)
    if [ -z "$live_instance" ]; then
        fail "P.1" "Target instance reachable" "Cannot reach instance $instance_id — check credentials and instance ID"
        layer_end; return
    fi
    local live_status live_alias
    live_status=$(echo "$live_instance" | jq -r '.Instance.InstanceStatus' | dos2unix)
    live_alias=$(echo "$live_instance" | jq -r '.Instance.InstanceAlias // "(no alias)"' | dos2unix)
    if [ "$live_status" = "ACTIVE" ]; then
        pass "P.1" "Target instance reachable: $live_alias (ACTIVE)"
    else
        fail "P.1" "Target instance" "status=$live_status (expected ACTIVE)"
        layer_end; return
    fi

    # 2. Credentials have write access (test with a benign describe call)
    local can_list
    can_list=$(aws_connect list-hours-of-operations --instance-id "$instance_id" --max-items 1 2>/dev/null)
    if [ -n "$can_list" ]; then
        pass "P.2" "API access confirmed (list operations working)"
    else
        fail "P.2" "API access" "list-hours-of-operations failed — check IAM permissions"
    fi

    # 3. External dependencies available
    local deps_file="$instance_alias_dir/external_dependencies.json"
    if [ -f "$deps_file" ]; then
        local lambda_count lex_count
        lambda_count=$(jq ".LambdaFunctions | length" "$deps_file" 2>/dev/null || echo 0)
        lex_count=$(jq ".LexV2Bots | length" "$deps_file" 2>/dev/null || echo 0)

        if [ "$lambda_count" -eq 0 ] && [ "$lex_count" -eq 0 ]; then
            pass "P.3" "No external dependencies required"
        else
            local dep_ok=0 dep_missing=0

            # Check Lambdas (use function name, not full ARN — ARN has source account)
            while IFS= read -r arn; do
                [ -z "$arn" ] && continue
                local func_name="${arn##*:function:}"
                func_name="${func_name%%:*}"
                local exists
                exists=$(aws_lambda get-function --function-name "$func_name" 2>/dev/null | jq -r '.Configuration.State // empty')
                if [ "$exists" = "Active" ]; then
                    dep_ok=$((dep_ok + 1))
                else
                    dep_missing=$((dep_missing + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Lambda not found: $func_name" >&2
                fi
            done < <(jq -r '.LambdaFunctions[].Arn' "$deps_file" 2>/dev/null)

            # Check Lex V2 bots (use bot name to search, not source ARN)
            while IFS= read -r bot_entry; do
                [ -z "$bot_entry" ] && continue
                local bot_name
                bot_name=$(echo "$bot_entry" | jq -r '.BotName // empty' 2>/dev/null)
                local bot_id
                bot_id=$(echo "$bot_entry" | jq -r '.BotId // empty' 2>/dev/null)
                [ -z "$bot_name" ] && bot_name="$bot_id"
                # Try by bot ID first (same ID might exist cross-account via import)
                local bot_check
                bot_check=$(aws_lex_v2 describe-bot --bot-id "$bot_id" 2>/dev/null | jq -r '.botStatus // empty')
                if [ "$bot_check" = "Available" ]; then
                    dep_ok=$((dep_ok + 1))
                else
                    # Bot ID won't match cross-account — search by name
                    local found_bot
                    found_bot=$(aws_lex_v2 list-bots 2>/dev/null | \
                        jq -r ".botSummaries[] | select(.botName == \"$bot_name\") | .botStatus" 2>/dev/null | head -1)
                    if [ "$found_bot" = "Available" ]; then
                        dep_ok=$((dep_ok + 1))
                    else
                        dep_missing=$((dep_missing + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Lex V2 bot not found: $bot_name" >&2
                    fi
                fi
            done < <(jq -c '.LexV2Bots[]' "$deps_file" 2>/dev/null)

            local dep_total=$((dep_ok + dep_missing))
            if [ "$dep_missing" -eq 0 ]; then
                pass "P.3" "External dependencies available ($dep_ok/$dep_total)"
            else
                fail "P.3" "External dependencies" "$dep_missing of $dep_total not deployed to target account"
            fi
        fi
    else
        skip "P.3" "External dependencies" "No manifest found (run connect_backup first)"
    fi

    # P.4: Users pre-provisioned on target
    local users_file="$instance_alias_dir/users.json"
    if [ -f "$users_file" ]; then
        local src_user_count
        src_user_count=$(jq -s 'length' "$users_file" 2>/dev/null || echo 0)
        if [ "$src_user_count" -gt 0 ]; then
            # List users on target
            local target_users
            target_users=$(aws_connect list-users --instance-id "$instance_id" --max-items $maxitems 2>/dev/null)
            local users_missing=0 users_found=0
            while IFS=$'\t' read -r uid uname; do
                [ -z "$uname" ] && continue
                local exists
                exists=$(echo "$target_users" | jq -r ".UserSummaryList // [] | .[] | select(.Username == \"$uname\") | .Id" 2>/dev/null | head -1)
                if [ -n "$exists" ]; then
                    users_found=$((users_found + 1))
                else
                    users_missing=$((users_missing + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → User not provisioned: $uname" >&2
                fi
            done < <(jq -r '.Id + "\t" + .Username' "$users_file" | tr -d '\r')

            if [ "$users_missing" -eq 0 ]; then
                pass "P.4" "All users pre-provisioned on target ($users_found/$src_user_count)"
            else
                fail "P.4" "Users not provisioned" "$users_missing of $src_user_count users missing on target. Pre-create via Identity Center or Connect console before restore."
            fi
        else
            skip "P.4" "Users" "none in source backup"
        fi
    else
        skip "P.4" "Users" "users.json not found"
    fi

    # 4. Summary guidance
    if [ -z "$JSON_OUTPUT" ]; then
        echo ""
        if [ "$FAIL" -eq 0 ]; then
            echo "  ✓ Target is ready to receive a restore."
            echo "    Next: connect_backup <target-alias>"
            echo "    Then: connect_plan <source-dir> <target-dir> <helper>"
            echo "    Then: connect_restore <helper>"
        else
            echo "  ✗ Target is NOT ready. Fix the issues above before restoring."
        fi
    fi

    layer_end
}

############################################################
# Layer 0: External Dependencies
############################################################

