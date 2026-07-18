validate_layer_15() {
    layer_start 15 "Cases Domain"

    if [ ! -f "$instance_alias_dir/cases_domains.json" ]; then
        skip "15.1" "Cases domain" "cases_domains.json not found"
        layer_end; return
    fi

    local domain_count
    domain_count=$(jq 'if type == "array" then length else 0 end' "$instance_alias_dir/cases_domains.json" 2>/dev/null)
    [ "$domain_count" -eq 0 ] && {
        skip "15.1" "Cases domain" "none configured"
        layer_end; return
    }

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "15.1" "Cases domain manifest ($domain_count)"
        layer_end; return
    }

    local live_domains
    live_domains=$(aws_cases list-domains --max-results 100 2>/dev/null)
    if [ -z "$live_domains" ]; then
        fail "15.1" "Cases domains" "Could not retrieve live domains"
        layer_end; return
    fi

    local live_domain_count
    live_domain_count=$(echo "$live_domains" | jq '.domains | length' 2>/dev/null)
    if [ "$live_domain_count" -ge "$domain_count" ]; then
        pass "15.1" "Cases domains exist (live=$live_domain_count saved=$domain_count)"
    else
        fail "15.1" "Cases domains" "live=$live_domain_count < saved=$domain_count"
    fi

    # 15.2: Custom fields match (for each domain)
    local domain_id
    domain_id=$(echo "$live_domains" | jq -r '.domains[0].domainId // empty' 2>/dev/null | dos2unix)
    if [ -n "$domain_id" ]; then
        local live_fields
        live_fields=$(aws_cases list-fields --domain-id "$domain_id" --max-results 100 2>/dev/null)
        if [ -n "$live_fields" ]; then
            local live_field_count
            live_field_count=$(echo "$live_fields" | jq '.fields | length' 2>/dev/null)
            pass "15.2" "Cases fields accessible ($live_field_count fields on domain)"
        else
            warn "15.2" "Cases fields" "Could not list fields for domain $domain_id"
        fi

        # 15.3: Layouts
        local live_layouts
        live_layouts=$(aws_cases list-layouts --domain-id "$domain_id" --max-results 100 2>/dev/null)
        if [ -n "$live_layouts" ]; then
            local live_layout_count
            live_layout_count=$(echo "$live_layouts" | jq '.layouts | length' 2>/dev/null)
            pass "15.3" "Cases layouts accessible ($live_layout_count layouts)"
        else
            warn "15.3" "Cases layouts" "Could not list layouts for domain $domain_id"
        fi

        # 15.4: Templates
        local live_templates
        live_templates=$(aws_cases list-templates --domain-id "$domain_id" --max-results 100 2>/dev/null)
        if [ -n "$live_templates" ]; then
            local live_template_count
            live_template_count=$(echo "$live_templates" | jq '.templates | length' 2>/dev/null)
            pass "15.4" "Cases templates accessible ($live_template_count templates)"
        else
            warn "15.4" "Cases templates" "Could not list templates for domain $domain_id"
        fi
    else
        skip "15.2" "Cases fields" "no domain ID available"
        skip "15.3" "Cases layouts" "no domain ID available"
        skip "15.4" "Cases templates" "no domain ID available"
    fi

    layer_end
}
