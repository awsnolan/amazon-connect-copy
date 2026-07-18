validate_layer_13() {
    layer_start 13 "Email Channel"

    if [ ! -f "$instance_alias_dir/email_addresses.json" ]; then
        skip "13.1" "Email addresses" "email_addresses.json not found"
        layer_end; return
    fi

    local email_count
    email_count=$(jq -s 'length' "$instance_alias_dir/email_addresses.json" 2>/dev/null)
    [ "$email_count" -eq 0 ] && {
        skip "13.1" "Email addresses" "none configured"
        layer_end; return
    }

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "13.1" "Email addresses manifest ($email_count)"
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local domain_verified=0 domain_pending=0
    local display_pass=0 display_fail=0

    while IFS=$'\t' read -r ea_id ea_addr; do
        [ -z "$ea_id" ] && continue
        local live_ea
        live_ea=$(aws_connect describe-email-address \
            --instance-id "$instance_id" \
            --email-address-id "$ea_id" 2>/dev/null)
        if [ -n "$live_ea" ]; then
            exist_pass=$((exist_pass + 1))

            # 13.2: Domain verified status
            local domain_status
            domain_status=$(echo "$live_ea" | jq -r '.EmailAddress.EmailAddressArn // empty' | dos2unix)
            # Check if there's a verification status in the response
            local email_status
            email_status=$(echo "$live_ea" | jq -r '.EmailAddress.Status // empty' | dos2unix)
            if [ -n "$email_status" ] && [ "$email_status" = "PENDING" ]; then
                domain_pending=$((domain_pending + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Domain PENDING verification: $ea_addr" >&2
            else
                domain_verified=$((domain_verified + 1))
            fi

            # 13.3: Display name matches
            local saved_display live_display
            saved_display=$(jq -r "select(.EmailAddressId == \"$ea_id\") | .DisplayName // empty" "$instance_alias_dir/email_addresses.json" 2>/dev/null | dos2unix)
            live_display=$(echo "$live_ea" | jq -r '.EmailAddress.DisplayName // empty' | dos2unix)
            if [ -n "$saved_display" ] || [ -n "$live_display" ]; then
                if nullable_eq "$saved_display" "$live_display"; then
                    display_pass=$((display_pass + 1))
                else
                    display_fail=$((display_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Display name mismatch: $ea_addr (saved=$saved_display live=$live_display)" >&2
                fi
            else
                display_pass=$((display_pass + 1))
            fi
        else
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $ea_addr ($ea_id)" >&2
        fi
    done < <(jq -r '.EmailAddressId + "\t" + .EmailAddress' "$instance_alias_dir/email_addresses.json" 2>/dev/null | dos2unix)

    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "13.1" "All email addresses exist ($exist_pass/$email_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "13.1" "Email addresses" "$exist_fail of $email_count missing"
    fi

    if [ "$domain_pending" -eq 0 ] && [ "$domain_verified" -gt 0 ]; then
        pass "13.2" "All email domains verified ($domain_verified/$exist_pass)"
    elif [ "$domain_pending" -gt 0 ]; then
        warn "13.2" "Email domain status" "$domain_pending PENDING verification"
    fi

    if [ "$display_fail" -eq 0 ] && [ "$display_pass" -gt 0 ]; then
        pass "13.3" "Email display names match ($display_pass/$exist_pass)"
    elif [ "$display_fail" -gt 0 ]; then
        fail "13.3" "Email display names" "$display_fail mismatched"
    fi

    layer_end
}

############################################################
# Layer 14: Supporting Resources
############################################################

