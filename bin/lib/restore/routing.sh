############################################################
#
# Routing Profiles
#

gen_helper_rpqr() {
    # Routing Profile Queue Reference
    routing_name=$1
    out_file="$helper/routingQRs_$routing_name.json"
    cat "$instance_alias_dir_a/routingQs_$routing_name.json" |
    jq ".RoutingProfileQueueConfigSummaryList[] |
        { QueueReference: { QueueId, Channel }, Priority, Delay }" \
    > "$out_file"
    echo "$out_file"
}

gen_helper_routing_new() {
    # Must not have QueueConfigs in creation, leave it to association to handle >10 cases
    routing_name=$1
    out_file="$helper/routingNew_$routing_name.json"
    cat "$instance_alias_dir_a/routing_$routing_name.json" |
    jq --arg iid $instance_id_b \
        ".RoutingProfile |
        del(.RoutingProfileId, .RoutingProfileArn, .NumberOfAssociatedQueues,
            .NumberOfAssociatedUsers, .NumberOfAssociatedManualAssignmentQueues,
            .IsDefault, .LastModifiedRegion, .LastModifiedTime) |
        . + { InstanceId: \$iid } |
        del(.MediaConcurrencies[] | select(.Concurrency == 0))" |
    sed -f "$helper_sed" > "$out_file"
    echo "$out_file"
}

cat <<EOD

Routing Profiles
----------------
EOD
# Preload as $helper_old may change
egrep "^routing_" "$helper_old" > $TEMPOLD
# Create what is in $helper_new
egrep "^routing_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No routing profiles to create"
else
    num_routings=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_routings routing profiles"
    ii=0
    sort $TEMPNEW |
    while read routing_json; do
        ii=$[ii+1]
        echo "$ii. $routing_json"
        routing_name=${routing_json#routing_}
        routing_name=${routing_name%.json}
        routing_name_decoded=$(path_decode "$routing_name")

        routing_id_a=$(jq -r ".RoutingProfile.RoutingProfileId" "$instance_alias_dir_a/$routing_json" | dos2unix)
        routing_new_file=$(gen_helper_routing_new "$routing_name" | dos2unix)
        out_file="$helper/output_routing_new_$routing_name.json"

        cat <<EOD >> "$helper_log"

$actionLead Create routing profile: $routing_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create routing profile
$(cat "$routing_new_file")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-routing-profile \
--cli-input-json "file://$routing_new_file" \
> "$out_file"
EOD
            # rm "$routing_new_file"
            continue
        fi

        aws_connect create-routing-profile \
            --cli-input-json "file://$routing_new_file" \
            > "$out_file" || error $LINENO
        routing_id_b=$(jq -r ".RoutingProfileId" "$out_file" | dos2unix)

        # All routing profiles will be updated with queues
        echo "$routing_json" >> $TEMPOLD

        # Update instance B (even it is not final) to allow comparison in update
        aws_connect describe-routing-profile \
            --instance-id $instance_id_b \
            --routing-profile-id $routing_id_b |
            jq -r "del(.RoutingProfile.NumberOfAssociatedQueues, .RoutingProfile.NumberOfAssociatedUsers)" \
            > "$instance_alias_dir_b/$routing_json" || error $LINENO

        aws_connect list-routing-profile-queues \
            --instance-id $instance_id_b \
            --routing-profile-id $routing_id_b \
            > "$instance_alias_dir_b/routingQs_$routing_name.json" || error $LINENO

        # Moving routing_json from helper_new to helper_old
        echo "$routing_json" >> "$helper_old"
        sed -e"/$routing_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Routing Profile: $routing_name_decoded
s%$routing_id_a%$routing_id_b%g
EOD
    done
    test $? -eq 0 || error

    if [ -z "$dryrun" ]; then
        # Update instance B routing profiles
        aws_connect list-routing-profiles \
            --instance-id $instance_id_b \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r ".RoutingProfileSummaryList[]" > "$instance_alias_dir_b/routings.json"
    fi
fi

if [ ! -s $TEMPOLD ]; then
    echo "No routing profiles to update"
else
    num_routings=$(echo $(cat $TEMPOLD | wc -l))
    # echo $num_routings existing routing profiles: not to be auto-updated due to possible operation impact
    echo -e "\nChecking $num_routings routing profiles for an update"
    ii=0
    sort $TEMPOLD |
    while read routing_json; do
        ii=$[ii+1]
        echo -n "$ii. $routing_json ... "
        routing_name=${routing_json#routing_}
        routing_name=${routing_name%.json}
        routing_name_decoded=$(path_decode "$routing_name")

        cat "$instance_alias_dir_a/$routing_json" |
        jq "del(.RoutingProfile.MediaConcurrencies[] | select(.Concurrency == 0))" > $TEMPA
        cat "$instance_alias_dir_b/$routing_json" |
        jq "del(.RoutingProfile.MediaConcurrencies[] | select(.Concurrency == 0))" > $TEMPB
        # df=$(diff_files); echo $df; test "$df" == "same" && continue
        df_r=$(diff_files)

        cat "$instance_alias_dir_a/routingQs_$routing_name.json" > $TEMPA
        cat "$instance_alias_dir_b/routingQs_$routing_name.json" > $TEMPB
        # df=$(diff_files); echo $df; test "$df" == "same" && continue
        df_rq=$(diff_files)

        if [ "$df_r" == "same" -a "$df_rq" == "same" ]; then
            echo same
            continue
        fi

        echo " routing $df_r routing-queues $df_rq"
        echo "Updating $routing_json"

        # routing_old_file=$(gen_helper_routing_old "$routing_name")
        routing_id_b=$(jq -r ".RoutingProfile.RoutingProfileId" "$instance_alias_dir_b/$routing_json" | dos2unix)

        if [ "$df_r" != "same" ]; then
            # Update Routing Profile of Instance B ahead of time
            # then update the concurrency and default-outbound-queue.
            # (The name must have already matched.)
            if [ -z "$dryrun" ]; then
                cat "$instance_alias_dir_a/$routing_json" |
                sed -f "$helper_sed" > "$instance_alias_dir_b/$routing_json"
            fi

            routing_doq_b=$(cat "$instance_alias_dir_b/$routing_json" |
                jq -r ".RoutingProfile.DefaultOutboundQueueId" |
                dos2unix)

            cat "$instance_alias_dir_b/$routing_json" |
            jq -r ".RoutingProfile.MediaConcurrencies[] | select(.Concurrency != 0)" |
            jq -s "." > "$helper/routingConcurrency_$routing_name.json"

            cat <<EOD >> "$helper_log"

$actionLead Update routing profile: $routing_decoded
EOD
            if [ -n "$dryrun" ]; then
                cat <<EOD
Dry-update routing profile default outbound queue to "$routing_doq_b"
Dry-update routing profile concurrency
$(cat "$helper/routingConcurrency_$routing_name.json")

EOD
                cat <<EOD >> "$helper_log"
aws connect update-routing-profile-default-outbound-queue \
--instance-id $instance_id_b \
--routing-profile-id $routing_id_b \
--default-outbound-queue-id $routing_doq_b
aws connect update-routing-profile-concurrency \
--instance-id $instance_id_b \
--routing-profile-id $routing_id_b \
--media-concurrencies "file://$helper/routingConcurrency_$routing_name.json"
EOD
                # rm "$helper/routingConcurrency_$routing_name.json"
            else
                aws_connect update-routing-profile-default-outbound-queue \
                    --instance-id $instance_id_b \
                    --routing-profile-id $routing_id_b \
                    --default-outbound-queue-id $routing_doq_b || error $LINENO

                aws_connect update-routing-profile-concurrency \
                    --instance-id $instance_id_b \
                    --routing-profile-id $routing_id_b \
                    --media-concurrencies "file://$helper/routingConcurrency_$routing_name.json" || error $LINENO

                aws_connect describe-routing-profile \
                    --instance-id $instance_id_b \
                    --routing-profile-id $routing_id_b |
                    jq -r "del(.RoutingProfile.NumberOfAssociatedQueues, .RoutingProfile.NumberOfAssociatedUsers)" \
                    > "$instance_alias_dir_b/$routing_json" || error $LINENO
            fi
        fi

        if [ "$df_rq" != "same" ]; then

            cat "$instance_alias_dir_a/routingQs_$routing_name.json" |
                jq -r ".RoutingProfileQueueConfigSummaryList[].QueueName" |
                sort -u > $TEMPA
            cat "$instance_alias_dir_b/routingQs_$routing_name.json" |
                jq -r ".RoutingProfileQueueConfigSummaryList[].QueueName" |
                sort -u > $TEMPB
            > $TEMP1
            diff $TEMPA $TEMPB | grep "^< " | sed -e"s/^< //" > $TEMP2
            if [ -s $TEMP2 ]; then
                helper_rqc_json="$helper/routingQueueConfig_$routing_name.json"
                cat $TEMP2 |
                while read q_name; do
                    # cat "$instance_alias_dir_a/routingQs_$routing_name.json" |
                    #     jq -r ".RoutingProfileQueueConfigSummaryList[] | select(.QueueName == \"${q_name//\"/\\\"}\") | { QueueReference: { QueueId, Channel }, Priority, Delay }" >> $TEMP1
                    sed -e's/\\"/%22/g' "$instance_alias_dir_a/routingQs_$routing_name.json" |
                        jq -r ".RoutingProfileQueueConfigSummaryList[] | select(.QueueName == \"${q_name//\"/%22}\") | { QueueReference: { QueueId, Channel }, Priority, Delay }" >> $TEMP1
                done

                cat $TEMP1 | sed -f "$helper_sed" | jq -s "." > "$helper_rqc_json"

                cat <<EOD >> "$helper_log"

$actionLead Associate queues to routing profile: $routing_name_decoded
EOD
                num_queue_configs=$(cat "$helper_rqc_json" | jq "length")
                if [ -n "$dryrun" ]; then
                    cat <<EOD
Dry-associate queues to routing profile $routing_name_decoded
$(cat $TEMP2)

EOD
# $(cat $TEMPFILE)
                    if [ "$num_queue_configs" -ge "$AWS_CLI_MAX_QUEUE_CONFIGS" ]; then
                        echo "# The $num_queue_configs queue configs will be split into lots of $AWS_CLI_MAX_QUEUE_CONFIGS in dry-run mode." >> "$helper_log"
                    fi
                    cat <<EOD >> "$helper_log"
aws connect associate-routing-profile-queues \
--instance-id $instance_id_b \
--routing-profile-id $routing_id_b \
--queue-configs "file://$helper_rqc_json"
EOD
                    # rm "$helper_rqc_json"
                else
                    # cat $TEMP2
                    # aws_connect associate-routing-profile-queues \
                    #     --instance-id $instance_id_b \
                    #     --routing-profile-id $routing_id_b \
                    #     --queue-configs "file://$helper_rqc_json" || error $LINENO
                    # echo $num_queue_configs Queue Configs
                    iii=0
                    while [ "$iii" -lt "$num_queue_configs" ]; do
                        jjj=$[iii+AWS_CLI_MAX_QUEUE_CONFIGS]
                        arg_queue_configs="'$(cat "$helper_rqc_json" | jq ".[$iii:$jjj]")'"
                        aws_connect associate-routing-profile-queues \
                            --instance-id $instance_id_b \
                            --routing-profile-id $routing_id_b \
                            --queue-configs $arg_queue_configs || error $LINENO
                        iii=$jjj
                    done
                fi
            fi

            if [ -z "$dryrun" ]; then
                aws_connect list-routing-profile-queues \
                    --instance-id $instance_id_b \
                    --routing-profile-id $routing_id_b \
                    > "$instance_alias_dir_b/routingQs_$routing_name.json" || error $LINENO
            fi
        fi
    done
    test $? -eq 0 || error
fi


############################################################
