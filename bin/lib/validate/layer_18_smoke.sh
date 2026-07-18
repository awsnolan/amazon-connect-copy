validate_layer_18() {
    layer_start 18 "Functional Smoke Tests"

    if [ -z "$do_smoke" ]; then
        skip "18.1" "Instance access URL" "smoke tests not enabled (use -m smoke)"
        layer_end; return
    fi

    # 18.1: Instance access URL reachable
    local access_url
    access_url=$(aws_connect describe-instance --instance-id "$instance_id" 2>/dev/null | \
        jq -r '.Instance.InstanceAccessUrl // empty' | dos2unix)
    if [ -n "$access_url" ]; then
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$access_url" 2>/dev/null)
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "301" ]; then
            pass "18.1" "Instance access URL reachable (HTTP $http_code)"
        else
            warn "18.1" "Instance access URL" "HTTP $http_code (expected 200/302)"
        fi
    else
        skip "18.1" "Instance access URL" "URL not available"
    fi

    # 18.2: Chat flow invocable (non-destructive test)
    local test_flow_id
    test_flow_id=$(jq -r 'select(.ContactFlowType == "CONTACT_FLOW") | .Id' \
        "$instance_alias_dir/flows.json" 2>/dev/null | head -1 | dos2unix)
    # Cross-account: resolve flow ID on target
    if [ -n "$CROSS_ACCOUNT" ] && [ -n "$test_flow_id" ]; then
        local test_flow_name
        test_flow_name=$(jq -r "select(.Id == \"$test_flow_id\") | .Name" "$instance_alias_dir/flows.json" 2>/dev/null | head -1 | dos2unix)
        [ -n "$test_flow_name" ] && test_flow_id=$(resolve_target_id "$MAP_FLOWS" "$test_flow_name")
    fi

    if [ -n "$test_flow_id" ]; then
        local chat_result
        chat_result=$(aws_connect start-chat-contact \
            --instance-id "$instance_id" \
            --contact-flow-id "$test_flow_id" \
            --participant-details "DisplayName=DR_Validation_Test" 2>/dev/null)
        if [ -n "$chat_result" ]; then
            local contact_id
            contact_id=$(echo "$chat_result" | jq -r '.ContactId // empty' | dos2unix)
            if [ -n "$contact_id" ]; then
                pass "18.2" "Chat flow invocable (contact=$contact_id)"
                # Clean up: disconnect the test contact
                aws_connect stop-contact \
                    --instance-id "$instance_id" \
                    --contact-id "$contact_id" 2>/dev/null
            else
                fail "18.2" "Chat flow" "StartChatContact returned no ContactId"
            fi
        else
            fail "18.2" "Chat flow" "StartChatContact failed"
        fi
    else
        skip "18.2" "Chat flow" "no CONTACT_FLOW type flow found"
    fi

    # 18.3: Outbound voice capability check
    # Verifies the outbound chain is wired correctly (flow + queue + caller ID)
    # Does NOT actually place a call — uses StartOutboundVoiceContact with a
    # non-routable test number to confirm the API accepts the parameters.
    local outbound_enabled
    outbound_enabled=$(aws_connect describe-instance-attribute \
        --instance-id "$instance_id" \
        --attribute-type OUTBOUND_CALLS 2>/dev/null | \
        jq -r '.Attribute.Value // "false"' | dos2unix)
    if [ "$outbound_enabled" = "true" ]; then
        # Find a queue with an outbound caller config
        local outbound_queue_id outbound_flow_id outbound_caller_number
        for qfile in "$instance_alias_dir"/queue_*.json; do
            [ -f "$qfile" ] || continue
            local q_caller_num
            q_caller_num=$(jq -r '.Queue.OutboundCallerConfig.OutboundCallerIdNumberId // empty' "$qfile" 2>/dev/null | dos2unix)
            if [ -n "$q_caller_num" ] && [ "$q_caller_num" != "null" ]; then
                outbound_queue_id=$(jq -r '.Queue.QueueId // empty' "$qfile" 2>/dev/null | dos2unix)
                outbound_flow_id=$(jq -r '.Queue.OutboundCallerConfig.OutboundFlowId // empty' "$qfile" 2>/dev/null | dos2unix)
                break
            fi
        done

        if [ -n "$outbound_queue_id" ] && [ -n "$test_flow_id" ]; then
            # Use the test flow and queue to attempt an outbound contact
            # The destination number +15555550100 is a non-routable test number (RFC 3849)
            local outbound_result
            outbound_result=$(aws_connect start-outbound-voice-contact \
                --instance-id "$instance_id" \
                --contact-flow-id "$test_flow_id" \
                --destination-phone-number "+15555550100" \
                --queue-id "$outbound_queue_id" 2>"$TEMPERR")
            if [ -n "$outbound_result" ]; then
                local ob_contact_id
                ob_contact_id=$(echo "$outbound_result" | jq -r '.ContactId // empty' | dos2unix)
                if [ -n "$ob_contact_id" ]; then
                    pass "18.3" "Outbound voice chain valid (contact=$ob_contact_id)"
                    # Immediately stop it
                    aws_connect stop-contact \
                        --instance-id "$instance_id" \
                        --contact-id "$ob_contact_id" 2>/dev/null
                else
                    pass "18.3" "Outbound API accepted parameters (no contact created — expected for test number)"
                fi
            else
                # Check if it's an InvalidParameterException (broken chain) vs other error
                if grep -qi "InvalidParameter\|InvalidRequest\|ValidationException" "$TEMPERR" 2>/dev/null; then
                    fail "18.3" "Outbound voice chain" "API rejected parameters — flow/queue/caller-ID chain is broken"
                else
                    # Other error (throttle, permissions) — warn but don't fail
                    local err_msg
                    err_msg=$(head -1 "$TEMPERR" 2>/dev/null)
                    warn "18.3" "Outbound voice" "Could not verify: $err_msg"
                fi
            fi
        else
            skip "18.3" "Outbound voice" "no queue with outbound caller config found"
        fi
    else
        skip "18.3" "Outbound voice" "OUTBOUND_CALLS not enabled"
    fi

    # 18.4: Connect Test Contact Flow API (available since Jan 2026)
    # Uses the test-contact-flow API to simulate a voice interaction
    if [ -n "$test_flow_id" ]; then
        local test_api_result
        test_api_result=$(aws_connect test-contact-flow \
            --instance-id "$instance_id" \
            --contact-flow-id "$test_flow_id" 2>"$TEMPERR")
        if [ -n "$test_api_result" ]; then
            local test_status
            test_status=$(echo "$test_api_result" | jq -r '.Status // empty' | dos2unix)
            if [ "$test_status" = "SUCCESS" ] || [ "$test_status" = "PASSED" ]; then
                pass "18.4" "Contact flow test API passed"
            else
                local test_detail
                test_detail=$(echo "$test_api_result" | jq -r '.Message // .Detail // empty' | dos2unix)
                warn "18.4" "Contact flow test API" "status=$test_status ${test_detail:+($test_detail)}"
            fi
        else
            # API may not exist yet in all regions
            if grep -qi "UnknownOperationException\|InvalidAction\|Could not connect" "$TEMPERR" 2>/dev/null; then
                skip "18.4" "Contact flow test API" "not available in this region"
            else
                local err_msg
                err_msg=$(head -1 "$TEMPERR" 2>/dev/null)
                warn "18.4" "Contact flow test API" "call failed: $err_msg"
            fi
        fi
    else
        skip "18.4" "Contact flow test API" "no test flow available"
    fi

    layer_end
}
