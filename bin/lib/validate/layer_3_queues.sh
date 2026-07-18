validate_layer_3() {
    layer_start 3 "Queues"

    if [ ! -f "$instance_alias_dir/queues.json" ]; then
        skip "3.1" "Queues" "queues.json not found"
        layer_end; return
    fi

    local queue_count
    queue_count=$(jq -s 'length' "$instance_alias_dir/queues.json" 2>/dev/null)

    # Local: validate detail files
    if [ -n "$do_local" ]; then
        local local_ok=0
        for qfile in "$instance_alias_dir"/queue_*.json; do
            [ -f "$qfile" ] || continue
            if jq empty "$qfile" 2>/dev/null; then
                local_ok=$((local_ok + 1))
            fi
        done
        if [ "$local_ok" -ge "$queue_count" ]; then
            pass "3.1a" "Queue detail files valid ($local_ok)"
        else
            warn "3.1" "Queue detail files" "$local_ok valid of $queue_count expected"
        fi
    fi

    [ -z "$do_live" ] && { layer_end; return; }

    local exist_pass=0 exist_fail=0
    local hoo_pass=0 hoo_fail=0
    local config_pass=0 config_fail=0
    local status_pass=0 status_warn=0
    local qc_pass=0 qc_fail=0 qc_total=0
    local desc_pass=0 desc_fail=0
    local tag_pass=0 tag_fail=0

    while IFS=$'\t' read -r queue_id queue_name; do
        [ -z "$queue_id" ] && continue

        # 3.1: Existence
        local live_queue
        # Cross-account: resolve by name
        local eff_queue_id
        eff_queue_id=$(effective_id "$MAP_QUEUES" "$queue_id" "$queue_name")
        live_queue=$(aws_connect describe-queue \
            --instance-id "$instance_id" \
            --queue-id "${eff_queue_id:-$queue_id}" 2>/dev/null)
        if [ -z "$live_queue" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $queue_name ($queue_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # 3.4: Status
        local live_status
        live_status=$(echo "$live_queue" | jq -r '.Queue.Status // ""' | dos2unix)
        if [ "$live_status" = "ENABLED" ]; then
            status_pass=$((status_pass + 1))
        else
            status_warn=$((status_warn + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Not ENABLED: $queue_name (status=$live_status)" >&2
        fi

        # Find saved detail file
        local saved_file=""
        for qfile in "$instance_alias_dir"/queue_*.json; do
            [ -f "$qfile" ] || continue
            local fid
            fid=$(jq -r '.Queue.QueueId // empty' "$qfile" 2>/dev/null | dos2unix)
            [ "$fid" = "$queue_id" ] && saved_file="$qfile" && break
        done
        [ -z "$saved_file" ] && continue

        # 3.2: HoursOfOperation reference
        local saved_hoo_id live_hoo_id
        saved_hoo_id=$(jq -r '.Queue.HoursOfOperationId // empty' "$saved_file" | dos2unix)
        live_hoo_id=$(echo "$live_queue" | jq -r '.Queue.HoursOfOperationId // empty' | dos2unix)
        if [ "$saved_hoo_id" = "$live_hoo_id" ]; then
            hoo_pass=$((hoo_pass + 1))
        else
            # Check if they resolve to same name
            local saved_hoo_name live_hoo_name
            saved_hoo_name=$(resolve_name_by_id "hours.json" ".Id" ".Name" "$saved_hoo_id")
            live_hoo_name=$(aws_connect describe-hours-of-operation \
                --instance-id "$instance_id" \
                --hours-of-operation-id "$live_hoo_id" 2>/dev/null | \
                jq -r '.HoursOfOperation.Name // empty' | dos2unix)
            if [ -n "$saved_hoo_name" ] && [ "$saved_hoo_name" = "$live_hoo_name" ]; then
                hoo_pass=$((hoo_pass + 1))
            else
                hoo_fail=$((hoo_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → HoO mismatch: $queue_name (saved=$saved_hoo_name live=$live_hoo_name)" >&2
            fi
        fi

        # 3.3: Outbound caller config
        local saved_caller live_caller
        saved_caller=$(jq -S '.Queue.OutboundCallerConfig // {}' "$saved_file" 2>/dev/null)
        live_caller=$(echo "$live_queue" | jq -S '.Queue.OutboundCallerConfig // {}' 2>/dev/null)
        # Compare just the caller ID name (IDs will differ cross-instance)
        local saved_caller_name live_caller_name
        saved_caller_name=$(echo "$saved_caller" | jq -r '.OutboundCallerIdName // empty')
        live_caller_name=$(echo "$live_caller" | jq -r '.OutboundCallerIdName // empty')
        if nullable_eq "$saved_caller_name" "$live_caller_name"; then
            config_pass=$((config_pass + 1))
        else
            config_fail=$((config_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Caller config mismatch: $queue_name" >&2
        fi

        # 3.6: Max contacts
        local saved_max live_max
        saved_max=$(jq -r '.Queue.MaxContacts // 0' "$saved_file" | dos2unix)
        live_max=$(echo "$live_queue" | jq -r '.Queue.MaxContacts // 0' | dos2unix)
        if [ "$saved_max" != "$live_max" ] && [ "$saved_max" != "0" ]; then
            [ -z "$JSON_OUTPUT" ] && echo "         → MaxContacts mismatch: $queue_name (saved=$saved_max live=$live_max)" >&2
        fi

        # 3.5: Queue quick connect associations
        local qc_saved_file=""
        for qcf in "$instance_alias_dir"/queueQCs_*.json; do
            [ -f "$qcf" ] || continue
            local qcf_base
            qcf_base=$(basename "$qcf" .json)
            qcf_base="${qcf_base#queueQCs_}"
            local sf_base
            sf_base=$(basename "$saved_file" .json)
            sf_base="${sf_base#queue_}"
            if [ "$qcf_base" = "$sf_base" ]; then
                qc_saved_file="$qcf"
                break
            fi
        done

        if [ -n "$qc_saved_file" ] && [ -f "$qc_saved_file" ]; then
            qc_total=$((qc_total + 1))
            local saved_qc_names live_qc_data live_qc_names
            saved_qc_names=$(jq -r '.QuickConnectSummaryList[]?.Name // empty' "$qc_saved_file" 2>/dev/null | sort)
            live_qc_data=$(aws_connect list-queue-quick-connects \
                --instance-id "$instance_id" \
                --queue-id "$eff_queue_id" \
                --max-items $maxitems 2>/dev/null)
            live_qc_names=$(echo "$live_qc_data" | jq -r '.QuickConnectSummaryList[]?.Name // empty' 2>/dev/null | sort)
            if [ "$saved_qc_names" = "$live_qc_names" ]; then
                qc_pass=$((qc_pass + 1))
            else
                qc_fail=$((qc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → QC association mismatch: $queue_name" >&2
            fi
        fi

        # 3.7: Description match
        local saved_desc live_desc
        saved_desc=$(jq -r '.Queue.Description // empty' "$saved_file" | dos2unix)
        live_desc=$(echo "$live_queue" | jq -r '.Queue.Description // empty' | dos2unix)
        if compare_description "$saved_desc" "$live_desc"; then
            desc_pass=$((desc_pass + 1))
        else
            desc_fail=$((desc_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $queue_name" >&2
        fi

        # 3.8: Tags match
        local saved_tags live_tags
        saved_tags=$(jq -c '.Queue.Tags // {}' "$saved_file" 2>/dev/null)
        live_tags=$(echo "$live_queue" | jq -c '.Queue.Tags // {}' 2>/dev/null)
        if compare_tags "$saved_tags" "$live_tags"; then
            tag_pass=$((tag_pass + 1))
        else
            tag_fail=$((tag_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Tags mismatch: $queue_name ($TAGS_DIFF_DETAIL)" >&2
        fi
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/queues.json" 2>/dev/null | dos2unix)

    # Report queue results
    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "3.1" "All queues exist ($exist_pass/$queue_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "3.1" "Queues" "$exist_fail of $queue_count missing"
    fi

    if [ "$hoo_fail" -eq 0 ] && [ "$hoo_pass" -gt 0 ]; then
        pass "3.2" "Queue HoursOfOperation correct ($hoo_pass/$exist_pass)"
    elif [ "$hoo_fail" -gt 0 ]; then
        fail "3.2" "Queue HoursOfOperation" "$hoo_fail mismatched"
    fi

    if [ "$config_fail" -eq 0 ] && [ "$config_pass" -gt 0 ]; then
        pass "3.3" "Queue outbound caller config ($config_pass/$exist_pass)"
    elif [ "$config_fail" -gt 0 ]; then
        fail "3.3" "Queue outbound caller config" "$config_fail mismatched"
    fi

    if [ "$status_warn" -eq 0 ] && [ "$status_pass" -gt 0 ]; then
        pass "3.4" "All queues ENABLED ($status_pass/$exist_pass)"
    elif [ "$status_warn" -gt 0 ]; then
        warn "3.4" "Queue status" "$status_warn not ENABLED"
    fi

    if [ "$qc_total" -gt 0 ]; then
        if [ "$qc_fail" -eq 0 ]; then
            pass "3.5" "Queue quick connect associations ($qc_pass/$qc_total)"
        else
            fail "3.5" "Queue QC associations" "$qc_fail mismatched"
        fi
    else
        skip "3.5" "Queue QC associations" "no saved QC files"
    fi

    if [ "$desc_fail" -eq 0 ] && [ "$desc_pass" -gt 0 ]; then
        pass "3.7" "Queue descriptions match ($desc_pass/$exist_pass)"
    elif [ "$desc_fail" -gt 0 ]; then
        fail "3.7" "Queue descriptions" "$desc_fail mismatched"
    fi

    if [ "$tag_fail" -eq 0 ] && [ "$tag_pass" -gt 0 ]; then
        pass "3.8" "Queue tags match ($tag_pass/$exist_pass)"
    elif [ "$tag_fail" -gt 0 ]; then
        fail "3.8" "Queue tags" "$tag_fail mismatched"
    fi

    layer_end
}

############################################################
# Layer 4: Routing Profiles
############################################################

