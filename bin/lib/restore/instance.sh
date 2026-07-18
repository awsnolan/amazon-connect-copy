############################################################
#
# Instance Attributes (feature flags)
#

section_header "Instance Foundation"
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
# Users — update routing profiles, security profiles, hierarchy
#
# Cross-account constraints:
#   - Users cannot be CREATED cross-account (password/DirectoryUserId unavailable)
#   - Users that exist on target are UPDATED (routing, security, hierarchy)
#   - Users that do NOT exist on target are SKIPPED gracefully
#

cat <<EOD

Users
-----
EOD

# Helper: resolve routing profile ID → name using source routings.json
_resolve_routing_profile_name() {
    local rp_id="$1"
    local rp_name
    rp_name=$(jq -r "select(.Id == \"$rp_id\") | .Name" "$instance_alias_dir_a/routings.json" 2>/dev/null | head -1 | tr -d '\r')
    if [ -z "$rp_name" ]; then
        rp_name="$rp_id"
    fi
    echo "$rp_name"
}

# Helper: resolve security profile IDs → names using source securityprofiles.json
_resolve_security_profile_names() {
    local sp_ids="$1"  # newline-separated IDs
    local names=""
    while IFS= read -r sp_id; do
        [ -z "$sp_id" ] && continue
        local sp_name
        sp_name=$(jq -r "select(.Id == \"$sp_id\") | .Name" "$instance_alias_dir_a/securityprofiles.json" 2>/dev/null | head -1 | tr -d '\r')
        if [ -z "$sp_name" ]; then
            sp_name="$sp_id"
        fi
        if [ -z "$names" ]; then
            names="$sp_name"
        else
            names="$names, $sp_name"
        fi
    done <<< "$sp_ids"
    echo "$names"
}

if [ -s "$instance_alias_dir_a/users.json" ]; then
    echo "Processing users (routing profiles and security profiles must exist)"

    # Build target user lookup: list users on target instance
    declare -A target_user_ids
    if [ -z "$dryrun" ]; then
        while IFS=$'\t' read -r t_uid t_uname; do
            [ -z "$t_uid" ] && continue
            target_user_ids["$t_uname"]="$t_uid"
        done < <(aws_connect list-users \
            --instance-id "$instance_id_b" 2>/dev/null | \
            jq -r '.UserSummaryList[] | .Id + "\t" + .Username' | tr -d '\r')
    else
        # Dry-run: use local target backup files if available
        while IFS=$'\t' read -r t_uid t_uname; do
            [ -z "$t_uid" ] && continue
            target_user_ids["$t_uname"]="$t_uid"
        done < <(jq -r '.User.Id + "\t" + .User.Username' "$instance_alias_dir_b"/user_*.json 2>/dev/null | tr -d '\r')
    fi

    echo

    jq -r ".Id + \" \" + .Username" "$instance_alias_dir_a/users.json" |
    dos2unix > "$TEMPFILE"_userlist

    while read user_id_a user_name; do
        user_name_encoded=$(path_encode "$user_name")
        user_file="$instance_alias_dir_a/user_$user_name_encoded.json"
        [ -f "$user_file" ] || continue

        # Determine target user ID
        user_id_b="${target_user_ids[$user_name]:-}"
        # Fallback: check local backup file
        if [ -z "$user_id_b" ]; then
            user_id_b=$(jq -r ".User.Id // empty" "$instance_alias_dir_b/user_$user_name_encoded.json" 2>/dev/null | tr -d '\r')
        fi

        if [ -z "$user_id_b" ] || [ "$user_id_b" = "null" ]; then
            # User does not exist on target
            # If --user-password-file provided, attempt to create the user
            if [ -n "$USER_PASSWORD_FILE" ] && [ -f "$USER_PASSWORD_FILE" ]; then
                local user_password
                user_password=$(grep "^${user_name}," "$USER_PASSWORD_FILE" 2>/dev/null | head -1 | cut -d, -f2-)
                if [ -n "$user_password" ]; then
                    # Build create-user payload
                    local create_json
                    create_json=$(cat "$user_file" | \
                        jq --arg iid "$instance_id_b" --arg pw "$user_password" \
                        '.User | del(.Id, .Arn, .DirectoryUserId, .LastModifiedTime, .LastModifiedRegion,
                                      .AfterContactWorkConfigs, .AutoAcceptConfigs,
                                      .PersistentConnectionConfigs, .PhoneNumberConfigs,
                                      .VoiceEnhancementConfigs) |
                         . + { InstanceId: $iid, Password: $pw }' | \
                        sed -f "$helper_sed")

                    cat <<EOD >> "$helper_log"

$actionLead Create user: $user_name (via password file)
EOD
                    if [ -n "$dryrun" ]; then
                        echo -e "  ${C_WARN}[dry] Would create $user_name (password from file)${C_RESET}"
                    else
                        echo "$create_json" > "$helper/user_create_$user_name_encoded.json"
                        aws_connect create-user \
                            --cli-input-json "file://$helper/user_create_$user_name_encoded.json" \
                            > "$helper/output_user_$user_name_encoded.json" 2>/dev/null
                        user_id_b=$(jq -r '.UserId // empty' "$helper/output_user_$user_name_encoded.json" 2>/dev/null | tr -d '\r')
                        if [ -n "$user_id_b" ] && [ "$user_id_b" != "null" ]; then
                            echo -e "  ${C_PASS}✓ Created $user_name${C_RESET}"
                            cat <<EOD >> "$helper_sed"
# User: $user_name
s%$user_id_a%$user_id_b%g
EOD
                        else
                            echo -e "  ${C_FAIL}✗ Failed to create $user_name${C_RESET}" >&2
                            continue
                        fi
                    fi
                    # Fall through to update routing/security/hierarchy below
                else
                    # Password not in file — skip
                    if [ -n "$dryrun" ]; then
                        echo -e "  ${C_SKIP}[skip] $user_name not found on target (no password in file)${C_RESET}"
                    else
                        echo -e "  ${C_SKIP}- Skipped $user_name (not found on target, no password in file)${C_RESET}"
                    fi
                    continue
                fi
            else
                # No password file — skip gracefully
                if [ -n "$dryrun" ]; then
                    echo -e "  ${C_SKIP}[skip] $user_name not found on target${C_RESET}"
                else
                    echo -e "  ${C_SKIP}- Skipped $user_name (not found on target)${C_RESET}"
                fi
                continue
            fi
        fi

        # --- User exists on target: update routing profile, security profiles, hierarchy ---

        # Resolve source routing profile name
        src_rp_id=$(jq -r '.User.RoutingProfileId // empty' "$user_file" | tr -d '\r')
        src_rp_name=$(_resolve_routing_profile_name "$src_rp_id")
        target_rp_id=$(echo "$src_rp_id" | sed -f "$helper_sed")

        # Resolve source security profile names
        src_sp_ids=$(jq -r '.User.SecurityProfileIds // [] | .[]' "$user_file" | tr -d '\r')
        src_sp_names=$(_resolve_security_profile_names "$src_sp_ids")
        target_sp_ids=$(echo "$src_sp_ids" | sed -f "$helper_sed" | tr -d '\r')

        if [ -n "$dryrun" ]; then
            # Dry-run output
            if [ -n "$src_rp_id" ]; then
                echo -e "  ${C_WARN}[dry] Would update $user_name routing profile → $src_rp_name${C_RESET}"
                verbose_detail "update-user-routing-profile --user-id $user_id_b --routing-profile-id $target_rp_id"
            fi
            if [ -n "$src_sp_ids" ]; then
                echo -e "  ${C_WARN}[dry] Would update $user_name security profiles → $src_sp_names${C_RESET}"
                verbose_detail "update-user-security-profiles --user-id $user_id_b --security-profile-ids $target_sp_ids"
            fi
            # Hierarchy group
            src_hg_id=$(jq -r '.User.HierarchyGroupId // empty' "$user_file" | tr -d '\r')
            if [ -n "$src_hg_id" ] && [ "$src_hg_id" != "null" ]; then
                echo -e "  ${C_WARN}[dry] Would update $user_name hierarchy group${C_RESET}"
                verbose_detail "update-user-hierarchy --user-id $user_id_b --hierarchy-group-id $(echo "$src_hg_id" | sed -f "$helper_sed")"
            fi
        else
            # --- Live update ---

            # Update routing profile
            if [ -n "$src_rp_id" ]; then
                cat <<EOD >> "$helper_log"

$actionLead Update user routing profile: $user_name → $src_rp_name
EOD
                aws_connect update-user-routing-profile \
                    --instance-id "$instance_id_b" \
                    --user-id "$user_id_b" \
                    --routing-profile-id "$target_rp_id" 2>/dev/null || true
                echo -e "  ${C_PASS}✓ Updated $user_name routing profile → $src_rp_name${C_RESET}"
            fi

            # Update security profiles
            if [ -n "$target_sp_ids" ]; then
                cat <<EOD >> "$helper_log"

$actionLead Update user security profiles: $user_name → $src_sp_names
EOD
                aws_connect update-user-security-profiles \
                    --instance-id "$instance_id_b" \
                    --user-id "$user_id_b" \
                    --security-profile-ids $target_sp_ids 2>/dev/null || true
                echo -e "  ${C_PASS}✓ Updated $user_name security profiles → $src_sp_names${C_RESET}"
            fi

            # Update hierarchy group (if set)
            src_hg_id=$(jq -r '.User.HierarchyGroupId // empty' "$user_file" | tr -d '\r')
            if [ -n "$src_hg_id" ] && [ "$src_hg_id" != "null" ]; then
                target_hg_id=$(echo "$src_hg_id" | sed -f "$helper_sed")
                cat <<EOD >> "$helper_log"

$actionLead Update user hierarchy group: $user_name
EOD
                aws_connect update-user-hierarchy \
                    --instance-id "$instance_id_b" \
                    --user-id "$user_id_b" \
                    --hierarchy-group-id "$target_hg_id" 2>/dev/null || true
                echo -e "  ${C_PASS}✓ Updated $user_name hierarchy group${C_RESET}"
            fi
        fi

        # Record ID mapping
        cat <<EOD >> "$helper_sed"
# User: $user_name
s%$user_id_a%$user_id_b%g
EOD
    done < "$TEMPFILE"_userlist
    rm -f "$TEMPFILE"_userlist
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

