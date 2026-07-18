validate_layer_8() {
    layer_start 8 "Quick Connects"

    if [ ! -f "$instance_alias_dir/quickconnects.json" ]; then
        skip "8.1" "Quick connects" "quickconnects.json not found"
        layer_end; return
    fi

    local qc_count
    qc_count=$(jq -s 'length' "$instance_alias_dir/quickconnects.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "8.1" "Quick connects manifest ($qc_count)"
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local type_pass=0 type_fail=0
    local config_pass=0 config_fail=0
    local desc_pass=0 desc_fail=0
    local tag_pass=0 tag_fail=0

    while IFS=$'\t' read -r qc_id qc_name; do
        [ -z "$qc_id" ] && continue

        local live_qc
        # Cross-account: resolve by name
        local eff_qc_id
        eff_qc_id=$(effective_id "$MAP_QC" "$qc_id" "$qc_name")
        live_qc=$(aws_connect describe-quick-connect \
            --instance-id "$instance_id" \
            --quick-connect-id "${eff_qc_id:-$qc_id}" 2>/dev/null)
        if [ -z "$live_qc" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $qc_name ($qc_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # 8.2: Type matches
        local saved_file=""
        for qcf in "$instance_alias_dir"/quickconnect_*.json; do
            [ -f "$qcf" ] || continue
            local fid
            fid=$(jq -r '.QuickConnect.QuickConnectId // empty' "$qcf" 2>/dev/null | dos2unix)
            [ "$fid" = "$qc_id" ] && saved_file="$qcf" && break
        done

        if [ -n "$saved_file" ]; then
            local saved_type live_type
            saved_type=$(jq -r '.QuickConnect.QuickConnectConfig.QuickConnectType // empty' "$saved_file" | dos2unix)
            live_type=$(echo "$live_qc" | jq -r '.QuickConnect.QuickConnectConfig.QuickConnectType // empty' | dos2unix)
            if [ "$saved_type" = "$live_type" ]; then
                type_pass=$((type_pass + 1))
            else
                type_fail=$((type_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Type mismatch: $qc_name (saved=$saved_type live=$live_type)" >&2
            fi

            # 8.3: Quick connect config correct
            if [ "$saved_type" = "$live_type" ]; then
                local config_ok=true
                case "$saved_type" in
                    USER)
                        local saved_uid live_uid
                        saved_uid=$(jq -r '.QuickConnect.QuickConnectConfig.UserConfig.UserId // empty' "$saved_file" | dos2unix)
                        live_uid=$(echo "$live_qc" | jq -r '.QuickConnect.QuickConnectConfig.UserConfig.UserId // empty' | dos2unix)
                        if [ "$saved_uid" != "$live_uid" ]; then
                            # Cross-account: resolve by username
                            local saved_uname live_uname
                            saved_uname=$(resolve_name_by_id "users.json" ".Id" ".Username" "$saved_uid")
                            live_uname=$(aws_connect describe-user \
                                --instance-id "$instance_id" \
                                --user-id "$live_uid" 2>/dev/null | \
                                jq -r '.User.Username // empty' | dos2unix)
                            if [ -z "$saved_uname" ] || [ "$saved_uname" != "$live_uname" ]; then
                                config_ok=false
                            fi
                        fi
                        ;;
                    QUEUE)
                        local saved_qid live_qid
                        saved_qid=$(jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.QueueId // empty' "$saved_file" | dos2unix)
                        live_qid=$(echo "$live_qc" | jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.QueueId // empty' | dos2unix)
                        if [ "$saved_qid" != "$live_qid" ]; then
                            local saved_qname live_qname
                            saved_qname=$(resolve_name_by_id "queues.json" ".Id" ".Name" "$saved_qid")
                            live_qname=$(aws_connect describe-queue \
                                --instance-id "$instance_id" \
                                --queue-id "$live_qid" 2>/dev/null | \
                                jq -r '.Queue.Name // empty' | dos2unix)
                            if [ -z "$saved_qname" ] || [ "$saved_qname" != "$live_qname" ]; then
                                config_ok=false
                            fi
                        fi
                        local saved_cfid live_cfid
                        saved_cfid=$(jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.ContactFlowId // empty' "$saved_file" | dos2unix)
                        live_cfid=$(echo "$live_qc" | jq -r '.QuickConnect.QuickConnectConfig.QueueConfig.ContactFlowId // empty' | dos2unix)
                        if [ "$saved_cfid" != "$live_cfid" ]; then
                            local saved_fname live_fname
                            saved_fname=$(resolve_name_by_id "flows.json" ".Id" ".Name" "$saved_cfid")
                            live_fname=$(aws_connect describe-contact-flow \
                                --instance-id "$instance_id" \
                                --contact-flow-id "$live_cfid" 2>/dev/null | \
                                jq -r '.ContactFlow.Name // empty' | dos2unix)
                            if [ -z "$saved_fname" ] || [ "$saved_fname" != "$live_fname" ]; then
                                config_ok=false
                            fi
                        fi
                        ;;
                esac
                if [ "$config_ok" = true ]; then
                    config_pass=$((config_pass + 1))
                else
                    config_fail=$((config_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Config mismatch: $qc_name (type=$saved_type)" >&2
                fi
            fi

            # 8.4: Description match
            local saved_desc live_desc
            saved_desc=$(jq -r '.QuickConnect.Description // empty' "$saved_file" | dos2unix)
            live_desc=$(echo "$live_qc" | jq -r '.QuickConnect.Description // empty' | dos2unix)
            if compare_description "$saved_desc" "$live_desc"; then
                desc_pass=$((desc_pass + 1))
            else
                desc_fail=$((desc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $qc_name" >&2
            fi

            # 8.5: Tags match
            local saved_tags live_tags
            saved_tags=$(jq -c '.QuickConnect.Tags // {}' "$saved_file" 2>/dev/null)
            live_tags=$(echo "$live_qc" | jq -c '.QuickConnect.Tags // {}' 2>/dev/null)
            if compare_tags "$saved_tags" "$live_tags"; then
                tag_pass=$((tag_pass + 1))
            else
                tag_fail=$((tag_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Tags mismatch: $qc_name ($TAGS_DIFF_DETAIL)" >&2
            fi
        fi
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/quickconnects.json" 2>/dev/null | dos2unix)

    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "8.1" "All quick connects exist ($exist_pass/$qc_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "8.1" "Quick connects" "$exist_fail of $qc_count missing"
    fi

    if [ "$type_fail" -eq 0 ] && [ "$type_pass" -gt 0 ]; then
        pass "8.2" "Quick connect types correct ($type_pass/$exist_pass)"
    elif [ "$type_fail" -gt 0 ]; then
        fail "8.2" "Quick connect types" "$type_fail mismatched"
    fi

    if [ "$config_fail" -eq 0 ] && [ "$config_pass" -gt 0 ]; then
        pass "8.3" "Quick connect configs correct ($config_pass/$exist_pass)"
    elif [ "$config_fail" -gt 0 ]; then
        fail "8.3" "Quick connect configs" "$config_fail mismatched"
    fi

    if [ "$desc_fail" -eq 0 ] && [ "$desc_pass" -gt 0 ]; then
        pass "8.4" "Quick connect descriptions match ($desc_pass/$exist_pass)"
    elif [ "$desc_fail" -gt 0 ]; then
        fail "8.4" "Quick connect descriptions" "$desc_fail mismatched"
    fi

    if [ "$tag_fail" -eq 0 ] && [ "$tag_pass" -gt 0 ]; then
        pass "8.5" "Quick connect tags match ($tag_pass/$exist_pass)"
    elif [ "$tag_fail" -gt 0 ]; then
        fail "8.5" "Quick connect tags" "$tag_fail mismatched"
    fi

    layer_end
}

############################################################
# Layers 9-10: Contact Flow Modules and Contact Flows
############################################################

