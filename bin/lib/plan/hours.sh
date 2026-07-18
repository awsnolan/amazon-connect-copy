############################################################
#
# Hours of operations
#

echo Checking Hours of operations ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/hours.json" |
dos2unix |
while read hour_id_a hour_name; do
    hour_name_encoded=$(path_encode "$hour_name")
    hour_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/hours.json" | jq -r "select(.Name == \"${hour_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$hour_id_b" ]; then
        add_file "$instance_alias_dir_a" "hour_$hour_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "hour_$hour_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Hour of operation: $hour_name
s%$hour_id_a%$hour_id_b%g
EOD
    fi
done
test $? -eq 0 || error
