validate_layer_11() {
    layer_start 11 "Phone Numbers"

    if [ ! -f "$instance_alias_dir/phonenumbers.json" ]; then
        skip "11.1" "Phone numbers" "phonenumbers.json not found"
        layer_end; return
    fi

    local pn_count
    pn_count=$(jq -s 'length' "$instance_alias_dir/phonenumbers.json" 2>/dev/null)

    [ -z "$do_live" ] && {
        [ -n "$do_local" ] && pass "11.1" "Phone numbers manifest ($pn_count)"
        layer_end; return
    }

    local exist_pass=0 exist_fail=0
    local flow_pass=0 flow_fail=0 flow_total=0
    local type_pass=0 type_fail=0
    local country_pass=0 country_fail=0

    while IFS=$'\t' read -r pn_id pn_number; do
        [ -z "$pn_id" ] && continue

        local live_pn
        live_pn=$(aws_connect describe-phone-number --phone-number-id "$pn_id" 2>/dev/null)
        if [ -z "$live_pn" ]; then
            exist_fail=$((exist_fail + 1))
            [ -z "$JSON_OUTPUT" ] && echo "         → Missing: $pn_number ($pn_id)" >&2
            continue
        fi
        exist_pass=$((exist_pass + 1))

        # 11.2: Phone type match
        local saved_type live_type
        saved_type=$(jq -r "select(.PhoneNumberId == \"$pn_id\") | .PhoneNumberType // empty" "$instance_alias_dir/phonenumbers.json" 2>/dev/null | dos2unix)
        live_type=$(echo "$live_pn" | jq -r '.ClaimedPhoneNumberSummary.PhoneNumberType // empty' | dos2unix)
        if [ -n "$saved_type" ]; then
            if [ "$saved_type" = "$live_type" ]; then
                type_pass=$((type_pass + 1))
            else
                type_fail=$((type_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Phone type mismatch: $pn_number (saved=$saved_type live=$live_type)" >&2
            fi
        fi

        # 11.4: Country code match
        local saved_country live_country
        saved_country=$(jq -r "select(.PhoneNumberId == \"$pn_id\") | .PhoneNumberCountryCode // empty" "$instance_alias_dir/phonenumbers.json" 2>/dev/null | dos2unix)
        live_country=$(echo "$live_pn" | jq -r '.ClaimedPhoneNumberSummary.PhoneNumberCountryCode // empty' | dos2unix)
        if [ -n "$saved_country" ]; then
            if [ "$saved_country" = "$live_country" ]; then
                country_pass=$((country_pass + 1))
            else
                country_fail=$((country_fail + 1))
                [ -z "$JSON_OUTPUT" ] && echo "         → Country code mismatch: $pn_number (saved=$saved_country live=$live_country)" >&2
            fi
        fi

        # 11.3: Flow association
        local live_target
        live_target=$(echo "$live_pn" | jq -r '.ClaimedPhoneNumberSummary.TargetArn // empty' | dos2unix)
        if [ -n "$live_target" ] && [ "$live_target" != "null" ]; then
            # Only validate if target is a contact-flow ARN (not just the instance ARN)
            if [[ "$live_target" == *"/contact-flow/"* ]]; then
                flow_total=$((flow_total + 1))
                local flow_id_from_arn
                flow_id_from_arn=$(echo "$live_target" | sed 's|.*/contact-flow/||')
                local flow_check
                flow_check=$(aws_connect describe-contact-flow \
                    --instance-id "$instance_id" \
                    --contact-flow-id "$flow_id_from_arn" 2>/dev/null)
                if [ -n "$flow_check" ]; then
                    flow_pass=$((flow_pass + 1))
                else
                    flow_fail=$((flow_fail + 1))
                    [ -z "$JSON_OUTPUT" ] && echo "         → Flow target not found: $pn_number → $live_target" >&2
                fi
            fi
            # If TargetArn is just the instance ARN, no flow is assigned — skip silently
        fi
    done < <(jq -r '.PhoneNumberId + "\t" + .PhoneNumber' "$instance_alias_dir/phonenumbers.json" 2>/dev/null | dos2unix)

    if [ "$exist_fail" -eq 0 ] && [ "$exist_pass" -gt 0 ]; then
        pass "11.1" "All phone numbers exist ($exist_pass/$pn_count)"
    elif [ "$exist_fail" -gt 0 ]; then
        fail "11.1" "Phone numbers" "$exist_fail of $pn_count missing"
    fi

    if [ "$type_fail" -eq 0 ] && [ "$type_pass" -gt 0 ]; then
        pass "11.2" "Phone number types match ($type_pass/$exist_pass)"
    elif [ "$type_fail" -gt 0 ]; then
        fail "11.2" "Phone number types" "$type_fail mismatched"
    fi

    if [ "$flow_total" -gt 0 ]; then
        if [ "$flow_fail" -eq 0 ]; then
            pass "11.3" "Phone flow associations valid ($flow_pass/$flow_total)"
        else
            fail "11.3" "Phone flow associations" "$flow_fail broken"
        fi
    else
        skip "11.3" "Phone flow associations" "no numbers have flow targets"
    fi

    if [ "$country_fail" -eq 0 ] && [ "$country_pass" -gt 0 ]; then
        pass "11.4" "Phone country codes match ($country_pass/$exist_pass)"
    elif [ "$country_fail" -gt 0 ]; then
        fail "11.4" "Phone country codes" "$country_fail mismatched"
    fi

    layer_end
}

############################################################
# Layer 12: Integration Associations
############################################################

