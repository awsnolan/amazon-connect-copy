############################################################
#
# Instance Attributes (feature flags)
#

cat <<EOD

Instance Attributes
-------------------
EOD
if [ -f "$instance_alias_dir_a/instance_attributes.json" ]; then
    echo "Applying instance attributes from source to target"
    # Each line in the file is a separate JSON object with Attribute.AttributeType and Attribute.Value
    jq -r ".Attribute | .AttributeType + \" \" + .Value" "$instance_alias_dir_a/instance_attributes.json" 2>/dev/null |
    dos2unix |
    while read attr_type attr_value; do
        [ -z "$attr_type" ] && continue
        echo "  Setting $attr_type = $attr_value"
        cat <<EOD >> "$helper_log"

$actionLead Update instance attribute: $attr_type = $attr_value
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update instance attribute $attr_type = $attr_value

EOD
            cat <<EOD >> "$helper_log"
aws connect update-instance-attribute \
--instance-id $instance_id_b \
--attribute-type $attr_type \
--value $attr_value
EOD
            continue
        fi
        aws_connect update-instance-attribute \
            --instance-id $instance_id_b \
            --attribute-type $attr_type \
            --value $attr_value 2>/dev/null || true
    done
    test $? -eq 0 || error
else
    echo "No instance attributes file found (skipping)"
fi


############################################################
#
# Instance Storage Configs
#

cat <<EOD

Instance Storage Configs
------------------------
EOD
if [ -f "$instance_alias_dir_a/storage_configs.json" ]; then
    echo "Storage configs recorded — will require manual configuration."
    manual_action "Storage Configs" "Configure S3 buckets and KMS keys on target. Source: $instance_alias_dir_a/storage_configs.json"
else
    echo "No instance storage configs file found (skipping)"
fi


############################################################
#
# User Hierarchy Structure
#

cat <<EOD

User Hierarchy Structure
------------------------
EOD
if [ -f "$instance_alias_dir_a/hierarchy_structure.json" ]; then
    hg_struct=$(jq -r ".HierarchyStructure" "$instance_alias_dir_a/hierarchy_structure.json" 2>/dev/null)
    if [ -n "$hg_struct" ] && [ "$hg_struct" != "null" ]; then
        echo "Applying user hierarchy structure"
        cat "$instance_alias_dir_a/hierarchy_structure.json" |
        jq ".HierarchyStructure | {HierarchyStructure: .}" |
        sed -f "$helper_sed" > "$helper/hierarchy_structure.json"

        cat <<EOD >> "$helper_log"

$actionLead Update user hierarchy structure
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-update user hierarchy structure
$(cat "$helper/hierarchy_structure.json")

EOD
            cat <<EOD >> "$helper_log"
aws connect update-user-hierarchy-structure \
--instance-id $instance_id_b \
--hierarchy-structure "file://$helper/hierarchy_structure.json"
EOD
        else
            aws_connect update-user-hierarchy-structure \
                --instance-id $instance_id_b \
                --hierarchy-structure "$(jq -r '.HierarchyStructure' "$helper/hierarchy_structure.json")" 2>/dev/null || true
        fi
    else
        echo "No hierarchy structure defined"
    fi
else
    echo "No hierarchy structure file found (skipping)"
fi


############################################################
#
# User Hierarchy Groups
#

cat <<EOD

User Hierarchy Groups
---------------------
EOD
if [ -s "$instance_alias_dir_a/hierarchy_groups.json" ]; then
    # Process level by level (LevelId 1 first, then children)
    echo "Creating/updating user hierarchy groups (level order)"
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/hierarchy_groups.json" |
    dos2unix |
    while read hg_id_a hg_name; do
        hg_name_encoded=$(path_encode "$hg_name")
        hg_file="$instance_alias_dir_a/hierarchygroup_$hg_name_encoded.json"
        [ -f "$hg_file" ] || continue

        hg_id_b=$(jq -r ".HierarchyGroup.HierarchyGroupId" "$instance_alias_dir_b/hierarchygroup_$hg_name_encoded.json" 2>/dev/null | dos2unix)
        hg_level=$(jq -r ".HierarchyGroup.LevelId" "$hg_file" | dos2unix)
        hg_parent_id_a=$(jq -r ".HierarchyGroup.HierarchyPath | to_entries | last | .value.Id // empty" "$hg_file" 2>/dev/null | dos2unix)

        if [ -z "$hg_id_b" ] || [ "$hg_id_b" = "null" ]; then
            echo "Creating hierarchy group $hg_name"
            cat <<EOD >> "$helper_log"

$actionLead Create user hierarchy group: $hg_name
EOD
            if [ -n "$dryrun" ]; then
                cat <<EOD
Dry-create hierarchy group $hg_name (level $hg_level)

EOD
                cat <<EOD >> "$helper_log"
aws connect create-user-hierarchy-group \
--instance-id $instance_id_b \
--name "${hg_name//\"/\\\"}"
EOD
            else
                create_args="--instance-id $instance_id_b --name \"${hg_name//\"/\\\"}\""
                # Substitute parent ID if present
                if [ -n "$hg_parent_id_a" ]; then
                    hg_parent_id_b=$(sed -n "s%$hg_parent_id_a%&%p" "$helper_sed" 2>/dev/null | head -1)
                    hg_parent_id_b=$(sed -f "$helper_sed" <<< "$hg_parent_id_a" 2>/dev/null)
                    [ -n "$hg_parent_id_b" ] && create_args="$create_args --parent-group-id $hg_parent_id_b"
                fi
                aws_connect create-user-hierarchy-group \
                    --instance-id $instance_id_b \
                    --name "${hg_name//\"/\\\"}" \
                    > "$helper/output_hierarchygroup_$hg_name_encoded.json" 2>/dev/null || true
                hg_id_b=$(jq -r ".HierarchyGroupId" "$helper/output_hierarchygroup_$hg_name_encoded.json" 2>/dev/null | dos2unix)
                if [ -n "$hg_id_b" ] && [ "$hg_id_b" != "null" ]; then
                    cat <<EOD >> "$helper_sed"
# Hierarchy Group: $hg_name
s%$hg_id_a%$hg_id_b%g
EOD
                fi
            fi
        else
            echo "Hierarchy group $hg_name already exists"
        fi
    done
    test $? -eq 0 || error
else
    echo "No user hierarchy groups to process"
fi


############################################################
#
# Users
#

cat <<EOD

Users
-----
EOD
if [ -s "$instance_alias_dir_a/users.json" ]; then
    echo "Processing users (routing profiles and security profiles must exist)"
    jq -r ".Id + \" \" + .Username" "$instance_alias_dir_a/users.json" |
    dos2unix |
    while read user_id_a user_name; do
        user_name_encoded=$(path_encode "$user_name")
        user_file="$instance_alias_dir_a/user_$user_name_encoded.json"
        [ -f "$user_file" ] || continue

        user_id_b=$(jq -r ".User.Id" "$instance_alias_dir_b/user_$user_name_encoded.json" 2>/dev/null | dos2unix)
        if [ -z "$user_id_b" ] || [ "$user_id_b" = "null" ]; then
            echo "Creating user $user_name"
            cat "$user_file" |
            jq --arg iid $instance_id_b \
                ".User | del(.Id, .Arn, .DirectoryUserId, .LastModifiedTime, .LastModifiedRegion, .AfterContactWorkConfigs, .AutoAcceptConfigs, .PersistentConnectionConfigs, .PhoneNumberConfigs, .VoiceEnhancementConfigs) | . + { InstanceId: \$iid }" |
            sed -f "$helper_sed" > "$helper/user_$user_name_encoded.json"

            cat <<EOD >> "$helper_log"

$actionLead Create user: $user_name
EOD
            if [ -n "$dryrun" ]; then
                cat <<EOD
Dry-create user $user_name

EOD
                cat <<EOD >> "$helper_log"
aws connect create-user \
--cli-input-json "file://$helper/user_$user_name_encoded.json" \
> "$helper/output_user_$user_name_encoded.json"
EOD
            else
                aws_connect create-user \
                    --cli-input-json "file://$helper/user_$user_name_encoded.json" \
                    > "$helper/output_user_$user_name_encoded.json" 2>/dev/null || true
                user_id_b=$(jq -r ".UserId" "$helper/output_user_$user_name_encoded.json" 2>/dev/null | dos2unix)
                if [ -n "$user_id_b" ] && [ "$user_id_b" != "null" ]; then
                    cat <<EOD >> "$helper_sed"
# User: $user_name
s%$user_id_a%$user_id_b%g
EOD
                fi
            fi
        else
            echo "User $user_name already exists"
        fi
    done
    test $? -eq 0 || error
else
    echo "No users to process"
fi


############################################################
#
# Authentication Profiles
#

cat <<EOD

Authentication Profiles
-----------------------
EOD
if [ -s "$instance_alias_dir_a/auth_profiles.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/auth_profiles.json" 2>/dev/null |
    dos2unix |
    while read ap_id_a ap_name; do
        ap_name_encoded=$(path_encode "$ap_name")
        ap_file="$instance_alias_dir_a/authprofile_$ap_name_encoded.json"
        [ -f "$ap_file" ] || continue

        ap_id_b=$(jq -r ".AuthenticationProfile.Id" "$instance_alias_dir_b/authprofile_$ap_name_encoded.json" 2>/dev/null | dos2unix)
        if [ -n "$ap_id_b" ] && [ "$ap_id_b" != "null" ]; then
            echo "Updating authentication profile $ap_name"
            cat <<EOD >> "$helper_log"

$actionLead Update authentication profile: $ap_name
EOD
            if [ -n "$dryrun" ]; then
                cat <<EOD
Dry-update authentication profile $ap_name

EOD
                cat <<EOD >> "$helper_log"
aws connect update-authentication-profile \
--instance-id $instance_id_b \
--authentication-profile-id $ap_id_b
EOD
            else
                aws_connect update-authentication-profile \
                    --instance-id $instance_id_b \
                    --authentication-profile-id $ap_id_b \
                    --name "${ap_name//\"/\\\"}" 2>/dev/null || true
            fi
        else
            echo "Authentication profile $ap_name not found on target (may be auto-created by instance)"
        fi
    done
    test $? -eq 0 || error
else
    echo "No authentication profiles to process"
fi


############################################################
#
# Integration Associations
#

cat <<EOD

Integration Associations
------------------------
EOD
if [ -s "$instance_alias_dir_a/integrations.json" ]; then
    local_int_count=$(jq -s 'length' "$instance_alias_dir_a/integrations.json" 2>/dev/null)
    echo "$local_int_count integration associations recorded."
    jq -r ".IntegrationAssociationId + \" \" + .IntegrationType" "$instance_alias_dir_a/integrations.json" |
    dos2unix |
    while read ia_id ia_type; do
        manual_action "Integrations" "Verify $ia_type integration exists on target (source id=$ia_id)"
    done
else
    echo "No integration associations to process"
fi


############################################################
#
# Approved Origins
#

cat <<EOD

Approved Origins
----------------
EOD
if [ -s "$instance_alias_dir_a/approved_origins.json" ]; then
    jq -r "." "$instance_alias_dir_a/approved_origins.json" |
    dos2unix |
    while read origin; do
        [ -z "$origin" ] && continue
        echo "Associating approved origin: $origin"
        cat <<EOD >> "$helper_log"

$actionLead Associate approved origin: $origin
EOD
        if [ -n "$dryrun" ]; then
            cat <<EOD
Dry-associate approved origin $origin

EOD
            cat <<EOD >> "$helper_log"
aws connect associate-approved-origin \
--instance-id $instance_id_b \
--origin $origin
EOD
        else
            aws_connect associate-approved-origin \
                --instance-id $instance_id_b \
                --origin "$origin" 2>/dev/null || true
        fi
    done
    test $? -eq 0 || error
else
    echo "No approved origins to process"
fi


############################################################
#
# Security Keys
#

cat <<EOD

Security Keys
-------------
EOD
if [ -s "$instance_alias_dir_a/security_keys.json" ]; then
    local_sk_count=$(jq -s 'length' "$instance_alias_dir_a/security_keys.json" 2>/dev/null)
    echo "$local_sk_count security key(s) recorded — requires manual re-association."
    manual_action "Security Keys" "Re-associate $local_sk_count security key(s) on target instance. Source: $instance_alias_dir_a/security_keys.json"
else
    echo "No security keys to process"
fi

