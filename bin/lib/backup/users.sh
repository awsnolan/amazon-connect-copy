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
    jq -r '.UserHierarchyGroupSummaryList // [] | sort_by(.Name) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/hierarchy_groups.json"
    echo "$(jq -s 'length' "$instance_alias_dir/hierarchy_groups.json") user hierarchy groups"

    while read hg_id hg_name; do
        [ -z "$hg_id" ] && continue
        echo "  Exporting hierarchy group $hg_name"
        hg_name_encoded=$(path_encode "$hg_name")
        aws_connect describe-user-hierarchy-group \
            --instance-id $instance_id \
            --hierarchy-group-id $hg_id \
            > "$instance_alias_dir/hierarchygroup_$hg_name_encoded.json" || error $LINENO
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/hierarchy_groups.json" | dos2unix)
else
    echo "  No user hierarchy groups found"
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
    jq -r '.UserSummaryList // [] | sort_by(.Username) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/users.json"
    echo "$(jq -s 'length' "$instance_alias_dir/users.json") users"

    while IFS=$'\t' read -r user_id user_name; do
        [ -z "$user_id" ] && continue
        echo "  Exporting user $user_name"
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
    done < <(jq -r '.Id + "\t" + .Username' "$instance_alias_dir/users.json" | dos2unix)
else
    echo "  No users found"
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
    jq -r '.AuthenticationProfileSummaryList // [] | sort_by(.Name) | .[]' "$TEMPFILE" \
    > "$instance_alias_dir/auth_profiles.json"
    echo "$(jq -s 'length' "$instance_alias_dir/auth_profiles.json") authentication profiles"

    while IFS=$'\t' read -r ap_id ap_name; do
        [ -z "$ap_id" ] && continue
        echo "  Exporting authentication profile $ap_name"
        ap_name_encoded=$(path_encode "$ap_name")
        aws_connect describe-authentication-profile \
            --instance-id $instance_id \
            --authentication-profile-id $ap_id \
            > "$instance_alias_dir/authprofile_$ap_name_encoded.json" 2>/dev/null || true
    done < <(jq -r '.Id + "\t" + .Name' "$instance_alias_dir/auth_profiles.json" | dos2unix)
else
    echo "  No authentication profiles found"
    echo "[]" > "$instance_alias_dir/auth_profiles.json"
fi
