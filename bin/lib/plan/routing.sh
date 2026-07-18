############################################################
#
# Routing Profiles
#

echo Checking Routing Profiles ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/routings.json" |
dos2unix |
while read routing_id_a routing_name; do
    routing_name_encoded=$(path_encode "$routing_name")
    routing_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/routings.json" | jq -r "select(.Name == \"${routing_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$routing_id_b" ]; then
        add_file "$instance_alias_dir_a" "routing_$routing_name_encoded.json" $helper_new
        add_file "$instance_alias_dir_a" "routingQs_$routing_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "routing_$routing_name_encoded.json" $helper_old
        add_file "$instance_alias_dir_b" "routingQs_$routing_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Routing Profile: $routing_name
s%$routing_id_a%$routing_id_b%g
EOD
    fi
done
test $? -eq 0 || error
