############################################################
#
# Quick Connects
#

echo Checking Quick Connects ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/quickconnects.json" |
dos2unix |
while read qc_id_a qc_name; do
    qc_name_encoded=$(path_encode "$qc_name")
    qc_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/quickconnects.json" | jq -r "select(.Name == \"${qc_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$qc_id_b" ]; then
        add_file "$instance_alias_dir_a" "quickconnect_$qc_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "quickconnect_$qc_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Quick Connect: $qc_name
s%$qc_id_a%$qc_id_b%g
EOD
    fi
done
test $? -eq 0 || error
