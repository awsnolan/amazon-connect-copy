############################################################
# backup/external.sh — Cases, campaigns, contact flow modules,
#                      contact flows, external dependencies manifest
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $instance_alias,
#   $profile_flag, $maxitems, $TEMPFILE, $TEMPCF,
#   $contact_flow_prefix_filter, $contact_flow_prefix_text,
#   $jq_prefix_filter, $jq_prefix_filter_text, $skip_cf_errors
############################################################

echo ""
echo "━━━ External Systems & Flows ━━━ $(ts)"

############################################################
# Amazon Connect Cases (separate CLI namespace)
############################################################

aws connectcases list-domains \
    --max-results 100 \
    $profile_flag \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.domains // [] | sort_by(.name) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/cases_domains.json"
    echo -e "\n$(jq -s "length") Cases domains listed in \"$instance_alias_dir/cases_domains.json\""

    while read domain_id domain_name; do
        echo "Exporting Cases domain $domain_name"
        domain_name_encoded=$(path_encode "$domain_name")
        aws connectcases list-fields \
            --domain-id $domain_id \
            --max-results 100 \
            $profile_flag \
            > "$instance_alias_dir/cases_fields_$domain_name_encoded.json" 2>/dev/null || true
        aws connectcases list-layouts \
            --domain-id $domain_id \
            --max-results 100 \
            $profile_flag \
            > "$instance_alias_dir/cases_layouts_$domain_name_encoded.json" 2>/dev/null || true
        aws connectcases list-templates \
            --domain-id $domain_id \
            --max-results 100 \
            $profile_flag \
            > "$instance_alias_dir/cases_templates_$domain_name_encoded.json" 2>/dev/null || true
    done < <(    jq -r ".domainId + \" \" + .name" "$instance_alias_dir/cases_domains.json" | dos2unix)
    test $? -eq 0 || error
else
    echo "No Connect Cases domains found"
    echo "[]" > "$instance_alias_dir/cases_domains.json"
fi

############################################################
# Outbound Campaigns V2 (separate CLI namespace)
############################################################

aws connect-campaigns-v2 list-campaigns \
    --max-results 100 \
    $profile_flag \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
        jq -r '.campaignSummaryList // [] | sort_by(.name) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/campaigns.json"
    echo -e "\n$(jq -s "length") outbound campaigns listed in \"$instance_alias_dir/campaigns.json\""

    while read camp_id camp_name; do
        echo "Exporting campaign $camp_name"
        camp_name_encoded=$(path_encode "$camp_name")
        aws connect-campaigns-v2 describe-campaign \
            --id $camp_id \
            $profile_flag \
            > "$instance_alias_dir/campaign_$camp_name_encoded.json" 2>/dev/null || true
    done < <(    jq -r ".id + \" \" + .name" "$instance_alias_dir/campaigns.json" | dos2unix)
    test $? -eq 0 || error
else
    echo "No outbound campaigns found"
    echo "[]" > "$instance_alias_dir/campaigns.json"
fi

############################################################
# Contact Flow Modules
############################################################

aws_connect list-contact-flow-modules \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r "[.ContactFlowModulesSummaryList[]${contact_flow_prefix_filter}${jq_prefix_filter}] | sort_by(.Name) | .[]" "$TEMPFILE" \
> "$instance_alias_dir/modules.json"
echo -e "\n$(jq -s "length") contact flow modules listed in \"$instance_alias_dir/modules.json\"$contact_flow_prefix_text$jq_prefix_filter_text"

# Export Contact Flow Modules
cat "$instance_alias_dir/modules.json" > $TEMPFILE
while read module_id module_name; do
    echo "Exporting contact flow module $module_name"
    module_name_encoded=$(path_encode "$module_name")
    aws_connect describe-contact-flow-module \
        --instance-id $instance_id \
        --contact-flow-module-id $module_id > $TEMPCF \
        || error $LINENO "$module_name" "$instance_alias_dir/modules.json"
    if [ -s $TEMPCF ]; then
        cfm_status=$(jq -r ".ContactFlowModule.Status" $TEMPCF | dos2unix)
        if [ "$cfm_status" == "published" ]; then
            cat $TEMPCF |
            jq -r '.ContactFlowModule.Content' > "$instance_alias_dir/module_$module_name_encoded.json"
            cfm_description=$(cat $TEMPCF | jq -r '.ContactFlowModule.Description')
            add_json_attribute Description "$cfm_description" $module_id "$instance_alias_dir/modules.json"
        else
            echo
            echo "$module_name: Contact flow module not published"
            error $LINENO "$module_name" "$instance_alias_dir/modules.json"
        fi
    fi
done < <(jq -r ".Id + \" \" + .Name" $TEMPFILE | dos2unix)
test $? -eq 0 || error

############################################################
# Contact Flows
############################################################

aws_connect list-contact-flows \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE || error $LINENO

jq -r "[.ContactFlowSummaryList[]${contact_flow_prefix_filter}${jq_prefix_filter}] | sort_by(.Name) | .[]" "$TEMPFILE" \
> "$instance_alias_dir/flows.json"
echo "$(jq -s 'length' "$instance_alias_dir/flows.json") contact flows listed in \"$instance_alias_dir/flows.json\"$contact_flow_prefix_text$jq_prefix_filter_text"

# Export Contact Flows
cat "$instance_alias_dir/flows.json" > $TEMPFILE
while read flow_id flow_name; do
    echo "Exporting contact flow $flow_name"
    aws_connect describe-contact-flow \
        --instance-id $instance_id \
        --contact-flow-id $flow_id > $TEMPCF \
        2> /dev/null
    flow_name_encoded=$(path_encode "$flow_name")
    if [ -s $TEMPCF ]; then
        cat $TEMPCF |
        jq -r '.ContactFlow.Content' > "$instance_alias_dir/flow_$flow_name_encoded.json"
        cf_description=$(cat $TEMPCF | jq -r '.ContactFlow.Description')
        add_json_attribute Description "$cf_description" $flow_id "$instance_alias_dir/flows.json"
    else
        echo
        echo "$flow_name: Contact flow not published"
        error $LINENO "$flow_name" "$instance_alias_dir/flows.json"
    fi
done < <(jq -r ".Id + \" \" + .Name" $TEMPFILE | dos2unix)
test $? -eq 0 || error

############################################################
# External Dependencies Manifest
############################################################

echo
echo "Building external dependencies manifest..."

manifest_file="$instance_alias_dir/external_dependencies.json"

all_flow_files=$(ls "$instance_alias_dir"/flow_*.json "$instance_alias_dir"/module_*.json 2>/dev/null)

lambda_arns=$(echo "$all_flow_files" | xargs -I{} sh -c '[ -f "{}" ] && cat "{}"' 2>/dev/null |
    jq -r '.. | strings | select(startswith("arn:aws:lambda:"))' 2>/dev/null |
    sort -u)

lex_v2_arns=$(echo "$all_flow_files" | xargs -I{} sh -c '[ -f "{}" ] && cat "{}"' 2>/dev/null |
    jq -r '.. | strings | select(startswith("arn:aws:lex:"))' 2>/dev/null |
    sort -u)

lex_classic_bots=$(echo "$all_flow_files" | xargs -I{} sh -c '[ -f "{}" ] && cat "{}"' 2>/dev/null |
    jq -r '.Actions[]? | select(.Type == "ConnectParticipantWithLexBot") | .Parameters.LexBot | select(. != null) | .Name + " " + .Region' 2>/dev/null |
    sort -u)

{
    echo "{"
    echo "  \"GeneratedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"InstanceAlias\": \"$instance_alias\","
    echo "  \"InstanceId\": \"$instance_id\","

    echo "  \"LambdaFunctions\": ["
    first=1
    while IFS= read -r arn; do
        [ -z "$arn" ] && continue
        func_name="${arn##*:function:}"
        func_name="${func_name%%:*}"
        runtime=""
        description=""
        handler=""
        code_sha256=""
        func_config=$(aws lambda get-function-configuration \
            $profile_flag \
            --function-name "$arn" \
            2>/dev/null)
        if [ -n "$func_config" ]; then
            runtime=$(echo "$func_config" | jq -r '.Runtime // ""')
            description=$(echo "$func_config" | jq -r '.Description // ""')
            handler=$(echo "$func_config" | jq -r '.Handler // ""')
            memory=$(echo "$func_config" | jq -r '.MemorySize // ""')
            timeout=$(echo "$func_config" | jq -r '.Timeout // ""')
            code_sha256=$(echo "$func_config" | jq -r '.CodeSha256 // ""')
        fi
        [ "$first" -eq 0 ] && echo "  ,"
        first=0
        cat <<JSONEOF
    {
      "Arn": "$arn",
      "FunctionName": "$func_name",
      "Runtime": "$runtime",
      "Handler": "$handler",
      "Description": "$description",
      "MemorySize": $( [ -n "$memory" ] && echo "$memory" || echo "null" ),
      "Timeout": $( [ -n "$timeout" ] && echo "$timeout" || echo "null" ),
      "CodeSha256": "$code_sha256"
    }
JSONEOF
    done <<< "$lambda_arns"
    echo "  ],"

    echo "  \"LexV2Bots\": ["
    first=1
    while IFS= read -r arn; do
        [ -z "$arn" ] && continue
        bot_id=$(echo "$arn" | sed 's|.*bot-alias/\([^/]*\)/.*|\1|')
        alias_id=$(echo "$arn" | sed 's|.*bot-alias/[^/]*/\(.*\)|\1|')
        bot_name=""
        alias_name=""
        bot_locale=""
        bot_config=$(aws lexv2-models describe-bot \
            $profile_flag \
            --bot-id "$bot_id" \
            2>/dev/null)
        if [ -n "$bot_config" ]; then
            bot_name=$(echo "$bot_config" | jq -r '.botName // ""')
        fi
        alias_config=$(aws lexv2-models describe-bot-alias \
            $profile_flag \
            --bot-id "$bot_id" \
            --bot-alias-id "$alias_id" \
            2>/dev/null)
        if [ -n "$alias_config" ]; then
            alias_name=$(echo "$alias_config" | jq -r '.botAliasName // ""')
            bot_locale=$(echo "$alias_config" | jq -r '.botAliasLocaleSettings | keys | join(",")' 2>/dev/null || echo "")
        fi
        [ "$first" -eq 0 ] && echo "  ,"
        first=0
        cat <<JSONEOF
    {
      "Arn": "$arn",
      "BotId": "$bot_id",
      "BotName": "$bot_name",
      "AliasId": "$alias_id",
      "AliasName": "$alias_name",
      "Locales": "$bot_locale"
    }
JSONEOF
    done <<< "$lex_v2_arns"
    echo "  ],"

    echo "  \"LexClassicBots\": ["
    first=1
    while IFS= read -r bot_entry; do
        [ -z "$bot_entry" ] && continue
        bot_name="${bot_entry%% *}"
        bot_region="${bot_entry##* }"
        bot_version=""
        bot_config=$(aws lex-models get-bot \
            $profile_flag \
            --name "$bot_name" \
            --version-or-alias '$LATEST' \
            2>/dev/null)
        if [ -n "$bot_config" ]; then
            bot_version=$(echo "$bot_config" | jq -r '.version // ""')
        fi
        [ "$first" -eq 0 ] && echo "  ,"
        first=0
        cat <<JSONEOF
    {
      "Name": "$bot_name",
      "Region": "$bot_region",
      "Version": "$bot_version"
    }
JSONEOF
    done <<< "$lex_classic_bots"
    echo "  ]"

    echo "}"
} > "$manifest_file"

lambda_count=$(jq ".LambdaFunctions | length" "$manifest_file" 2>/dev/null || echo 0)
lex_v2_count=$(jq ".LexV2Bots | length" "$manifest_file" 2>/dev/null || echo 0)
lex_classic_count=$(jq ".LexClassicBots | length" "$manifest_file" 2>/dev/null || echo 0)
echo "External dependencies manifest saved: $manifest_file"
echo "  Lambda functions : $lambda_count"
echo "  Lex V2 bots      : $lex_v2_count"
echo "  Lex Classic bots : $lex_classic_count"
