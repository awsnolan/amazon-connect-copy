validate_layer_1() {
    layer_start 1 "Instance Foundation"

    # --- Local checks ---
    if [ -n "$do_local" ]; then
        if [ ! -f "$instance_alias_dir/instance.json" ]; then
            fail "1.0" "instance.json exists" "File missing"
            layer_end; return
        fi
        # Validate JSON
        if ! jq empty "$instance_alias_dir/instance.json" 2>/dev/null; then
            fail "1.0" "instance.json valid JSON" "Parse error"
            layer_end; return
        fi
        local saved_alias
        saved_alias=$(jq -r '.InstanceAlias // .Alias // empty' "$instance_alias_dir/instance.json" | dos2unix)
        # Only check alias locally if not also doing live (avoids duplicate output)
        if [ -z "$do_live" ]; then
            if [ -n "$saved_alias" ] && [ "$saved_alias" = "$instance_alias" ]; then
                pass "1.2" "Instance alias matches: $instance_alias"
            elif [ -n "$saved_alias" ]; then
                warn "1.2" "Instance alias" "saved=$saved_alias dir=$instance_alias"
            fi
        fi
    fi

    # --- Live checks ---
    if [ -z "$do_live" ]; then
        layer_end; return
    fi

    # 1.1: Instance reachable
    local live_instance
    live_instance=$(aws_connect describe-instance --instance-id "$instance_id" 2>/dev/null)
    if [ -z "$live_instance" ]; then
        fail "1.1" "Instance reachable" "describe-instance failed for $instance_id"
        layer_end; return
    fi
    local live_status
    live_status=$(echo "$live_instance" | jq -r '.Instance.InstanceStatus' | dos2unix)
    if [ "$live_status" = "ACTIVE" ]; then
        pass "1.1" "Instance reachable: ACTIVE"
    else
        fail "1.1" "Instance reachable" "status=$live_status (expected ACTIVE)"
        layer_end; return
    fi

    # 1.2: Alias match (live)
    local live_alias
    live_alias=$(echo "$live_instance" | jq -r '.Instance.InstanceAlias' | dos2unix)
    if [ "$live_alias" = "$instance_alias" ]; then
        pass "1.2" "Instance alias matches: $instance_alias"
    else
        warn "1.2" "Instance alias" "saved=$instance_alias live=$live_alias"
    fi

    # 1.3: Instance attributes match
    if [ -f "$instance_alias_dir/instance_attributes.json" ]; then
        local attr_types="INBOUND_CALLS OUTBOUND_CALLS CONTACTFLOW_LOGS CONTACT_LENS AUTO_RESOLVE_BEST_VOICES USE_CUSTOM_TTS_VOICES EARLY_MEDIA MULTI_PARTY_CONFERENCE HIGH_VOLUME_OUTBOUND ENHANCED_CONTACT_MONITORING ENHANCED_CHAT_MONITORING"
        local attr_match=0 attr_total=0 attr_mismatch=""
        for attr_type in $attr_types; do
            local saved_val live_val
            saved_val=$(jq -r "select(.Attribute.AttributeType == \"$attr_type\") | .Attribute.Value // empty" \
                "$instance_alias_dir/instance_attributes.json" 2>/dev/null | head -1 | dos2unix)
            [ -z "$saved_val" ] && continue
            attr_total=$((attr_total + 1))
            live_val=$(aws_connect describe-instance-attribute \
                --instance-id "$instance_id" \
                --attribute-type "$attr_type" 2>/dev/null | \
                jq -r '.Attribute.Value // empty' | dos2unix)
            if [ "$saved_val" = "$live_val" ]; then
                attr_match=$((attr_match + 1))
            else
                attr_mismatch="$attr_mismatch $attr_type(saved=$saved_val,live=$live_val)"
            fi
        done
        if [ "$attr_match" -eq "$attr_total" ] && [ "$attr_total" -gt 0 ]; then
            pass "1.3" "Instance attributes match ($attr_match/$attr_total)"
        elif [ "$attr_total" -eq 0 ]; then
            skip "1.3" "Instance attributes" "none found in saved file"
        else
            fail "1.3" "Instance attributes" "Mismatched:$attr_mismatch"
        fi
    else
        skip "1.3" "Instance attributes" "instance_attributes.json not found"
    fi

    # 1.4: Storage configs match
    if [ -f "$instance_alias_dir/storage_configs.json" ]; then
        local storage_types="CALL_RECORDINGS CHAT_TRANSCRIPTS SCHEDULED_REPORTS MEDIA_STREAMS CONTACT_TRACE_RECORDS AGENT_EVENTS REAL_TIME_CONTACT_ANALYSIS_SEGMENTS REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS ATTACHMENTS CONTACT_EVALUATIONS SCREEN_RECORDINGS"
        local stor_match=0 stor_total=0 stor_mismatch=""
        for stype in $storage_types; do
            local saved_config live_config
            saved_config=$(jq -r ".StorageConfigs[]? | select(.AssociationId != null)" \
                "$instance_alias_dir/storage_configs.json" 2>/dev/null | head -1)
            # Only count types that were actually saved
            local has_saved
            has_saved=$(grep -c "\"$stype\"" "$instance_alias_dir/storage_configs.json" 2>/dev/null)
            [ "$has_saved" -eq 0 ] && continue
            stor_total=$((stor_total + 1))
            live_config=$(aws_connect list-instance-storage-configs \
                --instance-id "$instance_id" \
                --resource-type "$stype" 2>/dev/null)
            if [ -n "$live_config" ]; then
                stor_match=$((stor_match + 1))
            else
                stor_mismatch="$stor_mismatch $stype"
            fi
        done
        if [ "$stor_match" -eq "$stor_total" ] && [ "$stor_total" -gt 0 ]; then
            pass "1.4" "Storage configs present ($stor_match/$stor_total types)"
        elif [ "$stor_total" -eq 0 ]; then
            skip "1.4" "Storage configs" "none configured"
        else
            warn "1.4" "Storage configs" "Could not verify:$stor_mismatch"
        fi
    else
        skip "1.4" "Storage configs" "storage_configs.json not found"
    fi

    # 1.5: Approved origins match
    if [ -f "$instance_alias_dir/approved_origins.json" ]; then
        local saved_origins live_origins
        saved_origins=$(jq -r '.[]? // empty' "$instance_alias_dir/approved_origins.json" 2>/dev/null | sort)
        local live_origins_json
        live_origins_json=$(aws_connect list-approved-origins --instance-id "$instance_id" 2>/dev/null)
        live_origins=$(echo "$live_origins_json" | jq -r '.Origins // [] | .[]' 2>/dev/null | sort)
        if [ "$saved_origins" = "$live_origins" ]; then
            local origin_count=0
            [ -n "$saved_origins" ] && origin_count=$(echo "$saved_origins" | wc -l | tr -d ' ')
            pass "1.5" "Approved origins match ($origin_count)"
        else
            fail "1.5" "Approved origins" "Sets differ"
        fi
    else
        skip "1.5" "Approved origins" "approved_origins.json not found"
    fi

    # 1.6: Security keys
    if [ -f "$instance_alias_dir/security_keys.json" ]; then
        local saved_key_count live_key_count
        saved_key_count=$(jq -s 'length' "$instance_alias_dir/security_keys.json" 2>/dev/null)
        local live_keys
        live_keys=$(aws_connect list-security-keys --instance-id "$instance_id" 2>/dev/null)
        live_key_count=$(echo "$live_keys" | jq '.SecurityKeysList | length' 2>/dev/null)
        if [ "$saved_key_count" = "$live_key_count" ]; then
            pass "1.6" "Security keys count matches ($saved_key_count)"
        elif [ "${saved_key_count:-0}" -eq 0 ]; then
            pass "1.6" "Security keys (none configured)"
        else
            warn "1.6" "Security keys" "saved=$saved_key_count live=$live_key_count (manual re-association needed)"
        fi
    else
        skip "1.6" "Security keys" "security_keys.json not found"
    fi

    layer_end
}

############################################################
# Layer 2: Hours of Operations + Scheduling
############################################################

