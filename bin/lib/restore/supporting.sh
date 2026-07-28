############################################################
#
# Task Templates
#

section_header "Supporting Resources"
egrep "^tasktemplate_" "$helper_old" > $TEMPOLD
egrep "^tasktemplate_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No task templates to create"
else
    num_tt=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_tt task templates"
    ii=0
    sort $TEMPNEW |
    while read tt_json; do
        ii=$[ii+1]
        echo "$ii. $tt_json"
        tt_name=${tt_json#tasktemplate_}
        tt_name=${tt_name%.json}
        tt_name_decoded=$(path_decode "$tt_name")

        tt_id_a=$(jq -r ".Id" "$instance_alias_dir_a/$tt_json" | dos2unix)

        cat "$instance_alias_dir_a/$tt_json" |
        jq --arg iid $instance_id_b \
            "del(.Id, .Arn, .CreatedTime, .LastModifiedTime) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$tt_json"

        cat <<EOD >> "$helper_log"

$actionLead Create task template: $tt_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create task template
$(cat "$helper/$tt_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-task-template \
--cli-input-json "file://$helper/$tt_json" \
> "$helper/output_$tt_json"
EOD
            continue
        fi

        aws_connect create-task-template \
            --cli-input-json "file://$helper/$tt_json" \
            > "$helper/output_$tt_json" || error $LINENO
        tt_id_b=$(jq -r ".Id" "$helper/output_$tt_json" | dos2unix)

        aws_connect get-task-template \
            --instance-id $instance_id_b \
            --task-template-id $tt_id_b \
            > "$instance_alias_dir_b/$tt_json" || error $LINENO

        echo $tt_json >> "$helper_old"
        sed -e"/$tt_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Task Template: $tt_name_decoded
s%$tt_id_a%$tt_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No task templates to update"
else
    num_tt=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_tt task templates for an update"
    ii=0
    sort $TEMPOLD |
    while read tt_json; do
        ii=$[ii+1]
        echo -n "$ii. $tt_json ... "
        tt_name=${tt_json#tasktemplate_}
        tt_name=${tt_name%.json}
        tt_name_decoded=$(path_decode "$tt_name")
        cat "$instance_alias_dir_a/$tt_json" > $TEMPA
        cat "$instance_alias_dir_b/$tt_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $tt_json"

        tt_id_b=$(jq -r ".Id" "$instance_alias_dir_b/$tt_json" | dos2unix)

        cat "$instance_alias_dir_a/$tt_json" |
        jq --arg iid $instance_id_b --arg ttid $tt_id_b \
            "del(.Arn, .CreatedTime, .LastModifiedTime) | . + { InstanceId: \$iid, Id: \$ttid }" |
        sed -f "$helper_sed" > "$helper/$tt_json"

        cat <<EOD >> "$helper_log"

$actionLead Update task template: $tt_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update task template
$(cat "$helper/$tt_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-task-template \
--task-template-id $tt_id_b \
--cli-input-json "file://$helper/$tt_json"
EOD
            continue
        fi

        aws_connect update-task-template \
            --task-template-id $tt_id_b \
            --instance-id $instance_id_b \
            --cli-input-json "file://$helper/$tt_json" || error $LINENO

        aws_connect get-task-template \
            --instance-id $instance_id_b \
            --task-template-id $tt_id_b \
            > "$instance_alias_dir_b/$tt_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
#
# Evaluation Forms (Quality Management)
#

cat <<EOD

Evaluation Forms
----------------
EOD
egrep "^evaluationform_" "$helper_old" > $TEMPOLD
egrep "^evaluationform_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No evaluation forms to create"
else
    num_ef=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_ef evaluation forms"
    ii=0
    sort $TEMPNEW |
    while read ef_json; do
        ii=$[ii+1]
        echo "$ii. $ef_json"
        ef_title=${ef_json#evaluationform_}
        ef_title=${ef_title%.json}
        ef_title_decoded=$(path_decode "$ef_title")

        ef_id_a=$(jq -r ".EvaluationForm.EvaluationFormId" "$instance_alias_dir_a/$ef_json" | dos2unix)

        cat "$instance_alias_dir_a/$ef_json" |
        jq --arg iid $instance_id_b \
            ".EvaluationForm | del(.EvaluationFormId, .EvaluationFormArn, .EvaluationFormVersion, .CreatedTime, .LastModifiedTime, .CreatedBy, .LastModifiedBy) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$ef_json"

        cat <<EOD >> "$helper_log"

$actionLead Create evaluation form: $ef_title_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create evaluation form
$(cat "$helper/$ef_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-evaluation-form \
--cli-input-json "file://$helper/$ef_json" \
> "$helper/output_$ef_json"
EOD
            continue
        fi

        aws_connect create-evaluation-form \
            --cli-input-json "file://$helper/$ef_json" \
            > "$helper/output_$ef_json" || error $LINENO
        ef_id_b=$(jq -r ".EvaluationFormId" "$helper/output_$ef_json" | dos2unix)
        ef_ver_b=$(jq -r ".EvaluationFormVersion" "$helper/output_$ef_json" | dos2unix)

        # Activate the form so it can be used in rules
        aws_connect activate-evaluation-form \
            --instance-id $instance_id_b \
            --evaluation-form-id $ef_id_b \
            --evaluation-form-version $ef_ver_b || error $LINENO

        aws_connect describe-evaluation-form \
            --instance-id $instance_id_b \
            --evaluation-form-id $ef_id_b \
            > "$instance_alias_dir_b/$ef_json" || error $LINENO

        echo $ef_json >> "$helper_old"
        sed -e"/$ef_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Evaluation Form: $ef_title_decoded
s%$ef_id_a%$ef_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No evaluation forms to update"
else
    num_ef=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_ef evaluation forms for an update"
    ii=0
    sort $TEMPOLD |
    while read ef_json; do
        ii=$[ii+1]
        echo -n "$ii. $ef_json ... "
        cat "$instance_alias_dir_a/$ef_json" > $TEMPA
        cat "$instance_alias_dir_b/$ef_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Please update $ef_json manually - evaluation form updates require version management."
    done
fi


############################################################
#
# Rules (Contact Lens automation rules)
#

cat <<EOD

Rules
-----
EOD
egrep "^rule_" "$helper_old" > $TEMPOLD
egrep "^rule_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No rules to create"
else
    num_rules=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_rules rules"
    ii=0
    sort $TEMPNEW |
    while read rule_json; do
        ii=$[ii+1]
        echo "$ii. $rule_json"
        rule_name=${rule_json#rule_}
        rule_name=${rule_name%.json}
        rule_name_decoded=$(path_decode "$rule_name")

        rule_id_a=$(jq -r ".Rule.RuleId" "$instance_alias_dir_a/$rule_json" | dos2unix)

        cat "$instance_alias_dir_a/$rule_json" |
        jq --arg iid $instance_id_b \
            ".Rule | del(.RuleId, .RuleArn, .CreatedTime, .LastUpdatedTime, .CreatedBy, .LastUpdatedBy) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$rule_json"

        cat <<EOD >> "$helper_log"

$actionLead Create rule: $rule_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-create rule
$(cat "$helper/$rule_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect create-rule \
--cli-input-json "file://$helper/$rule_json" \
> "$helper/output_$rule_json"
EOD
            continue
        fi

        aws_connect create-rule \
            --cli-input-json "file://$helper/$rule_json" \
            > "$helper/output_$rule_json" || error $LINENO
        rule_id_b=$(jq -r ".RuleId" "$helper/output_$rule_json" | dos2unix)

        aws_connect describe-rule \
            --instance-id $instance_id_b \
            --rule-id $rule_id_b \
            > "$instance_alias_dir_b/$rule_json" || error $LINENO

        echo $rule_json >> "$helper_old"
        sed -e"/$rule_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# Rule: $rule_name_decoded
s%$rule_id_a%$rule_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No rules to update"
else
    num_rules=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_rules rules for an update"
    ii=0
    sort $TEMPOLD |
    while read rule_json; do
        ii=$[ii+1]
        echo -n "$ii. $rule_json ... "
        rule_name=${rule_json#rule_}
        rule_name=${rule_name%.json}
        rule_name_decoded=$(path_decode "$rule_name")
        cat "$instance_alias_dir_a/$rule_json" > $TEMPA
        cat "$instance_alias_dir_b/$rule_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $rule_json"

        rule_id_b=$(jq -r ".Rule.RuleId" "$instance_alias_dir_b/$rule_json" | dos2unix)

        cat "$instance_alias_dir_a/$rule_json" |
        jq --arg iid $instance_id_b --arg rid $rule_id_b \
            ".Rule | del(.RuleArn, .CreatedTime, .LastUpdatedTime, .CreatedBy, .LastUpdatedBy) | . + { InstanceId: \$iid, RuleId: \$rid }" |
        sed -f "$helper_sed" > "$helper/$rule_json"

        cat <<EOD >> "$helper_log"

$actionLead Update rule: $rule_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update rule
$(cat "$helper/$rule_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-rule \
--rule-id $rule_id_b \
--cli-input-json "file://$helper/$rule_json"
EOD
            continue
        fi

        aws_connect update-rule \
            --rule-id $rule_id_b \
            --instance-id $instance_id_b \
            --name "${rule_name_decoded//\"/\\\"}" \
            --function "$(jq -r '.Rule.Function' "$helper/$rule_json")" \
            --actions "$(jq -r '.Rule.Actions' "$helper/$rule_json")" \
            --publish-status "$(jq -r '.Rule.PublishStatus' "$helper/$rule_json")" || error $LINENO

        aws_connect describe-rule \
            --instance-id $instance_id_b \
            --rule-id $rule_id_b \
            > "$instance_alias_dir_b/$rule_json" || error $LINENO
    done
    test $? -eq 0 || error
fi


############################################################
#
# Views (Agent Workspace)
#

cat <<EOD

Views
-----
EOD
egrep "^view_" "$helper_old" > $TEMPOLD
egrep "^view_" "$helper_new" > $TEMPNEW
if [ ! -s $TEMPNEW ]; then
    echo "No views to create"
else
    num_views=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_views views"
    ii=0
    sort $TEMPNEW |
    while read view_json; do
        ii=$[ii+1]
        echo "$ii. $view_json"
        view_name=${view_json#view_}
        view_name=${view_name%.json}
        view_name_decoded=$(path_decode "$view_name")

        view_id_a=$(jq -r ".View.Id" "$instance_alias_dir_a/$view_json" | dos2unix)

        cat "$instance_alias_dir_a/$view_json" |
        jq --arg iid $instance_id_b \
            ".View | del(.Id, .Arn, .Version, .VersionDescription, .CreatedTime, .LastModifiedTime, .Type, .ViewContentSha256) | .Content |= del(.InputSchema) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$view_json"

        cat <<EOD >> "$helper_log"

$actionLead Create view: $view_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            local view_size=$(wc -c < "$helper/$view_json" | tr -d ' ')
            echo "  [dry] Would create view: $view_name_decoded ($view_size bytes)"
            cat <<EOD >> "$helper_log"
aws connect create-view \
--cli-input-json "file://$helper/$view_json" \
> "$helper/output_$view_json"
EOD
            continue
        fi

        aws_connect create-view \
            --cli-input-json "file://$helper/$view_json" \
            > "$helper/output_$view_json" || error $LINENO
        view_id_b=$(jq -r ".View.Id" "$helper/output_$view_json" | dos2unix)

        aws_connect describe-view \
            --instance-id $instance_id_b \
            --view-id $view_id_b \
            > "$instance_alias_dir_b/$view_json" || error $LINENO

        echo $view_json >> "$helper_old"
        sed -e"/$view_json/d" "$helper_new" > $TEMPFILE
        cat $TEMPFILE > "$helper_new"

        cat <<EOD >> "$helper_sed"
# View: $view_name_decoded
s%$view_id_a%$view_id_b%g
EOD
    done
    test $? -eq 0 || error
fi

if [ ! -s $TEMPOLD ]; then
    echo "No views to update"
else
    num_views=$(echo $(cat $TEMPOLD | wc -l))
    echo -e "\nChecking $num_views views for an update"
    ii=0
    sort $TEMPOLD |
    while read view_json; do
        ii=$[ii+1]
        echo -n "$ii. $view_json ... "
        view_name=${view_json#view_}
        view_name=${view_name%.json}
        view_name_decoded=$(path_decode "$view_name")
        cat "$instance_alias_dir_a/$view_json" > $TEMPA
        cat "$instance_alias_dir_b/$view_json" > $TEMPB
        df=$(diff_files); echo $df; test "$df" == "same" && continue
        echo "Updating $view_json"

        view_id_b=$(jq -r ".View.Id" "$instance_alias_dir_b/$view_json" | dos2unix)

        cat "$instance_alias_dir_a/$view_json" |
        jq --arg iid $instance_id_b \
            ".View | del(.Arn, .Version, .VersionDescription, .CreatedTime, .LastModifiedTime, .Type, .ViewContentSha256) | .Content |= del(.InputSchema) | . + { InstanceId: \$iid }" |
        sed -f "$helper_sed" > "$helper/$view_json"

        cat <<EOD >> "$helper_log"

$actionLead Update view: $view_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            local view_size=$(wc -c < "$helper/$view_json" | tr -d ' ')
            echo "  [dry] Would update view: $view_name_decoded ($view_size bytes)"
            cat <<EOD >> "$helper_log"
aws connect update-view-content \
--instance-id $instance_id_b \
--view-id $view_id_b \
--status PUBLISHED \
--content "file://$helper/$view_json"
EOD
            continue
        fi

        view_content=$(cat "$helper/$view_json" | jq -r '.View.Content')
        aws_connect update-view-content \
            --instance-id $instance_id_b \
            --view-id $view_id_b \
            --status PUBLISHED \
            --content "$view_content" || error $LINENO

        aws_connect describe-view \
            --instance-id $instance_id_b \
            --view-id $view_id_b \
            > "$instance_alias_dir_b/$view_json" || error $LINENO
    done
    test $? -eq 0 || error
fi

############################################################

############################################################
#
# Vocabularies (Contact Lens)
#

cat <<EOD

Vocabularies
------------
EOD
egrep "^vocabulary_" "$helper_new" > $TEMPNEW 2>/dev/null || true
if [ ! -s $TEMPNEW ]; then
    echo "No vocabularies to create"
else
    num_vocab=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_vocab vocabularies"
    ii=0
    sort $TEMPNEW |
    while read vocab_json; do
        ii=$[ii+1]
        echo "$ii. $vocab_json"
        vocab_name=${vocab_json#vocabulary_}
        vocab_name=${vocab_name%.json}
        vocab_name_decoded=$(path_decode "$vocab_name")

        vocab_id_a=$(jq -r ".Vocabulary.VocabularyId // .VocabularyId // empty" "$instance_alias_dir_a/$vocab_json" | dos2unix)
        vocab_language=$(jq -r ".Vocabulary.LanguageCode // .LanguageCode // empty" "$instance_alias_dir_a/$vocab_json" | dos2unix)
        vocab_content=$(jq -r ".Vocabulary.Content // .Content // empty" "$instance_alias_dir_a/$vocab_json" | dos2unix)

        if [ -z "$vocab_language" ] || [ -z "$vocab_content" ]; then
            echo "  WARNING: Missing language or content for vocabulary $vocab_name_decoded — skipping"
            continue
        fi

        cat <<EOD >> "$helper_log"

$actionLead Create vocabulary: $vocab_name_decoded (language: $vocab_language)
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
  [dry] Would create vocabulary: $vocab_name_decoded (language: $vocab_language)
EOD
            verbose_detail "create-vocabulary --vocabulary-name $vocab_name_decoded --language-code $vocab_language --content <${#vocab_content} chars>"
            continue
        fi

        create_output=$(aws_connect create-vocabulary \
            --instance-id $instance_id_b \
            --vocabulary-name "$vocab_name_decoded" \
            --language-code "$vocab_language" \
            --content "$vocab_content" 2>/dev/null) || true

        if [ -n "$create_output" ]; then
            vocab_id_b=$(echo "$create_output" | jq -r '.VocabularyId // empty' | dos2unix)
            echo -e "  ${C_PASS}✓ Created vocabulary: $vocab_name_decoded (ID: $vocab_id_b)${C_RESET}"
            if [ -n "$vocab_id_a" ] && [ -n "$vocab_id_b" ]; then
                cat <<EOD >> "$helper_sed"
# Vocabulary: $vocab_name_decoded
s%$vocab_id_a%$vocab_id_b%g
EOD
            fi
            # Wait for vocabulary to become ACTIVE (async creation)
            echo -n "    Waiting for ACTIVE state..."
            for attempt in 1 2 3 4 5 6; do
                sleep 5
                vocab_state=$(aws_connect describe-vocabulary \
                    --instance-id $instance_id_b \
                    --vocabulary-id $vocab_id_b 2>/dev/null | jq -r '.Vocabulary.State // empty' | dos2unix)
                [ "$vocab_state" = "ACTIVE" ] && break
            done
            if [ "$vocab_state" = "ACTIVE" ]; then
                echo -e " ${C_PASS}ACTIVE${C_RESET}"
            else
                echo -e " ${C_WARN}state=$vocab_state (may still be processing)${C_RESET}"
            fi
        else
            echo -e "  ${C_FAIL}✗ Failed to create vocabulary: $vocab_name_decoded${C_RESET}" >&2
        fi
    done
    test $? -eq 0 || error
fi

############################################################
#
# Data Tables (structure + row data)
#

cat <<EOD

Data Tables
-----------
EOD
egrep "^datatable_" "$helper_new" > $TEMPNEW 2>/dev/null || true
if [ ! -s $TEMPNEW ]; then
    echo "No data tables to create"
else
    num_dt=$(echo $(cat $TEMPNEW | wc -l))
    echo -e "\nCreating $num_dt data tables"
    ii=0
    sort $TEMPNEW |
    while read dt_json; do
        ii=$[ii+1]
        echo "$ii. $dt_json"
        dt_name=${dt_json#datatable_}
        dt_name=${dt_name%.json}
        dt_name_decoded=$(path_decode "$dt_name")

        dt_id_a=$(jq -r ".TableId // empty" "$instance_alias_dir_a/$dt_json" | dos2unix)

        # Build create payload from describe output
        cat "$instance_alias_dir_a/$dt_json" |
        jq --arg iid $instance_id_b \
            '{InstanceId: $iid, TableName: .TableName, Description: (.Description // ""), Attributes: [(.Attributes // [])[] | del(.AttributeId)]}' \
        > "$helper/$dt_json" 2>/dev/null

        cat <<EOD >> "$helper_log"

$actionLead Create data table: $dt_name_decoded
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
  [dry] Would create data table: $dt_name_decoded
EOD
            verbose_detail "create-data-table --cli-input-json file://$helper/$dt_json"
            # Check for row data
            dt_data_file="$instance_alias_dir_a/datatable_data_${dt_name}.json"
            if [ -f "$dt_data_file" ] && [ -s "$dt_data_file" ]; then
                row_count=$(jq -s 'length' "$dt_data_file" 2>/dev/null || echo "0")
                verbose_detail "Would restore $row_count rows of data"
            fi
            continue
        fi

        create_output=$(aws_connect create-data-table \
            --cli-input-json "file://$helper/$dt_json" 2>/dev/null) || true

        if [ -n "$create_output" ]; then
            dt_id_b=$(echo "$create_output" | jq -r '.TableId // empty' | dos2unix)
            echo -e "  ${C_PASS}✓ Created data table: $dt_name_decoded (ID: $dt_id_b)${C_RESET}"
            if [ -n "$dt_id_a" ] && [ -n "$dt_id_b" ]; then
                cat <<EOD >> "$helper_sed"
# Data Table: $dt_name_decoded
s%$dt_id_a%$dt_id_b%g
EOD
            fi

            # Restore row data if available
            dt_data_file="$instance_alias_dir_a/datatable_data_${dt_name}.json"
            if [ -f "$dt_data_file" ] && [ -s "$dt_data_file" ]; then
                row_count=$(jq -s 'length' "$dt_data_file" 2>/dev/null || echo "0")
                echo "    Restoring $row_count rows..."
                # Process rows individually via batch-create-data-table-value
                batch_file="$helper/dt_batch_${dt_name}.json"
                while IFS= read -r row_json; do
                    [ -z "$row_json" ] && continue
                    echo "$row_json" |
                    jq --arg iid "$instance_id_b" --arg tid "$dt_id_b" \
                        '. + {InstanceId: $iid, TableId: $tid}' > "$batch_file"
                    aws_connect batch-create-data-table-value \
                        --cli-input-json "file://$batch_file" 2>/dev/null || true
                done < <(jq -c '.' "$dt_data_file" 2>/dev/null)
                echo -e "    ${C_PASS}✓ Row data restored${C_RESET}"
            fi
        else
            echo -e "  ${C_FAIL}✗ Failed to create data table: $dt_name_decoded${C_RESET}" >&2
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Cases Config Restore (domain → fields → layouts → templates)
#

cat <<EOD

Cases Config
------------
EOD
egrep "^cases_fields_\|^cases_layouts_\|^cases_templates_" "$helper_new" > $TEMPNEW 2>/dev/null || true
if [ ! -s $TEMPNEW ] && [ ! -s "$instance_alias_dir_a/cases_domains.json" ]; then
    echo "No Cases config to restore"
else
    cases_domain_count=$(jq -s 'length' "$instance_alias_dir_a/cases_domains.json" 2>/dev/null || echo 0)
    if [ "$cases_domain_count" -eq 0 ]; then
        echo "No Cases domains in source backup"
    else
        while read domain_id_a domain_name; do
            [ -z "$domain_id_a" ] && continue
            domain_name_encoded=$(path_encode "$domain_name")

            # Check if target already has a Cases domain
            target_domain_id=$(jq -r ".domainId // empty" "$instance_alias_dir_b/cases_domains.json" 2>/dev/null | head -1 | dos2unix)

            if [ -z "$target_domain_id" ]; then
                # Create domain on target
                cat <<EOD >> "$helper_log"

$actionLead Create Cases domain: $domain_name
EOD
                if [ -n "$dryrun" ]; then
                    echo "  [dry] Would create Cases domain: $domain_name"
                else
                    create_output=$(aws connectcases create-domain \
                        --name "$domain_name" \
                        $profile_flag 2>/dev/null) || true
                    if [ -n "$create_output" ]; then
                        target_domain_id=$(echo "$create_output" | jq -r '.domainId // empty' | dos2unix)
                        echo -e "  ${C_PASS}✓ Created Cases domain: $domain_name (ID: $target_domain_id)${C_RESET}"
                        cat <<EOD >> "$helper_sed"
# Cases Domain: $domain_name
s%$domain_id_a%$target_domain_id%g
EOD
                    else
                        echo -e "  ${C_FAIL}✗ Failed to create Cases domain: $domain_name${C_RESET}" >&2
                        continue
                    fi
                fi
            else
                echo "  Cases domain already exists on target (ID: $target_domain_id)"
            fi

            # Skip field/layout/template creation in dry-run if no domain ID
            if [ -n "$dryrun" ] && [ -z "$target_domain_id" ]; then
                target_domain_id="<new-domain-id>"
            fi

            # --- Create fields ---
            fields_file="$instance_alias_dir_a/cases_fields_$domain_name_encoded.json"
            if [ -f "$fields_file" ] && [ -s "$fields_file" ]; then
                field_count=$(jq '.fields | length' "$fields_file" 2>/dev/null || echo 0)
                if [ "$field_count" -gt 0 ]; then
                    if [ -n "$dryrun" ]; then
                        echo "  [dry] Would create $field_count field(s) in domain $domain_name"
                    else
                        # Filter out system fields (type SYSTEM) — only create custom fields
                        custom_fields=$(jq '[.fields[] | select(.namespace != "System")]' "$fields_file" 2>/dev/null)
                        custom_count=$(echo "$custom_fields" | jq 'length' 2>/dev/null || echo 0)
                        if [ "$custom_count" -gt 0 ]; then
                            # batch-create-field accepts up to 50 fields
                            echo "$custom_fields" | jq -c '.[] | {name: .name, type: .type, description: (.description // "")}' |
                            while IFS= read -r field_def; do
                                [ -z "$field_def" ] && continue
                                field_name=$(echo "$field_def" | jq -r '.name')
                                aws connectcases batch-create-field \
                                    --domain-id "$target_domain_id" \
                                    --fields "[$field_def]" \
                                    $profile_flag 2>/dev/null || true
                            done
                            echo -e "  ${C_PASS}✓ Created $custom_count custom field(s)${C_RESET}"
                        fi
                    fi
                fi
            fi

            # --- Create layouts ---
            layouts_file="$instance_alias_dir_a/cases_layouts_$domain_name_encoded.json"
            if [ -f "$layouts_file" ] && [ -s "$layouts_file" ]; then
                layout_count=$(jq '.layouts | length' "$layouts_file" 2>/dev/null || echo 0)
                if [ "$layout_count" -gt 0 ]; then
                    if [ -n "$dryrun" ]; then
                        echo "  [dry] Would create $layout_count layout(s) in domain $domain_name"
                    else
                        while IFS= read -r layout_entry; do
                            [ -z "$layout_entry" ] && continue
                            layout_name=$(echo "$layout_entry" | jq -r '.name')
                            layout_content=$(echo "$layout_entry" | jq -c '.content // {}')
                            aws connectcases create-layout \
                                --domain-id "$target_domain_id" \
                                --name "$layout_name" \
                                --content "$layout_content" \
                                $profile_flag 2>/dev/null || true
                        done < <(jq -c '.layouts[]' "$layouts_file" 2>/dev/null)
                        echo -e "  ${C_PASS}✓ Created $layout_count layout(s)${C_RESET}"
                    fi
                fi
            fi

            # --- Create templates ---
            templates_file="$instance_alias_dir_a/cases_templates_$domain_name_encoded.json"
            if [ -f "$templates_file" ] && [ -s "$templates_file" ]; then
                template_count=$(jq '.templates | length' "$templates_file" 2>/dev/null || echo 0)
                if [ "$template_count" -gt 0 ]; then
                    if [ -n "$dryrun" ]; then
                        echo "  [dry] Would create $template_count template(s) in domain $domain_name"
                    else
                        while IFS= read -r template_entry; do
                            [ -z "$template_entry" ] && continue
                            template_name=$(echo "$template_entry" | jq -r '.name')
                            template_payload=$(echo "$template_entry" | jq -c 'del(.templateId, .templateArn, .createdTime, .lastModifiedTime)')
                            echo "$template_payload" > "$helper/cases_template_tmp.json"
                            aws connectcases create-template \
                                --domain-id "$target_domain_id" \
                                --name "$template_name" \
                                --cli-input-json "file://$helper/cases_template_tmp.json" \
                                $profile_flag 2>/dev/null || true
                        done < <(jq -c '.templates[]' "$templates_file" 2>/dev/null)
                        echo -e "  ${C_PASS}✓ Created $template_count template(s)${C_RESET}"
                    fi
                fi
            fi

        done < <(jq -r ".domainId + \" \" + .name" "$instance_alias_dir_a/cases_domains.json" 2>/dev/null | tr -d '\r')
    fi
fi

############################################################
#
# Customer Profiles Config Restore (domain → object types → calculated attributes)
#

cat <<EOD

Customer Profiles Config
------------------------
EOD
egrep "^profiles_objecttype_\|^profiles_calcattr_" "$helper_new" > $TEMPNEW 2>/dev/null || true
profiles_domain_file="$instance_alias_dir_a/profiles_domain.json"
if [ ! -f "$profiles_domain_file" ] || [ "$(jq '.DomainName // empty' "$profiles_domain_file" 2>/dev/null)" = "" ]; then
    echo "No Customer Profiles config to restore"
else
    src_domain_name=$(jq -r '.DomainName // empty' "$profiles_domain_file" | dos2unix)
    echo "  Source domain: $src_domain_name"

    # Check if target has a profiles domain
    target_profiles_domain=$(jq -r '.DomainName // empty' "$instance_alias_dir_b/profiles_domain.json" 2>/dev/null | dos2unix)

    if [ -z "$target_profiles_domain" ]; then
        # Create domain on target (use target instance alias as domain name)
        target_domain_name="${instance_alias_b:-$src_domain_name}"
        cat <<EOD >> "$helper_log"

$actionLead Create Customer Profiles domain: $target_domain_name
EOD
        if [ -n "$dryrun" ]; then
            echo "  [dry] Would create Customer Profiles domain: $target_domain_name"
        else
            create_output=$(aws customer-profiles create-domain \
                --domain-name "$target_domain_name" \
                --default-expiration-days 366 \
                $profile_flag 2>/dev/null) || true
            if [ -n "$create_output" ]; then
                echo -e "  ${C_PASS}✓ Created Customer Profiles domain: $target_domain_name${C_RESET}"
                target_profiles_domain="$target_domain_name"
            else
                echo -e "  ${C_FAIL}✗ Failed to create Customer Profiles domain${C_RESET}" >&2
            fi
        fi
    else
        echo "  Target domain exists: $target_profiles_domain"
    fi

    # --- Restore object types ---
    if [ -s $TEMPNEW ] || [ -s "$instance_alias_dir_a/profiles_object_types.json" ]; then
        ot_count=$(jq 'length' "$instance_alias_dir_a/profiles_object_types.json" 2>/dev/null || echo 0)
        if [ "$ot_count" -gt 0 ]; then
            restored_ot=0
            while IFS= read -r ot_name; do
                [ -z "$ot_name" ] && continue
                ot_name_encoded=$(path_encode "$ot_name")
                ot_file="$instance_alias_dir_a/profiles_objecttype_$ot_name_encoded.json"
                [ -f "$ot_file" ] || continue

                cat <<EOD >> "$helper_log"

$actionLead Create/update object type: $ot_name
EOD
                if [ -n "$dryrun" ]; then
                    echo "  [dry] Would put object type: $ot_name"
                else
                    # PutProfileObjectType is idempotent (creates or updates)
                    ot_payload=$(jq 'del(.LastUpdatedAt, .CreatedAt, .Tags)' "$ot_file" 2>/dev/null)
                    echo "$ot_payload" > "$helper/profiles_ot_$ot_name_encoded.json"
                    aws customer-profiles put-profile-object-type \
                        --domain-name "${target_profiles_domain:-$src_domain_name}" \
                        --object-type-name "$ot_name" \
                        --cli-input-json "file://$helper/profiles_ot_$ot_name_encoded.json" \
                        $profile_flag 2>/dev/null || true
                    restored_ot=$((restored_ot + 1))
                fi
            done < <(jq -r '.[].ObjectTypeName // empty' "$instance_alias_dir_a/profiles_object_types.json" | tr -d '\r')
            if [ -z "$dryrun" ] && [ "$restored_ot" -gt 0 ]; then
                echo -e "  ${C_PASS}✓ Restored $restored_ot object type(s)${C_RESET}"
            fi
        fi
    fi

    # --- Restore calculated attributes ---
    ca_count=$(jq 'length' "$instance_alias_dir_a/profiles_calculated_attrs.json" 2>/dev/null || echo 0)
    if [ "$ca_count" -gt 0 ]; then
        restored_ca=0
        while IFS= read -r ca_name; do
            [ -z "$ca_name" ] && continue
            ca_name_encoded=$(path_encode "$ca_name")
            ca_file="$instance_alias_dir_a/profiles_calcattr_$ca_name_encoded.json"
            [ -f "$ca_file" ] || continue

            cat <<EOD >> "$helper_log"

$actionLead Create calculated attribute: $ca_name
EOD
            if [ -n "$dryrun" ]; then
                echo "  [dry] Would create calculated attribute: $ca_name"
            else
                ca_payload=$(jq 'del(.CreatedAt, .LastUpdatedAt, .Tags)' "$ca_file" 2>/dev/null)
                echo "$ca_payload" > "$helper/profiles_ca_$ca_name_encoded.json"
                aws customer-profiles create-calculated-attribute-definition \
                    --domain-name "${target_profiles_domain:-$src_domain_name}" \
                    --calculated-attribute-name "$ca_name" \
                    --cli-input-json "file://$helper/profiles_ca_$ca_name_encoded.json" \
                    $profile_flag 2>/dev/null || true
                restored_ca=$((restored_ca + 1))
            fi
        done < <(jq -r '.[].CalculatedAttributeName // empty' "$instance_alias_dir_a/profiles_calculated_attrs.json" | tr -d '\r')
        if [ -z "$dryrun" ] && [ "$restored_ca" -gt 0 ]; then
            echo -e "  ${C_PASS}✓ Created $restored_ca calculated attribute(s)${C_RESET}"
        fi
    fi
fi
