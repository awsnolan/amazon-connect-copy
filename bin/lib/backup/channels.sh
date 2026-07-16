############################################################
# backup/channels.sh — Email addresses, attachment config,
#                      phone numbers
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE
############################################################

echo ""
echo "━━━ Channels & Phone Numbers ━━━"

############################################################
# Email Addresses
############################################################

aws_connect search-email-addresses \
    --instance-id $instance_id \
    --max-results 100 \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".EmailAddresses[]" |
    jq -s "sort_by(.EmailAddress) | .[]" |
    tee "$instance_alias_dir/email_addresses.json" |
    echo -e "\n$(jq -s "length") email addresses listed in \"$instance_alias_dir/email_addresses.json\""

    jq -r ".EmailAddressId + \" \" + .EmailAddress" "$instance_alias_dir/email_addresses.json" |
    dos2unix |
    while read ea_id ea_address; do
        echo "Exporting email address $ea_address"
        ea_encoded=$(path_encode "$ea_address")
        aws_connect describe-email-address \
            --instance-id $instance_id \
            --email-address-id $ea_id \
            > "$instance_alias_dir/emailaddress_$ea_encoded.json" 2>/dev/null || true
    done
    test $? -eq 0 || error
else
    echo "No email addresses found"
    echo "[]" > "$instance_alias_dir/email_addresses.json"
fi

############################################################
# Attachment Configuration
############################################################

aws_connect describe-instance-attribute \
    --instance-id $instance_id \
    --attribute-type "ATTACHMENTS" \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    attach_enabled=$(jq -r '.Attribute.Value // "false"' $TEMPFILE | dos2unix)
    if [ "$attach_enabled" = "true" ]; then
        aws_connect describe-attachment-configuration \
            --instance-id $instance_id \
            > "$instance_alias_dir/attachment_config.json" 2>/dev/null || true
        if [ -s "$instance_alias_dir/attachment_config.json" ]; then
            echo "Attachment configuration saved"
        else
            echo "Attachments enabled but configuration API not available"
            echo "{}" > "$instance_alias_dir/attachment_config.json"
        fi
    else
        echo "Attachments not enabled"
        echo "{}" > "$instance_alias_dir/attachment_config.json"
    fi
else
    echo "{}" > "$instance_alias_dir/attachment_config.json"
fi

############################################################
# Phone Numbers
############################################################

aws_connect list-phone-numbers-v2 \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".ListPhoneNumbersSummaryList[]" |
    jq -s "sort_by(.PhoneNumber) | .[]" |
    tee "$instance_alias_dir/phonenumbers.json" |
    echo -e "\n$(jq -s "length") phone numbers listed in \"$instance_alias_dir/phonenumbers.json\""

    jq -r ".PhoneNumberId + \" \" + .PhoneNumber" "$instance_alias_dir/phonenumbers.json" |
    dos2unix |
    while read pn_id pn_number; do
        echo "Exporting phone number $pn_number"
        pn_encoded=$(path_encode "$pn_number")
        aws_connect describe-phone-number \
            --phone-number-id $pn_id \
            > "$instance_alias_dir/phonenumber_$pn_encoded.json" || error $LINENO
    done
    test $? -eq 0 || error
else
    echo "No phone numbers found"
    echo "[]" > "$instance_alias_dir/phonenumbers.json"
fi
