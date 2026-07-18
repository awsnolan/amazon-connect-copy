############################################################
#
# Lambda Function Associations & Prefix Mapping
#

echo Checking Lambda Function Associations ...
if [ -s "$instance_alias_dir_a/lambda_associations.json" ]; then
    echo "lambda_associations.json" >> $helper_old
fi
