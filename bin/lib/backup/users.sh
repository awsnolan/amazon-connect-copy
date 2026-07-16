############################################################
# backup/users.sh — Hierarchy groups, users + proficiencies,
#                   authentication profiles
#
# Expects from orchestrator:
#   $instance_alias_dir, $instance_id, $profile_flag,
#   $maxitems, $TEMPFILE
############################################################

echo ""
echo "━━━ Users & Hierarchy ━━━"

############################################################
# User Hierarchy Groups
############################################################

aws_connect list-user-hierarchy-groups \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".UserHierarchyGroupSummaryList // [] | .[]" |
    jq -s "sort_by(.Name) | .[]" |
    tee "$instance_alias_dir/hierarchy_groups.json" |
    echo -e "\n$(jq -s "length") user hierarchy groups listed in \"$instance_alias_dir/hierarchy_groups.json\""

    jq -r ".Id + \" \" + .Name" "$instance_alias_dir/hierarchy_groups.json" |
    dos2unix |
    while read hg_id hg_name; do
        echo "Exporting hierarchy group $hg_name"
        hg_name_encoded=$(path_encode "$hg_name")
        aws_connect describe-user-hierarchy-group \
            --instance-id $instance_id \
            --hierarchy-group-id $hg_id \
            > "$instance_alias_dir/hierarchygroup_$hg_name_encoded.json" || error $LINENO
    done
    test $? -eq 0 || error
else
    echo "No user hierarchy groups found"
    echo "[]" > "$instance_alias_dir/hierarchy_groups.json"
fi

############################################################
# Users
############################################################

aws_connect list-users \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".UserSummaryList // [] | .[]" |
    jq -s "sort_by(.Username) | .[]" |
    tee "$instance_alias_dir/users.json" |
    echo -e "\n$(jq -s "length") users listed in \"$instance_alias_dir/users.json\""

    jq -r ".Id + \" \" + .Username" "$instance_alias_dir/users.json" |
    dos2unix |
    while read user_id user_name; do
        echo "Exporting user $user_name"
        user_name_encoded=$(path_encode "$user_name")
        aws_connect describe-user \
            --instance-id $instance_id \
            --user-id $user_id \
            > "$instance_alias_dir/user_$user_name_encoded.json" || error $LINENO
        # Export user proficiencies (skill levels)
        aws_connect list-user-proficiencies \
            --instance-id $instance_id \
            --user-id $user_id \
            --max-items $maxitems \
            > "$instance_alias_dir/userProficiencies_$user_name_encoded.json" 2>/dev/null || true
    done
    test $? -eq 0 || error
else
    echo "No users found"
    echo "[]" > "$instance_alias_dir/users.json"
fi

############################################################
# Authentication Profiles
############################################################

aws_connect list-authentication-profiles \
    --instance-id $instance_id \
    --max-items $maxitems \
    > $TEMPFILE 2>/dev/null || true

if [ -s $TEMPFILE ]; then
    cat $TEMPFILE |
    jq -r ".AuthenticationProfileSummaryList // [] | .[]" |
    jq -s "sort_by(.Name) | .[]" |
    tee "$instance_alias_dir/auth_profiles.json" |
    echo -e "\n$(jq -s "length") authentication profiles listed in \"$instance_alias_dir/auth_profiles.json\""

    jq -r ".Id + \" \" + .Name" "$instance_alias_dir/auth_profiles.json" |
    dos2unix |
    while read ap_id ap_name; do
        echo "Exporting authentication profile $ap_name"
        ap_name_encoded=$(path_encode "$ap_name")
        aws_connect describe-authentication-profile \
            --instance-id $instance_id \
            --authentication-profile-id $ap_id \
            > "$instance_alias_dir/authprofile_$ap_name_encoded.json" 2>/dev/null || true
    done
    test $? -eq 0 || error
else
    echo "No authentication profiles found"
    echo "[]" > "$instance_alias_dir/auth_profiles.json"
fi
