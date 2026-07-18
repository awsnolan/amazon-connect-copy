validate_layer_14() {
    layer_start 14 "Supporting Resources"

    # --- 14A: Agent Statuses ---
    if [ -f "$instance_alias_dir/agentstatuses.json" ]; then
        local as_count
        as_count=$(jq -s 'length' "$instance_alias_dir/agentstatuses.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$as_count" -gt 0 ]; then
            local as_pass=0 as_fail=0
            local as_state_pass=0 as_state_fail=0
            while IFS=$'\t' read -r as_id as_name; do
                [ -z "$as_id" ] && continue
                local live_as
                local eff_as_id
                eff_as_id=$(effective_id "$MAP_STATUSES" "$as_id" "$as_name")
                live_as=$(aws_connect describe-agent-status \
                    --instance-id "$instance_id" \
                    --agent-status-id "${eff_as_id:-$as_id}" 2>/dev/null)
                if [ -n "$live_as" ]; then
                    as_pass=$((as_pass + 1))
                    # 14A.2: State correct
                    local as_name_encoded
                    as_name_encoded=$(path_encode "$as_name")
                    local saved_state live_state
                    saved_state=$(jq -r '.AgentStatus.State // empty' "$instance_alias_dir/agentstatus_$as_name_encoded.json" 2>/dev/null | dos2unix)
                    live_state=$(echo "$live_as" | jq -r '.AgentStatus.State // empty' | dos2unix)
                    if [ -z "$saved_state" ] || [ "$saved_state" = "$live_state" ]; then
                        as_state_pass=$((as_state_pass + 1))
                    else
                        as_state_fail=$((as_state_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → State mismatch: $as_name (saved=$saved_state live=$live_state)" >&2
                    fi
                else
                    as_fail=$((as_fail + 1))
                fi
            done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/agentstatuses.json" 2>/dev/null | dos2unix)
            if [ "$as_fail" -eq 0 ]; then
                pass "14A.1" "Agent statuses exist ($as_pass/$as_count)"
            else
                fail "14A.1" "Agent statuses" "$as_fail of $as_count missing"
            fi
            if [ "$as_state_fail" -eq 0 ] && [ "$as_state_pass" -gt 0 ]; then
                pass "14A.2" "Agent status states correct ($as_state_pass/$as_pass)"
            elif [ "$as_state_fail" -gt 0 ]; then
                fail "14A.2" "Agent status states" "$as_state_fail mismatched"
            fi
        else
            [ -n "$do_local" ] && pass "14A.1" "Agent statuses manifest ($as_count)"
        fi
    else
        skip "14A.1" "Agent statuses" "agentstatuses.json not found"
    fi

    # --- 14B: Predefined Attributes ---
    if [ -f "$instance_alias_dir/predefinedattributes.json" ]; then
        local pa_count
        pa_count=$(jq -s 'length' "$instance_alias_dir/predefinedattributes.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$pa_count" -gt 0 ]; then
            local pa_pass=0 pa_fail=0
            local pa_val_pass=0 pa_val_fail=0
            while IFS= read -r pa_name; do
                [ -z "$pa_name" ] && continue
                local live_pa
                live_pa=$(aws_connect describe-predefined-attribute \
                    --instance-id "$instance_id" --name "$pa_name" 2>/dev/null)
                if [ -n "$live_pa" ]; then
                    pa_pass=$((pa_pass + 1))
                    # 14B.2: Values match
                    local pa_name_encoded
                    pa_name_encoded=$(path_encode "$pa_name")
                    local saved_vals live_vals
                    saved_vals=$(jq -S '.Values.StringList // [] | sort' \
                        "$instance_alias_dir/predefinedattribute_$pa_name_encoded.json" 2>/dev/null)
                    live_vals=$(echo "$live_pa" | jq -S '.PredefinedAttribute.Values.StringList // [] | sort' 2>/dev/null)
                    if [ "$saved_vals" = "$live_vals" ]; then
                        pa_val_pass=$((pa_val_pass + 1))
                    else
                        pa_val_fail=$((pa_val_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Values mismatch: $pa_name" >&2
                    fi
                else
                    pa_fail=$((pa_fail + 1))
                fi
            done < <(jq -r '.Name' "$instance_alias_dir/predefinedattributes.json" 2>/dev/null | dos2unix)
            if [ "$pa_fail" -eq 0 ]; then
                pass "14B.1" "Predefined attributes exist ($pa_pass/$pa_count)"
            else
                fail "14B.1" "Predefined attributes" "$pa_fail of $pa_count missing"
            fi
            if [ "$pa_val_fail" -eq 0 ] && [ "$pa_val_pass" -gt 0 ]; then
                pass "14B.2" "Predefined attribute values match ($pa_val_pass/$pa_pass)"
            elif [ "$pa_val_fail" -gt 0 ]; then
                fail "14B.2" "Predefined attribute values" "$pa_val_fail mismatched"
            fi
        else
            [ -n "$do_local" ] && pass "14B.1" "Predefined attributes manifest ($pa_count)"
        fi
    else
        skip "14B.1" "Predefined attributes" "not found"
    fi

    # --- 14C: Task Templates ---
    if [ -f "$instance_alias_dir/tasktemplates.json" ]; then
        local tt_count
        tt_count=$(jq -s 'length' "$instance_alias_dir/tasktemplates.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$tt_count" -gt 0 ]; then
            local tt_pass=0 tt_fail=0
            local tt_status_pass=0 tt_status_fail=0
            while IFS=$'\t' read -r tt_id tt_name; do
                [ -z "$tt_id" ] && continue
                local live_tt
                live_tt=$(aws_connect get-task-template \
                    --instance-id "$instance_id" --task-template-id "$tt_id" 2>/dev/null)
                if [ -n "$live_tt" ]; then
                    tt_pass=$((tt_pass + 1))
                    # 14C.2: Status ACTIVE
                    local live_tt_status
                    live_tt_status=$(echo "$live_tt" | jq -r '.Status // empty' | dos2unix)
                    if [ "$live_tt_status" = "ACTIVE" ]; then
                        tt_status_pass=$((tt_status_pass + 1))
                    else
                        tt_status_fail=$((tt_status_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Not ACTIVE: $tt_name (status=$live_tt_status)" >&2
                    fi
                else
                    tt_fail=$((tt_fail + 1))
                fi
            done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/tasktemplates.json" 2>/dev/null | dos2unix)
            if [ "$tt_fail" -eq 0 ]; then
                pass "14C.1" "Task templates exist ($tt_pass/$tt_count)"
            else
                fail "14C.1" "Task templates" "$tt_fail of $tt_count missing"
            fi
            if [ "$tt_status_fail" -eq 0 ] && [ "$tt_status_pass" -gt 0 ]; then
                pass "14C.2" "Task templates ACTIVE ($tt_status_pass/$tt_pass)"
            elif [ "$tt_status_fail" -gt 0 ]; then
                fail "14C.2" "Task template status" "$tt_status_fail not ACTIVE"
            fi
        else
            [ -n "$do_local" ] && pass "14C.1" "Task templates manifest ($tt_count)"
        fi
    else
        skip "14C.1" "Task templates" "not found"
    fi

    # --- 14D: Evaluation Forms ---
    if [ -f "$instance_alias_dir/evaluationforms.json" ]; then
        local ef_count
        ef_count=$(jq -s 'length' "$instance_alias_dir/evaluationforms.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$ef_count" -gt 0 ]; then
            local ef_pass=0 ef_fail=0
            local ef_status_pass=0 ef_status_fail=0
            while IFS=$'\t' read -r ef_id ef_title; do
                [ -z "$ef_id" ] && continue
                local live_ef
                live_ef=$(aws_connect describe-evaluation-form \
                    --instance-id "$instance_id" --evaluation-form-id "$ef_id" 2>/dev/null)
                if [ -n "$live_ef" ]; then
                    ef_pass=$((ef_pass + 1))
                    # 14D.2: Status ACTIVE
                    local live_ef_status
                    live_ef_status=$(echo "$live_ef" | jq -r '.EvaluationForm.Status // empty' | dos2unix)
                    if [ "$live_ef_status" = "ACTIVE" ]; then
                        ef_status_pass=$((ef_status_pass + 1))
                    else
                        ef_status_fail=$((ef_status_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Not ACTIVE: $ef_title (status=$live_ef_status)" >&2
                    fi
                else
                    ef_fail=$((ef_fail + 1))
                fi
            done < <(jq -r '.EvaluationFormId + "\t" + .Title' "$instance_alias_dir/evaluationforms.json" 2>/dev/null | dos2unix)
            if [ "$ef_fail" -eq 0 ]; then
                pass "14D.1" "Evaluation forms exist ($ef_pass/$ef_count)"
            else
                fail "14D.1" "Evaluation forms" "$ef_fail of $ef_count missing"
            fi
            if [ "$ef_status_fail" -eq 0 ] && [ "$ef_status_pass" -gt 0 ]; then
                pass "14D.2" "Evaluation forms ACTIVE ($ef_status_pass/$ef_pass)"
            elif [ "$ef_status_fail" -gt 0 ]; then
                fail "14D.2" "Evaluation form status" "$ef_status_fail not ACTIVE"
            fi
        else
            [ -n "$do_local" ] && pass "14D.1" "Evaluation forms manifest ($ef_count)"
        fi
    else
        skip "14D.1" "Evaluation forms" "not found"
    fi

    # --- 14E: Rules ---
    if [ -f "$instance_alias_dir/rules.json" ]; then
        local rule_count
        rule_count=$(jq -s 'length' "$instance_alias_dir/rules.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$rule_count" -gt 0 ]; then
            local rule_pass=0 rule_fail=0
            local rule_pub_pass=0 rule_pub_fail=0
            while IFS=$'\t' read -r rule_id rule_name; do
                [ -z "$rule_id" ] && continue
                local live_rule
                live_rule=$(aws_connect describe-rule \
                    --instance-id "$instance_id" --rule-id "$rule_id" 2>/dev/null)
                if [ -n "$live_rule" ]; then
                    rule_pass=$((rule_pass + 1))
                    # 14E.2: Publish status
                    local live_pub_status
                    live_pub_status=$(echo "$live_rule" | jq -r '.Rule.PublishStatus // empty' | dos2unix)
                    if [ "$live_pub_status" = "PUBLISHED" ]; then
                        rule_pub_pass=$((rule_pub_pass + 1))
                    else
                        rule_pub_fail=$((rule_pub_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Not PUBLISHED: $rule_name (status=$live_pub_status)" >&2
                    fi
                else
                    rule_fail=$((rule_fail + 1))
                fi
            done < <(jq -r '.RuleId + "\t" + .Name' "$instance_alias_dir/rules.json" 2>/dev/null | dos2unix)
            if [ "$rule_fail" -eq 0 ]; then
                pass "14E.1" "Rules exist ($rule_pass/$rule_count)"
            else
                fail "14E.1" "Rules" "$rule_fail of $rule_count missing"
            fi
            if [ "$rule_pub_fail" -eq 0 ] && [ "$rule_pub_pass" -gt 0 ]; then
                pass "14E.2" "Rules PUBLISHED ($rule_pub_pass/$rule_pass)"
            elif [ "$rule_pub_fail" -gt 0 ]; then
                fail "14E.2" "Rule publish status" "$rule_pub_fail not PUBLISHED"
            fi
        else
            [ -n "$do_local" ] && pass "14E.1" "Rules manifest ($rule_count)"
        fi
    else
        skip "14E.1" "Rules" "not found"
    fi

    # --- 14F: Views ---
    if [ -f "$instance_alias_dir/views.json" ]; then
        local view_count=0
        while IFS=$'\t' read -r view_id view_name; do
            [ -z "$view_id" ] && continue
            local has_detail=0
            for vf in "$instance_alias_dir"/view_*.json; do
                [ -f "$vf" ] || continue
                local vf_id=$(jq -r '.View.Id // empty' "$vf" 2>/dev/null | dos2unix)
                if [ "$vf_id" = "$view_id" ]; then
                    has_detail=1
                    break
                fi
            done
            [ "$has_detail" -eq 1 ] && view_count=$((view_count + 1))
        done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/views.json" 2>/dev/null | dos2unix)

        if [ -n "$do_live" ] && [ "$view_count" -gt 0 ]; then
            local view_pass=0 view_fail=0
            local view_status_pass=0 view_status_fail=0
            for vf in "$instance_alias_dir"/view_*.json; do
                [ -f "$vf" ] || continue
                local vf_id=$(jq -r '.View.Id // empty' "$vf" 2>/dev/null | dos2unix)
                [ -z "$vf_id" ] && continue
                local vf_name=$(jq -r '.View.Name // empty' "$vf" 2>/dev/null | dos2unix)
                local live_view
                local eff_view_id
                eff_view_id=$(effective_id "$MAP_VIEWS" "$vf_id" "$vf_name")
                live_view=$(aws_connect describe-view \
                    --instance-id "$instance_id" --view-id "${eff_view_id:-$vf_id}" 2>/dev/null)
                if [ -n "$live_view" ]; then
                    view_pass=$((view_pass + 1))
                    # 14F.2: Status PUBLISHED
                    local live_view_status
                    live_view_status=$(echo "$live_view" | jq -r '.View.Status // empty' | dos2unix)
                    if [ "$live_view_status" = "PUBLISHED" ] || [ "$live_view_status" = "SAVED" ]; then
                        view_status_pass=$((view_status_pass + 1))
                    else
                        view_status_fail=$((view_status_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → View not PUBLISHED: $vf_name (status=$live_view_status)" >&2
                    fi
                else
                    view_fail=$((view_fail + 1))
                fi
            done
            if [ "$view_fail" -eq 0 ]; then
                pass "14F.1" "Views exist ($view_pass/$view_count)"
            else
                fail "14F.1" "Views" "$view_fail of $view_count missing"
            fi
            if [ "$view_status_fail" -eq 0 ] && [ "$view_status_pass" -gt 0 ]; then
                pass "14F.2" "Views PUBLISHED ($view_status_pass/$view_pass)"
            elif [ "$view_status_fail" -gt 0 ]; then
                fail "14F.2" "View status" "$view_status_fail not PUBLISHED"
            fi
        elif [ "$view_count" -gt 0 ]; then
            [ -n "$do_local" ] && pass "14F.1" "Views ($view_count custom views backed up)"
        else
            skip "14F.1" "Views" "only AWS-managed views (not backed up)"
        fi
    else
        skip "14F.1" "Views" "not found"
    fi

    # --- 14G: Vocabularies ---
    if [ -f "$instance_alias_dir/vocabularies.json" ]; then
        local vocab_count
        vocab_count=$(jq -s 'length' "$instance_alias_dir/vocabularies.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$vocab_count" -gt 0 ]; then
            local vocab_pass=0 vocab_fail=0
            local vocab_state_pass=0 vocab_state_fail=0
            while IFS=$'\t' read -r vocab_id vocab_name; do
                [ -z "$vocab_id" ] && continue
                local live_vocab
                live_vocab=$(aws_connect describe-vocabulary \
                    --instance-id "$instance_id" --vocabulary-id "$vocab_id" 2>/dev/null)
                if [ -n "$live_vocab" ]; then
                    vocab_pass=$((vocab_pass + 1))
                    # 14G.2: State ACTIVE
                    local live_vocab_state
                    live_vocab_state=$(echo "$live_vocab" | jq -r '.Vocabulary.State // empty' | dos2unix)
                    if [ "$live_vocab_state" = "ACTIVE" ]; then
                        vocab_state_pass=$((vocab_state_pass + 1))
                    else
                        vocab_state_fail=$((vocab_state_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Not ACTIVE: $vocab_name (state=$live_vocab_state)" >&2
                    fi
                else
                    vocab_fail=$((vocab_fail + 1))
                fi
            done < <(jq -r '.VocabularyId + "\t" + .VocabularyName' "$instance_alias_dir/vocabularies.json" 2>/dev/null | dos2unix)
            if [ "$vocab_fail" -eq 0 ]; then
                pass "14G.1" "Vocabularies exist ($vocab_pass/$vocab_count)"
            else
                fail "14G.1" "Vocabularies" "$vocab_fail of $vocab_count missing"
            fi
            if [ "$vocab_state_fail" -eq 0 ] && [ "$vocab_state_pass" -gt 0 ]; then
                pass "14G.2" "Vocabularies ACTIVE ($vocab_state_pass/$vocab_pass)"
            elif [ "$vocab_state_fail" -gt 0 ]; then
                fail "14G.2" "Vocabulary state" "$vocab_state_fail not ACTIVE"
            fi
        else
            [ -n "$do_local" ] && pass "14G.1" "Vocabularies manifest ($vocab_count)"
        fi
    else
        skip "14G.1" "Vocabularies" "not found"
    fi

    # --- 14H: Data Tables ---
    if [ -f "$instance_alias_dir/datatables.json" ]; then
        local dt_count
        dt_count=$(jq -s 'length' "$instance_alias_dir/datatables.json" 2>/dev/null)
        if [ -n "$do_live" ] && [ "$dt_count" -gt 0 ]; then
            local dt_pass=0 dt_fail=0
            while IFS=$'\t' read -r dt_id dt_name; do
                [ -z "$dt_id" ] && continue
                local live_dt
                live_dt=$(aws_connect describe-data-table \
                    --instance-id "$instance_id" --table-id "$dt_id" 2>/dev/null)
                if [ -n "$live_dt" ]; then
                    dt_pass=$((dt_pass + 1))
                else
                    dt_fail=$((dt_fail + 1))
                fi
            done < <(jq -r '.TableId + "\t" + .TableName' "$instance_alias_dir/datatables.json" 2>/dev/null | dos2unix)
            if [ "$dt_fail" -eq 0 ]; then
                pass "14H.1" "Data tables exist ($dt_pass/$dt_count)"
            else
                fail "14H.1" "Data tables" "$dt_fail of $dt_count missing"
            fi
        else
            [ -n "$do_local" ] && pass "14H.1" "Data tables manifest ($dt_count)"
        fi
    else
        skip "14H.1" "Data tables" "not found"
    fi

    layer_end
}
