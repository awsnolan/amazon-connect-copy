#!/bin/bash
###############################################################################
#
# Deploy and verify the DR Validation Pipeline
#
# Usage:
#   ./deploy.sh <source-instance-alias> <target-instance-id> [options]
#
# Options:
#   --email <addr>          Email for failure alerts
#   --source-profile <p>    AWS profile for source instance (if cross-account)
#   --target-profile <p>    AWS profile for target instance (if cross-account)
#   --region <r>            AWS region (default: from AWS config or ap-southeast-2)
#
# Examples:
#   # Same account
#   ./deploy.sh qs-builder-in-sydney ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb --email oncall@example.com
#
#   # Cross-account
#   ./deploy.sh qs-builder-in-sydney ffffffff-eeee-dddd-cccc-bbbbbbbbbbbb \
#     --source-profile prod --target-profile dr --email oncall@example.com
#
# What it does:
#   1. Validates the CloudFormation template
#   2. Deploys the stack (S3 bucket, CodeBuild, EventBridge, SNS, CloudWatch alarm)
#   3. Triggers the first validation run
#   4. Waits for it to complete
#   5. Reports the result (metric value, S3 output, build status)
#
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_NAME="connect-dr-pipeline"

SOURCE_INSTANCE=""
TARGET_INSTANCE=""
ALERT_EMAIL=""
SOURCE_PROFILE=""
TARGET_PROFILE=""
REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-southeast-2")}"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --email)          ALERT_EMAIL="$2"; shift 2;;
        --source-profile) SOURCE_PROFILE="$2"; shift 2;;
        --target-profile) TARGET_PROFILE="$2"; shift 2;;
        --region)         REGION="$2"; shift 2;;
        --help|-h)
            sed -n '3,28p' "$0" | sed 's/^# \?//'
            exit 0;;
        -*)
            echo "Unknown option: $1"; exit 1;;
        *)
            if [ -z "$SOURCE_INSTANCE" ]; then
                SOURCE_INSTANCE="$1"
            elif [ -z "$TARGET_INSTANCE" ]; then
                TARGET_INSTANCE="$1"
            fi
            shift;;
    esac
done

if [ -z "$SOURCE_INSTANCE" ] || [ -z "$TARGET_INSTANCE" ]; then
    echo "Usage: $0 <source-instance-alias> <target-instance-id> [--email addr] [--source-profile p] [--target-profile p]"
    echo ""
    echo "Run '$0 --help' for full usage."
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DR Validation Pipeline — Deploy & Verify"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Source:         $SOURCE_INSTANCE"
echo "  Target:         $TARGET_INSTANCE"
echo "  Region:         $REGION"
echo "  Source profile: ${SOURCE_PROFILE:-<default>}"
echo "  Target profile: ${TARGET_PROFILE:-<same as source>}"
echo "  Alert email:    ${ALERT_EMAIL:-<none>}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

###############################################################################
# Step 1: Validate template
###############################################################################

echo "Step 1: Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://$SCRIPT_DIR/template.yaml" \
    --region "$REGION" > /dev/null
echo "  ✓ Template valid"
echo ""

###############################################################################
# Step 2: Deploy stack
###############################################################################

echo "Step 2: Deploying stack '$STACK_NAME'..."

PARAMS="SourceInstance=$SOURCE_INSTANCE TargetInstance=$TARGET_INSTANCE"
[ -n "$ALERT_EMAIL" ] && PARAMS="$PARAMS AlertEmail=$ALERT_EMAIL"
[ -n "$SOURCE_PROFILE" ] && PARAMS="$PARAMS SourceProfile=$SOURCE_PROFILE"
[ -n "$TARGET_PROFILE" ] && PARAMS="$PARAMS TargetProfile=$TARGET_PROFILE"

aws cloudformation deploy \
    --template-file "$SCRIPT_DIR/template.yaml" \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides $PARAMS \
    --no-fail-on-empty-changeset

echo "  ✓ Stack deployed"
echo ""

# Get outputs
BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='BackupBucketName'].OutputValue" --output text)
PROJECT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='ProjectName'].OutputValue" --output text)

echo "  Bucket:  $BUCKET"
echo "  Project: $PROJECT"
echo ""

###############################################################################
# Step 3: Trigger first validation run
###############################################################################

echo "Step 3: Triggering first validation run..."
BUILD_ID=$(aws codebuild start-build \
    --project-name "$PROJECT" \
    --region "$REGION" \
    --query 'build.id' --output text)
echo "  Build ID: $BUILD_ID"
echo ""

###############################################################################
# Step 4: Wait for completion
###############################################################################

echo "Step 4: Waiting for build to complete..."
echo -n "  "

while true; do
    STATUS=$(aws codebuild batch-get-builds \
        --ids "$BUILD_ID" --region "$REGION" \
        --query 'builds[0].buildStatus' --output text)
    
    case "$STATUS" in
        SUCCEEDED|FAILED|FAULT|STOPPED|TIMED_OUT)
            echo ""
            break
            ;;
        *)
            echo -n "."
            sleep 10
            ;;
    esac
done

echo "  Build status: $STATUS"
echo ""

###############################################################################
# Step 5: Report results
###############################################################################

echo "Step 5: Verifying results..."
echo ""

# Check S3 for validation result
echo "  S3 validation result:"
RESULT_JSON=$(aws s3 cp "s3://$BUCKET/validations/latest.json" - 2>/dev/null || echo "")
if [ -n "$RESULT_JSON" ]; then
    RESULT=$(echo "$RESULT_JSON" | jq -r '.result // "UNKNOWN"')
    PASS_COUNT=$(echo "$RESULT_JSON" | jq -r '.summary.pass // 0')
    FAIL_COUNT=$(echo "$RESULT_JSON" | jq -r '.summary.fail // 0')
    TOTAL_COUNT=$(echo "$RESULT_JSON" | jq -r '.summary.total // 0')
    echo "    Result: $RESULT ($PASS_COUNT passed, $FAIL_COUNT failed, $TOTAL_COUNT total)"
else
    echo "    (not found in S3 — check build logs)"
    RESULT="UNKNOWN"
fi
echo ""

# Check CloudWatch metric
echo "  CloudWatch metric:"
METRIC_VALUE=$(aws cloudwatch get-metric-statistics \
    --namespace ConnectDR \
    --metric-name ValidationResult \
    --dimensions "Name=SourceInstance,Value=$SOURCE_INSTANCE" "Name=TargetInstance,Value=$TARGET_INSTANCE" \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 3600 --statistics Minimum \
    --region "$REGION" \
    --query 'Datapoints[0].Minimum' --output text 2>/dev/null || echo "None")
echo "    ConnectDR/ValidationResult = $METRIC_VALUE"
echo ""

# Check backup in S3
echo "  S3 backup:"
BACKUP_COUNT=$(aws s3 ls "s3://$BUCKET/backups/latest/" --region "$REGION" 2>/dev/null | wc -l | tr -d ' ')
echo "    $BACKUP_COUNT files in backups/latest/"
echo ""

###############################################################################
# Summary
###############################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$STATUS" = "SUCCEEDED" ] && ([ "$RESULT" = "PASS" ] || [ "$RESULT" = "WARN" ]); then
    echo "  ✓ Pipeline deployed and verified successfully"
    echo ""
    echo "  Your DR instance is validated. The pipeline will run daily at 06:00 UTC."
    echo "  If validation fails, you'll receive an alert at: ${ALERT_EMAIL:-<no email configured>}"
else
    echo "  ⚠ Pipeline deployed but validation did not pass"
    echo ""
    echo "  Build status: $STATUS"
    echo "  Validation:   $RESULT"
    echo ""
    echo "  Check build logs:"
    echo "    aws codebuild batch-get-builds --ids $BUILD_ID --query 'builds[0].logs.deepLink' --output text"
    echo ""
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "  Failures:"
        echo "$RESULT_JSON" | jq -r '.failures[]? | "    [\(.id)] \(.label): \(.detail)"' 2>/dev/null
    fi
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
