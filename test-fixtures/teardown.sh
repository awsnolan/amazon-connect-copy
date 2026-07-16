#!/bin/bash
#
# Remove DR toolkit test fixtures from AWS
#
# Usage: ./teardown.sh <connect-instance-arn>
#

set -e

STACK_NAME="dr-toolkit-test-fixtures"
REGION="${AWS_REGION:-ap-southeast-2}"

CONNECT_INSTANCE_ARN="$1"
if [ -z "$CONNECT_INSTANCE_ARN" ]; then
    echo "Usage: $0 <connect-instance-arn>"
    exit 1
fi

INSTANCE_ID="${CONNECT_INSTANCE_ARN##*/}"

echo "━━━ Tearing down test fixtures ━━━"
echo ""

# 1. Get Lambda ARNs before deleting stack
CUSTOMER_LOOKUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='CustomerLookupArn'].OutputValue" \
    --output text 2>/dev/null || echo "")
AFTER_HOURS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AfterHoursArn'].OutputValue" \
    --output text 2>/dev/null || echo "")
LEX_BOT_ALIAS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LexBotAliasArn'].OutputValue" \
    --output text 2>/dev/null || echo "")

# 2. Disassociate from Connect
echo "Step 1: Disassociating from Connect instance..."
[ -n "$CUSTOMER_LOOKUP_ARN" ] && aws connect disassociate-lambda-function \
    --instance-id "$INSTANCE_ID" \
    --function-arn "$CUSTOMER_LOOKUP_ARN" \
    --region "$REGION" 2>/dev/null || true
[ -n "$AFTER_HOURS_ARN" ] && aws connect disassociate-lambda-function \
    --instance-id "$INSTANCE_ID" \
    --function-arn "$AFTER_HOURS_ARN" \
    --region "$REGION" 2>/dev/null || true
if [ -n "$LEX_BOT_ALIAS_ARN" ]; then
    aws connect disassociate-bot \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --lex-v2-bot "AliasArn=$LEX_BOT_ALIAS_ARN" 2>/dev/null || true
fi
echo "  Done"

# 3. Delete the contact flow
echo "Step 2: Deleting DR Test IVR contact flow..."
FLOW_ID=$(aws connect list-contact-flows \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "ContactFlowSummaryList[?Name=='DR Test IVR'].Id" \
    --output text 2>/dev/null)
if [ -n "$FLOW_ID" ] && [ "$FLOW_ID" != "None" ]; then
    aws connect delete-contact-flow \
        --instance-id "$INSTANCE_ID" \
        --contact-flow-id "$FLOW_ID" \
        --region "$REGION" 2>/dev/null || true
    echo "  Deleted"
else
    echo "  Not found (already deleted)"
fi

# 4. Delete CloudFormation stack
echo "Step 3: Deleting CloudFormation stack $STACK_NAME..."
aws cloudformation delete-stack \
    --stack-name "$STACK_NAME" \
    --region "$REGION"
echo "  Delete initiated (may take a few minutes)"

echo ""
echo "━━━ Teardown complete ━━━"
