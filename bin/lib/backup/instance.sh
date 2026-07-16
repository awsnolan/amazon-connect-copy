############################################################
# backup/instance.sh — Instance bootstrap, attributes, storage,
#                      integrations, origins, keys, lambda associations
#
# Expects from orchestrator:
#   $instance_alias, $instance_alias_dir, $instance_id,
#   $profile_flag, $maxitems, $TEMPFILE, $aws_cli_log
############################################################

echo ""
echo "━━━ Instance Foundation ━━━"

############################################################
# Instance Attributes (feature flags)
############################################################

instance_attribute_types="INBOUND_CALLS OUTBOUND_CALLS CONTACTFLOW_LOGS CONTACT_LENS AUTO_RESOLVE_BEST_VOICES USE_CUSTOM_TTS_VOICES EARLY_MEDIA MULTI_PARTY_CONFERENCE MULTI_PARTY_CHAT_CONFERENCE"

> "$instance_alias_dir/instance_attributes.json"
for attr_type in $instance_attribute_types; do
    aws_connect describe-instance-attribute \
        --instance-id $instance_id \
        --attribute-type $attr_type \
        >> "$instance_alias_dir/instance_attributes.json" 2>/dev/null || true
done
echo "Instance attributes saved in \"$instance_alias_dir/instance_attributes.json\""

############################################################
# Instance Storage Configs (S3/KMS destinations)
############################################################

instance_storage_types="CALL_RECORDINGS CHAT_TRANSCRIPTS SCHEDULED_REPORTS MEDIA_STREAMS CONTACT_TRACE_RECORDS AGENT_EVENTS REAL_TIME_CONTACT_ANALYSIS_SEGMENTS REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS ATTACHMENTS CONTACT_EVALUATIONS SCREEN_RECORDINGS"

> "$instance_alias_dir/storage_configs.json"
for storage_type in $instance_storage_types; do
    aws_connect list-instance-storage-configs \
        --instance-id $instance_id \
        --resource-type $storage_type \
        --max-items $maxitems \
        >> "$instance_alias_dir/storage_configs.json" 2>/dev/null || true
done
echo "Instance storage configs saved in \"$instance_alias_dir/storage_configs.json\""

############################################################
# User Hierarchy Structure
############################################################

aws_connect describe-user-hierarchy-structure \
    --instance-id $instance_id \
    > "$instance_alias_dir/hierarchy_structure.json" 2>/dev/null || true
echo "User hierarchy structure saved in \"$instance_alias_dir/hierarchy_structure.json\""

############################################################
# Integration Associations (Lex V2, Wisdom/Amazon Q, Voice ID, Cases)
############################################################

aws_connect list-integration-associations \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".IntegrationAssociationSummaryList // [] | .[]" |
    jq -s "sort_by(.IntegrationAssociationId) | .[]" |
    tee "$instance_alias_dir/integrations.json" |
    echo -e "\n$(jq -s "length") integration associations listed in \"$instance_alias_dir/integrations.json\""
else
    echo "No integration associations found"
    echo "[]" > "$instance_alias_dir/integrations.json"
fi

############################################################
# Approved Origins (CCP embed CORS)
############################################################

aws_connect list-approved-origins \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".Origins // [] | .[]" |
    jq -s "sort | .[]" |
    tee "$instance_alias_dir/approved_origins.json" |
    echo -e "\n$(jq -s "length") approved origins listed in \"$instance_alias_dir/approved_origins.json\""
else
    echo "No approved origins found"
    echo "[]" > "$instance_alias_dir/approved_origins.json"
fi

############################################################
# Security Keys (customer input encryption - informational only)
############################################################

aws_connect list-security-keys \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".SecurityKeysList // [] | .[]" |
    jq -s "sort_by(.AssociationId) | .[]" |
    tee "$instance_alias_dir/security_keys.json" |
    echo -e "\n$(jq -s "length") security keys listed in \"$instance_alias_dir/security_keys.json\""
else
    echo "No security keys found"
    echo "[]" > "$instance_alias_dir/security_keys.json"
fi

############################################################
# Lambda Function Associations
############################################################

aws_connect list-lambda-functions \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r '.LambdaFunctions // [] | sort | .[]' |
    jq -Rs '[split("\n") | .[] | select(. != "")]' |
    tee "$instance_alias_dir/lambda_associations.json" |
    echo -e "\n$(jq 'length' "$instance_alias_dir/lambda_associations.json") Lambda function associations listed in \"$instance_alias_dir/lambda_associations.json\""
else
    echo "No Lambda function associations found"
    echo "[]" > "$instance_alias_dir/lambda_associations.json"
fi
