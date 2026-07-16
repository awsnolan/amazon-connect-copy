#!/bin/bash
#
# Deploy DR toolkit test fixtures to AWS
#
# Usage: ./deploy.sh <connect-instance-arn>
# Example: ./deploy.sh arn:aws:connect:ap-southeast-2:123456789012:instance/07995ce5-...
#

set -e

STACK_NAME="dr-toolkit-test-fixtures"
REGION="${AWS_REGION:-ap-southeast-2}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CONNECT_INSTANCE_ARN="$1"
if [ -z "$CONNECT_INSTANCE_ARN" ]; then
    echo "Usage: $0 <connect-instance-arn>"
    echo ""
    echo "Get your instance ARN with:"
    echo "  aws connect list-instances --query 'InstanceSummaryList[].Arn' --output text"
    exit 1
fi

INSTANCE_ID="${CONNECT_INSTANCE_ARN##*/}"

echo "━━━ Deploying test fixtures ━━━"
echo "  Stack  : $STACK_NAME"
echo "  Region : $REGION"
echo "  Instance: $INSTANCE_ID"
echo ""

# 1. Deploy SAM stack (DynamoDB + Lambdas + Lex)
echo "Step 1: Deploying SAM stack..."
sam build -t "$SCRIPT_DIR/template.yaml" --build-dir "$SCRIPT_DIR/.aws-sam/build"
sam deploy \
    --template-file "$SCRIPT_DIR/.aws-sam/build/template.yaml" \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "ConnectInstanceArn=$CONNECT_INSTANCE_ARN" \
    --no-confirm-changeset \
    --no-fail-on-empty-changeset

echo ""

# 2. Get outputs
echo "Step 2: Retrieving stack outputs..."
CUSTOMER_LOOKUP_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='CustomerLookupArn'].OutputValue" \
    --output text)
AFTER_HOURS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='AfterHoursArn'].OutputValue" \
    --output text)
LEX_BOT_ALIAS_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='LexBotAliasArn'].OutputValue" \
    --output text)

echo "  CustomerLookup ARN : $CUSTOMER_LOOKUP_ARN"
echo "  AfterHours ARN     : $AFTER_HOURS_ARN"
echo "  Lex Bot Alias ARN  : $LEX_BOT_ALIAS_ARN"
echo ""

# 3. Associate Lambdas with Connect instance
echo "Step 3: Associating Lambdas with Connect instance..."
aws connect associate-lambda-function \
    --instance-id "$INSTANCE_ID" \
    --function-arn "$CUSTOMER_LOOKUP_ARN" \
    --region "$REGION" 2>/dev/null || echo "  (already associated)"
aws connect associate-lambda-function \
    --instance-id "$INSTANCE_ID" \
    --function-arn "$AFTER_HOURS_ARN" \
    --region "$REGION" 2>/dev/null || echo "  (already associated)"
echo "  Done"
echo ""

# 4. Associate Lex V2 bot with Connect instance
echo "Step 4: Associating Lex V2 bot with Connect instance..."
aws connect associate-bot \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --lex-v2-bot "AliasArn=$LEX_BOT_ALIAS_ARN" 2>/dev/null || echo "  (already associated)"
echo "  Done"
echo ""

# 5. Seed DynamoDB with test data
echo "Step 5: Seeding DynamoDB test data..."
aws dynamodb batch-write-item \
    --region "$REGION" \
    --request-items '{
        "dr-test-customers": [
            {"PutRequest": {"Item": {"PhoneNumber": {"S": "+61400111222"}, "CustomerName": {"S": "Alice Johnson"}, "AccountTier": {"S": "Premium"}, "Language": {"S": "en-AU"}}}},
            {"PutRequest": {"Item": {"PhoneNumber": {"S": "+61400333444"}, "CustomerName": {"S": "Bob Smith"}, "AccountTier": {"S": "Standard"}, "Language": {"S": "en-AU"}}}},
            {"PutRequest": {"Item": {"PhoneNumber": {"S": "+61400555666"}, "CustomerName": {"S": "Charlie Brown"}, "AccountTier": {"S": "Enterprise"}, "Language": {"S": "en-AU"}}}}
        ]
    }' > /dev/null
echo "  3 test customers seeded"
echo ""

# 6. Create the contact flow
echo "Step 6: Creating DR Test IVR contact flow..."

# Get queue ARNs for the flow
BASIC_QUEUE_ARN=$(aws connect list-queues \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --queue-types STANDARD \
    --query "QueueSummaryList[?Name=='BasicQueue'].Arn" \
    --output text)
INBOUND_RECK_QUEUE_ARN=$(aws connect list-queues \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --queue-types STANDARD \
    --query "QueueSummaryList[?Name=='InboundReckQueue'].Arn" \
    --output text)

FLOW_CONTENT=$(cat "$SCRIPT_DIR/flows/dr_test_ivr.json" |
    sed "s|CUSTOMER_LOOKUP_ARN|$CUSTOMER_LOOKUP_ARN|g" |
    sed "s|AFTER_HOURS_ARN|$AFTER_HOURS_ARN|g" |
    sed "s|LEX_BOT_ALIAS_ARN|$LEX_BOT_ALIAS_ARN|g" |
    sed "s|BASIC_QUEUE_ARN|$BASIC_QUEUE_ARN|g" |
    sed "s|INBOUND_RECK_QUEUE_ARN|$INBOUND_RECK_QUEUE_ARN|g")

# Check if flow already exists
EXISTING_FLOW_ID=$(aws connect list-contact-flows \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --query "ContactFlowSummaryList[?Name=='DR Test IVR'].Id" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_FLOW_ID" ] && [ "$EXISTING_FLOW_ID" != "None" ]; then
    echo "  Flow exists, updating content..."
    aws connect update-contact-flow-content \
        --instance-id "$INSTANCE_ID" \
        --contact-flow-id "$EXISTING_FLOW_ID" \
        --content "$FLOW_CONTENT" \
        --region "$REGION"
else
    echo "  Creating new flow..."
    aws connect create-contact-flow \
        --instance-id "$INSTANCE_ID" \
        --name "DR Test IVR" \
        --description "Test IVR flow for DR toolkit - exercises Lambda, Lex, queues" \
        --type CONTACT_FLOW \
        --content "$FLOW_CONTENT" \
        --region "$REGION"
fi
echo "  Done"
echo ""

echo "━━━ Deployment complete ━━━"
echo ""
echo "Run connect_backup to verify:"
echo "  connect_backup -f qs-builder-in-sydney"
echo ""
echo "Teardown when done:"
echo "  ./teardown.sh $CONNECT_INSTANCE_ARN"
