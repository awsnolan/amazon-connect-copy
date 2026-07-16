############################################################
#
# Contact Flow Modules Creation
# TODO:
#   - Use $helper/module_template.json as a template to create new contact flows
#
# Note: Must create all flow modules and flows from an empty template first
# such that references can be resolved in updates
#

cat <<EOD

Contact Flow Modules Creation
-----------------------------
EOD

# Preload as $helper_old may change
# Use TEMPMOD instead of TEMPOLD to carry over to module update
egrep "^module_$contact_flow_prefix_encoded" "$helper_old" > $TEMPMOD
# Create what is in $helper_new
egrep "^module_$contact_flow_prefix_encoded" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No contact flow modules$contact_flow_prefix_text to create"
else
    num_modules=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_modules contact flow modules$contact_flow_prefix_text"
    ii=0
    sort $TEMPNEW |
    while read module_json; do
        ii=$[ii+1]
        echo "$ii. $module_json"
        module_name=${module_json#module_}
        module_name=${module_name%.json}
        module_name_decoded=$(path_decode "$module_name")

        # module_id_a=$(jq -r "select(.Name == \"${module_name_decoded//\"/\\\"}\") | .Id" "$instance_alias_dir_a/modules.json")
        module_id_a=$(sed -e's/\\"/%22/g' "$instance_alias_dir_a/modules.json" | jq -r "select(.Name == \"${module_name_decoded//\"/%22}\") | .Id" | dos2unix)
        out_file="$helper/output_$module_json"

        # Contact Flow Module template file
        module_template_file=$helper/module_template.json

        # cat "$instance_alias_dir_a/$module_json" |
        # sed -f "$helper_sed" |
        # sub_lex_bot \
        # > "$helper/$module_json"

        cat <<EOD >> "$helper_log"

$actionLead Create contact flow module: $module_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create contact flow module
--instance-id $instance_id_b
--name "${module_name_decoded//\"/\\\"}"

EOD
            cat <<EOD >> "$helper_log"
aws connect create-contact-flow-module \
--instance-id $instance_id_b \
--name "${module_name_decoded//\"/\\\"}" \
--content "file://$module_template_file" \
> "$out_file"
EOD
            # rm "$helper/$module_json"
            continue
        fi

        aws_connect create-contact-flow-module \
            --instance-id $instance_id_b \
            --name "${module_name_decoded//\"/\\\"}" \
            --content "file://$module_template_file" \
            > "$out_file" || error $LINENO
        module_id_b=$(jq -r ".Id" "$out_file" | dos2unix)

        # All flow modules will be updated with content
        echo "$module_json" >> $TEMPMOD

        aws_connect describe-contact-flow-module \
            --instance-id $instance_id_b \
            --contact-flow-module-id $module_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r '.ContactFlowModule.Content' > "$instance_alias_dir_b/$module_json"

        # Moving module_json from helper_new to helper_old
        echo "$module_json" >> "$helper_old"
        sed -e"/$module_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Contact Flow Module: $module_name_decoded
s%$module_id_a%$module_id_b%g
EOD
    done
    test $? -eq 0 || error

    if [ -z "$dryrun" ]; then
        # Update instance B flow modules
        aws_connect list-contact-flow-modules \
            --instance-id $instance_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r ".ContactFlowModulesSummaryList[] | select(.Name | test(\"^($contact_flow_prefix|Default ).*\"))" \
        > "$instance_alias_dir_b/modules.json"
    fi
fi


############################################################
#
# Contact Flows Creation
#
# TODO:
#   - Use $helper/flow_template.json as a template to create new contact flows
#   - Use the Default special type contact flow to create special type contact flows
#   - Skip "Default " and "Sample " contact flows

cat <<EOD

Contact Flows Creation
----------------------
EOD

# Preload as $helper_old may change
egrep "^flow_$contact_flow_prefix_encoded" "$helper_old" | egrep -v "^flow_Default |^flow_Sample " > $TEMPOLD
# Create what is in $helper_new
egrep "^flow_$contact_flow_prefix_encoded" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No contact flows$contact_flow_prefix_text to create"
else
    num_flows=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_flows contact flows$contact_flow_prefix_text"
    ii=0
    sort $TEMPNEW |
    while read flow_json; do
        ii=$[ii+1]
        echo "$ii. $flow_json"
        flow_name=${flow_json#flow_}
        flow_name=${flow_name%.json}
        flow_name_decoded=$(path_decode "$flow_name")
        # flow_type=$(jq -r "select(.Name == \"${flow_name_decoded//\"/\\\"}\") | .ContactFlowType" "$instance_alias_dir_a/flows.json")
        flow_type=$(sed -e's/\\"/%22/g' "$instance_alias_dir_a/flows.json" | jq -r "select(.Name == \"${flow_name_decoded//\"/%22}\") | .ContactFlowType" | dos2unix)
        # flow_id_a=$(jq -r "select(.Name == \"${flow_name_decoded//\"/\\\"}\") | .Id" "$instance_alias_dir_a/flows.json")
        flow_id_a=$(sed -e's/\\"/%22/g' "$instance_alias_dir_a/flows.json" | jq -r "select(.Name == \"${flow_name_decoded//\"/%22}\") | .Id" | dos2unix)
        out_file="$helper/output_$flow_json"

        # Contact Flow template file
        flow_template_file=$helper/flow_template.json
        case "$flow_type" in
        CUSTOMER_QUEUE)
            flow_template_file="$instance_alias_dir_b/flow_Default%20customer%20queue.json";;
        CUSTOMER_HOLD)
            flow_template_file="$instance_alias_dir_b/flow_Default%20customer%20hold.json";;
        CUSTOMER_WHISPER)
            flow_template_file="$instance_alias_dir_b/flow_Default%20customer%20whisper.json";;
        AGENT_HOLD)
            flow_template_file="$instance_alias_dir_b/flow_Default%20agent%20hold.json";;
        AGENT_WHISPER)
            flow_template_file="$instance_alias_dir_b/flow_Default%20agent%20whisper.json";;
        OUTBOUND_WHISPER)
            flow_template_file="$instance_alias_dir_b/flow_Default%20outbound.json";;
        AGENT_TRANSFER)
            flow_template_file="$instance_alias_dir_b/flow_Default%20agent%20transfer.json";;
        QUEUE_TRANSFER)
            flow_template_file="$instance_alias_dir_b/flow_Default%20queue%20transfer.json";;
        esac

        cat <<EOD >> "$helper_log"

$actionLead Create contact flow: $flow_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create contact flow from Template (Default flows)
--instance-id $instance_id_b
--name "${flow_name_decoded//\"/\\\"}"
--type $flow_type

EOD
            cat <<EOD >> "$helper_log"
aws connect create-contact-flow \
--instance-id $instance_id_b \
--name "${flow_name_decoded//\"/\\\"}" \
--type $flow_type \
--content "file://$flow_template_file" \
> "$out_file"
EOD
            continue
        fi

        aws_connect create-contact-flow \
            --instance-id $instance_id_b \
            --name "${flow_name_decoded//\"/\\\"}" \
            --type $flow_type \
            --content "file://$flow_template_file" \
            > "$out_file" || error $LINENO
        flow_id_b=$(jq -r ".ContactFlowId" "$out_file" | dos2unix)

        # All flows will be updated with content
        echo "$flow_json" >> $TEMPOLD

        aws_connect describe-contact-flow \
            --instance-id $instance_id_b \
            --contact-flow-id $flow_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r '.ContactFlow.Content' > "$instance_alias_dir_b/$flow_json"

        # Moving flow_json from helper_new to helper_old
        echo "$flow_json" >> "$helper_old"
        sed -e"/$flow_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Contact Flow: $flow_name_decoded
s%$flow_id_a%$flow_id_b%g
EOD
    done
    test $? -eq 0 || error

    if [ -z "$dryrun" ]; then
        # Update instance B flows
        aws_connect list-contact-flows \
            --instance-id $instance_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r ".ContactFlowSummaryList[] | select(.Name | test(\"^($contact_flow_prefix|Default ).*\"))" \
        > "$instance_alias_dir_b/flows.json"
    fi
fi


############################################################
#
# Contact Flow Modules Update
#

cat <<EOD

Contact Flow Modules Update
---------------------------
EOD

if [ ! -s $TEMPMOD ]; then
    echo "No contact flow modules to update"
else
    num_modules=$(echo $(cat $TEMPMOD | wc -l))
    echo -e "\nChecking $num_modules contact flow modules$contact_flow_prefix_text for an update"
    ii=0
    sort $TEMPMOD |
    while read module_json; do
        ii=$[ii+1]
        echo -n "$ii. $module_json ... "
        module_name=${module_json#module_}
        module_name=${module_name%.json}
        module_name_decoded=$(path_decode "$module_name")

        # module_id_b=$(jq -r "select(.Name == \"${module_name_decoded//\"/\\\"}\") | .Id" "$instance_alias_dir_b/modules.json")
        module_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/modules.json" | jq -r "select(.Name == \"${module_name_decoded//\"/%22}\") | .Id" | dos2unix)
        module_desc=$(cat "$instance_alias_dir_a/modules.json" | jq -r "select(.Name == \"${module_name_decoded//\"/%22}\") | .Description | select(. != null)" | dos2unix)
        # Description cannot be blank, or the AWS CLI will fail.
        if [ -z "$module_desc" ]; then
            module_desc=$module_name_decoded
        fi

        cat "$instance_alias_dir_a/$module_json" > $TEMPA
        cat "$instance_alias_dir_b/$module_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue

        cat "$instance_alias_dir_a/$module_json" |
        sed -f "$helper_sed" |
        sub_lex_bot \
        > "$helper/$module_json"

        cat <<EOD >> "$helper_log"

$actionLead Update contact flow module: $module_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update contact flow module
--instance-id $instance_id_b
--contact-flow-module-id $module_id_b

EOD
            check_contact_flow $helper/$module_json || cat $TEMPCHK >> "$helper_log"
            cat <<EOD >> "$helper_log"
aws connect update-contact-flow-module-content \
--instance-id $instance_id_b \
--contact-flow-module-id $module_id_b \
--content "file://$helper/$module_json" \
> "$helper/output_content_$module_json"
aws connect update-contact-flow-module-metadata \
--instance-id $instance_id_b \
--contact-flow-module-id $module_id_b \
--description "${module_desc//\"/\\\"}" \
>> "$helper/output_content_$module_json"
EOD
            # rm "$helper/$module_json"
            continue
        fi

        check_contact_flow $helper/$module_json
        if [ $? -ne 0 ]; then
            cat $TEMPCHK >> "$helper_log"
            # Continue to handle error
        fi

        aws_connect update-contact-flow-module-content \
            --instance-id $instance_id_b \
            --contact-flow-module-id $module_id_b \
            --content "file://$helper/$module_json" \
            > "$helper/output_content_$module_json" || error $LINENO

        aws_connect update-contact-flow-module-metadata \
            --instance-id $instance_id_b \
            --contact-flow-module-id $module_id_b \
            --description "${module_desc//\"/\\\"}" \
            >> "$helper/output_content_$module_json" || error $LINENO

        aws_connect describe-contact-flow-module \
            --instance-id $instance_id_b \
            --contact-flow-module-id $module_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r '.ContactFlowModule.Content' > "$instance_alias_dir_b/$module_json"
    done
    test $? -eq 0 || error
fi


############################################################
#
# Contact Flows Update
#

cat <<EOD

Contact Flows Update
--------------------
EOD

if [ ! -s $TEMPOLD ]; then
    echo "No contact flows to update"
else
    num_flows=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_flows contact flows$contact_flow_prefix_text for an update"
    ii=0
    sort $TEMPOLD |
    while read flow_json; do
        ii=$[ii+1]
        echo -n "$ii. $flow_json ... "
        flow_name=${flow_json#flow_}
        flow_name=${flow_name%.json}
        flow_name_decoded=$(path_decode "$flow_name")
        # flow_id_b=$(jq -r "select(.Name == \"${flow_name_decoded//\"/\\\"}\") | .Id" "$instance_alias_dir_b/flows.json")
        flow_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/flows.json" | jq -r "select(.Name == \"${flow_name_decoded//\"/%22}\") | .Id" | dos2unix)
        flow_desc=$(cat "$instance_alias_dir_a/flows.json" | jq -r "select(.Name == \"${flow_name_decoded//\"/%22}\") | .Description | select(. != null)" | dos2unix)
        # Description cannot be blank, or the AWS CLI will fail.
        if [ -z "$flow_desc" ]; then
            flow_desc=$flow_name_decoded
        fi

        cat "$instance_alias_dir_a/$flow_json" > $TEMPA
        cat "$instance_alias_dir_b/$flow_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue

        cat "$instance_alias_dir_a/$flow_json" |
        sed -f "$helper_sed" |
        sub_lex_bot \
        > "$helper/$flow_json"

        cat <<EOD >> "$helper_log"

$actionLead Update contact flow: $flow_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update contact flow
--instance-id $instance_id_b
--contact-flow-id $flow_id_b

EOD
            check_contact_flow $helper/$flow_json || cat $TEMPCHK >> "$helper_log"
            cat <<EOD >> "$helper_log"
aws connect update-contact-flow-content \
--instance-id $instance_id_b \
--contact-flow-id $flow_id_b \
--content "file://$helper/$flow_json" \
> "$helper/output_content_$flow_json"
aws connect update-contact-flow-metadata \
--instance-id $instance_id_b \
--contact-flow-id $flow_id_b \
--description "${flow_desc//\"/\\\"}" \
>> "$helper/output_content_$flow_json"
EOD
            # rm "$helper/$flow_json"
            continue
        fi

        check_contact_flow $helper/$flow_json
        if [ $? -ne 0 ]; then
            cat $TEMPCHK >> "$helper_log"
            # Continue to handle error
        fi

        aws_connect update-contact-flow-content \
            --instance-id $instance_id_b \
            --contact-flow-id $flow_id_b \
            --content "file://$helper/$flow_json" \
            > "$helper/output_content_$flow_json" || error $LINENO

        aws_connect update-contact-flow-metadata \
            --instance-id $instance_id_b \
            --contact-flow-id $flow_id_b \
            --description "${flow_desc//\"/\\\"}" \
            >> "$helper/output_content_$flow_json" || error $LINENO

        aws_connect describe-contact-flow \
            --instance-id $instance_id_b \
            --contact-flow-id $flow_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r '.ContactFlow.Content' > "$instance_alias_dir_b/$flow_json"
    done
    test $? -eq 0 || error
fi


############################################################
#
# Contact flows and modules association with Lambda functions
#

lambdaArnLead=arn:aws:lambda:$region_b:$aws_ac_b:function:
cat \
    "$instance_alias_dir_b/flow_${contact_flow_prefix_encoded}"* \
    "$instance_alias_dir_b/module_${contact_flow_prefix_encoded}"* 2> /dev/null |
    jq -r ".Actions[] | select(.Type == \"InvokeLambdaFunction\") | .Parameters.LambdaFunctionARN" |
    grep "$lambdaArnLead" |
    sort -u > $TEMPFILE

if [ -s $TEMPFILE ]; then
    echo
    echo Associating Lambda functions to $instance_alias_b
    # Use "aws connect" instead of "aws_connect" to avoid logging
    aws connect list-lambda-functions \
        $profile_flag \
        --instance-id $instance_id_b \
        > $TEMPOLD || error $LINENO
    cat $TEMPOLD |
    jq -r ".LambdaFunctions" > "$helper/lambdas.json"

    ii=0
    cat $TEMPFILE |
    while read lambdaArn; do
        ii=$[ii+1]
        echo -n "$ii. $lambdaArn ... "
        lambdaExists=$(echo $(cat "$helper/lambdas.json" | jq ".[] | select(. == \"$lambdaArn\")" | wc -l))
        if [ "$lambdaExists" -gt 0 ]; then
            echo "already associated"
            continue
        fi
        echo "to be associated"

        cat <<EOD >> "$helper_log"

$actionLead Associate Lambda function: $lambdaArn
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-associating lambda function
--instance-id $instance_id_b \
--function-arn $lambdaArn \


EOD
            cat <<EOD >> "$helper_log"

aws connect associate-lambda-function \
--instance-id $instance_id_b \
--function-arn $lambdaArn
EOD
            continue
        fi
        aws_connect associate-lambda-function \
            --instance-id $instance_id_b \
            --function-arn $lambdaArn || error $LINENO
    done
fi


############################################################
#
# Contact flows and modules association with Lex bots
#
instance_alias_dir_to_discover=$instance_alias_dir_b
if [ -n "$dryrun" ]; then
    instance_alias_dir_to_discover=$instance_alias_dir_a
fi

cat \
    "$instance_alias_dir_to_discover/flow_${contact_flow_prefix_encoded}"* \
    "$instance_alias_dir_to_discover/module_${contact_flow_prefix_encoded}"* 2> /dev/null |
    jq -r ".Actions[] |
select(.Type == \"ConnectParticipantWithLexBot\") |
.Parameters.LexBot |
select(. != null) |
\"Name=\" + .Name + \",LexRegion=\" + .Region" |
    sort -u > $TEMPFILE

if [ -s $TEMPFILE ]; then
    echo
    echo "Associating Lex bots (Classic) to $instance_alias_b"
    cat $TEMPFILE
    # Use "aws connect" instead of "aws_connect" to avoid logging
    aws connect list-lex-bots \
        $profile_flag \
        --instance-id $instance_id_b \
        > $TEMPOLD || error $LINENO
    cat $TEMPOLD |
    jq -r ".LexBots" > "$helper/lex-bots.json"

    ii=0
    cat $TEMPFILE |
    while read lexBot; do
        ii=$[ii+1]
        echo -n "$ii. $lexBot ... "
        lexBotName=${lexBot%%,*}
        lexBotName=${lexBotName#Name=}
        lexBotExists=$(echo $(cat "$helper/lex-bots.json" | jq ".[] | select(.Name == \"$lexBotName\")" | wc -l))
        if [ "$lexBotExists" -gt 0 ]; then
            echo "already associated"
            continue
        fi
        echo "to be associated"

        cat <<EOD >> "$helper_log"

$actionLead Associate Lex Bot (Classic): $lexBot
EOD
        if [ -n "$dryrun" ]; then
            if [ -n "$lex_bot_prefix_a" -o -n "$lex_bot_prefix_b" ]; then
                lexBot=$(echo "$lexBot" | sed -e"s/^Name=$lex_bot_prefix_a/Name=$lex_bot_prefix_b/")
            fi
            cat <<EOD
Dry-associating lex bot
--instance-id $instance_id_b \
--lex-bot $lexBot \


EOD
            cat <<EOD >> "$helper_log"

aws connect associate-lex-bot \
--instance-id $instance_id_b \
--lex-bot $lexBot
EOD
            continue
        fi
        aws_connect associate-lex-bot \
            --instance-id $instance_id_b \
            --lex-bot $lexBot || error $LINENO
    done
fi




############################################################
