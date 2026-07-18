############################################################
#
# Contact Flows
#

echo Checking Contact Flows ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/flows.json" |
dos2unix |
while read flow_id_a flow_name; do
    flow_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/flows.json" | jq -r "select(.Name == \"${flow_name//\"/%22}\") | .Id" | dos2unix)
    flow_name_encoded=$(path_encode "$flow_name")
    if [ -z "$flow_id_b" ]; then
        add_file "$instance_alias_dir_a" "flow_$flow_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "flow_$flow_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Contact Flow: $flow_name
s%$flow_id_a%$flow_id_b%g
EOD
    fi
done
test $? -eq 0 || error

cat > $flow_template <<'EOD'
{
    "Version": "2019-10-30",
    "StartAction": "e093fb75-2263-4594-875e-2d8e9974595f",
    "Metadata": {
        "entryPointPosition": {
            "x": 20,
            "y": 20
        },
        "snapToGrid": false,
        "ActionMetadata": {
            "e093fb75-2263-4594-875e-2d8e9974595f": {
                "position": {
                    "x": 120,
                    "y": 20
                }
            }
        }
    },
    "Actions": [
        {
            "Identifier": "e093fb75-2263-4594-875e-2d8e9974595f",
            "Type": "DisconnectParticipant",
            "Parameters": {},
            "Transitions": {}
        }
    ]
}
EOD
