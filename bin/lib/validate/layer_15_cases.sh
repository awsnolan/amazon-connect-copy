validate_layer_15() {
    layer_start 15 "Cases & Customer Profiles"

    # --- 15A: Cases Domain ---
    if [ ! -f "$instance_alias_dir/cases_domains.json" ]; then
        skip "15.1" "Cases domain" "cases_domains.json not found"
    else
        local domain_count
        domain_count=$(jq -s 'length' "$instance_alias_dir/cases_domains.json" 2>/dev/null || echo 0)
        if [ "$domain_count" -eq 0 ]; then
            skip "15.1" "Cases domain" "none configured"
        elif [ -z "$do_live" ]; then
            [ -n "$do_local" ] && pass "15.1" "Cases domain manifest ($domain_count)"
        else
            local live_domains
            live_domains=$(aws_cases list-domains --max-results 100 2>/dev/null)
            if [ -z "$live_domains" ]; then
                fail "15.1" "Cases domains" "Could not retrieve live domains"
            else
                local live_domain_count
                live_domain_count=$(echo "$live_domains" | jq '.domains | length' 2>/dev/null)
                if [ "$live_domain_count" -ge "$domain_count" ]; then
                    pass "15.1" "Cases domains exist (live=$live_domain_count saved=$domain_count)"
                else
                    fail "15.1" "Cases domains" "live=$live_domain_count < saved=$domain_count"
                fi

                # 15.2-15.4: Compare field/layout/template counts
                local domain_id
                domain_id=$(echo "$live_domains" | jq -r '.domains[0].domainId // empty' 2>/dev/null | dos2unix)
                if [ -n "$domain_id" ]; then
                    # Fields
                    local live_fields saved_field_count
                    live_fields=$(aws_cases list-fields --domain-id "$domain_id" --max-results 100 2>/dev/null)
                    local live_field_count=$(echo "$live_fields" | jq '.fields | length' 2>/dev/null || echo 0)
                    local domain_name=$(jq -r '.name // empty' "$instance_alias_dir/cases_domains.json" 2>/dev/null | head -1 | dos2unix)
                    local domain_name_enc=$(path_encode "$domain_name")
                    saved_field_count=$(jq '.fields | length' "$instance_alias_dir/cases_fields_$domain_name_enc.json" 2>/dev/null || echo 0)
                    if [ "$live_field_count" -ge "$saved_field_count" ]; then
                        pass "15.2" "Cases fields (live=$live_field_count saved=$saved_field_count)"
                    else
                        fail "15.2" "Cases fields" "live=$live_field_count < saved=$saved_field_count"
                    fi

                    # Layouts
                    local live_layouts
                    live_layouts=$(aws_cases list-layouts --domain-id "$domain_id" --max-results 100 2>/dev/null)
                    local live_layout_count=$(echo "$live_layouts" | jq '.layouts | length' 2>/dev/null || echo 0)
                    local saved_layout_count=$(jq '.layouts | length' "$instance_alias_dir/cases_layouts_$domain_name_enc.json" 2>/dev/null || echo 0)
                    if [ "$live_layout_count" -ge "$saved_layout_count" ]; then
                        pass "15.3" "Cases layouts (live=$live_layout_count saved=$saved_layout_count)"
                    else
                        fail "15.3" "Cases layouts" "live=$live_layout_count < saved=$saved_layout_count"
                    fi

                    # Templates
                    local live_templates
                    live_templates=$(aws_cases list-templates --domain-id "$domain_id" --max-results 100 2>/dev/null)
                    local live_template_count=$(echo "$live_templates" | jq '.templates | length' 2>/dev/null || echo 0)
                    local saved_template_count=$(jq '.templates | length' "$instance_alias_dir/cases_templates_$domain_name_enc.json" 2>/dev/null || echo 0)
                    if [ "$live_template_count" -ge "$saved_template_count" ]; then
                        pass "15.4" "Cases templates (live=$live_template_count saved=$saved_template_count)"
                    else
                        fail "15.4" "Cases templates" "live=$live_template_count < saved=$saved_template_count"
                    fi
                fi
            fi
        fi
    fi

    # --- 15B: Customer Profiles ---
    local profiles_domain_file="$instance_alias_dir/profiles_domain.json"
    if [ ! -f "$profiles_domain_file" ] || [ "$(jq '.DomainName // empty' "$profiles_domain_file" 2>/dev/null)" = "" ]; then
        skip "15.5" "Customer Profiles" "not configured"
    else
        local src_domain_name
        src_domain_name=$(jq -r '.DomainName // empty' "$profiles_domain_file" | dos2unix)
        local src_ot_count=$(jq 'length' "$instance_alias_dir/profiles_object_types.json" 2>/dev/null || echo 0)
        local src_ca_count=$(jq 'length' "$instance_alias_dir/profiles_calculated_attrs.json" 2>/dev/null || echo 0)

        if [ -z "$do_live" ]; then
            [ -n "$do_local" ] && pass "15.5" "Customer Profiles domain: $src_domain_name ($src_ot_count object types, $src_ca_count calculated attrs)"
        else
            # Check target domain exists
            local target_domain_name="${instance_alias:-$src_domain_name}"
            local live_domain
            live_domain=$(aws customer-profiles get-domain \
                --domain-name "$target_domain_name" 2>/dev/null)
            if [ -n "$live_domain" ]; then
                pass "15.5" "Customer Profiles domain exists: $target_domain_name"

                # 15.6: Object types match
                local live_ot
                live_ot=$(aws customer-profiles list-profile-object-types \
                    --domain-name "$target_domain_name" \
                    --max-results 100 2>/dev/null)
                local live_ot_count=$(echo "$live_ot" | jq '.Items | length' 2>/dev/null || echo 0)
                if [ "$live_ot_count" -ge "$src_ot_count" ]; then
                    pass "15.6" "Profile object types (live=$live_ot_count saved=$src_ot_count)"
                else
                    fail "15.6" "Profile object types" "live=$live_ot_count < saved=$src_ot_count"
                fi

                # 15.7: Calculated attributes match
                local live_ca
                live_ca=$(aws customer-profiles list-calculated-attribute-definitions \
                    --domain-name "$target_domain_name" \
                    --max-results 100 2>/dev/null)
                local live_ca_count=$(echo "$live_ca" | jq '.Items | length' 2>/dev/null || echo 0)
                if [ "$live_ca_count" -ge "$src_ca_count" ]; then
                    pass "15.7" "Calculated attributes (live=$live_ca_count saved=$src_ca_count)"
                else
                    fail "15.7" "Calculated attributes" "live=$live_ca_count < saved=$src_ca_count"
                fi
            else
                fail "15.5" "Customer Profiles domain" "domain '$target_domain_name' not found on target"
            fi
        fi
    fi

    layer_end
}
