validate_layer_17() {
    layer_start 17 "Cross-Reference Integrity"

    # Build a set of all known resource IDs from the saved instance
    local known_ids_file="${TEMPFILE}_known_ids"
    > "$known_ids_file"

    # Collect IDs from manifests
    for manifest in hours queues quickconnects routings agentstatuses securityprofiles; do
        local mfile="$instance_alias_dir/${manifest}.json"
        [ -f "$mfile" ] || continue
        jq -r '.Id // empty' "$mfile" 2>/dev/null >> "$known_ids_file"
    done
    # Collect from modules and flows manifests
    [ -f "$instance_alias_dir/modules.json" ] && \
        jq -r '.Id // empty' "$instance_alias_dir/modules.json" 2>/dev/null >> "$known_ids_file"
    [ -f "$instance_alias_dir/flows.json" ] && \
        jq -r '.Id // empty' "$instance_alias_dir/flows.json" 2>/dev/null >> "$known_ids_file"
    # Prompts
    [ -f "$instance_alias_dir/prompts.json" ] && \
        jq -r '.Id // empty' "$instance_alias_dir/prompts.json" 2>/dev/null >> "$known_ids_file"
    # Users
    [ -f "$instance_alias_dir/users.json" ] && \
        jq -r '.Id // empty' "$instance_alias_dir/users.json" 2>/dev/null >> "$known_ids_file"
    # Hierarchy groups
    [ -f "$instance_alias_dir/hierarchy_groups.json" ] && \
        jq -r '.Id // empty' "$instance_alias_dir/hierarchy_groups.json" 2>/dev/null >> "$known_ids_file"

    local known_count
    known_count=$(wc -l < "$known_ids_file" | tr -d ' ')

    # --- 17.1-17.6: Flow references resolve ---
    local ref_queue_pass=0 ref_queue_fail=0
    local ref_prompt_pass=0 ref_prompt_fail=0
    local ref_flow_pass=0 ref_flow_fail=0 ref_flow_warn=0
    local ref_module_pass=0 ref_module_fail=0
    local ref_lambda_pass=0 ref_lambda_fail=0
    local ref_lex_pass=0 ref_lex_fail=0
    local unresolved_details=""

    for ffile in "$instance_alias_dir"/flow_*.json "$instance_alias_dir"/module_*.json; do
        [ -f "$ffile" ] || continue
        local fname
        fname=$(basename "$ffile")

        # Extract all ARN references from the flow
        while IFS= read -r arn; do
            [ -z "$arn" ] && continue

            if [[ "$arn" == *"/queue/"* ]]; then
                local qid="${arn##*/queue/}"
                if grep -qF "$qid" "$known_ids_file" 2>/dev/null; then
                    ref_queue_pass=$((ref_queue_pass + 1))
                else
                    ref_queue_fail=$((ref_queue_fail + 1))
                    unresolved_details="$unresolved_details\n         → Queue ref in $fname: $qid"
                fi
            elif [[ "$arn" == *"/prompt/"* ]]; then
                local pid="${arn##*/prompt/}"
                if grep -qF "$pid" "$known_ids_file" 2>/dev/null; then
                    ref_prompt_pass=$((ref_prompt_pass + 1))
                else
                    ref_prompt_fail=$((ref_prompt_fail + 1))
                    unresolved_details="$unresolved_details\n         → Prompt ref in $fname: $pid"
                fi
            elif [[ "$arn" == *"/contact-flow/"* ]]; then
                local cfid="${arn##*/contact-flow/}"
                if grep -qF "$cfid" "$known_ids_file" 2>/dev/null; then
                    ref_flow_pass=$((ref_flow_pass + 1))
                else
                    # In live mode, check if the flow exists on the instance at all
                    # If it doesn't, this is a pre-existing dead reference (not a DR risk)
                    if [ -n "$do_live" ]; then
                        local cf_check
                        cf_check=$(aws_connect describe-contact-flow \
                            --instance-id "$instance_id" \
                            --contact-flow-id "$cfid" 2>/dev/null)
                        if [ -z "$cf_check" ]; then
                            ref_flow_warn=$((ref_flow_warn + 1))
                            unresolved_details="$unresolved_details\n         → Dead flow ref in $fname: $cfid (does not exist on instance)"
                        else
                            ref_flow_pass=$((ref_flow_pass + 1))
                        fi
                    else
                        ref_flow_fail=$((ref_flow_fail + 1))
                        unresolved_details="$unresolved_details\n         → Flow ref in $fname: $cfid"
                    fi
                fi
            elif [[ "$arn" == *"/flow-module/"* ]] || [[ "$arn" == *"/module/"* ]]; then
                local mid="${arn##*/}"
                if grep -qF "$mid" "$known_ids_file" 2>/dev/null; then
                    ref_module_pass=$((ref_module_pass + 1))
                else
                    ref_module_fail=$((ref_module_fail + 1))
                fi
            elif [[ "$arn" == *":function:"* ]]; then
                ref_lambda_pass=$((ref_lambda_pass + 1))
                # Lambda validation is in Layer 0; just count here
            elif [[ "$arn" == *":lex:"* ]] || [[ "$arn" == *"bot-alias"* ]]; then
                ref_lex_pass=$((ref_lex_pass + 1))
            fi
        done < <(jq -r '.. | strings | select(test("arn:aws:"))' "$ffile" 2>/dev/null | sort -u)
    done

    # Report cross-reference results
    local total_queue=$((ref_queue_pass + ref_queue_fail))
    if [ "$total_queue" -gt 0 ]; then
        if [ "$ref_queue_fail" -eq 0 ]; then
            pass "17.1" "Flow → queue references ($ref_queue_pass/$total_queue)"
        else
            fail "17.1" "Flow → queue references" "$ref_queue_fail of $total_queue unresolved"
        fi
    fi

    local total_prompt=$((ref_prompt_pass + ref_prompt_fail))
    if [ "$total_prompt" -gt 0 ]; then
        if [ "$ref_prompt_fail" -eq 0 ]; then
            pass "17.2" "Flow → prompt references ($ref_prompt_pass/$total_prompt)"
        else
            fail "17.2" "Flow → prompt references" "$ref_prompt_fail of $total_prompt unresolved"
        fi
    fi

    local total_flow_ref=$((ref_flow_pass + ref_flow_fail + ref_flow_warn))
    if [ "$total_flow_ref" -gt 0 ]; then
        if [ "$ref_flow_fail" -eq 0 ] && [ "$ref_flow_warn" -eq 0 ]; then
            pass "17.3" "Flow → flow references ($ref_flow_pass/$total_flow_ref)"
        elif [ "$ref_flow_fail" -eq 0 ] && [ "$ref_flow_warn" -gt 0 ]; then
            warn "17.3" "Flow → flow references" "$ref_flow_warn pre-existing dead reference(s) on instance"
            [ -z "$JSON_OUTPUT" ] && echo -e "  ${C_SKIP}       (not caused by restore — clean up in flow designer if desired)${C_RESET}"
        else
            fail "17.3" "Flow → flow references" "$ref_flow_fail of $total_flow_ref unresolved"
        fi
    fi

    local total_module_ref=$((ref_module_pass + ref_module_fail))
    if [ "$total_module_ref" -gt 0 ]; then
        if [ "$ref_module_fail" -eq 0 ]; then
            pass "17.4" "Flow → module references ($ref_module_pass/$total_module_ref)"
        else
            fail "17.4" "Flow → module references" "$ref_module_fail of $total_module_ref unresolved"
        fi
    fi

    if [ "$ref_lambda_pass" -gt 0 ]; then
        pass "17.5" "Flow → Lambda references ($ref_lambda_pass found, validated in Layer 0)"
    fi

    if [ "$ref_lex_pass" -gt 0 ]; then
        pass "17.6" "Flow → Lex references ($ref_lex_pass found, validated in Layer 0)"
    fi

    # Print unresolved details if any failures
    if [ -n "$unresolved_details" ] && [ -z "$JSON_OUTPUT" ]; then
        echo -e "$unresolved_details" >&2
    fi

    # --- 17.7: Routing profile → queue references ---
    local rp_queue_pass=0 rp_queue_fail=0
    for rqs_file in "$instance_alias_dir"/routingQs_*.json; do
        [ -f "$rqs_file" ] || continue
        while IFS= read -r q_id; do
            [ -z "$q_id" ] && continue
            if grep -qF "$q_id" "$known_ids_file" 2>/dev/null; then
                rp_queue_pass=$((rp_queue_pass + 1))
            else
                rp_queue_fail=$((rp_queue_fail + 1))
            fi
        done < <(jq -r '.RoutingProfileQueueConfigSummaryList[]?.QueueId // empty' "$rqs_file" 2>/dev/null)
    done
    local total_rp_q=$((rp_queue_pass + rp_queue_fail))
    if [ "$total_rp_q" -gt 0 ]; then
        if [ "$rp_queue_fail" -eq 0 ]; then
            pass "17.7" "Routing profile → queue references ($rp_queue_pass/$total_rp_q)"
        else
            fail "17.7" "Routing profile → queue" "$rp_queue_fail unresolved"
        fi
    fi

    # --- 17.8: Queue → hours references ---
    local q_hoo_pass=0 q_hoo_fail=0
    for qfile in "$instance_alias_dir"/queue_*.json; do
        [ -f "$qfile" ] || continue
        local hoo_id
        hoo_id=$(jq -r '.Queue.HoursOfOperationId // empty' "$qfile" 2>/dev/null | dos2unix)
        [ -z "$hoo_id" ] && continue
        if grep -qF "$hoo_id" "$known_ids_file" 2>/dev/null; then
            q_hoo_pass=$((q_hoo_pass + 1))
        else
            q_hoo_fail=$((q_hoo_fail + 1))
        fi
    done
    local total_q_hoo=$((q_hoo_pass + q_hoo_fail))
    if [ "$total_q_hoo" -gt 0 ]; then
        if [ "$q_hoo_fail" -eq 0 ]; then
            pass "17.8" "Queue → hours references ($q_hoo_pass/$total_q_hoo)"
        else
            fail "17.8" "Queue → hours" "$q_hoo_fail unresolved"
        fi
    fi

    # --- 17.9-17.11: User → resource references ---
    if [ -f "$instance_alias_dir/users.json" ]; then
        local user_rp_pass=0 user_rp_fail=0
        local user_sp_pass=0 user_sp_fail=0
        local user_hg_pass=0 user_hg_fail=0 user_hg_total=0

        # Also add routing profile IDs to known set (they're already there from routings manifest)
        for ufile in "$instance_alias_dir"/user_*.json; do
            [ -f "$ufile" ] || continue

            # 17.9: User → routing profile
            local u_rp_id
            u_rp_id=$(jq -r '.User.RoutingProfileId // empty' "$ufile" 2>/dev/null | dos2unix)
            if [ -n "$u_rp_id" ]; then
                if grep -qF "$u_rp_id" "$known_ids_file" 2>/dev/null; then
                    user_rp_pass=$((user_rp_pass + 1))
                else
                    user_rp_fail=$((user_rp_fail + 1))
                fi
            fi

            # 17.10: User → security profiles
            while IFS= read -r sp_id; do
                [ -z "$sp_id" ] && continue
                if grep -qF "$sp_id" "$known_ids_file" 2>/dev/null; then
                    user_sp_pass=$((user_sp_pass + 1))
                else
                    user_sp_fail=$((user_sp_fail + 1))
                fi
            done < <(jq -r '.User.SecurityProfileIds[]? // empty' "$ufile" 2>/dev/null | dos2unix)

            # 17.11: User → hierarchy group
            local u_hg_id
            u_hg_id=$(jq -r '.User.HierarchyGroupId // empty' "$ufile" 2>/dev/null | dos2unix)
            if [ -n "$u_hg_id" ] && [ "$u_hg_id" != "null" ]; then
                user_hg_total=$((user_hg_total + 1))
                # Hierarchy group IDs need to be in our known set — add them
                if grep -qF "$u_hg_id" "$known_ids_file" 2>/dev/null; then
                    user_hg_pass=$((user_hg_pass + 1))
                else
                    user_hg_fail=$((user_hg_fail + 1))
                fi
            fi
        done

        local total_user_rp=$((user_rp_pass + user_rp_fail))
        if [ "$total_user_rp" -gt 0 ]; then
            if [ "$user_rp_fail" -eq 0 ]; then
                pass "17.9" "User → routing profile references ($user_rp_pass/$total_user_rp)"
            else
                fail "17.9" "User → routing profile" "$user_rp_fail unresolved"
            fi
        fi

        local total_user_sp=$((user_sp_pass + user_sp_fail))
        if [ "$total_user_sp" -gt 0 ]; then
            if [ "$user_sp_fail" -eq 0 ]; then
                pass "17.10" "User → security profile references ($user_sp_pass/$total_user_sp)"
            else
                fail "17.10" "User → security profile" "$user_sp_fail unresolved"
            fi
        fi

        if [ "$user_hg_total" -gt 0 ]; then
            if [ "$user_hg_fail" -eq 0 ]; then
                pass "17.11" "User → hierarchy group references ($user_hg_pass/$user_hg_total)"
            else
                fail "17.11" "User → hierarchy group" "$user_hg_fail unresolved"
            fi
        fi
    fi

    # --- 17.12: Quick connect → target references ---
    if [ -f "$instance_alias_dir/quickconnects.json" ]; then
        local qc_ref_pass=0 qc_ref_fail=0
        for qcfile in "$instance_alias_dir"/quickconnect_*.json; do
            [ -f "$qcfile" ] || continue
            # Check target references (user/queue/flow IDs in the config)
            local qc_type
            qc_type=$(jq -r '.QuickConnect.QuickConnectConfig.QuickConnectType // empty' "$qcfile" 2>/dev/null | dos2unix)
            case "$qc_type" in
            USER)
                local qc_uid qc_cfid
                qc_uid=$(jq -r '.QuickConnect.QuickConnectConfig.UserConfig.UserId // empty' "$qcfile" 2>/dev/null | dos2unix)
                qc_cfid=$(jq -r '.QuickConnect.QuickConnectConfig.UserConfig.ContactFlowId // empty' "$qcfile" 2>/dev/null | dos2unix)
                local qc_ok=1
                [ -n "$qc_uid" ] && ! grep -qF "$qc_uid" "$known_ids_file" 2>/dev/null && qc_ok=0
                [ -n "$qc_cfid" ] && ! grep -qF "$qc_cfid" "$known_ids_file" 2>/dev/null && qc_ok=0
                [ "$qc_ok" -eq 1 ] && qc_ref_pass=$((qc_ref_pass + 1)) || qc_ref_fail=$((qc_ref_fail + 1))
                ;;
            QUEUE)
                local qc_qid qc_cfid
                qc_qid=$(jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.QueueId // empty' "$qcfile" 2>/dev/null | dos2unix)
                qc_cfid=$(jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.ContactFlowId // empty' "$qcfile" 2>/dev/null | dos2unix)
                local qc_ok=1
                [ -n "$qc_qid" ] && ! grep -qF "$qc_qid" "$known_ids_file" 2>/dev/null && qc_ok=0
                [ -n "$qc_cfid" ] && ! grep -qF "$qc_cfid" "$known_ids_file" 2>/dev/null && qc_ok=0
                [ "$qc_ok" -eq 1 ] && qc_ref_pass=$((qc_ref_pass + 1)) || qc_ref_fail=$((qc_ref_fail + 1))
                ;;
            PHONE_NUMBER)
                # Phone number QCs reference a phone number string, not an ID — always pass
                qc_ref_pass=$((qc_ref_pass + 1))
                ;;
            esac
        done
        local total_qc_ref=$((qc_ref_pass + qc_ref_fail))
        if [ "$total_qc_ref" -gt 0 ]; then
            if [ "$qc_ref_fail" -eq 0 ]; then
                pass "17.12" "Quick connect → target references ($qc_ref_pass/$total_qc_ref)"
            else
                fail "17.12" "Quick connect → target" "$qc_ref_fail unresolved"
            fi
        fi
    fi

    # --- 17.13: Phone → flow references ---
    if [ -f "$instance_alias_dir/phonenumbers.json" ]; then
        if [ -n "$do_live" ]; then
            pass "17.13" "Phone → flow references (validated in Layer 11)"
        else
            # Local: check saved phone number files for flow references
            local pn_flow_pass=0 pn_flow_fail=0 pn_flow_total=0
            for pnfile in "$instance_alias_dir"/phonenumber_*.json; do
                [ -f "$pnfile" ] || continue
                local pn_target
                pn_target=$(jq -r '.TargetArn // .ContactFlowId // empty' "$pnfile" 2>/dev/null | dos2unix)
                [ -z "$pn_target" ] && continue
                [[ "$pn_target" != *"/contact-flow/"* ]] && continue
                pn_flow_total=$((pn_flow_total + 1))
                local pn_cfid="${pn_target##*/contact-flow/}"
                if grep -qF "$pn_cfid" "$known_ids_file" 2>/dev/null; then
                    pn_flow_pass=$((pn_flow_pass + 1))
                else
                    pn_flow_fail=$((pn_flow_fail + 1))
                fi
            done
            if [ "$pn_flow_total" -gt 0 ]; then
                if [ "$pn_flow_fail" -eq 0 ]; then
                    pass "17.13" "Phone → flow references ($pn_flow_pass/$pn_flow_total)"
                else
                    fail "17.13" "Phone → flow" "$pn_flow_fail unresolved"
                fi
            fi
        fi
    fi

    # --- 17.14: Task template → flow references ---
    if [ -f "$instance_alias_dir/tasktemplates.json" ]; then
        local tt_flow_pass=0 tt_flow_fail=0 tt_flow_total=0
        for ttfile in "$instance_alias_dir"/tasktemplate_*.json; do
            [ -f "$ttfile" ] || continue
            local tt_cfid
            tt_cfid=$(jq -r '.ContactFlowId // empty' "$ttfile" 2>/dev/null | dos2unix)
            [ -z "$tt_cfid" ] && continue
            tt_flow_total=$((tt_flow_total + 1))
            if grep -qF "$tt_cfid" "$known_ids_file" 2>/dev/null; then
                tt_flow_pass=$((tt_flow_pass + 1))
            else
                tt_flow_fail=$((tt_flow_fail + 1))
            fi
        done
        if [ "$tt_flow_total" -gt 0 ]; then
            if [ "$tt_flow_fail" -eq 0 ]; then
                pass "17.14" "Task template → flow references ($tt_flow_pass/$tt_flow_total)"
            else
                fail "17.14" "Task template → flow" "$tt_flow_fail unresolved"
            fi
        fi
    fi

    # --- 17.15: Rule → resource references ---
    if [ -f "$instance_alias_dir/rules.json" ]; then
        local rule_ref_pass=0 rule_ref_fail=0 rule_ref_total=0
        for rulefile in "$instance_alias_dir"/rule_*.json; do
            [ -f "$rulefile" ] || continue
            # Check for queue/flow ARN references inside rule actions
            while IFS= read -r arn; do
                [ -z "$arn" ] && continue
                rule_ref_total=$((rule_ref_total + 1))
                local res_id="${arn##*/}"
                if grep -qF "$res_id" "$known_ids_file" 2>/dev/null; then
                    rule_ref_pass=$((rule_ref_pass + 1))
                else
                    rule_ref_fail=$((rule_ref_fail + 1))
                fi
            done < <(jq -r '.. | strings | select(test("arn:aws:connect:.*/(queue|contact-flow)/"))' "$rulefile" 2>/dev/null | sort -u)
        done
        if [ "$rule_ref_total" -gt 0 ]; then
            if [ "$rule_ref_fail" -eq 0 ]; then
                pass "17.15" "Rule → resource references ($rule_ref_pass/$rule_ref_total)"
            else
                fail "17.15" "Rule → resource" "$rule_ref_fail unresolved"
            fi
        fi
    fi

    rm -f "$known_ids_file"
    layer_end
}

############################################################
# Layer 18: Functional Smoke Tests (optional)
############################################################

