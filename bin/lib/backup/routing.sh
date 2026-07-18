############################################################
# backup/routing.sh — Prompts, hours of operations, queues,
#                     queue QC associations, routing profiles
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE, $jq_prefix_filter, $jq_prefix_filter_text
############################################################

echo ""
echo "━━━ Routing Infrastructure ━━━"

############################################################
# Prompts
############################################################

aws_connect list-prompts \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

cat $TEMPFILE |
jq -r '.PromptSummaryList // [] | sort_by(.Name) | .[]' \
> "$instance_alias_dir/prompts.json"
echo -e "\n$(jq -s "length") prompts listed in \"$instance_alias_dir/prompts.json\""

# Describe each prompt to capture S3 storage location and tags
while read prompt_id prompt_name; do
    [ -z "$prompt_id" ] && continue
    prompt_name_encoded=$(path_encode "$prompt_name")
    describe_or_skip "$prompt_name" "$instance_alias_dir/prompt_$prompt_name_encoded.json" \
        aws_connect describe-prompt \
        --instance-id $instance_id \
        --prompt-id $prompt_id || true
done < <(jq -r ".Id + \" \" + .Name" "$instance_alias_dir/prompts.json" | dos2unix)
echo "Prompt details saved"

############################################################
# Hours of Operations
############################################################

aws_connect list-hours-of-operations \
    --instance-id $instance_id \
    --max-items $maxitems |\
    jq '.HoursOfOperationSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r '[.HoursOfOperationSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/hours.json"
echo -e "\n$(jq -s "length") hours of operations listed in \"$instance_alias_dir/hours.json\"$jq_prefix_filter_text"

while read hour_id hour_name; do
    echo "Exporting hours of operation $hour_name"
    hour_name_encoded=$(path_encode "$hour_name")
    aws_connect describe-hours-of-operation \
        --instance-id $instance_id \
        --hours-of-operation-id $hour_id |\
        jq 'del(.HoursOfOperation.LastModifiedRegion, .HoursOfOperation.LastModifiedTime)' \
        > "$instance_alias_dir/hour_$hour_name_encoded.json" || error $LINENO
    # Export hours of operation overrides (schedule exceptions)
    aws_connect list-hours-of-operation-overrides \
        --instance-id $instance_id \
        --hours-of-operation-id $hour_id \
        --max-items $maxitems \
        > "$instance_alias_dir/hourOverrides_$hour_name_encoded.json" 2>/dev/null || true
done < <(jq -r ".Id + \" \" + .Name" "$instance_alias_dir/hours.json" | dos2unix)
test $? -eq 0 || error

############################################################
# Queues
############################################################

aws_connect list-queues \
    --instance-id $instance_id \
    --max-items $maxitems \
    --queue-types "STANDARD" |\
    jq '.QueueSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r '[.QueueSummaryList[] | select(.QueueType != \"AGENT\")$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/queues.json"
echo -e "\n$(jq -s "length") queues listed in \"$instance_alias_dir/queues.json\"$jq_prefix_filter_text"

while read queue_id queue_name; do
    echo "Exporting queue $queue_name"
    queue_name_encoded=$(path_encode "$queue_name")
    aws_connect describe-queue \
        --instance-id $instance_id \
        --queue-id $queue_id |\
        jq 'del(.Queue.LastModifiedRegion, .Queue.LastModifiedTime)' \
        > "$instance_alias_dir/queue_$queue_name_encoded.json" || error $LINENO
done < <(jq -r ".Id + \" \" + .Name" "$instance_alias_dir/queues.json" | dos2unix)
test $? -eq 0 || error

############################################################
# Queue → Quick Connect Associations
############################################################

while read queue_id queue_name; do
    queue_name_encoded=$(path_encode "$queue_name")
    aws_connect list-queue-quick-connects \
        --instance-id $instance_id \
        --queue-id $queue_id \
        --max-items $maxitems \
        > "$instance_alias_dir/queueQCs_$queue_name_encoded.json" 2>/dev/null || true
done < <(jq -r ".Id + \" \" + .Name" "$instance_alias_dir/queues.json" | dos2unix)
test $? -eq 0 || error
echo "Queue quick connect associations saved"

############################################################
# Routing Profiles
############################################################

aws_connect list-routing-profiles \
    --instance-id $instance_id \
    --max-items $maxitems |\
    jq '.RoutingProfileSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r '[.RoutingProfileSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/routings.json"
echo -e "\n$(jq -s "length") routing profiles listed in \"$instance_alias_dir/routings.json\"$jq_prefix_filter_text"

while read routing_id routing_name; do
    echo "Exporting routing profile $routing_name"
    routing_name_encoded=$(path_encode "$routing_name")
    aws_connect describe-routing-profile \
        --instance-id $instance_id \
        --routing-profile-id $routing_id |
        jq -r "del(.RoutingProfile.NumberOfAssociatedQueues, .RoutingProfile.NumberOfAssociatedUsers, .RoutingProfile.LastModifiedRegion, .RoutingProfile.LastModifiedTime)" \
        > "$instance_alias_dir/routing_$routing_name_encoded.json" || error $LINENO
    aws_connect list-routing-profile-queues \
        --instance-id $instance_id \
        --routing-profile-id $routing_id \
        --max-items $maxitems \
        > "$instance_alias_dir/routingQs_$routing_name_encoded.json" || error $LINENO
done < <(jq -r ".Id + \" \" + .Name" "$instance_alias_dir/routings.json" | dos2unix)
test $? -eq 0 || error
