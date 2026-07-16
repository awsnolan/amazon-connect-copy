############################################################
#
# Queues
#

cat <<EOD

Queues
------
EOD
# Preload as $helper_old may change
egrep "^queue_" "$helper_old" > $TEMPOLD
# Create what is in $helper_new
egrep "^queue_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No queues to create"
else
    num_queues=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_queues queues"
    ii=0
    sort $TEMPNEW |
    while read queue_json; do
        ii=$[ii+1]
        echo "$ii. $queue_json"
        queue_name=${queue_json#queue_}
        queue_name=${queue_name%.json}
        queue_name_decoded=$(path_decode "$queue_name")

        queue_id_a=$(jq -r ".Queue.QueueId" "$instance_alias_dir_a/$queue_json" | dos2unix)

        cat "$instance_alias_dir_a/$queue_json" |
        jq --arg instance_id $instance_id_b \
            ".Queue | del(.QueueId, .QueueArn, .OutboundCallerConfig, .Status) | . + { InstanceId: \$instance_id}" |
        sed -f "$helper_sed" > "$helper/$queue_json"

        cat <<EOD >> "$helper_log"

$actionLead Create queue: $queue_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create queue
$(cat "$helper/$queue_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-queue \
--cli-input-json "file://$helper/$queue_json" \
> "$helper/output_$queue_json"
EOD
            # rm "$helper/$queue_json"
            continue
        fi

        aws_connect create-queue \
            --cli-input-json "file://$helper/$queue_json" \
            > "$helper/output_$queue_json" || error $LINENO
        queue_id_b=$(jq -r ".QueueId" "$helper/output_$queue_json" | dos2unix)

        aws_connect describe-queue \
            --instance-id $instance_id_b \
            --queue-id $queue_id_b \
            > "$instance_alias_dir_b/$queue_json" || error $LINENO

        # Moving queue_json from helper_new to helper_old
        echo $queue_json >> "$helper_old"
        sed -e"/$queue_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Queue: $queue_name_decoded
s%$queue_id_a%$queue_id_b%g
EOD
    done
    test $? -eq 0 || error

    if [ -z "$dryrun" ]; then
        # Update instance B queues
        aws_connect list-queues \
            --instance-id $instance_id_b \
            --queue-types "STANDARD" \
            > $TEMPFILE || error $LINENO
        cat $TEMPFILE |
        jq -r ".QueueSummaryList[] | select(.QueueType != \"AGENT\")" > "$instance_alias_dir_b/queues.json"
    fi
fi

if [ ! -s $TEMPOLD ]; then
    echo "No queues to update"
else
    num_queues=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_queues queues for an update"
    ii=0
    sort $TEMPOLD |
    while read queue_json; do
        ii=$[ii+1]
        echo -n "$ii. $queue_json ... "
        cat "$instance_alias_dir_a/$queue_json" |
        jq "del(.Queue.OutboundCallerConfig)" > $TEMPA
        cat "$instance_alias_dir_b/$queue_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Please update $queue_json manually considering potential operation impact."
    done
fi


############################################################
