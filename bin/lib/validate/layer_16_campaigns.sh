validate_layer_16() {
    layer_start 16 "Outbound Campaigns"

    if [ ! -f "$instance_alias_dir/campaigns.json" ]; then
        skip "16.1" "Campaigns" "campaigns.json not found"
        layer_end; return
    fi

    local camp_count
    camp_count=$(jq 'if type == "array" then length else 0 end' "$instance_alias_dir/campaigns.json" 2>/dev/null)
    [ "$camp_count" -eq 0 ] && {
        skip "16.1" "Campaigns" "none configured"
        layer_end; return
    }

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "16.1" "Campaigns manifest ($camp_count)"
        layer_end; return
    }

    local camp_pass=0 camp_fail=0
    local camp_queue_pass=0 camp_queue_fail=0 camp_queue_total=0
    while IFS=$'\t' read -r camp_id camp_name; do
        [ -z "$camp_id" ] && continue
        local live_camp
        live_camp=$(aws_campaigns describe-campaign --id "$camp_id" 2>/dev/null)
        if [ -n "$live_camp" ]; then
            camp_pass=$((camp_pass + 1))

            # 16.3: Connect queue reference valid
            local camp_queue_id
            camp_queue_id=$(echo "$live_camp" | jq -r '.campaign.connectCampaignFlowArn // .campaign.channelSubtypeConfig.telephony.connectQueueId // empty' 2>/dev/null | dos2unix)
            if [ -n "$camp_queue_id" ] && [ "$camp_queue_id" != "null" ]; then
                camp_queue_total=$((camp_queue_total + 1))
                # Verify the queue exists on the instance
                local queue_check
                queue_check=$(aws_connect describe-queue \
                    --instance-id "$instance_id" \
                    --queue-id "$camp_queue_id" 2>/dev/null)
                if [ -n "$queue_check" ]; then
                    camp_queue_pass=$((camp_queue_pass + 1))
                else
                    camp_queue_fail=$((camp_queue_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Campaign queue not found: $camp_name (queue=$camp_queue_id)" >&2
                fi
            fi
        else
            camp_fail=$((camp_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $camp_name ($camp_id)" >&2
        fi
    done < <(jq -r '.id + "\t" + .name' "$instance_alias_dir/campaigns.json" 2>/dev/null | dos2unix)

    if [ "$camp_fail" -eq 0 ] && [ "$camp_pass" -gt 0 ]; then
        pass "16.1" "All campaigns exist ($camp_pass/$camp_count)"
    elif [ "$camp_fail" -gt 0 ]; then
        fail "16.1" "Campaigns" "$camp_fail of $camp_count missing"
    fi

    if [ "$camp_queue_total" -gt 0 ]; then
        if [ "$camp_queue_fail" -eq 0 ]; then
            pass "16.3" "Campaign queue references valid ($camp_queue_pass/$camp_queue_total)"
        else
            fail "16.3" "Campaign queue references" "$camp_queue_fail of $camp_queue_total invalid"
        fi
    fi

    layer_end
}
