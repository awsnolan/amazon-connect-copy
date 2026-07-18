validate_layer_7() {
    layer_start 7 "Users"

    if [ ! -f "$instance_alias_dir/users.json" ]; then
        skip "7.1" "Users" "users.json not found"
        layer_end; return
    fi

    local user_count
    user_count=$(jq -s 'length' "$instance_alias_dir/users.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "7.1" "Users manifest ($user_count)"
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local rp_pass=0 rp_fail=0
    local sp_pass=0 sp_fail=0
    local hg_pass=0 hg_fail=0 hg_total=0
    local id_pass=0 id_fail=0
    local phone_pass=0 phone_fail=0
    local tag_pass=0 tag_fail=0
    local prof_pass=0 prof_fail=0 prof_total=0

    while IFS=$'\t' read -r user_id user_name; do
        [ -z "$user_id" ] && continue

        local live_user
        # Cross-account: resolve by name
        local eff_user_id
        eff_user_id=$(effective_id "$MAP_USERS" "$user_id" "$user_name")
        live_user=$(aws_connect describe-user \
            --instance-id "$instance_id" \
            --user-id "${eff_user_id:-$user_id}" 2>/dev/null)
        if [ -z "$live_user" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $user_name ($user_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # Find saved detail
        local saved_file=""
        for ufile in "$instance_alias_dir"/user_*.json; do
            [ -f "$ufile" ] || continue
            local fid
            fid=$(jq -r '.User.Id // empty' "$ufile" 2>/dev/null | dos2unix)
            [ "$fid" = "$user_id" ] && saved_file="$ufile" && break
        done
        [ -z "$saved_file" ] && continue

        # 7.2: Routing profile
        local saved_rp_id live_rp_id
        saved_rp_id=$(jq -r '.User.RoutingProfileId // empty' "$saved_file" | dos2unix)
        live_rp_id=$(echo "$live_user" | jq -r '.User.RoutingProfileId // empty' | dos2unix)
        if [ "$saved_rp_id" = "$live_rp_id" ]; then
            rp_pass=$((rp_pass + 1))
        else
            # Cross-account: resolve by name
            local saved_rp_name live_rp_name
            saved_rp_name=$(resolve_name_by_id "routings.json" ".Id" ".Name" "$saved_rp_id")
            live_rp_name=$(aws_connect describe-routing-profile \
                --instance-id "$instance_id" \
                --routing-profile-id "$live_rp_id" 2>/dev/null | \
                jq -r '.RoutingProfile.Name // empty' | dos2unix)
            if [ -n "$saved_rp_name" ] && [ "$saved_rp_name" = "$live_rp_name" ]; then
                rp_pass=$((rp_pass + 1))
            else
                rp_fail=$((rp_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Routing profile mismatch: $user_name (saved=$saved_rp_name live=$live_rp_name)" >&2
            fi
        fi

        # 7.3: Security profiles
        local saved_sps live_sps
        saved_sps=$(jq -r '.User.SecurityProfileIds[]? // empty' "$saved_file" 2>/dev/null | sort)
        live_sps=$(echo "$live_user" | jq -r '.User.SecurityProfileIds[]? // empty' 2>/dev/null | sort)
        if [ "$saved_sps" = "$live_sps" ]; then
            sp_pass=$((sp_pass + 1))
        else
            # Cross-account: resolve by name
            local saved_sp_names live_sp_names
            saved_sp_names=$(for sid in $saved_sps; do resolve_name_by_id "securityprofiles.json" ".Id" ".Name" "$sid"; done | sort)
            live_sp_names=$(for sid in $(echo "$live_user" | jq -r '.User.SecurityProfileIds[]? // empty' | dos2unix); do
                aws_connect describe-security-profile \
                    --instance-id "$instance_id" \
                    --security-profile-id "$sid" 2>/dev/null | \
                    jq -r '.SecurityProfile.SecurityProfileName // empty' | dos2unix
            done | sort)
            if [ "$saved_sp_names" = "$live_sp_names" ]; then
                sp_pass=$((sp_pass + 1))
            else
                sp_fail=$((sp_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Security profiles mismatch: $user_name" >&2
            fi
        fi

        # 7.4: Hierarchy group
        local saved_hg live_hg
        saved_hg=$(jq -r '.User.HierarchyGroupId // empty' "$saved_file" | dos2unix)
        live_hg=$(echo "$live_user" | jq -r '.User.HierarchyGroupId // empty' | dos2unix)
        [ "$saved_hg" = "null" ] && saved_hg=""
        [ "$live_hg" = "null" ] && live_hg=""
        if [ -z "$saved_hg" ] && [ -z "$live_hg" ]; then
            # Both null — pass (don't count toward total)
            :
        else
            hg_total=$((hg_total + 1))
            if [ "$saved_hg" = "$live_hg" ]; then
                hg_pass=$((hg_pass + 1))
            else
                hg_fail=$((hg_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Hierarchy group mismatch: $user_name" >&2
            fi
        fi

        # 7.5: Identity info (FirstName, LastName, Email)
        local saved_fn live_fn saved_ln live_ln saved_em live_em
        saved_fn=$(jq -r '.User.IdentityInfo.FirstName // empty' "$saved_file" | dos2unix)
        live_fn=$(echo "$live_user" | jq -r '.User.IdentityInfo.FirstName // empty' | dos2unix)
        saved_ln=$(jq -r '.User.IdentityInfo.LastName // empty' "$saved_file" | dos2unix)
        live_ln=$(echo "$live_user" | jq -r '.User.IdentityInfo.LastName // empty' | dos2unix)
        saved_em=$(jq -r '.User.IdentityInfo.Email // empty' "$saved_file" | dos2unix)
        live_em=$(echo "$live_user" | jq -r '.User.IdentityInfo.Email // empty' | dos2unix)
        if nullable_eq "$saved_fn" "$live_fn" && nullable_eq "$saved_ln" "$live_ln" && nullable_eq "$saved_em" "$live_em"; then
            id_pass=$((id_pass + 1))
        else
            id_fail=$((id_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Identity info mismatch: $user_name" >&2
        fi

        # 7.6: Phone config (PhoneType, AutoAccept, AfterContactWorkTimeLimit)
        local saved_pt live_pt saved_aa live_aa saved_acw live_acw
        saved_pt=$(jq -r '.User.PhoneConfig.PhoneType // empty' "$saved_file" | dos2unix)
        live_pt=$(echo "$live_user" | jq -r '.User.PhoneConfig.PhoneType // empty' | dos2unix)
        saved_aa=$(jq -r '.User.PhoneConfig.AutoAccept // false' "$saved_file" | dos2unix)
        live_aa=$(echo "$live_user" | jq -r '.User.PhoneConfig.AutoAccept // false' | dos2unix)
        saved_acw=$(jq -r '.User.PhoneConfig.AfterContactWorkTimeLimit // 0' "$saved_file" | dos2unix)
        live_acw=$(echo "$live_user" | jq -r '.User.PhoneConfig.AfterContactWorkTimeLimit // 0' | dos2unix)
        if [ "$saved_pt" = "$live_pt" ] && [ "$saved_aa" = "$live_aa" ] && [ "$saved_acw" = "$live_acw" ]; then
            phone_pass=$((phone_pass + 1))
        else
            phone_fail=$((phone_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Phone config mismatch: $user_name (type=$saved_pt→$live_pt)" >&2
        fi

        # 7.7: Tags
        local saved_tags live_tags
        saved_tags=$(jq -c '.User.Tags // {}' "$saved_file" 2>/dev/null)
        live_tags=$(echo "$live_user" | jq -c '.User.Tags // {}' 2>/dev/null)
        if compare_tags "$saved_tags" "$live_tags"; then
            tag_pass=$((tag_pass + 1))
        else
            tag_fail=$((tag_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Tags mismatch: $user_name ($TAGS_DIFF_DETAIL)" >&2
        fi

        # 7.8: Proficiencies
        local user_name_encoded
        user_name_encoded=$(path_encode "$user_name")
        local prof_file="$instance_alias_dir/userProficiencies_$user_name_encoded.json"
        if [ -f "$prof_file" ]; then
            prof_total=$((prof_total + 1))
            local saved_profs live_profs_data live_profs
            saved_profs=$(jq -S '[.UserProficiencyList[]? | {AttributeName, AttributeValue, Level}] | sort_by(.AttributeName, .AttributeValue)' "$prof_file" 2>/dev/null)
            live_profs_data=$(aws_connect list-user-proficiencies \
                --instance-id "$instance_id" \
                --user-id "${eff_user_id:-$user_id}" \
                --max-items $maxitems 2>/dev/null)
            live_profs=$(echo "$live_profs_data" | jq -S '[.UserProficiencyList[]? | {AttributeName, AttributeValue, Level}] | sort_by(.AttributeName, .AttributeValue)' 2>/dev/null)
            if [ "$saved_profs" = "$live_profs" ]; then
                prof_pass=$((prof_pass + 1))
            else
                prof_fail=$((prof_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Proficiencies mismatch: $user_name" >&2
            fi
        fi
    done < <(jq -r '.Id + "\t" + .Username' "$instance_alias_dir/users.json" 2>/dev/null | dos2unix)

    # --- Report results ---

    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "7.1" "All users exist ($exist_pass/$user_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "7.1" "Users" "$exist_fail of $user_count missing"
    fi

    if [ "$rp_fail" -eq 0 ] && [ "$rp_pass" -gt 0 ]; then
        pass "7.2" "User routing profiles correct ($rp_pass/$exist_pass)"
    elif [ "$rp_fail" -gt 0 ]; then
        fail "7.2" "User routing profiles" "$rp_fail mismatched"
    fi

    if [ "$sp_fail" -eq 0 ] && [ "$sp_pass" -gt 0 ]; then
        pass "7.3" "User security profiles correct ($sp_pass/$exist_pass)"
    elif [ "$sp_fail" -gt 0 ]; then
        fail "7.3" "User security profiles" "$sp_fail mismatched"
    fi

    if [ "$hg_total" -gt 0 ]; then
        if [ "$hg_fail" -eq 0 ]; then
            pass "7.4" "User hierarchy groups correct ($hg_pass/$hg_total)"
        else
            fail "7.4" "User hierarchy groups" "$hg_fail mismatched"
        fi
    else
        skip "7.4" "User hierarchy groups" "no users have hierarchy assignments"
    fi

    if [ "$id_fail" -eq 0 ] && [ "$id_pass" -gt 0 ]; then
        pass "7.5" "User identity info matches ($id_pass/$exist_pass)"
    elif [ "$id_fail" -gt 0 ]; then
        fail "7.5" "User identity info" "$id_fail mismatched"
    fi

    if [ "$phone_fail" -eq 0 ] && [ "$phone_pass" -gt 0 ]; then
        pass "7.6" "User phone config matches ($phone_pass/$exist_pass)"
    elif [ "$phone_fail" -gt 0 ]; then
        fail "7.6" "User phone config" "$phone_fail mismatched"
    fi

    if [ "$tag_fail" -eq 0 ] && [ "$tag_pass" -gt 0 ]; then
        pass "7.7" "User tags match ($tag_pass/$exist_pass)"
    elif [ "$tag_fail" -gt 0 ]; then
        fail "7.7" "User tags" "$tag_fail mismatched"
    fi

    if [ "$prof_total" -gt 0 ]; then
        if [ "$prof_fail" -eq 0 ]; then
            pass "7.8" "User proficiencies match ($prof_pass/$prof_total)"
        else
            fail "7.8" "User proficiencies" "$prof_fail mismatched"
        fi
    else
        skip "7.8" "User proficiencies" "no proficiency files found"
    fi

    layer_end
}
