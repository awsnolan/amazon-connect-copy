validate_layer_2() {
    layer_start 2 "Hours of Operations"

    if [ ! -f "$instance_alias_dir/hours.json" ]; then
        skip "2.1" "Hours of operations" "hours.json not found"
        layer_end; return
    fi

    local hour_count
    hour_count=$(jq -s 'length' "$instance_alias_dir/hours.json" 2>/dev/null)

    # Local: validate each hour detail file exists and is valid JSON
    if [ -n "$do_local" ]; then
        local local_ok=0 local_fail=0
        while IFS=$'\t' read -r hour_id hour_name; do
            [ -z "$hour_id" ] && continue
            # Find detail file by searching for matching HoursOfOperationId
            local found_file=""
            for hfile in "$instance_alias_dir"/hour_*.json; do
                [ -f "$hfile" ] || continue
                local fid
                fid=$(jq -r '.HoursOfOperation.HoursOfOperationId // empty' "$hfile" 2>/dev/null | dos2unix)
                if [ "$fid" = "$hour_id" ]; then
                    found_file="$hfile"
                    break
                fi
            done
            if [ -n "$found_file" ] && jq empty "$found_file" 2>/dev/null; then
                local_ok=$((local_ok + 1))
            else
                local_fail=$((local_fail + 1))
            fi
        done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/hours.json" 2>/dev/null | dos2unix)
        if [ "$local_fail" -eq 0 ]; then
            pass "2.1a" "All hours of operations saved ($hour_count)"
        else
            fail "2.1a" "Hours of operations" "$local_fail of $hour_count missing detail files"
        fi
    fi

    [ -z "$do_live" ] && { layer_end; return; }

    # Live: verify existence, config match, and overrides
    local exist_pass=0 exist_fail=0
    local config_pass=0 config_fail=0
    local override_pass=0 override_fail=0 override_total=0

    while IFS=$'\t' read -r hour_id hour_name; do
        [ -z "$hour_id" ] && continue

        # 2.1: Existence
        local live_hour
        # Cross-account: resolve by name
        local eff_hour_id
        eff_hour_id=$(effective_id "$MAP_HOURS" "$hour_id" "$hour_name")
        live_hour=$(aws_connect describe-hours-of-operation \
            --instance-id "$instance_id" \
            --hours-of-operation-id "${eff_hour_id:-$hour_id}" 2>/dev/null)
        if [ -z "$live_hour" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $hour_name ($hour_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # 2.2: Config match (TimeZone + day/time config)
        # Find saved detail file
        local saved_file=""
        for hfile in "$instance_alias_dir"/hour_*.json; do
            [ -f "$hfile" ] || continue
            local fid
            fid=$(jq -r '.HoursOfOperation.HoursOfOperationId // empty' "$hfile" 2>/dev/null | dos2unix)
            [ "$fid" = "$hour_id" ] && saved_file="$hfile" && break
        done

        if [ -n "$saved_file" ]; then
            local saved_tz live_tz
            saved_tz=$(jq -r '.HoursOfOperation.TimeZone' "$saved_file" | dos2unix)
            live_tz=$(echo "$live_hour" | jq -r '.HoursOfOperation.TimeZone' | dos2unix)

            local saved_config live_config
            saved_config=$(jq -S '.HoursOfOperation.Config | sort_by(.Day, .StartTime.Hours, .StartTime.Minutes)' "$saved_file" 2>/dev/null)
            live_config=$(echo "$live_hour" | jq -S '.HoursOfOperation.Config | sort_by(.Day, .StartTime.Hours, .StartTime.Minutes)' 2>/dev/null)

            if [ "$saved_tz" = "$live_tz" ] && [ "$saved_config" = "$live_config" ]; then
                config_pass=$((config_pass + 1))
            else
                config_fail=$((config_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Config mismatch: $hour_name" >&2
            fi
        fi

        # 2.3: Overrides match
        local override_file="$instance_alias_dir/hourOverrides_*.json"
        # Find the matching overrides file by hour name encoding
        local saved_overrides_file=""
        for ofile in "$instance_alias_dir"/hourOverrides_*.json; do
            [ -f "$ofile" ] || continue
            # Match by checking if file corresponds to this hour
            # The file naming uses path_encode of the hour name
            # Simpler: check all override files, match by content if needed
            local ofile_base
            ofile_base=$(basename "$ofile" .json)
            ofile_base="${ofile_base#hourOverrides_}"
            # Check if this corresponds to our hour by checking the saved detail file basename
            if [ -n "$saved_file" ]; then
                local saved_base
                saved_base=$(basename "$saved_file" .json)
                saved_base="${saved_base#hour_}"
                if [ "$ofile_base" = "$saved_base" ]; then
                    saved_overrides_file="$ofile"
                    break
                fi
            fi
        done

        if [ -n "$saved_overrides_file" ] && [ -f "$saved_overrides_file" ]; then
            override_total=$((override_total + 1))
            local saved_override_count live_overrides live_override_count
            saved_override_count=$(jq '.HoursOfOperationOverrideList | length' "$saved_overrides_file" 2>/dev/null || echo 0)
            live_overrides=$(aws_connect list-hours-of-operation-overrides \
                --instance-id "$instance_id" \
                --hours-of-operation-id "$eff_hour_id" \
                --max-items $maxitems 2>/dev/null)
            live_override_count=$(echo "$live_overrides" | jq '.HoursOfOperationOverrideList | length' 2>/dev/null || echo 0)
            if [ "$saved_override_count" = "$live_override_count" ]; then
                override_pass=$((override_pass + 1))
            else
                override_fail=$((override_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Override count mismatch: $hour_name (saved=$saved_override_count live=$live_override_count)" >&2
            fi
        fi
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/hours.json" 2>/dev/null | dos2unix)

    # Report
    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "2.1" "All hours exist ($exist_pass/$hour_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "2.1" "Hours of operations" "$exist_fail of $hour_count missing"
    fi

    if [ "$config_fail" -eq 0 ] && [ "$config_pass" -gt 0 ]; then
        pass "2.2" "Hour configs match ($config_pass/$exist_pass)"
    elif [ "$config_fail" -gt 0 ]; then
        fail "2.2" "Hour configs" "$config_fail mismatched"
    fi

    if [ "$override_total" -gt 0 ]; then
        if [ "$override_fail" -eq 0 ]; then
            pass "2.3" "Hour overrides match ($override_pass/$override_total)"
        else
            fail "2.3" "Hour overrides" "$override_fail mismatched"
        fi
    else
        skip "2.3" "Hour overrides" "no override files found"
    fi

    layer_end
}

############################################################
# Layer 3: Queues
############################################################

