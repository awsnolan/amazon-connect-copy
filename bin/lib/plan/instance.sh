############################################################
#
# Instance setup — produces helper.var and base SED commands
#

echo "instance_alias_a=\"$instance_alias_a\"" | tee -a $helper_var
echo "instance_alias_dir_a=\"$instance_alias_dir_a\"" | tee -a $helper_var
echo "instance_alias_b=\"$instance_alias_b\"" | tee -a $helper_var
echo "instance_alias_dir_b=\"$instance_alias_dir_b\"" | tee -a $helper_var

. "$instance_alias_dir_a/instance.var"
instance_id_a=$instance_Id
instance_arn_a=$instance_Arn
eval $(echo $instance_arn_a | (IFS=: read x x x r a x; echo "region_a=$r; aws_ac_a=$a"))
region_a=$region_a
aws_ac_a=$aws_ac_a
echo "instance_id_a=\"$instance_id_a\"" | tee -a $helper_var
echo "instance_arn_a=\"$instance_arn_a\"" | tee -a $helper_var
echo "region_a=\"$region_a\"" | tee -a $helper_var
echo "aws_ac_a=\"$aws_ac_a\"" | tee -a $helper_var
echo "aws_profile_a=\"$aws_Profile\"" | tee -a $helper_var
echo "lambda_prefix_a=\"$lambda_prefix_a\"" | tee -a $helper_var
echo "lex_bot_prefix_a=\"$lex_bot_prefix_a\"" | tee -a $helper_var

. "$instance_alias_dir_b/instance.var"
instance_id_b=$instance_Id
instance_arn_b=$instance_Arn
eval $(echo $instance_arn_b | (IFS=: read x x x r a x; echo "region_b=$r; aws_ac_b=$a"))
region_b=$region_b
aws_ac_b=$aws_ac_b
echo "instance_id_b=\"$instance_id_b\"" | tee -a $helper_var
echo "instance_arn_b=\"$instance_arn_b\"" | tee -a $helper_var
echo "region_b=\"$region_b\"" | tee -a $helper_var
echo "aws_ac_b=\"$aws_ac_b\"" | tee -a $helper_var
echo "aws_profile_b=\"$aws_Profile\"" | tee -a $helper_var
echo "lambda_prefix_b=\"$lambda_prefix_b\"" | tee -a $helper_var
echo "lex_bot_prefix_b=\"$lex_bot_prefix_b\"" | tee -a $helper_var
echo "contact_flow_prefix=\"$instance_contact_flow_prefix\"" | tee -a $helper_var

# General SED commands
connect_arn_prefix_a="arn:aws:connect:$region_a:$aws_ac_a"
connect_arn_prefix_b="arn:aws:connect:$region_b:$aws_ac_b"
cat <<EOD >> $helper_sed
# General SED commands
s%$instance_id_a%$instance_id_b%g
s%$connect_arn_prefix_a%$connect_arn_prefix_b%g
EOD

if [ "$aws_ac_a" != "$aws_ac_b" ] || [ "$region_a" != "$region_b" ]; then
    echo "# Cross-account Lambda ARN remapping" >> $helper_sed
    echo "s%arn:aws:lambda:$region_a:$aws_ac_a%arn:aws:lambda:$region_b:$aws_ac_b%g" >> $helper_sed
    echo "# Cross-account Lex ARN remapping" >> $helper_sed
    echo "s%arn:aws:lex:$region_a:$aws_ac_a%arn:aws:lex:$region_b:$aws_ac_b%g" >> $helper_sed
fi

lambda_arn_prefix_a="arn:aws:lambda:$region_a:$aws_ac_a:function:$lambda_prefix_a"
lambda_arn_prefix_b="arn:aws:lambda:$region_b:$aws_ac_b:function:$lambda_prefix_b"
if [ -n "$lambda_prefix_a" ] && [ "$lambda_arn_prefix_a" != "$lambda_arn_prefix_b" ]; then
    echo "s%$lambda_arn_prefix_a%$lambda_arn_prefix_b%g" >> $helper_sed
fi

echo
