############################################################
#
# Quick Connects
#

cat <<EOD

Quick Connects
--------------
EOD
# Preload as $helper_old may change
egrep "^quickconnect_" "$helper_old" > $TEMPOLD
# Create what is in $helper_new
egrep "^quickconnect_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No quick connects to create"
else
    num_qcs=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_qcs quick connects"
    ii=0
    sort $TEMPNEW |
    while read qc_json; do
        ii=$[ii+1]
        echo "$ii. $qc_json"
        qc_name=${qc_json#quickconnect_}
        qc_name=${qc_name%.json}
        qc_name_decoded=$(path_decode "$qc_name")

        qc_id_a=$(jq -r ".QuickConnect.QuickConnectId" "$instance_alias_dir_a/$qc_json" | dos2unix)

        cat "$instance_alias_dir_a/$qc_json" |
        jq --arg iid $instance_id_b \
            ".QuickConnect | del(.QuickConnectId, .QuickConnectARN, .LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$qc_json"

        cat <<EOD >> "$helper_log"

$actionLead Create quick connect: $qc_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create quick connect
$(cat "$helper/$qc_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-quick-connect \
--cli-input-json "file://$helper/$qc_json" \
> "$helper/output_$qc_json"
EOD
            continue
        fi

        aws_connect create-quick-connect \
            --cli-input-json "file://$helper/$qc_json" \
            > "$helper/output_$qc_json" || error $LINENO
        qc_id_b=$(jq -r ".QuickConnectId" "$helper/output_$qc_json" | dos2unix)

        aws_connect describe-quick-connect \
            --instance-id $instance_id_b \
            --quick-connect-id $qc_id_b |\
            jq 'del(.QuickConnect.LastModifiedRegion, .QuickConnect.LastModifiedTime)' \
            > "$instance_alias_dir_b/$qc_json" || error $LINENO

        echo $qc_json >> "$helper_old"
        sed -e"/$qc_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Quick Connect: $qc_name_decoded
s%$qc_id_a%$qc_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No quick connects to update"
else
    num_qcs=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_qcs quick connects for an update"
    ii=0
    sort $TEMPOLD |
    while read qc_json; do
        ii=$[ii+1]
        echo -n "$ii. $qc_json ... "
        cat "$instance_alias_dir_a/$qc_json" > $TEMPA
        cat "$instance_alias_dir_b/$qc_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $qc_json"

        qc_id_b=$(jq -r ".QuickConnect.QuickConnectId" "$instance_alias_dir_b/$qc_json" | dos2unix)

        cat "$instance_alias_dir_a/$qc_json" |
        jq --arg iid $instance_id_b --arg qcid $qc_id_b \
            ".QuickConnect | del(.QuickConnectARN, .Tags, .LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid, QuickConnectId: \$qcid }" |
        sed -f "$helper_sed" > "$helper/$qc_json"

        cat <<EOD >> "$helper_log"

$actionLead Update quick connect: $qc_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update quick connect
$(cat "$helper/$qc_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-quick-connect-config \
--instance-id $instance_id_b \
--quick-connect-id $qc_id_b \
--quick-connect-config "$(jq -r '.QuickConnectConfig' "$helper/$qc_json")"
EOD
            continue
        fi

        qc_config=$(cat "$helper/$qc_json" | jq -r '.QuickConnectConfig' | sed -f "$helper_sed")
        aws_connect update-quick-connect-config \
            --instance-id $instance_id_b \
            --quick-connect-id $qc_id_b \
            --quick-connect-config "$qc_config" || error $LINENO

        aws_connect describe-quick-connect \
            --instance-id $instance_id_b \
            --quick-connect-id $qc_id_b |\
            jq 'del(.QuickConnect.LastModifiedRegion, .QuickConnect.LastModifiedTime)' \
            > "$instance_alias_dir_b/$qc_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
#
# Agent Statuses
#

cat <<EOD

Agent Statuses
--------------
EOD
egrep "^agentstatus_" "$helper_old" > $TEMPOLD
egrep "^agentstatus_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No agent statuses to create"
else
    num_as=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_as agent statuses"
    ii=0
    sort $TEMPNEW |
    while read as_json; do
        ii=$[ii+1]
        echo "$ii. $as_json"
        as_name=${as_json#agentstatus_}
        as_name=${as_name%.json}
        as_name_decoded=$(path_decode "$as_name")

        as_id_a=$(jq -r ".AgentStatus.AgentStatusId" "$instance_alias_dir_a/$as_json" | dos2unix)

        cat "$instance_alias_dir_a/$as_json" |
        jq --arg iid $instance_id_b \
            ".AgentStatus | del(.AgentStatusId, .AgentStatusARN, .Type, .LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$as_json"

        cat <<EOD >> "$helper_log"

$actionLead Create agent status: $as_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create agent status
$(cat "$helper/$as_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-agent-status \
--cli-input-json "file://$helper/$as_json" \
> "$helper/output_$as_json"
EOD
            continue
        fi

        aws_connect create-agent-status \
            --cli-input-json "file://$helper/$as_json" \
            > "$helper/output_$as_json" || error $LINENO
        as_id_b=$(jq -r ".AgentStatusId" "$helper/output_$as_json" | dos2unix)

        aws_connect describe-agent-status \
            --instance-id $instance_id_b \
            --agent-status-id $as_id_b \
            > "$instance_alias_dir_b/$as_json" || error $LINENO

        echo $as_json >> "$helper_old"
        sed -e"/$as_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Agent Status: $as_name_decoded
s%$as_id_a%$as_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No agent statuses to update"
else
    num_as=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_as agent statuses for an update"
    ii=0
    sort $TEMPOLD |
    while read as_json; do
        ii=$[ii+1]
        echo -n "$ii. $as_json ... "
        as_name=${as_json#agentstatus_}
        as_name=${as_name%.json}
        as_name_decoded=$(path_decode "$as_name")
        cat "$instance_alias_dir_a/$as_json" > $TEMPA
        cat "$instance_alias_dir_b/$as_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $as_json"

        as_id_b=$(jq -r ".AgentStatus.AgentStatusId" "$instance_alias_dir_b/$as_json" | dos2unix)
        as_order=$(jq -r ".AgentStatus.DisplayOrder" "$instance_alias_dir_a/$as_json" | dos2unix)
        as_desc=$(jq -r ".AgentStatus.Description | select(. != null)" "$instance_alias_dir_a/$as_json" | dos2unix)
        as_state=$(jq -r ".AgentStatus.State" "$instance_alias_dir_a/$as_json" | dos2unix)

        cat <<EOD >> "$helper_log"

$actionLead Update agent status: $as_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update agent status $as_name_decoded

EOD
            cat <<EOD >> "$helper_log"
aws connect update-agent-status \
--instance-id $instance_id_b \
--agent-status-id $as_id_b \
--display-order $as_order \
--state $as_state
EOD
            continue
        fi

        aws_connect update-agent-status \
            --instance-id $instance_id_b \
            --agent-status-id $as_id_b \
            --display-order $as_order \
            --state $as_state || error $LINENO

        aws_connect describe-agent-status \
            --instance-id $instance_id_b \
            --agent-status-id $as_id_b \
            > "$instance_alias_dir_b/$as_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
#
# Security Profiles
#

cat <<EOD

Security Profiles
-----------------
EOD
egrep "^securityprofile_" "$helper_old" > $TEMPOLD
egrep "^securityprofile_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No security profiles to create"
else
    num_sp=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_sp security profiles"
    ii=0
    sort $TEMPNEW |
    while read sp_json; do
        ii=$[ii+1]
        echo "$ii. $sp_json"
        sp_name=${sp_json#securityprofile_}
        sp_name=${sp_name%.json}
        sp_name_decoded=$(path_decode "$sp_name")

        sp_id_a=$(jq -r ".SecurityProfile.Id" "$instance_alias_dir_a/$sp_json" | dos2unix)
        sp_perms_file="$instance_alias_dir_a/securityprofilePerms_$sp_name.json"
        sp_desc=$(jq -r ".SecurityProfile.Description | select(. != null)" "$instance_alias_dir_a/$sp_json" | dos2unix)
        if [ -z "$sp_desc" ]; then sp_desc=$sp_name_decoded; fi

        # Build create payload
        cat "$instance_alias_dir_a/$sp_json" |
        jq --arg iid $instance_id_b --arg desc "$sp_desc" \
            ".SecurityProfile | del(.Id, .Arn, .LastModifiedRegion, .LastModifiedTime, .OrganizationResourceId) | . + { InstanceId: \$iid, Description: \$desc }" |
        sed -f "$helper_sed" > "$helper/$sp_json"

        # Embed permissions array
        if [ -s "$sp_perms_file" ]; then
            perms_array=$(jq -r ".Permissions" "$sp_perms_file")
            cat "$helper/$sp_json" | jq --argjson perms "$perms_array" ". + { Permissions: \$perms }" > "${helper}/${sp_json}.tmp"
            mv "${helper}/${sp_json}.tmp" "$helper/$sp_json"
        fi

        cat <<EOD >> "$helper_log"

$actionLead Create security profile: $sp_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create security profile
$(cat "$helper/$sp_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-security-profile \
--cli-input-json "file://$helper/$sp_json" \
> "$helper/output_$sp_json"
EOD
            continue
        fi

        aws_connect create-security-profile \
            --cli-input-json "file://$helper/$sp_json" \
            > "$helper/output_$sp_json" || error $LINENO
        sp_id_b=$(jq -r ".SecurityProfileId" "$helper/output_$sp_json" | dos2unix)

        aws_connect describe-security-profile \
            --instance-id $instance_id_b \
            --security-profile-id $sp_id_b \
            > "$instance_alias_dir_b/$sp_json" || error $LINENO

        echo $sp_json >> "$helper_old"
        sed -e"/$sp_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Security Profile: $sp_name_decoded
s%$sp_id_a%$sp_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No security profiles to update"
else
    num_sp=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_sp security profiles for an update"
    ii=0
    sort $TEMPOLD |
    while read sp_json; do
        ii=$[ii+1]
        echo -n "$ii. $sp_json ... "
        cat "$instance_alias_dir_a/$sp_json" > $TEMPA
        cat "$instance_alias_dir_b/$sp_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Please update $sp_json manually considering potential permission impact."
    done
fi


############################################################
#
# Predefined Attributes
#

cat <<EOD

Predefined Attributes
---------------------
EOD
egrep "^predefinedattribute_" "$helper_old" > $TEMPOLD
egrep "^predefinedattribute_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No predefined attributes to create"
else
    num_pa=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_pa predefined attributes"
    ii=0
    sort $TEMPNEW |
    while read pa_json; do
        ii=$[ii+1]
        echo "$ii. $pa_json"
        pa_name=${pa_json#predefinedattribute_}
        pa_name=${pa_name%.json}
        pa_name_decoded=$(path_decode "$pa_name")

        cat "$instance_alias_dir_a/$pa_json" |
        jq --arg iid $instance_id_b \
            ".PredefinedAttribute | del(.LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$pa_json"

        cat <<EOD >> "$helper_log"

$actionLead Create predefined attribute: $pa_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create predefined attribute
$(cat "$helper/$pa_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-predefined-attribute \
--cli-input-json "file://$helper/$pa_json"
EOD
            continue
        fi

        aws_connect create-predefined-attribute \
            --cli-input-json "file://$helper/$pa_json" || error $LINENO

        aws_connect describe-predefined-attribute \
            --instance-id $instance_id_b \
            --name "$pa_name_decoded" \
            > "$instance_alias_dir_b/$pa_json" || error $LINENO

        echo $pa_json >> "$helper_old"
        sed -e"/$pa_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No predefined attributes to update"
else
    num_pa=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_pa predefined attributes for an update"
    ii=0
    sort $TEMPOLD |
    while read pa_json; do
        ii=$[ii+1]
        echo -n "$ii. $pa_json ... "
        pa_name=${pa_json#predefinedattribute_}
        pa_name=${pa_name%.json}
        pa_name_decoded=$(path_decode "$pa_name")
        cat "$instance_alias_dir_a/$pa_json" > $TEMPA
        cat "$instance_alias_dir_b/$pa_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $pa_json"

        cat "$instance_alias_dir_a/$pa_json" |
        jq --arg iid $instance_id_b \
            ".PredefinedAttribute | del(.LastModifiedRegion, .LastModifiedTime) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$pa_json"

        cat <<EOD >> "$helper_log"

$actionLead Update predefined attribute: $pa_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update predefined attribute
$(cat "$helper/$pa_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-predefined-attribute \
--cli-input-json "file://$helper/$pa_json"
EOD
            continue
        fi

        aws_connect update-predefined-attribute \
            --cli-input-json "file://$helper/$pa_json" || error $LINENO

        aws_connect describe-predefined-attribute \
            --instance-id $instance_id_b \
            --name "$pa_name_decoded" \
            > "$instance_alias_dir_b/$pa_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
