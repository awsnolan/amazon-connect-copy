############################################################
#
# Queues
#

echo Checking Queues ...
jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/queues.json" |
dos2unix |
while read queue_id_a queue_name; do
    queue_name_encoded=$(path_encode "$queue_name")
    queue_id_b=$(sed -e's/\\"/%22/g' "$instance_alias_dir_b/queues.json" | jq -r "select(.Name == \"${queue_name//\"/%22}\") | .Id" | dos2unix)
    if [ -z "$queue_id_b" ]; then
        add_file "$instance_alias_dir_a" "queue_$queue_name_encoded.json" $helper_new
    else
        add_file "$instance_alias_dir_b" "queue_$queue_name_encoded.json" $helper_old
        cat <<EOD >> $helper_sed
# Queue: $queue_name
s%$queue_id_a%$queue_id_b%g
EOD
    fi
done
test $? -eq 0 || error


############################################################
#
# Queue → Quick Connect Associations
#

echo Checking Queue Quick Connect Associations ...
if [ -s "$instance_alias_dir_a/queues.json" ]; then
    jq -r ".Id + \" \" + .Name" "$instance_alias_dir_a/queues.json" |
    dos2unix |
    while read queue_id_a queue_name; do
        queue_name_encoded=$(path_encode "$queue_name")
        qc_file_a="$instance_alias_dir_a/queueQCs_$queue_name_encoded.json"
        qc_file_b="$instance_alias_dir_b/queueQCs_$queue_name_encoded.json"
        if [ -f "$qc_file_a" ]; then
            echo "queueQCs_$queue_name_encoded.json" >> $helper_old
        fi
    done
    test $? -eq 0 || error
fi
