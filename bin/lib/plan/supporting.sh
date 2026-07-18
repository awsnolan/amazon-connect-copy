############################################################
#
# Agent Statuses
#

echo Checking Agent Statuses ...
if [ -s "$instance_alias_dir_a/agentstatuses.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/agentstatuses.json" |
    dos2unix |
    while read as_id_a as_name; do
        as_name_encoded=$(path_encode "$as_name")
        as_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/agentstatuses.json" | jq -r "select(.Name == \"${as_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$as_id_b" ]; then
            add_file "$instance_alias_dir_a" "agentstatus_$as_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "agentstatus_$as_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Agent Status: $as_name
s%$as_id_a%$as_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Security Profiles
#

echo Checking Security Profiles ...
if [ -s "$instance_alias_dir_a/securityprofiles.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/securityprofiles.json" |
    dos2unix |
    while read sp_id_a sp_name; do
        sp_name_encoded=$(path_encode "$sp_name")
        sp_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/securityprofiles.json" | jq -r "select(.Name == \"${sp_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$sp_id_b" ]; then
            add_file "$instance_alias_dir_a" "securityprofile_$sp_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "securityprofile_$sp_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Security Profile: $sp_name
s%$sp_id_a%$sp_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Predefined Attributes
#

echo Checking Predefined Attributes ...
if [ -s "$instance_alias_dir_a/predefinedattributes.json" ]; then
    jq -r ".Name" "$instance_alias_dir_a/predefinedattributes.json" |
    dos2unix |
    while read pa_name; do
        pa_name_encoded=$(path_encode "$pa_name")
        pa_exists_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/predefinedattributes.json" | jq -r "select(.Name == \"${pa_name//\"/%22}\") | .Name" | dos2unix)
        if [ -z "$pa_exists_b" ]; then
            add_file "$instance_alias_dir_a" "predefinedattribute_$pa_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "predefinedattribute_$pa_name_encoded.json" $helper_old
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Task Templates
#

echo Checking Task Templates ...
if [ -s "$instance_alias_dir_a/tasktemplates.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/tasktemplates.json" |
    dos2unix |
    while read tt_id_a tt_name; do
        tt_name_encoded=$(path_encode "$tt_name")
        tt_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/tasktemplates.json" | jq -r "select(.Name == \"${tt_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$tt_id_b" ]; then
            add_file "$instance_alias_dir_a" "tasktemplate_$tt_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "tasktemplate_$tt_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Task Template: $tt_name
s%$tt_id_a%$tt_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Evaluation Forms
#

echo Checking Evaluation Forms ...
if [ -s "$instance_alias_dir_a/evaluationforms.json" ]; then
    jq -r ".EvaluationFormId + \" \" + .Title" "$instance_alias_dir_a/evaluationforms.json" |
    dos2unix |
    while read ef_id_a ef_title; do
        ef_title_encoded=$(path_encode "$ef_title")
        ef_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/evaluationforms.json" | jq -r "select(.Title == \"${ef_title//\"/%22}\") | .EvaluationFormId" | dos2unix)
        if [ -z "$ef_id_b" ]; then
            add_file "$instance_alias_dir_a" "evaluationform_$ef_title_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "evaluationform_$ef_title_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Evaluation Form: $ef_title
s%$ef_id_a%$ef_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Rules
#

echo Checking Rules ...
if [ -s "$instance_alias_dir_a/rules.json" ]; then
    jq -r ".RuleId + \" \" + .Name" "$instance_alias_dir_a/rules.json" |
    dos2unix |
    while read rule_id_a rule_name; do
        rule_name_encoded=$(path_encode "$rule_name")
        rule_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/rules.json" | jq -r "select(.Name == \"${rule_name//\"/%22}\") | .RuleId" | dos2unix)
        if [ -z "$rule_id_b" ]; then
            add_file "$instance_alias_dir_a" "rule_$rule_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "rule_$rule_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Rule: $rule_name
s%$rule_id_a%$rule_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Views
#

echo Checking Views ...
if [ -s "$instance_alias_dir_a/views.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/views.json" |
    dos2unix |
    while read view_id_a view_name; do
        view_name_encoded=$(path_encode "$view_name")
        # Skip AWS-managed views that don't have detail files
        [ ! -f "$instance_alias_dir_a/view_$view_name_encoded.json" ] && continue
        view_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/views.json" 2>/dev/null | jq -r "select(.Name == \"${view_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$view_id_b" ]; then
            add_file "$instance_alias_dir_a" "view_$view_name_encoded.json" $helper_new
        else
            # Only add to helper_old if target also has the detail file
            if [ -f "$instance_alias_dir_b/view_$view_name_encoded.json" ]; then
                add_file "$instance_alias_dir_b" "view_$view_name_encoded.json" $helper_old
            fi
            cat <<EOD >> $helper_sed
# View: $view_name
s%$view_id_a%$view_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Vocabularies
#

echo Checking Vocabularies ...
if [ -s "$instance_alias_dir_a/vocabularies.json" ]; then
    jq -r ".VocabularyId + \" \" + .VocabularyName" "$instance_alias_dir_a/vocabularies.json" |
    dos2unix |
    while read vocab_id_a vocab_name; do
        vocab_name_encoded=$(path_encode "$vocab_name")
        vocab_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/vocabularies.json" 2>/dev/null | jq -r "select(.VocabularyName == \"${vocab_name//\"/%22}\") | .VocabularyId" | dos2unix)
        if [ -z "$vocab_id_b" ]; then
            add_file "$instance_alias_dir_a" "vocabulary_$vocab_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "vocabulary_$vocab_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Vocabulary: $vocab_name
s%$vocab_id_a%$vocab_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Data Tables
#

echo Checking Data Tables ...
if [ -s "$instance_alias_dir_a/datatables.json" ]; then
    jq -r ".TableId + \" \" + .TableName" "$instance_alias_dir_a/datatables.json" |
    dos2unix |
    while read dt_id_a dt_name; do
        dt_name_encoded=$(path_encode "$dt_name")
        dt_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/datatables.json" 2>/dev/null | jq -r "select(.TableName == \"${dt_name//\"/%22}\") | .TableId" | dos2unix)
        if [ -z "$dt_id_b" ]; then
            add_file "$instance_alias_dir_a" "datatable_$dt_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "datatable_$dt_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Data Table: $dt_name
s%$dt_id_a%$dt_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Phone Numbers (flow associations only — numbers must be pre-claimed)
#

echo Checking Phone Numbers ...
if [ -s "$instance_alias_dir_a/phonenumbers.json" ]; then
    echo "phonenumbers.json" >> $helper_old
    jq -r ".PhoneNumberId + \" \" + .PhoneNumber" "$instance_alias_dir_a/phonenumbers.json" |
    dos2unix |
    while read pn_id_a pn_number; do
        pn_encoded=$(path_encode "$pn_number")
        pn_id_b=$(jq -r ".PhoneNumberId" "$instance_alias_dir_b/phonenumber_$pn_encoded.json" 2>/dev/null | dos2unix)
        if [ -n "$pn_id_b" ] && [ "$pn_id_b" != "null" ]; then
            cat <<EOD >> $helper_sed
# Phone Number: $pn_number
s%$pn_id_a%$pn_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Integration Associations
#

echo Checking Integration Associations ...
if [ -s "$instance_alias_dir_a/integrations.json" ]; then
    echo "integrations.json" >> $helper_old
    echo "NOTE: Integration associations reference external systems (Lex V2, Wisdom, Voice ID, Cases) - verify external resources exist on target account."
fi


############################################################
#
# Approved Origins
#

echo Checking Approved Origins ...
if [ -s "$instance_alias_dir_a/approved_origins.json" ]; then
    echo "approved_origins.json" >> $helper_old
fi


############################################################
#
# Security Keys
#

echo Checking Security Keys ...
if [ -s "$instance_alias_dir_a/security_keys.json" ]; then
    echo "security_keys.json" >> $helper_old
    echo "NOTE: Security keys (customer input encryption) cannot be automatically copied - manual re-association required."
fi


############################################################
#
# Email Addresses
#

echo Checking Email Addresses ...
if [ -s "$instance_alias_dir_a/email_addresses.json" ]; then
    echo "email_addresses.json" >> $helper_old
    echo "NOTE: Email addresses require domain verification on target instance - manual setup required."
fi


############################################################
#
# Attachment Configuration
#

echo Checking Attachment Configuration ...
if [ -f "$instance_alias_dir_a/attachment_config.json" ]; then
    echo "attachment_config.json" >> $helper_old
fi


############################################################
#
# Connect Cases
#

echo Checking Connect Cases ...
if [ -s "$instance_alias_dir_a/cases_domains.json" ]; then
    echo "cases_domains.json" >> $helper_old
    echo "NOTE: Connect Cases domains and resources may require manual verification on target instance."
fi


############################################################
#
# Outbound Campaigns
#

echo Checking Outbound Campaigns ...
if [ -s "$instance_alias_dir_a/campaigns.json" ]; then
    echo "campaigns.json" >> $helper_old
    echo "NOTE: Outbound campaigns reference Connect instance IDs and external resources - verify after copy."
fi
