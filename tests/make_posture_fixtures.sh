#!/bin/bash
# Generates facts fixtures for connect_storage_posture.
# Each fixture isolates one posture outcome so the rules can be tested
# without AWS access.
set -e
D="$(cd "$(dirname "$0")" && pwd)/fixtures/posture"
mkdir -p "$D"

B="amzn-s3-demo-bucket"
DB="amzn-s3-demo-dr-bucket"
KEY="arn:aws:kms:ap-southeast-2:111111111111:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
RKEY="arn:aws:kms:us-west-2:111111111111:key/ffffffff-9999-8888-7777-666666666666"

cfg() {  # $1=type $2=prefix $3=encryption
  cat <<EOD
{"resource_type":"$1","storage_type":"S3","bucket":"$B","prefix":"$2","encryption":"$3","kms_key":"$KEY","association_id":"assoc-$1"}
EOD
}

three_configs="$(cfg CALL_RECORDINGS connect/acme/CallRecordings KMS),$(cfg CHAT_TRANSCRIPTS connect/acme/ChatTranscripts KMS),$(cfg SCHEDULED_REPORTS connect/acme/Reports KMS)"

bucket() {  # $1=versioning $2=replication-json $3=replication_error $4=destinations $5=metrics
  cat <<EOD
    "$B": {
      "reachable": true,
      "region": "ap-southeast-2",
      "error": null,
      "versioning": "$1",
      "encryption": {"algorithm":"aws:kms","key":"$KEY"},
      "object_lock": "Disabled",
      "replication": $2,
      "replication_error": $3,
      "destinations": $4,
      "metrics": $5
    }
EOD
}

wrap() {  # $1=filename $2=buckets-block $3=dr_region
  cat > "$D/$1" <<EOD
{
  "collected_at": "2026-11-20T04:00:00Z",
  "dr_region_expected": $3,
  "configs": [$three_configs],
  "buckets": {
$2
  }
}
EOD
  jq -e . "$D/$1" >/dev/null || { echo "INVALID JSON: $1" >&2; exit 1; }
}

DESTS="{\"$DB\":{\"reachable\":true,\"region\":\"us-west-2\"}}"

# --- 1. No replication at all -> LOCAL_ONLY
wrap 01_no_replication.json "$(bucket Enabled null '"none configured"' '{}' null)" '"us-west-2"'

# --- 2. THE KMS TRAP: rule enabled, prefix covers, but SSE-KMS not replicated
RULE_NO_KMS='{"Rules":[{"ID":"dr","Status":"Enabled","Priority":1,
  "Filter":{"Prefix":"connect/"},
  "Destination":{"Bucket":"arn:aws:s3:::'$DB'"},
  "DeleteMarkerReplication":{"Status":"Disabled"}}]}'
wrap 02_kms_not_replicated.json "$(bucket Enabled "$RULE_NO_KMS" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 3. Prefix does not cover the Connect prefixes -> LOCAL_ONLY
RULE_WRONG_PREFIX='{"Rules":[{"ID":"other","Status":"Enabled","Priority":1,
  "Filter":{"Prefix":"analytics-export/"},
  "SourceSelectionCriteria":{"SseKmsEncryptedObjects":{"Status":"Enabled"}},
  "Destination":{"Bucket":"arn:aws:s3:::'$DB'","EncryptionConfiguration":{"ReplicaKmsKeyID":"'$RKEY'"}}}]}'
wrap 03_prefix_mismatch.json "$(bucket Enabled "$RULE_WRONG_PREFIX" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 4. Versioning suspended -> LOCAL_ONLY (replication cannot run)
RULE_GOOD='{"Rules":[{"ID":"dr","Status":"Enabled","Priority":1,
  "Filter":{"Prefix":"connect/"},
  "SourceSelectionCriteria":{"SseKmsEncryptedObjects":{"Status":"Enabled"}},
  "Destination":{"Bucket":"arn:aws:s3:::'$DB'","EncryptionConfiguration":{"ReplicaKmsKeyID":"'$RKEY'"}},
  "DeleteMarkerReplication":{"Status":"Disabled"}}]}'
wrap 04_versioning_suspended.json "$(bucket Suspended "$RULE_GOOD" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 5. Everything correct and healthy -> REGIONAL_VERIFIED
wrap 05_regional_verified.json "$(bucket Enabled "$RULE_GOOD" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 6. Correct but a backlog is present -> REGIONAL_DEGRADED
wrap 06_regional_degraded.json "$(bucket Enabled "$RULE_GOOD" null "$DESTS" '{"operations_pending":1407}')" '"us-west-2"'

# --- 7. Correct but health not measured -> REGIONAL_CONFIGURED
wrap 07_health_unmeasured.json "$(bucket Enabled "$RULE_GOOD" null "$DESTS" null)" '"us-west-2"'

# --- 8. Rule disabled -> LOCAL_ONLY
RULE_DISABLED=$(printf '%s' "$RULE_GOOD" | sed 's/"Status":"Enabled","Priority"/"Status":"Disabled","Priority"/')
wrap 08_rule_disabled.json "$(bucket Enabled "$RULE_DISABLED" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 9. Replication config unreadable -> UNKNOWN
wrap 09_access_denied.json "$(bucket Enabled null '"AccessDenied"' '{}' null)" '"us-west-2"'

# --- 10. Bucket itself unreachable -> UNKNOWN
cat > "$D/10_bucket_unreachable.json" <<EOD
{
  "collected_at": "2026-11-20T04:00:00Z",
  "dr_region_expected": "us-west-2",
  "configs": [$three_configs],
  "buckets": {
    "$B": {
      "reachable": false,
      "region": null,
      "error": "head-bucket failed (denied, missing, or another account)",
      "versioning": "unknown",
      "encryption": null,
      "object_lock": "unknown",
      "replication": null,
      "replication_error": null,
      "destinations": {},
      "metrics": null
    }
  }
}
EOD
jq -e . "$D/10_bucket_unreachable.json" >/dev/null

# --- 11. Tag-filtered rule only -> LOCAL_ONLY (coverage unverifiable)
RULE_TAGGED='{"Rules":[{"ID":"tagged","Status":"Enabled","Priority":1,
  "Filter":{"And":{"Prefix":"connect/","Tags":[{"Key":"replicate","Value":"yes"}]}},
  "SourceSelectionCriteria":{"SseKmsEncryptedObjects":{"Status":"Enabled"}},
  "Destination":{"Bucket":"arn:aws:s3:::'$DB'","EncryptionConfiguration":{"ReplicaKmsKeyID":"'$RKEY'"}}}]}'
wrap 11_tag_filtered.json "$(bucket Enabled "$RULE_TAGGED" null "$DESTS" '{"operations_pending":0}')" '"us-west-2"'

# --- 12. Replicating to a region that is not the intended DR region
DESTS_WRONG="{\"$DB\":{\"reachable\":true,\"region\":\"eu-west-1\"}}"
wrap 12_wrong_dr_region.json "$(bucket Enabled "$RULE_GOOD" null "$DESTS_WRONG" '{"operations_pending":0}')" '"us-west-2"'

# --- 13. Destination bucket not reachable -> REGIONAL_CONFIGURED
DESTS_UNREACH="{\"$DB\":{\"reachable\":false,\"region\":null}}"
wrap 13_dest_unreachable.json "$(bucket Enabled "$RULE_GOOD" null "$DESTS_UNREACH" '{"operations_pending":0}')" '"us-west-2"'

# --- 14. Non-S3 storage (Kinesis) -> NOT_APPLICABLE
cat > "$D/14_non_s3.json" <<EOD
{
  "collected_at": "2026-11-20T04:00:00Z",
  "dr_region_expected": "us-west-2",
  "configs": [
    {"resource_type":"CONTACT_TRACE_RECORDS","storage_type":"KINESIS_STREAM","bucket":null,"prefix":"","encryption":"NONE","kms_key":null,"association_id":"a1"}
  ],
  "buckets": {}
}
EOD
jq -e . "$D/14_non_s3.json" >/dev/null

# --- 15. Unencrypted bucket, replication without SSE-KMS -> still regional
cat > "$D/15_unencrypted_ok.json" <<EOD
{
  "collected_at": "2026-11-20T04:00:00Z",
  "dr_region_expected": "us-west-2",
  "configs": [
    {"resource_type":"SCHEDULED_REPORTS","storage_type":"S3","bucket":"$B","prefix":"connect/acme/Reports","encryption":"NONE","kms_key":null,"association_id":"a1"}
  ],
  "buckets": {
    "$B": {
      "reachable": true, "region": "ap-southeast-2", "error": null,
      "versioning": "Enabled",
      "encryption": {"algorithm":"AES256","key":null},
      "object_lock": "Disabled",
      "replication": $RULE_NO_KMS,
      "replication_error": null,
      "destinations": $DESTS,
      "metrics": {"operations_pending":0}
    }
  }
}
EOD
jq -e . "$D/15_unencrypted_ok.json" >/dev/null

echo "Wrote $(ls "$D" | wc -l | tr -d ' ') fixtures to $D"
