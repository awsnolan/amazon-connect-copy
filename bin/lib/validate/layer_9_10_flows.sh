validate_layer_9_10() {
    # --- Layer 9: Modules ---
    layer_start 9 "Contact Flow Modules"

    if [ ! -f "$instance_alias_dir/modules.json" ]; then
        skip "9.1" "Contact flow modules" "modules.json not found"
        layer_end
    else
        local mod_count
        mod_count=$(jq -s 'length' "$instance_alias_dir/modules.json" 2>/dev/null)

        if [ -n "$do_local" ]; then
            local mod_local_ok=0
            for mfile in "$instance_alias_dir"/module_*.json; do
                [ -f "$mfile" ] || continue
                if jq empty "$mfile" 2>/dev/null; then
                    # Check has Actions
                    local ac
                    ac=$(jq '.Actions | length' "$mfile" 2>/dev/null)
                    [ -n "$ac" ] && [ "$ac" -gt 0 ] && mod_local_ok=$((mod_local_ok + 1))
                fi
            done
            pass "9.1" "Module content files valid ($mod_local_ok)"
        fi

        if [ -n "$do_live" ]; then
            local mod_exist_pass=0 mod_exist_fail=0
            local mod_status_pass=0 mod_status_fail=0
            local mod_desc_pass=0 mod_desc_fail=0

            while IFS=$'\t' read -r mod_id mod_name; do
                [ -z "$mod_id" ] && continue
                # Cross-account: resolve by name
                local eff_mod_id
                eff_mod_id=$(effective_id "$MAP_MODULES" "$mod_id" "$mod_name")
                [ -z "$eff_mod_id" ] && { mod_exist_fail=$((mod_exist_fail + 1)); [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $mod_name" >&2; continue; }
                local live_mod
                live_mod=$(aws_connect describe-contact-flow-module \
                    --instance-id "$instance_id" \
                    --contact-flow-module-id "$eff_mod_id" 2>/dev/null)
                if [ -z "$live_mod" ]; then
                    mod_exist_fail=$((mod_exist_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $mod_name" >&2
                    continue
                fi
                mod_exist_pass=$((mod_exist_pass + 1))

                # 9.2: Published
                local mod_status
                mod_status=$(echo "$live_mod" | jq -r '.ContactFlowModule.Status // ""' | dos2unix)
                if [ "$mod_status" = "published" ]; then
                    mod_status_pass=$((mod_status_pass + 1))
                else
                    mod_status_fail=$((mod_status_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Not published: $mod_name (status=$mod_status)" >&2
                fi

                # 9.4: Module description match
                local mod_name_enc
                mod_name_enc=$(path_encode "$mod_name")
                local mod_saved_file="$instance_alias_dir/module_$mod_name_enc.json"
                if [ -f "$mod_saved_file" ]; then
                    local saved_mod_desc live_mod_desc
                    saved_mod_desc=$(jq -r '.Description // empty' "$mod_saved_file" 2>/dev/null | dos2unix)
                    live_mod_desc=$(echo "$live_mod" | jq -r '.ContactFlowModule.Description // empty' | dos2unix)
                    if compare_description "$saved_mod_desc" "$live_mod_desc"; then
                        mod_desc_pass=$((mod_desc_pass + 1))
                    else
                        mod_desc_fail=$((mod_desc_fail + 1))
                        [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $mod_name" >&2
                    fi
                fi
            done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/modules.json" 2>/dev/null | dos2unix)

            if [ "$mod_exist_fail" -eq 0 ] && [ "$mod_exist_pass" -gt 0 ]; then
                pass "9.1" "All modules exist ($mod_exist_pass/$mod_count)"
            elif [ "$mod_exist_fail" -gt 0 ]; then
                fail "9.1" "Contact flow modules" "$mod_exist_fail of $mod_count missing"
            fi

            if [ "$mod_status_fail" -eq 0 ] && [ "$mod_status_pass" -gt 0 ]; then
                pass "9.2" "All modules published ($mod_status_pass/$mod_exist_pass)"
            elif [ "$mod_status_fail" -gt 0 ]; then
                fail "9.2" "Module status" "$mod_status_fail not published"
            fi

            if [ "$mod_desc_fail" -eq 0 ] && [ "$mod_desc_pass" -gt 0 ]; then
                pass "9.4" "Module descriptions match ($mod_desc_pass/$mod_exist_pass)"
            elif [ "$mod_desc_fail" -gt 0 ]; then
                fail "9.4" "Module descriptions" "$mod_desc_fail mismatched"
            fi

            # 9.3: Module content matches (normalized diff)
            local mod_content_pass=0 mod_content_fail=0 mod_content_differ=""
            # Build source normalization sed script
            local src_norm_sed="${TEMPFILE}_src_norm_sed"
            _build_normalize_sed "$src_norm_sed" "$instance_alias_dir"
            # Build target normalization sed script (for live content)
            local tgt_norm_sed="${TEMPFILE}_tgt_norm_sed"
            if [ -n "$CROSS_ACCOUNT" ]; then
                # For cross-account, we need target instance info to normalize target content
                # Use the maps we already built: target IDs are in MAP files
                # Build a minimal target sed from the maps
                > "$tgt_norm_sed"
                [ -n "$instance_id" ] && echo "s%$instance_id%instance:NORMALIZED%g" >> "$tgt_norm_sed"
                # Normalize account/region from target ARNs
                local tgt_inst_info
                tgt_inst_info=$(aws_connect describe-instance --instance-id "$instance_id" 2>/dev/null)
                if [ -n "$tgt_inst_info" ]; then
                    local tgt_arn tgt_acct tgt_region
                    tgt_arn=$(echo "$tgt_inst_info" | jq -r '.Instance.Arn // empty' | dos2unix)
                    tgt_acct=$(echo "$tgt_arn" | cut -d: -f5)
                    tgt_region=$(echo "$tgt_arn" | cut -d: -f4)
                    [ -n "$tgt_acct" ] && echo "s%:$tgt_acct:%:account:NORMALIZED:%g" >> "$tgt_norm_sed"
                    [ -n "$tgt_region" ] && echo "s%:$tgt_region:%:region:NORMALIZED:%g" >> "$tgt_norm_sed"
                fi
                # Queue name→ID map: reverse to ID→name for normalization
                jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_QUEUES" 2>/dev/null | tr -d '\r' |
                while IFS=$'\t' read -r tid tname; do
                    [ -z "$tid" ] && continue
                    echo "s%$tid%queue:${tname//\%/%%}%g" >> "$tgt_norm_sed"
                done
                jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_FLOWS" 2>/dev/null | tr -d '\r' |
                while IFS=$'\t' read -r tid tname; do
                    [ -z "$tid" ] && continue
                    echo "s%$tid%flow:${tname//\%/%%}%g" >> "$tgt_norm_sed"
                done
                jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_MODULES" 2>/dev/null | tr -d '\r' |
                while IFS=$'\t' read -r tid tname; do
                    [ -z "$tid" ] && continue
                    echo "s%$tid%module:${tname//\%/%%}%g" >> "$tgt_norm_sed"
                done
                # Prompts: list from target
                aws_connect list-prompts --instance-id "$instance_id" --max-items $maxitems 2>/dev/null | \
                    jq -r '.PromptSummaryList[] | .Id + "\t" + .Name' 2>/dev/null | tr -d '\r' |
                while IFS=$'\t' read -r tid tname; do
                    [ -z "$tid" ] && continue
                    echo "s%$tid%prompt:${tname//\%/%%}%g" >> "$tgt_norm_sed"
                done
                # Lambda and Lex — same generic patterns as source
                echo 's%arn:aws:lambda:[^:]*:[^:]*:function:\([^:"]*\)%lambda:\1%g' >> "$tgt_norm_sed"
                echo 's%arn:aws:lex:[^:]*:[^:]*:%lex:NORMALIZED:%g' >> "$tgt_norm_sed"
            else
                # Same account: use same normalization for both
                cp "$src_norm_sed" "$tgt_norm_sed"
            fi

            while IFS=$'\t' read -r mod_id mod_name; do
                [ -z "$mod_id" ] && continue
                local eff_mod_id
                eff_mod_id=$(effective_id "$MAP_MODULES" "$mod_id" "$mod_name")
                [ -z "$eff_mod_id" ] && continue

                # Get source content from backup
                local mod_name_encoded
                mod_name_encoded=$(path_encode "$mod_name")
                local src_content_file="$instance_alias_dir/module_$mod_name_encoded.json"
                [ ! -f "$src_content_file" ] && continue
                local src_content
                src_content=$(jq -r '.' "$src_content_file" 2>/dev/null | normalize_flow_content "$src_norm_sed")

                # Get live content from target
                local live_mod_detail
                live_mod_detail=$(aws_connect describe-contact-flow-module \
                    --instance-id "$instance_id" \
                    --contact-flow-module-id "$eff_mod_id" 2>/dev/null)
                [ -z "$live_mod_detail" ] && continue
                local live_content
                live_content=$(echo "$live_mod_detail" | jq -r '.ContactFlowModule.Content // empty' | dos2unix)
                [ -z "$live_content" ] && continue
                local tgt_content
                tgt_content=$(echo "$live_content" | jq -r '.' 2>/dev/null | normalize_flow_content "$tgt_norm_sed")

                if [ "$src_content" = "$tgt_content" ]; then
                    mod_content_pass=$((mod_content_pass + 1))
                else
                    mod_content_fail=$((mod_content_fail + 1))
                    mod_content_differ="$mod_content_differ $mod_name"
                fi
            done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/modules.json" 2>/dev/null | dos2unix)

            if [ "$mod_content_fail" -eq 0 ]; then
                pass "9.3" "Module content matches ($mod_content_pass/$mod_content_pass)"
            else
                fail "9.3" "Module content matches" "$mod_content_fail module(s) differ:$mod_content_differ"
            fi
            rm -f "$src_norm_sed" "$tgt_norm_sed"
        fi
        layer_end
    fi

    # --- Layer 10: Contact Flows ---
    layer_start 10 "Contact Flows"

    if [ ! -f "$instance_alias_dir/flows.json" ]; then
        skip "10.1" "Contact flows" "flows.json not found"
        layer_end; return
    fi

    local flow_count
    flow_count=$(jq -s 'length' "$instance_alias_dir/flows.json" 2>/dev/null)

    if [ -n "$do_local" ]; then
        local flow_local_ok=0 flow_local_fail=0
        for ffile in "$instance_alias_dir"/flow_*.json; do
            [ -f "$ffile" ] || continue
            if jq empty "$ffile" 2>/dev/null; then
                local ac
                ac=$(jq '.Actions | length' "$ffile" 2>/dev/null)
                if [ -n "$ac" ] && [ "$ac" -gt 0 ]; then
                    # Check StartAction resolves
                    local start_id id_exists
                    start_id=$(jq -r '.StartAction // empty' "$ffile" 2>/dev/null)
                    if [ -n "$start_id" ]; then
                        id_exists=$(jq -r ".Actions[] | select(.Identifier == \"$start_id\") | .Identifier" "$ffile" 2>/dev/null | head -1)
                        if [ -n "$id_exists" ]; then
                            flow_local_ok=$((flow_local_ok + 1))
                        else
                            flow_local_fail=$((flow_local_fail + 1))
                            [ -z "$JSON_OUTPUT" ] && echo "         → StartAction unresolved: $(basename $ffile)" >&2
                        fi
                    else
                        flow_local_ok=$((flow_local_ok + 1))
                    fi
                fi
            fi
        done
        if [ "$flow_local_fail" -eq 0 ]; then
            pass "10.1a" "Flow content files valid ($flow_local_ok)"
        else
            fail "10.1a" "Flow content" "$flow_local_fail with unresolved StartAction"
        fi
    fi

    [ -z "$do_live" ] && { layer_end; return; }

    local flow_exist_pass=0 flow_exist_fail=0
    local flow_active_pass=0 flow_active_fail=0
    local flow_type_pass=0 flow_type_fail=0
    local flow_desc_pass=0 flow_desc_fail=0

    while IFS=$'\t' read -r flow_id flow_name flow_type; do
        [ -z "$flow_id" ] && continue

        local live_flow
        # Cross-account: resolve by name
        local eff_flow_id
        eff_flow_id=$(effective_id "$MAP_FLOWS" "$flow_id" "$flow_name")
        live_flow=$(aws_connect describe-contact-flow \
            --instance-id "$instance_id" \
            --contact-flow-id "${eff_flow_id:-$flow_id}" 2>/dev/null)
        if [ -z "$live_flow" ]; then
            flow_exist_fail=$((flow_exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $flow_name" >&2
            continue
        fi
        flow_exist_pass=$((flow_exist_pass + 1))

        # 10.2: State ACTIVE
        local live_state
        live_state=$(echo "$live_flow" | jq -r '.ContactFlow.State // ""' | dos2unix)
        if [ "$live_state" = "ACTIVE" ]; then
            flow_active_pass=$((flow_active_pass + 1))
        else
            flow_active_fail=$((flow_active_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Not ACTIVE: $flow_name (state=$live_state)" >&2
        fi

        # 10.3: Type matches
        if [ -n "$flow_type" ]; then
            local live_type
            live_type=$(echo "$live_flow" | jq -r '.ContactFlow.Type // ""' | dos2unix)
            if [ "$flow_type" = "$live_type" ]; then
                flow_type_pass=$((flow_type_pass + 1))
            else
                flow_type_fail=$((flow_type_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Type mismatch: $flow_name (saved=$flow_type live=$live_type)" >&2
            fi
        fi

        # 10.5: Flow description match
        local flow_name_enc
        flow_name_enc=$(path_encode "$flow_name")
        local flow_saved_file="$instance_alias_dir/flow_$flow_name_enc.json"
        if [ -f "$flow_saved_file" ]; then
            local saved_flow_desc live_flow_desc
            saved_flow_desc=$(jq -r '.Description // empty' "$flow_saved_file" 2>/dev/null | dos2unix)
            live_flow_desc=$(echo "$live_flow" | jq -r '.ContactFlow.Description // empty' | dos2unix)
            if compare_description "$saved_flow_desc" "$live_flow_desc"; then
                flow_desc_pass=$((flow_desc_pass + 1))
            else
                flow_desc_fail=$((flow_desc_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $flow_name" >&2
            fi
        fi
    done < <(jq -r '.Id + "\t" + .Name + "\t" + (.ContactFlowType // "")' "$instance_alias_dir/flows.json" 2>/dev/null | dos2unix)

    if [ "$flow_exist_fail" -eq 0 ] && [ "$flow_exist_pass" -gt 0 ]; then
        pass "10.1" "All flows exist ($flow_exist_pass/$flow_count)"
    elif [ "$flow_exist_fail" -gt 0 ]; then
        fail "10.1" "Contact flows" "$flow_exist_fail of $flow_count missing"
    fi

    if [ "$flow_active_fail" -eq 0 ] && [ "$flow_active_pass" -gt 0 ]; then
        pass "10.2" "All flows ACTIVE ($flow_active_pass/$flow_exist_pass)"
    elif [ "$flow_active_fail" -gt 0 ]; then
        fail "10.2" "Flow state" "$flow_active_fail not ACTIVE"
    fi

    if [ "$flow_type_fail" -eq 0 ] && [ "$flow_type_pass" -gt 0 ]; then
        pass "10.3" "Flow types correct ($flow_type_pass)"
    elif [ "$flow_type_fail" -gt 0 ]; then
        fail "10.3" "Flow types" "$flow_type_fail mismatched"
    fi

    if [ "$flow_desc_fail" -eq 0 ] && [ "$flow_desc_pass" -gt 0 ]; then
        pass "10.5" "Flow descriptions match ($flow_desc_pass/$flow_exist_pass)"
    elif [ "$flow_desc_fail" -gt 0 ]; then
        fail "10.5" "Flow descriptions" "$flow_desc_fail mismatched"
    fi

    # 10.4: Flow content matches (normalized diff)
    local flow_content_pass=0 flow_content_fail=0 flow_content_differ=""

    # Build normalization sed scripts (source and target)
    local src_norm_sed="${TEMPFILE}_src_flow_norm"
    _build_normalize_sed "$src_norm_sed" "$instance_alias_dir"
    local tgt_norm_sed="${TEMPFILE}_tgt_flow_norm"
    if [ -n "$CROSS_ACCOUNT" ]; then
        > "$tgt_norm_sed"
        [ -n "$instance_id" ] && echo "s%$instance_id%instance:NORMALIZED%g" >> "$tgt_norm_sed"
        local tgt_inst_info
        tgt_inst_info=$(aws_connect describe-instance --instance-id "$instance_id" 2>/dev/null)
        if [ -n "$tgt_inst_info" ]; then
            local tgt_arn tgt_acct tgt_region
            tgt_arn=$(echo "$tgt_inst_info" | jq -r '.Instance.Arn // empty' | dos2unix)
            tgt_acct=$(echo "$tgt_arn" | cut -d: -f5)
            tgt_region=$(echo "$tgt_arn" | cut -d: -f4)
            [ -n "$tgt_acct" ] && echo "s%:$tgt_acct:%:account:NORMALIZED:%g" >> "$tgt_norm_sed"
            [ -n "$tgt_region" ] && echo "s%:$tgt_region:%:region:NORMALIZED:%g" >> "$tgt_norm_sed"
        fi
        jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_QUEUES" 2>/dev/null | tr -d '\r' |
        while IFS=$'\t' read -r tid tname; do
            [ -z "$tid" ] && continue
            echo "s%$tid%queue:${tname//\%/%%}%g" >> "$tgt_norm_sed"
        done
        jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_FLOWS" 2>/dev/null | tr -d '\r' |
        while IFS=$'\t' read -r tid tname; do
            [ -z "$tid" ] && continue
            echo "s%$tid%flow:${tname//\%/%%}%g" >> "$tgt_norm_sed"
        done
        jq -r 'to_entries[] | .value + "\t" + .key' "$MAP_MODULES" 2>/dev/null | tr -d '\r' |
        while IFS=$'\t' read -r tid tname; do
            [ -z "$tid" ] && continue
            echo "s%$tid%module:${tname//\%/%%}%g" >> "$tgt_norm_sed"
        done
        aws_connect list-prompts --instance-id "$instance_id" --max-items $maxitems 2>/dev/null | \
            jq -r '.PromptSummaryList[] | .Id + "\t" + .Name' 2>/dev/null | tr -d '\r' |
        while IFS=$'\t' read -r tid tname; do
            [ -z "$tid" ] && continue
            echo "s%$tid%prompt:${tname//\%/%%}%g" >> "$tgt_norm_sed"
        done
        echo 's%arn:aws:lambda:[^:]*:[^:]*:function:\([^:"]*\)%lambda:\1%g' >> "$tgt_norm_sed"
        echo 's%arn:aws:lex:[^:]*:[^:]*:%lex:NORMALIZED:%g' >> "$tgt_norm_sed"
    else
        cp "$src_norm_sed" "$tgt_norm_sed"
    fi

    while IFS=$'\t' read -r flow_id flow_name flow_type; do
        [ -z "$flow_id" ] && continue

        local eff_flow_id
        eff_flow_id=$(effective_id "$MAP_FLOWS" "$flow_id" "$flow_name")
        [ -z "$eff_flow_id" ] && continue

        # Get source content from backup
        local flow_name_encoded
        flow_name_encoded=$(path_encode "$flow_name")
        local src_content_file="$instance_alias_dir/flow_$flow_name_encoded.json"
        [ ! -f "$src_content_file" ] && continue
        local src_content
        src_content=$(jq -r '.' "$src_content_file" 2>/dev/null | normalize_flow_content "$src_norm_sed")

        # Get live content from target
        local live_flow_detail
        live_flow_detail=$(aws_connect describe-contact-flow \
            --instance-id "$instance_id" \
            --contact-flow-id "$eff_flow_id" 2>/dev/null)
        [ -z "$live_flow_detail" ] && continue
        local live_content
        live_content=$(echo "$live_flow_detail" | jq -r '.ContactFlow.Content // empty' | dos2unix)
        [ -z "$live_content" ] && continue
        local tgt_content
        tgt_content=$(echo "$live_content" | jq -r '.' 2>/dev/null | normalize_flow_content "$tgt_norm_sed")

        if [ "$src_content" = "$tgt_content" ]; then
            flow_content_pass=$((flow_content_pass + 1))
        else
            flow_content_fail=$((flow_content_fail + 1))
            flow_content_differ="$flow_content_differ $flow_name"
        fi
    done < <(jq -r '.Id + "\t" + .Name + "\t" + (.ContactFlowType // "")' "$instance_alias_dir/flows.json" 2>/dev/null | dos2unix)

    if [ "$flow_content_fail" -eq 0 ] && [ "$flow_content_pass" -gt 0 ]; then
        pass "10.4" "Flow content matches ($flow_content_pass/$flow_content_pass)"
    elif [ "$flow_content_fail" -gt 0 ]; then
        fail "10.4" "Flow content matches" "$flow_content_fail flow(s) differ:$flow_content_differ"
    elif [ "$flow_content_pass" -eq 0 ]; then
        skip "10.4" "Flow content" "no flows to compare"
    fi
    rm -f "$src_norm_sed" "$tgt_norm_sed"

    layer_end
}

############################################################
# Layer 11: Phone Numbers
############################################################

