############################################################
#
# Contact Flow Modules
#

echo Checking Contact Flow Modules ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/modules.json" |
dos2unix |
while read module_id_a module_name; do
    module_name_encoded=$(path_encode "$module_name")
    module_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/modules.json" | jq -r "select(.Name == \"${module_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$module_id_b" ]; then
        add_file "$instance_alias_dir_a" "module_$module_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "module_$module_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Contact Flow Module: $module_name
s%$module_id_a%$module_id_b%g
EOD
    fi
done
test $? -eq 0 || error

cat > $module_template <<'EOD'
{
  "Version": "2019-10-30",
  "StartAction": "13f850a8-4882-4b78-ac83-508273b6a3d6",
  "Metadata": {
    "entryPointPosition": {
      "x": 20,
      "y": 20
    },
    "ActionMetadata": {
      "13f850a8-4882-4b78-ac83-508273b6a3d6": {
        "position": {
          "x": 120,
          "y": 20
        }
      }
    }
  },
  "Actions": [
    {
      "Parameters": {},
      "Identifier": "13f850a8-4882-4b78-ac83-508273b6a3d6",
      "Type": "EndFlowModuleExecution",
      "Transitions": {}
    }
  ],
  "Settings": {
    "InputParameters": [],
    "OutputParameters": [],
    "Transitions": []
  }
}
EOD
