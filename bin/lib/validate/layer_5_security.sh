validate_layer_5() {
    layer_start 5 "Security Profiles"

    if [ ! -f "$instance_alias_dir/securityprofiles.json" ]; then
        skip "5.1" "Security profiles" "securityprofiles.json not found"
        layer_end; return
    fi

    local sp_count
    sp_count=$(jq -s 'length' "$instance_alias_dir/securityprofiles.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "5.1" "Security profiles manifest ($sp_count)"
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local perm_pass=0 perm_fail=0
    local acl_pass=0 acl_fail=0
    local trr_pass=0 trr_fail=0
    local desc_pass=0 desc_fail=0

    while IFS=$'\t' read -r sp_id sp_name; do
        [ -z "$sp_id" ] && continue

        local live_sp
        # Cross-account: resolve by name
        local eff_sp_id
        eff_sp_id=$(effective_id "$MAP_SECURITY" "$sp_id" "$sp_name")
        live_sp=$(aws_connect describe-security-profile \
            --instance-id "$instance_id" \
            --security-profile-id "${eff_sp_id:-$sp_id}" 2>/dev/null)
        if [ -z "$live_sp" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $sp_name ($sp_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # 5.2: Permissions match
        local saved_base=""
        for spf in "$instance_alias_dir"/securityprofile_*.json; do
            [ -f "$spf" ] || continue
            [[ "$spf" == *Perms* ]] && continue
            local fid
            fid=$(jq -r '.SecurityProfile.Id // empty' "$spf" 2>/dev/null | dos2unix)
            if [ "$fid" = "$sp_id" ]; then
                saved_base=$(basename "$spf" .json)
                saved_base="${saved_base#securityprofile_}"
                break
            fi
        done

        if [ -n "$saved_base" ]; then
            local perms_file="$instance_alias_dir/securityprofilePerms_${saved_base}.json"
            if [ -f "$perms_file" ]; then
                local saved_perms live_perms_data live_perms
                saved_perms=$(jq -r '.Permissions[]? // empty' "$perms_file" 2>/dev/null | sort)
                live_perms_data=$(aws_connect list-security-profile-permissions \
                    --instance-id "$instance_id" \
                    --security-profile-id "$eff_sp_id" \
                    --max-items $maxitems 2>/dev/null)
                live_perms=$(echo "$live_perms_data" | jq -r '.Permissions[]? // empty' 2>/dev/null | sort)
                if [ "$saved_perms" = "$live_perms" ]; then
                    perm_pass=$((perm_pass + 1))
                else
                    perm_fail=$((perm_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Permissions mismatch: $sp_name" >&2
                fi
            fi
        fi

        # 5.3: Access control tags match
        if [ -n "$saved_base" ]; then
            local saved_file_sp="$instance_alias_dir/securityprofile_${saved_base}.json"
            if [ -f "$saved_file_sp" ]; then
                local saved_acl live_acl
                saved_acl=$(jq -S '.SecurityProfile.AllowedAccessControlTags // {}' "$saved_file_sp" 2>/dev/null)
                live_acl=$(echo "$live_sp" | jq -S '.SecurityProfile.AllowedAccessControlTags // {}' 2>/dev/null)
                if [ "$saved_acl" = "$live_acl" ]; then
                    acl_pass=$((acl_pass + 1))
                else
                    acl_fail=$((acl_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Access control tags mismatch: $sp_name" >&2
                fi

                # 5.4: Tag restricted resources
                local saved_trr live_trr
                saved_trr=$(jq -S '[.SecurityProfile.TagRestrictedResources[]? // empty] | sort' "$saved_file_sp" 2>/dev/null)
                live_trr=$(echo "$live_sp" | jq -S '[.SecurityProfile.TagRestrictedResources[]? // empty] | sort' 2>/dev/null)
                if [ "$saved_trr" = "$live_trr" ]; then
                    trr_pass=$((trr_pass + 1))
                else
                    trr_fail=$((trr_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Tag restricted resources mismatch: $sp_name" >&2
                fi

                # 5.5: Description match
                local saved_desc live_desc
                saved_desc=$(jq -r '.SecurityProfile.Description // empty' "$saved_file_sp" | dos2unix)
                live_desc=$(echo "$live_sp" | jq -r '.SecurityProfile.Description // empty' | dos2unix)
                if compare_description "$saved_desc" "$live_desc"; then
                    desc_pass=$((desc_pass + 1))
                else
                    desc_fail=$((desc_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Description mismatch: $sp_name" >&2
                fi
            fi
        fi
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/securityprofiles.json" 2>/dev/null | dos2unix)

    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "5.1" "All security profiles exist ($exist_pass/$sp_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "5.1" "Security profiles" "$exist_fail of $sp_count missing"
    fi

    if [ "$perm_fail" -eq 0 ] && [ "$perm_pass" -gt 0 ]; then
        pass "5.2" "Permissions match ($perm_pass/$exist_pass)"
    elif [ "$perm_fail" -gt 0 ]; then
        fail "5.2" "Security profile permissions" "$perm_fail mismatched"
    fi

    if [ "$acl_fail" -eq 0 ] && [ "$acl_pass" -gt 0 ]; then
        pass "5.3" "Access control tags match ($acl_pass/$exist_pass)"
    elif [ "$acl_fail" -gt 0 ]; then
        fail "5.3" "Access control tags" "$acl_fail mismatched"
    fi

    if [ "$trr_fail" -eq 0 ] && [ "$trr_pass" -gt 0 ]; then
        pass "5.4" "Tag restricted resources match ($trr_pass/$exist_pass)"
    elif [ "$trr_fail" -gt 0 ]; then
        fail "5.4" "Tag restricted resources" "$trr_fail mismatched"
    fi

    if [ "$desc_fail" -eq 0 ] && [ "$desc_pass" -gt 0 ]; then
        pass "5.5" "Security profile descriptions match ($desc_pass/$exist_pass)"
    elif [ "$desc_fail" -gt 0 ]; then
        fail "5.5" "Security profile descriptions" "$desc_fail mismatched"
    fi

    layer_end
}

############################################################
# Layer 6: User Hierarchy
############################################################

