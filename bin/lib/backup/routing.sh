############################################################
# backup/routing.sh — Prompts, hours of operations, queues,
#                     queue QC associations, routing profiles
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE, $jq_prefix_filter, $jq_prefix_filter_text
############################################################

echo ""
echo "━━━ Routing Infrastructure ━━━ $(ts)"

############################################################
# Prompts
############################################################

aws_connect list-prompts \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r '.PromptSummaryList // [] | sort_by(.Name) | .[]' "$TEMPFILE" \
> "$instance_alias_dir/prompts.json"
echo "$(jq -s 'length' "$instance_alias_dir/prompts.json") prompts"

# Describe each prompt to capture S3 storage location and tags
while read prompt_id prompt_name; do
    [ -z "$prompt_id" ] && continue
    prompt_name_encoded=$(path_encode "$prompt_name")
    describe_or_skip "$prompt_name" "$instance_alias_dir/prompt_$prompt_name_encoded.json" \
        aws_connect describe-prompt \
        --instance-id $instance_id \
        --prompt-id $prompt_id || true
done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/prompts.json" | tr -d '\r')
echo "  Prompt details saved"

############################################################
# Hours of Operations
############################################################

aws_connect list-hours-of-operations \
    --instance-id $instance_id \
    --max-items $maxitems |\
    jq '.HoursOfOperationSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r ".HoursOfOperationSummaryList[]$jq_prefix_filter" "$TEMPFILE" \
> "$instance_alias_dir/hours.json.tmp"
jq -s 'sort_by(.Name) | .[]' "$instance_alias_dir/hours.json.tmp" \
> "$instance_alias_dir/hours.json" 2>/dev/null || true
rm -f "$instance_alias_dir/hours.json.tmp"
echo "$(jq -s 'length' "$instance_alias_dir/hours.json" 2>/dev/null || echo 0) hours of operations"

while IFS=$'\t' read -r hour_id hour_name; do
    [ -z "$hour_id" ] && continue
    echo "  Exporting hours of operation $hour_name"
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
done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/hours.json" | tr -d '\r')

############################################################
# Queues
############################################################

aws_connect list-queues \
    --instance-id $instance_id \
    --max-items $maxitems \
    --queue-types "STANDARD" |\
    jq '.QueueSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r ".QueueSummaryList[] | select(.QueueType != \"AGENT\")$jq_prefix_filter" "$TEMPFILE" \
> "$instance_alias_dir/queues.json.tmp"
jq -s 'sort_by(.Name) | .[]' "$instance_alias_dir/queues.json.tmp" \
> "$instance_alias_dir/queues.json" 2>/dev/null || true
rm -f "$instance_alias_dir/queues.json.tmp"
echo "$(jq -s 'length' "$instance_alias_dir/queues.json" 2>/dev/null || echo 0) queues"

while IFS=$'\t' read -r queue_id queue_name; do
    [ -z "$queue_id" ] && continue
    echo "  Exporting queue $queue_name"
    queue_name_encoded=$(path_encode "$queue_name")
    aws_connect describe-queue \
        --instance-id $instance_id \
        --queue-id $queue_id |\
        jq 'del(.Queue.LastModifiedRegion, .Queue.LastModifiedTime)' \
        > "$instance_alias_dir/queue_$queue_name_encoded.json" || error $LINENO
done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/queues.json" | tr -d '\r')

############################################################
# Queue → Quick Connect Associations
############################################################

while IFS=$'\t' read -r queue_id queue_name; do
    [ -z "$queue_id" ] && continue
    queue_name_encoded=$(path_encode "$queue_name")
    aws_connect list-queue-quick-connects \
        --instance-id $instance_id \
        --queue-id $queue_id \
        --max-items $maxitems \
        > "$instance_alias_dir/queueQCs_$queue_name_encoded.json" 2>/dev/null || true
done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/queues.json" | tr -d '\r')
echo "  Queue quick connect associations saved"

############################################################
# Routing Profiles
############################################################

aws_connect list-routing-profiles \
    --instance-id $instance_id \
    --max-items $maxitems |\
    jq '.RoutingProfileSummaryList |= map(del(.LastModifiedRegion, .LastModifiedTime))' \
    > $TEMPFILE || error $LINENO

jq -r ".RoutingProfileSummaryList[]$jq_prefix_filter" "$TEMPFILE" \
> "$instance_alias_dir/routings.json.tmp"
jq -s 'sort_by(.Name) | .[]' "$instance_alias_dir/routings.json.tmp" \
> "$instance_alias_dir/routings.json" 2>/dev/null || true
rm -f "$instance_alias_dir/routings.json.tmp"
echo "$(jq -s 'length' "$instance_alias_dir/routings.json" 2>/dev/null || echo 0) routing profiles"

while IFS=$'\t' read -r routing_id routing_name; do
    [ -z "$routing_id" ] && continue
    echo "  Exporting routing profile $routing_name"
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
done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/routings.json" | tr -d '\r')
