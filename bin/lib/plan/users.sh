############################################################
#
# Instance Attributes
#

echo Checking Instance Attributes ...
if [ -f "$instance_alias_dir_a/instance_attributes.json" ] && [ -f "$instance_alias_dir_b/instance_attributes.json" ]; then
    echo "instance_attributes.json" >> $helper_old
fi


############################################################
#
# Instance Storage Configs
#

echo Checking Instance Storage Configs ...
if [ -f "$instance_alias_dir_a/storage_configs.json" ] && [ -f "$instance_alias_dir_b/storage_configs.json" ]; then
    echo "storage_configs.json" >> $helper_old
fi


############################################################
#
# User Hierarchy Structure
#

echo Checking User Hierarchy Structure ...
if [ -f "$instance_alias_dir_a/hierarchy_structure.json" ] && [ -f "$instance_alias_dir_b/hierarchy_structure.json" ]; then
    echo "hierarchy_structure.json" >> $helper_old
fi


############################################################
#
# User Hierarchy Groups
#

echo Checking User Hierarchy Groups ...
if [ -s "$instance_alias_dir_a/hierarchy_groups.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/hierarchy_groups.json" |
    dos2unix |
    while read hg_id_a hg_name; do
        hg_name_encoded=$(path_encode "$hg_name")
        hg_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/hierarchy_groups.json" 2>/dev/null | jq -r "select(.Name == \"${hg_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$hg_id_b" ]; then
            add_file "$instance_alias_dir_a" "hierarchygroup_$hg_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "hierarchygroup_$hg_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Hierarchy Group: $hg_name
s%$hg_id_a%$hg_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Users
#

echo Checking Users ...
if [ -s "$instance_alias_dir_a/users.json" ]; then
    jq -r ".Id + \" \" + .Username" "$instance_alias_dir_a/users.json" |
    dos2unix |
    while read user_id_a user_name; do
        user_name_encoded=$(path_encode "$user_name")
        user_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/users.json" 2>/dev/null | jq -r "select(.Username == \"${user_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$user_id_b" ]; then
            add_file "$instance_alias_dir_a" "user_$user_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "user_$user_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# User: $user_name
s%$user_id_a%$user_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi


############################################################
#
# Authentication Profiles
#

echo Checking Authentication Profiles ...
if [ -s "$instance_alias_dir_a/auth_profiles.json" ] && [ "$(jq 'length' "$instance_alias_dir_a/auth_profiles.json" 2>/dev/null)" != "0" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/auth_profiles.json" |
    dos2unix |
    while read ap_id_a ap_name; do
        ap_name_encoded=$(path_encode "$ap_name")
        ap_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/auth_profiles.json" 2>/dev/null | jq -r "select(.Name == \"${ap_name//\"/%22}\") | .Id" | dos2unix)
        if [ -z "$ap_id_b" ]; then
            add_file "$instance_alias_dir_a" "authprofile_$ap_name_encoded.json" $helper_new
        else
            add_file "$instance_alias_dir_b" "authprofile_$ap_name_encoded.json" $helper_old
            cat <<EOD >> $helper_sed
# Auth Profile: $ap_name
s%$ap_id_a%$ap_id_b%g
EOD
        fi
    done
    test $? -eq 0 || error
fi
