############################################################
#
# Hours of Operations
#
# ORDER MATTERS. The override replay below resolves its parent
# hours-of-operation ID from $instance_alias_dir_b/hours.json, which is
# only refreshed by the create/update block (see "Hours of operations").
# The replay must therefore run AFTER that block, or overrides for newly
# created hours are silently skipped. See BACKLOG.md item B5.
#
# Queue → Quick Connect associations used to live here. They moved to
# features.sh, because quick connects do not exist until that section.
#

RESTORE_STEP=$((RESTORE_STEP + 1)); section_header "Hours of Operation" $RESTORE_STEP $RESTORE_TOTAL
############################################################
#
# Hours of operations
#

cat <<EOD

Hours of operations
-------------------
EOD
# Preload as $helper_old may change
egrep "^hour_" "$helper_old" > $TEMPOLD
# Create what is in $helper_new
egrep "^hour_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No hours of operations to create"
else
    num_hours=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_hours Hours of operations"
    ii=0
    sort $TEMPNEW |
    while read hour_json; do
        ii=$[ii+1]
        echo "$ii. $hour_json"
        hour_name=${hour_json#hour_}
        hour_name=${hour_name%.json}
        hour_name_decoded=$(path_decode "$hour_name")

        hour_id_a=$(jq -r ".HoursOfOperation.HoursOfOperationId" "$instance_alias_dir_a/$hour_json" | dos2unix)

        hour_desc=$(jq -r ".HoursOfOperation.Description | select(. != null)" "$instance_alias_dir_a/$hour_json" | dos2unix)
        # Description cannot be blank, or the AWS CLI will fail.
        if [ -z "$hour_desc" ]; then
            hour_desc=$hour_name_decoded
        fi

        cat "$instance_alias_dir_a/$hour_json" |
        jq --arg iid $instance_id_b --arg desc "$hour_desc" \
            ".HoursOfOperation | del(.HoursOfOperationId, .HoursOfOperationArn) | . + { InstanceId: \$iid} | . + { Description: \$desc}" |
            sed -f "$helper_sed" > "$helper/$hour_json"

        cat <<EOD >> "$helper_log"

$actionLead Create hours of operation: $hour_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create hours of operation
$(cat "$helper/$hour_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-hours-of-operation \
--cli-input-json "file://$helper/$hour_json" \
> "$helper/output_$hour_json"
EOD
            # rm "$helper/$hour_json"
            continue
        fi

        aws_connect create-hours-of-operation \
            --cli-input-json "file://$helper/$hour_json" \
            > "$helper/output_$hour_json" || error $LINENO
        hour_id_b=$(jq -r ".HoursOfOperationId" "$helper/output_$hour_json" | dos2unix)

        aws_connect describe-hours-of-operation \
            --instance-id $instance_id_b \
            --hours-of-operation-id $hour_id_b |\
            jq 'del(.HoursOfOperation.LastModifiedRegion, .HoursOfOperation.LastModifiedTime)' \
            > "$instance_alias_dir_b/$hour_json" || error $LINENO

        # Moving hour_json from helper_new to helper_old
        echo $hour_json >> "$helper_old"
        sed -e"/$hour_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Hour of operation: $hour_name_decoded
s%$hour_id_a%$hour_id_b%g
EOD
    done
    test $? -eq 0 || error

    if [ -z "$dryrun" ]; then
        # Update instance B hours
        aws_connect list-hours-of-operations \
            --instance-id $instance_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq '.HoursOfOperationSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' |
        jq -r ".HoursOfOperationSummaryList[]" > "$instance_alias_dir_b/hours.json"
    fi
fi

if [ ! -s $TEMPOLD ]; then
    echo "No hours of operations to update"
else
    num_hours=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_hours hours of operations for an update"
    ii=0
    sort $TEMPOLD |
    while read hour_json; do
        ii=$[ii+1]
        echo -n "$ii. $hour_json ... "
        hour_name=${hour_json#hour_}
        hour_name=${hour_name%.json}
        hour_name_decoded=$(path_decode "$hour_name")
        cat "$instance_alias_dir_a/$hour_json" > $TEMPA
        cat "$instance_alias_dir_b/$hour_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $hour_json"

        hour_id_b=$(jq -r ".HoursOfOperation.HoursOfOperationId" "$instance_alias_dir_b/$hour_json" | dos2unix)
        arg_flags=$(cat "$instance_alias_dir_b/$hour_json" |
            jq -r ".HoursOfOperation | \"--arg id \" + .HoursOfOperationId" | dos2unix)
        cat "$instance_alias_dir_a/$hour_json" |
        jq --arg iid $instance_id_b $arg_flags \
            ".HoursOfOperation | del(.HoursOfOperationArn, .Tags) | . + { InstanceId: \$iid, HoursOfOperationId: \$id }" \
            > "$helper/$hour_json"

        cat <<EOD >> "$helper_log"

$actionLead Update hours of operation: $hour_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update hours of operation
$(cat "$helper/$hour_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-hours-of-operation \
--cli-input-json "file://$helper/$hour_json" \
> "$helper/output_$hour_json"
EOD
            # rm "$helper/$hour_json"
            continue
        fi

        aws_connect update-hours-of-operation \
            --cli-input-json "file://$helper/$hour_json" \
            > "$helper/output_$hour_json" || error $LINENO

        aws_connect describe-hours-of-operation \
            --instance-id $instance_id_b \
            --hours-of-operation-id $hour_id_b |\
            jq 'del(.HoursOfOperation.LastModifiedRegion, .HoursOfOperation.LastModifiedTime)' \
            > "$instance_alias_dir_b/$hour_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
#
# Hours of Operations Override Replay
#

cat <<EOD

Hours of Operation Overrides
-----------------------------
EOD
if [ -s "$instance_alias_dir_a/hours.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/hours.json" |
    dos2unix |
    while read hour_id_a hour_name; do
        hour_name_encoded=$(path_encode "$hour_name")
        override_file="$instance_alias_dir_a/hourOverrides_$hour_name_encoded.json"
        [ -f "$override_file" ] || continue

        override_count=$(jq ".HoursOfOperationOverrideList | length" "$override_file" 2>/dev/null)
        [ -z "$override_count" ] || [ "$override_count" -eq 0 ] && continue

        hour_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/hours.json" 2>/dev/null | jq -r "select(.Name == \"${hour_name//\"/%22}\") | .Id" | dos2unix)
        [ -z "$hour_id_b" ] && continue

        echo "Applying $override_count overrides to hours of operation $hour_name"
        jq -r ".HoursOfOperationOverrideList[]" "$override_file" |
        jq -s ".[]" |
        dos2unix |
        while IFS= read -r override_json; do
            override_payload=$(echo "$override_json" |
                jq --arg iid $instance_id_b --arg hid $hour_id_b \
                    "del(.HoursOfOperationOverrideId, .LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid, HoursOfOperationId: \$hid }")

            cat <<EOD >> "$helper_log"

$actionLead Create hours of operation override for: $hour_name
EOD
            if [ -n "$dryrun" ]; then
                cat <<EOD
Dry-create hours of operation override for $hour_name

EOD
                cat <<EOD >> "$helper_log"
aws connect create-hours-of-operation-override \
--instance-id $instance_id_b \
--hours-of-operation-id $hour_id_b
EOD
            else
                echo "$override_payload" > "$helper/override_${hour_name_encoded}_tmp.json"
                # Report failures instead of suppressing them, but keep the
                # non-zero status away from the "test $? -eq 0 || error" guard
                # below — error() calls exit 1, and because run_section sources
                # this file that would abort the entire restore. Both branches
                # end on a zero-status command by design. See BACKLOG.md B5.
                if aws_connect create-hours-of-operation-override \
                        --instance-id $instance_id_b \
                        --hours-of-operation-id $hour_id_b \
                        --cli-input-json "file://$helper/override_${hour_name_encoded}_tmp.json" \
                        > /dev/null; then
                    echo -e "    ${C_PASS}✓${C_RESET} Override applied to '$hour_name'"
                else
                    echo -e "    ${C_FAIL}✗${C_RESET} Override FAILED for '$hour_name' (AWS error above)" >&2
                    manual_action "Hours Overrides" "Override for hours of operation '$hour_name' was not applied. Re-apply in the console, or re-run connect_restore."
                fi
            fi
        done
    done
    test $? -eq 0 || error
else
    echo "No hours of operation overrides to process"
fi


############################################################
#
# Connect Cases — now automated in Supporting Resources section
#

echo ""
echo "Connect Cases: handled in Supporting Resources section"


############################################################
#
# Outbound Campaigns
#

cat <<EOD

Outbound Campaigns
------------------
EOD
if [ -s "$instance_alias_dir_a/campaigns.json" ]; then
    jq -r ".id + \" \" + .name" "$instance_alias_dir_a/campaigns.json" 2>/dev/null |
    dos2unix |
    while read camp_id camp_name; do
        echo "  Campaign: $camp_name"
        manual_action "Campaigns" "Recreate campaign '$camp_name' on target. Source: $instance_alias_dir_a/campaigns.json"
    done
else
    echo "No outbound campaigns to process"
fi


############################################################
