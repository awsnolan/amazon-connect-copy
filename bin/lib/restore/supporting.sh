############################################################
#
# Task Templates
#

cat <<EOD

Task Templates
--------------
EOD
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
            cat <<EOD
Dry-create view
$(cat "$helper/$view_json")

EOD
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
            cat <<EOD
Dry-update view
$(cat "$helper/$view_json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-view-content \
--instance-id $instance_id_b \
--view-id $view_id_b \
--status PUBLISHED \
--content "$(jq -r '.View.Content' "$helper/$view_json")"
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
