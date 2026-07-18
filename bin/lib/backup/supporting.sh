############################################################
# backup/supporting.sh — Task templates, evaluation forms,
#                        rules, views, vocabularies, data tables
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE, $jq_prefix_filter, $jq_prefix_filter_text
############################################################

echo ""
section_header "Supporting Resources"

############################################################
# Task Templates
############################################################

aws_connect list-task-templates \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r "[.TaskTemplates[]$jq_prefix_filter] | sort_by(.Name) | .[]" "$TEMPFILE" \
    > "$instance_alias_dir/tasktemplates.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/tasktemplates.json") task templates listed in \"$instance_alias_dir/tasktemplates.json\"$jq_prefix_filter_text"

    while read tt_id tt_name; do
        echo "Exporting task template $tt_name"
        tt_name_encoded=$(path_encode "$tt_name")
        aws_connect get-task-template \
            --instance-id $instance_id \
            --task-template-id $tt_id \
            > "$instance_alias_dir/tasktemplate_$tt_name_encoded.json" || error $LINENO
    done < <(    jq -r ".Id + \" \" + .Name" "$instance_alias_dir/tasktemplates.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No task templates found"
    echo "[]" > "$instance_alias_dir/tasktemplates.json"
fi

############################################################
# Evaluation Forms (Quality Management)
############################################################

aws_connect list-evaluation-forms \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r "[.EvaluationFormSummaryList[]$jq_prefix_filter] | sort_by(.Title) | .[]" "$TEMPFILE" \
    > "$instance_alias_dir/evaluationforms.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/evaluationforms.json") evaluation forms listed in \"$instance_alias_dir/evaluationforms.json\"$jq_prefix_filter_text"

    while read ef_id ef_title; do
        echo "Exporting evaluation form $ef_title"
        ef_title_encoded=$(path_encode "$ef_title")
        aws_connect describe-evaluation-form \
            --instance-id $instance_id \
            --evaluation-form-id $ef_id \
            > "$instance_alias_dir/evaluationform_$ef_title_encoded.json" || error $LINENO
    done < <(    jq -r ".EvaluationFormId + \" \" + .Title" "$instance_alias_dir/evaluationforms.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No evaluation forms found"
    echo "[]" > "$instance_alias_dir/evaluationforms.json"
fi

############################################################
# Rules (Contact Lens automation rules)
############################################################

aws_connect list-rules \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r "[.RuleSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]" "$TEMPFILE" \
    > "$instance_alias_dir/rules.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/rules.json") rules listed in \"$instance_alias_dir/rules.json\"$jq_prefix_filter_text"

    while read rule_id rule_name; do
        echo "Exporting rule $rule_name"
        rule_name_encoded=$(path_encode "$rule_name")
        aws_connect describe-rule \
            --instance-id $instance_id \
            --rule-id $rule_id \
            > "$instance_alias_dir/rule_$rule_name_encoded.json" || error $LINENO
    done < <(    jq -r ".RuleId + \" \" + .Name" "$instance_alias_dir/rules.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No rules found"
    echo "[]" > "$instance_alias_dir/rules.json"
fi

############################################################
# Views (Agent Workspace)
############################################################

aws_connect list-views \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r "[.ViewsSummaryList[]$jq_prefix_filter] | sort_by(.Name) | .[]" "$TEMPFILE" \
    > "$instance_alias_dir/views.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/views.json") views listed in \"$instance_alias_dir/views.json\"$jq_prefix_filter_text"

    while read view_id view_name; do
        echo "Exporting view $view_name"
        view_name_encoded=$(path_encode "$view_name")
        describe_or_skip "$view_name" "$instance_alias_dir/view_$view_name_encoded.json" \
            aws_connect describe-view \
            --instance-id $instance_id \
            --view-id $view_id || true
    done < <(    jq -r ".Id + \" \" + .Name" "$instance_alias_dir/views.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No views found"
    echo "[]" > "$instance_alias_dir/views.json"
fi

############################################################
# Vocabularies (custom vocabulary for Contact Lens transcription)
############################################################

aws_connect list-default-vocabularies \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r '[.DefaultVocabularyList[]] | sort_by(.VocabularyName) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/vocabularies.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/vocabularies.json") vocabularies listed in \"$instance_alias_dir/vocabularies.json\""

    while read vocab_id vocab_name; do
        echo "Exporting vocabulary content $vocab_name"
        vocab_name_encoded=$(path_encode "$vocab_name")
        aws_connect describe-vocabulary \
            --instance-id $instance_id \
            --vocabulary-id $vocab_id \
            > "$instance_alias_dir/vocabulary_$vocab_name_encoded.json" 2>/dev/null || true
    done < <(    jq -r ".VocabularyId + \" \" + .VocabularyName" "$instance_alias_dir/vocabularies.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No vocabularies found"
    echo "[]" > "$instance_alias_dir/vocabularies.json"
fi

############################################################
# Data Tables (flow lookup tables)
############################################################

aws_connect list-data-tables \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    jq -r '[.DataTableSummaryList[]] | sort_by(.TableName) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/datatables.json"
    echo -e "\n$(jq -s "length" "$instance_alias_dir/datatables.json") data tables listed in \"$instance_alias_dir/datatables.json\""

    while read dt_id dt_name; do
        echo "Exporting data table $dt_name"
        dt_name_encoded=$(path_encode "$dt_name")
        aws_connect describe-data-table \
            --instance-id $instance_id \
            --table-id $dt_id \
            > "$instance_alias_dir/datatable_$dt_name_encoded.json" 2>/dev/null || true
    done < <(    jq -r ".TableId + \" \" + .TableName" "$instance_alias_dir/datatables.json" | tr -d '\r')
    test $? -eq 0 || error
else
    echo "No data tables found"
    echo "[]" > "$instance_alias_dir/datatables.json"
fi
