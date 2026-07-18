############################################################
#
# Phone Number → Contact Flow Associations
#

section_header "Channels & Phone Numbers"
if [ -s "$instance_alias_dir_a/phonenumbers.json" ]; then
    jq -r ".PhoneNumberId + \" \" + .PhoneNumber" "$instance_alias_dir_a/phonenumbers.json" |
    dos2unix |
    while read pn_id_a pn_number; do
        pn_encoded=$(path_encode "$pn_number")
        pn_file="$instance_alias_dir_a/phonenumber_$pn_encoded.json"
        [ -f "$pn_file" ] || continue

        target_arn=$(jq -r ".ClaimedPhoneNumberSummary.TargetArn // empty" "$pn_file" | dos2unix)
        [ -z "$target_arn" ] && continue

        # Substitute instance ARN
        target_arn_b=$(echo "$target_arn" | sed -f "$helper_sed")
        pn_id_b=$(jq -r ".PhoneNumberId" "$instance_alias_dir_b/phonenumber_$pn_encoded.json" 2>/dev/null | dos2unix)
        if [ -z "$pn_id_b" ] || [ "$pn_id_b" = "null" ]; then
            manual_action "Phone Numbers" "Claim $pn_number on target instance and associate to contact flow"
            continue
        fi

        echo "Associating phone number $pn_number to flow"
        cat <<EOD >> "$helper_log"

$actionLead Associate phone number to flow: $pn_number
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-associate phone number $pn_number to $target_arn_b

EOD
            cat <<EOD >> "$helper_log"
aws connect associate-phone-number-contact-flow \
--phone-number-id $pn_id_b \
--instance-id $instance_id_b \
--contact-flow-id ${target_arn_b##*/}
EOD
        else
            flow_id_b="${target_arn_b##*/}"
            aws_connect associate-phone-number-contact-flow \
                --phone-number-id $pn_id_b \
                --instance-id $instance_id_b \
                --contact-flow-id $flow_id_b 2>/dev/null || true
        fi
    done
    test $? -eq 0 || error
else
    echo "No phone numbers to process"
fi


############################################################
