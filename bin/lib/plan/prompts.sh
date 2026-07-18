############################################################
#
# Prompts
#

echo Checking Prompts ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/prompts.json" |
dos2unix |
while read prompt_id_a prompt_name; do
    prompt_name_encoded=$(path_encode "$prompt_name")
    prompt_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/prompts.json" | jq -r "select(.Name == \"${prompt_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$prompt_id_b" ]; then
        echo "prompt_$prompt_name" >> $helper_new
    else
        echo "prompt_$prompt_name" >> $helper_old
        cat <<EOD >> $helper_sed
# Prompt: $prompt_name
s%$prompt_id_a%$prompt_id_b%g
EOD
    fi
done
test $? -eq 0 || error
