validate_layer_4() {
    layer_start 4 "Routing Profiles"

    if [ ! -f "$instance_alias_dir/routings.json" ]; then
        skip "4.1" "Routing profiles" "routings.json not found"
        layer_end; return
    fi

    local rp_count
    rp_count=$(jq -s 'length' "$instance_alias_dir/routings.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        # Local-only: check detail files exist
        if [ -n "$do_local" ]; then
            local local_ok=0
            for rfile in "$instance_alias_dir"/routing_*.json; do
                [ -f "$rfile" ] || continue
                [[ "$rfile" == *routingQs* ]] && continue
                jq empty "$rfile" 2>/dev/null && local_ok=$((local_ok + 1))
            done
            pass "4.1" "Routing profile detail files ($local_ok)"
        fi
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local doq_pass=0 doq_fail=0
    local media_pass=0 media_fail=0
    local assoc_pass=0 assoc_fail=0 assoc_total=0
    local desc_pass=0 desc_fail=0
    local tag_pass=0 tag_fail=0

    while IFS=$'\t' read -r rp_id rp_name; do
        [ -z "$rp_id" ] && continue

        local live_rp
        # Cross-account: resolve by name
        local eff_rp_id
        eff_rp_id=$(effective_id "$MAP_ROUTINGS" "$rp_id" "$rp_name")
        live_rp=$(aws_connect describe-routing-profile \
            --instance-id "$instance_id" \
            --routing-profile-id "${eff_rp_id:-$rp_id}" 2>/dev/null)
        if [ -z "$live_rp" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $rp_name ($rp_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # Find saved detail file
        local saved_file=""
        for rfile in "$instance_alias_dir"/routing_*.json; do
            [ -f "$rfile" ] || continue
            [[ "$rfile" == *routingQs* ]] && continue
            local fid
            fid=$(jq -r '.RoutingProfile.RoutingProfileId // empty' "$rfile" 2>/dev/null | dos2unix)
            [ "$fid" = "$rp_id" ] && saved_file="$rfile" && break
        done
        [ -z "$saved_file" ] && continue

        # 4.2: DefaultOutboundQueue
        local saved_doq live_doq
        saved_doq=$(jq -r '.RoutingProfile.DefaultOutboundQueueId // empty' "$saved_file" | dos2unix)
        live_doq=$(echo "$live_rp" | jq -r '.RoutingProfile.DefaultOutboundQueueId // empty' | dos2unix)
        if [ "$saved_doq" = "$live_doq" ]; then
            doq_pass=$((doq_pass + 1))
        else
            # Resolve by name
            local saved_doq_name live_doq_name
            saved_doq_name=$(resolve_name_by_id "queues.json" ".Id" ".Name" "$saved_doq")
            live_doq_name=$(aws_connect describe-queue \
                --instance-id "$instance_id" --queue-id "$live_doq" 2>/dev/null | \
                jq -r '.Queue.Name // empty' | dos2unix)
            if [ -n "$saved_doq_name" ] && [ "$saved_doq_name" = "$live_doq_name" ]; then
                doq_pass=$((doq_pass + 1))
            else
                doq_fail=$((doq_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → DefaultOutboundQueue mismatch: $rp_name" >&2
            fi
        fi

        # 4.3: MediaConcurrencies
        local saved_media live_media
        saved_media=$(jq -S '.RoutingProfile.MediaConcurrencies | sort_by(.Channel)' "$saved_file" 2>/dev/null)
        live_media=$(echo "$live_rp" | jq -S '.RoutingProfile.MediaConcurrencies | sort_by(.Channel)' 2>/dev/null)
        # Compare channel + concurrency values (ignore CrossChannelBehavior if not set)
        local saved_channels live_channels
        saved_channels=$(echo "$saved_media" | jq '[.[] | {Channel, Concurrency}] | sort_by(.Channel)' 2>/dev/null)
        live_channels=$(echo "$live_media" | jq '[.[] | {Channel, Concurrency}] | sort_by(.Channel)' 2>/dev/null)
        if [ "$saved_channels" = "$live_channels" ]; then
            media_pass=$((media_pass + 1))
        else
            media_fail=$((media_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → MediaConcurrencies mismatch: $rp_name" >&2
        fi

        # 4.4: Associated queues
        local saved_base
        saved_base=$(basename "$saved_file" .json)
        saved_base="${saved_base#routing_}"
        local rqs_file="$instance_alias_dir/routingQs_${saved_base}.json"
        if [ -f "$rqs_file" ]; then
            assoc_total=$((assoc_total + 1))
            local saved_q_names live_rqs live_q_names
            saved_q_names=$(jq -r '.RoutingProfileQueueConfigSummaryList[]?.QueueName // empty' "$rqs_file" 2>/dev/null | sort)
            live_rqs=$(aws_connect list-routing-profile-queues \
                --instance-id "$instance_id" \
                --routing-profile-id "$eff_rp_id" \
                --max-items $maxitems 2>/dev/null)
            live_q_names=$(echo "$live_rqs" | jq -r '.RoutingProfileQueueConfigSummaryList[]?.QueueName // empty' 2>/dev/null | sort)
            if [ "$saved_q_names" = "$live_q_names" ]; then
                assoc_pass=$((assoc_pass + 1))
            else
                assoc_fail=$((assoc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Queue associations mismatch: $rp_name" >&2
            fi
        fi

        # 4.5: Description match
        local saved_desc live_desc
        saved_desc=$(jq -r '.RoutingProfile.Description // empty' "$saved_file" | dos2unix)
        live_desc=$(echo "$live_rp" | jq -r '.RoutingProfile.Description // empty' | dos2unix)
        if compare_description "$saved_desc" "$live_desc"; then
            desc_pass=$((desc_pass + 1))
        else
            desc_fail=$((desc_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $rp_name" >&2
        fi

        # 4.6: Tags match
        local saved_tags live_tags
        saved_tags=$(jq -c '.RoutingProfile.Tags // {}' "$saved_file" 2>/dev/null)
        live_tags=$(echo "$live_rp" | jq -c '.RoutingProfile.Tags // {}' 2>/dev/null)
        if compare_tags "$saved_tags" "$live_tags"; then
            tag_pass=$((tag_pass + 1))
        else
            tag_fail=$((tag_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Tags mismatch: $rp_name ($TAGS_DIFF_DETAIL)" >&2
        fi
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/routings.json" 2>/dev/null | dos2unix)

    # Report
    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "4.1" "All routing profiles exist ($exist_pass/$rp_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "4.1" "Routing profiles" "$exist_fail of $rp_count missing"
    fi

    if [ "$doq_fail" -eq 0 ] && [ "$doq_pass" -gt 0 ]; then
        pass "4.2" "DefaultOutboundQueue correct ($doq_pass/$exist_pass)"
    elif [ "$doq_fail" -gt 0 ]; then
        fail "4.2" "DefaultOutboundQueue" "$doq_fail mismatched"
    fi

    if [ "$media_fail" -eq 0 ] && [ "$media_pass" -gt 0 ]; then
        pass "4.3" "MediaConcurrencies match ($media_pass/$exist_pass)"
    elif [ "$media_fail" -gt 0 ]; then
        fail "4.3" "MediaConcurrencies" "$media_fail mismatched"
    fi

    if [ "$assoc_total" -gt 0 ]; then
        if [ "$assoc_fail" -eq 0 ]; then
            pass "4.4" "Queue associations match ($assoc_pass/$assoc_total)"
        else
            fail "4.4" "Queue associations" "$assoc_fail mismatched"
        fi
    fi

    if [ "$desc_fail" -eq 0 ] && [ "$desc_pass" -gt 0 ]; then
        pass "4.5" "Routing profile descriptions match ($desc_pass/$exist_pass)"
    elif [ "$desc_fail" -gt 0 ]; then
        fail "4.5" "Routing profile descriptions" "$desc_fail mismatched"
    fi

    if [ "$tag_fail" -eq 0 ] && [ "$tag_pass" -gt 0 ]; then
        pass "4.6" "Routing profile tags match ($tag_pass/$exist_pass)"
    elif [ "$tag_fail" -gt 0 ]; then
        fail "4.6" "Routing profile tags" "$tag_fail mismatched"
    fi

    layer_end
}

############################################################
# Layer 5: Security Profiles
############################################################

