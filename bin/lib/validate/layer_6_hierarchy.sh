validate_layer_6() {
    layer_start 6 "User Hierarchy"

    # 6.1: Hierarchy structure
    if [ ! -f "$instance_alias_dir/hierarchy_structure.json" ]; then
        skip "6.1" "Hierarchy structure" "hierarchy_structure.json not found"
        layer_end; return
    fi

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "6.1" "Hierarchy structure file exists"
        layer_end; return
    }

    local live_structure
    live_structure=$(aws_connect describe-user-hierarchy-structure \
        --instance-id "$instance_id" 2>/dev/null)

    if [ -n "$live_structure" ]; then
        local saved_levels live_levels
        saved_levels=$(jq -S '.HierarchyStructure | to_entries | map(select(.value != null)) | map(.value.Name) | sort' \
            "$instance_alias_dir/hierarchy_structure.json" 2>/dev/null)
        live_levels=$(echo "$live_structure" | \
            jq -S '.HierarchyStructure | to_entries | map(select(.value != null)) | map(.value.Name) | sort' 2>/dev/null)
        if [ "$saved_levels" = "$live_levels" ]; then
            pass "6.1" "Hierarchy structure matches"
        else
            fail "6.1" "Hierarchy structure" "Level names differ"
        fi
    else
        fail "6.1" "Hierarchy structure" "Could not retrieve live structure"
    fi

    # 6.2: Hierarchy groups
    if [ -f "$instance_alias_dir/hierarchy_groups.json" ]; then
        local hg_count
        hg_count=$(jq -s 'length' "$instance_alias_dir/hierarchy_groups.json" 2>/dev/null)
        local hg_pass=0 hg_fail=0

        while IFS=$'\t' read -r hg_id hg_name; do
            [ -z "$hg_id" ] && continue
            local live_hg
            live_hg=$(aws_connect describe-user-hierarchy-group \
                --instance-id "$instance_id" \
                --hierarchy-group-id "$hg_id" 2>/dev/null)
            if [ -n "$live_hg" ]; then
                hg_pass=$((hg_pass + 1))
            else
                hg_fail=$((hg_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Missing group: $hg_name" >&2
            fi
        done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/hierarchy_groups.json" 2>/dev/null | dos2unix)

        if [ "$hg_fail" -eq 0 ] && [ "$hg_pass" -gt 0 ]; then
            pass "6.2" "All hierarchy groups exist ($hg_pass/$hg_count)"
        elif [ "$hg_fail" -gt 0 ]; then
            fail "6.2" "Hierarchy groups" "$hg_fail of $hg_count missing"
        fi
    else
        skip "6.2" "Hierarchy groups" "hierarchy_groups.json not found"
    fi

    layer_end
}

############################################################
# Layer 7: Users
############################################################

