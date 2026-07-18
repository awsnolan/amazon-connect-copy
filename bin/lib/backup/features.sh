############################################################
# backup/features.sh — Quick connects, agent statuses,
#                      security profiles, predefined attributes
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE, $jq_prefix_filter, $jq_prefix_filter_text
############################################################

echo ""
echo "━━━ Features & Access ━━━"

############################################################
# Quick Connects
############################################################

aws_connect list-quick-connects \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r '[.QuickConnectSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/quickconnects.json"
echo -e "\n$(jq -s "length") quick connects listed in \"$instance_alias_dir/quickconnects.json\"$jq_prefix_filter_text"

jq -r ".Id + \" \" + .Name" "$instance_alias_dir/quickconnects.json" |
dos2unix |
while read qc_id qc_name; do
    echo "Exporting quick connect $qc_name"
    qc_name_encoded=$(path_encode "$qc_name")
    aws_connect describe-quick-connect \
        --instance-id $instance_id \
        --quick-connect-id $qc_id |\
        jq 'del(.QuickConnect.LastModifiedRegion, .QuickConnect.LastModifiedTime)' \
        > "$instance_alias_dir/quickconnect_$qc_name_encoded.json" || error $LINENO
done
test $? -eq 0 || error

############################################################
# Agent Statuses
############################################################

aws_connect list-agent-statuses \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r '[.AgentStatusSummaryList[] | select(.Type == \"CUSTOM\")$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/agentstatuses.json"
echo -e "\n$(jq -s "length") agent statuses listed in \"$instance_alias_dir/agentstatuses.json\"$jq_prefix_filter_text"

jq -r ".Id + \" \" + .Name" "$instance_alias_dir/agentstatuses.json" |
dos2unix |
while read as_id as_name; do
    echo "Exporting agent status $as_name"
    as_name_encoded=$(path_encode "$as_name")
    aws_connect describe-agent-status \
        --instance-id $instance_id \
        --agent-status-id $as_id \
        > "$instance_alias_dir/agentstatus_$as_name_encoded.json" || error $LINENO
done
test $? -eq 0 || error

############################################################
# Security Profiles
############################################################

aws_connect list-security-profiles \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r '[.SecurityProfileSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/securityprofiles.json"
echo -e "\n$(jq -s "length") security profiles listed in \"$instance_alias_dir/securityprofiles.json\"$jq_prefix_filter_text"

jq -r ".Id + \" \" + .Name" "$instance_alias_dir/securityprofiles.json" |
dos2unix |
while read sp_id sp_name; do
    echo "Exporting security profile $sp_name"
    sp_name_encoded=$(path_encode "$sp_name")
    aws_connect describe-security-profile \
        --instance-id $instance_id \
        --security-profile-id $sp_id \
        > "$instance_alias_dir/securityprofile_$sp_name_encoded.json" || error $LINENO
    aws_connect list-security-profile-permissions \
        --instance-id $instance_id \
        --security-profile-id $sp_id \
        --max-items $maxitems \
        > "$instance_alias_dir/securityprofilePerms_$sp_name_encoded.json" || error $LINENO
done
test $? -eq 0 || error

############################################################
# Predefined Attributes
############################################################

aws_connect list-predefined-attributes \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.PredefinedAttributeSummaryList // [] | sort_by(.Name) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/predefinedattributes.json"
    echo -e "\n$(jq -s "length") predefined attributes listed in \"$instance_alias_dir/predefinedattributes.json\""

    jq -r ".Name" "$instance_alias_dir/predefinedattributes.json" |
    dos2unix |
    while read pa_name; do
        echo "Exporting predefined attribute $pa_name"
        pa_name_encoded=$(path_encode "$pa_name")
        describe_or_skip "$pa_name" "$instance_alias_dir/predefinedattribute_$pa_name_encoded.json" \
            aws_connect describe-predefined-attribute \
            --instance-id $instance_id \
            --name "$pa_name" || true
    done
    test $? -eq 0 || error
else
    echo "No predefined attributes found"
    echo "[]" > "$instance_alias_dir/predefinedattributes.json"
fi
