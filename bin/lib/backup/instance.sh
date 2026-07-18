############################################################
# backup/instance.sh — Instance bootstrap, attributes, storage,
#                      integrations, origins, keys, lambda associations
#
# Expects from orchestrator:
#   $instance_alias, $instance_alias_dir, $instance_id,
#   $profile_flag, $maxitems, $TEMPFILE, $aws_cli_log
############################################################

echo ""
echo "━━━ Instance Foundation ━━━ $(ts)"

############################################################
# Instance Attributes (feature flags)
############################################################

instance_attribute_types="INBOUND_CALLS OUTBOUND_CALLS CONTACTFLOW_LOGS CONTACT_LENS AUTO_RESOLVE_BEST_VOICES USE_CUSTOM_TTS_VOICES EARLY_MEDIA MULTI_PARTY_CONFERENCE MULTI_PARTY_CHAT_CONFERENCE"

echo -n "  Instance attributes"
> "$instance_alias_dir/instance_attributes.json"
for attr_type in $instance_attribute_types; do
    echo -n "."
    aws_connect describe-instance-attribute \
        --instance-id $instance_id \
        --attribute-type $attr_type \
        >> "$instance_alias_dir/instance_attributes.json" 2>/dev/null || true
done
echo " done"

############################################################
# Instance Storage Configs (S3/KMS destinations)
############################################################

instance_storage_types="CALL_RECORDINGS CHAT_TRANSCRIPTS SCHEDULED_REPORTS MEDIA_STREAMS CONTACT_TRACE_RECORDS AGENT_EVENTS REAL_TIME_CONTACT_ANALYSIS_SEGMENTS REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS ATTACHMENTS CONTACT_EVALUATIONS SCREEN_RECORDINGS"

echo -n "  Storage configs"
> "$instance_alias_dir/storage_configs.json"
for storage_type in $instance_storage_types; do
    echo -n "."
    aws_connect list-instance-storage-configs \
        --instance-id $instance_id \
        --resource-type $storage_type \
        --max-items $maxitems \
        >> "$instance_alias_dir/storage_configs.json" 2>/dev/null || true
done
echo " done"

############################################################
# User Hierarchy Structure
############################################################

echo -n "  Hierarchy structure..."
aws_connect describe-user-hierarchy-structure \
    --instance-id $instance_id \
    > "$instance_alias_dir/hierarchy_structure.json" 2>/dev/null || true
echo " done"

############################################################
# Integration Associations (Lex V2, Wisdom/Amazon Q, Voice ID, Cases)
############################################################

echo -n "  Integrations..."
aws_connect list-integration-associations \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.IntegrationAssociationSummaryList // [] | sort_by(.IntegrationAssociationId) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/integrations.json"
    echo " $(jq -s 'length' "$instance_alias_dir/integrations.json") found"
else
    echo " none"
    echo "[]" > "$instance_alias_dir/integrations.json"
fi

############################################################
# Approved Origins (CCP embed CORS)
############################################################

echo -n "  Approved origins..."
aws_connect list-approved-origins \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.Origins // [] | sort | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/approved_origins.json"
    echo " $(jq -s 'length' "$instance_alias_dir/approved_origins.json") found"
else
    echo " none"
    echo "[]" > "$instance_alias_dir/approved_origins.json"
fi

############################################################
# Security Keys (customer input encryption - informational only)
############################################################

echo -n "  Security keys..."
aws_connect list-security-keys \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.SecurityKeysList // [] | sort_by(.AssociationId) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/security_keys.json"
    echo " $(jq -s 'length' "$instance_alias_dir/security_keys.json") found"
else
    echo " none"
    echo "[]" > "$instance_alias_dir/security_keys.json"
fi

############################################################
# Lambda Function Associations
############################################################

echo -n "  Lambda associations..."
aws_connect list-lambda-functions \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r '.LambdaFunctions // [] | sort | .[]' "$TEMPFILE" |
    jq -Rs '[split("\n") | .[] | select(. != "")]' \
    > "$instance_alias_dir/lambda_associations.json"
    echo " $(jq 'length' "$instance_alias_dir/lambda_associations.json") found"
else
    echo " none"
    echo "[]" > "$instance_alias_dir/lambda_associations.json"
fi
