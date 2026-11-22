# R1 — Storage Attach Validation: Scope

Backlog item: **R1**, Layer 2 (Records). See
[DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md) and [BACKLOG.md](./BACKLOG.md).

Scoped November 2026 against `bin/lib/backup/instance.sh`,
`bin/lib/restore/instance.sh`, `bin/lib/validate/layer_1_instance.sh`, and the
two local backups in the working tree.

---

## 1. Why this ranks first

On the instance backed up locally, all three storage configurations are **S3
with KMS encryption**, and the instance has **email enabled**. That combination
is where the current code is weakest.

The present behaviour can report `✓ Updated storage` when nothing was updated,
and validation can report a pass when the target points at an entirely
different bucket. The failure is therefore silent in both tools, and the symptom
surfaces only when a live contact fails to record — after the DR instance has
started taking traffic.

That is a worse failure mode than B5. B5 printed nothing; this prints green.

---

## 2. Current state

### Backup — `bin/lib/backup/instance.sh:34-44`

Iterates a hardcoded list of 11 resource types and appends
`list-instance-storage-configs` output to `storage_configs.json` as
newline-delimited JSON. Errors are discarded (`2>/dev/null || true`).

Captured per config: `ResourceType`, `AssociationId`, `StorageType`, and the
type-specific block — for S3 that is `BucketName`, `BucketPrefix` and
`EncryptionConfig` (`EncryptionType`, `KeyId`).

### Restore — `bin/lib/restore/instance.sh:53-108`

For each saved config, calls `associate-instance-storage-config` on the target
using the **source** storage block unchanged. The inline comment states
"cross-account access assumed". If association returns no output it falls
through to `update-instance-storage-config`.

### Validate — `bin/lib/validate/layer_1_instance.sh:88-119`

Test 1.4. For each of the same 11 hardcoded types, if the type appears in the
saved file, calls `list-instance-storage-configs` on the live instance and
counts the type as matched **if the response is non-empty**.

---

## 3. Defects

Ranked by consequence.

### D1 — False success on update *(critical)*

`bin/lib/restore/instance.sh:93-98` — the `update` call begins at line 93, its
suppression is on line 97, and the unconditional success line is 98.

```bash
aws_connect update-instance-storage-config \
    ... 2>/dev/null || true
echo -e "  ${C_PASS}✓ Updated storage: $resource_type → $storage_type${C_RESET}"
```

The `|| true` discards the exit code and the success line prints
unconditionally. If the update fails — denied KMS key, bucket policy, invalid
config — the operator is told it succeeded.

This is the single most important fix in R1.

### D2 — Presence-only validation *(critical)*

`layer_1_instance.sh:101-108` checks only that *some* storage config exists for
the type. It never compares `BucketName`, `BucketPrefix`, or the KMS `KeyId`.

Consequence: a DR instance whose recordings point at a different bucket, or at
an unencrypted bucket, **passes test 1.4**. The variable `saved_config` is
assigned at line 94 and never read, which is likely where the comparison was
intended to go.

### D3 — Missing resource types *(high)*

Backup covers 11 of the 13 types the API now accepts. Missing:

| Type | Relevance here |
|---|---|
| `EMAIL_MESSAGES` | **Email is enabled on this instance.** Email message storage is not captured, restored, or validated at all. |
| `REAL_TIME_CONTACT_ANALYSIS_VOICE_SEGMENTS` | Needed if real-time voice analysis is used |

The identical list is duplicated verbatim in `layer_1_instance.sh:90`, so
backup and validation share the same blind spot and must be edited in lockstep.
They have already drifted from the API once.

### D4 — Success inferred from empty output, not exit status *(high)*

`restore/instance.sh:79-84` treats an empty response as "already configured".
Any failure also produces an empty response, so a denied or invalid association
is misclassified and routed into the update path.

### D5 — AWS error text suppressed *(high)*

Both calls use `2>/dev/null`, which defeats the error reporting already present
in `aws_connect_restore` (`common.sh:186-190`). Same defect class as B5. The
operator cannot see *why* a storage association failed.

### D6 — No proof the target can actually use the storage *(high)*

Associating a storage config is a control-plane operation. Succeeding at it does
not establish that the target account can write an object to the bucket or use
the KMS key, which are data-plane concerns. Nothing in the toolkit tests either.

For a cross-account restore the usual blockers are the source bucket policy and
the source KMS key policy, neither of which the toolkit creates or inspects.

### D7 — Minor

- `has_saved` uses `grep -c "\"$stype\""` against the whole file, so a type
  named inside another field's value would match.
- The loop body recomputes `saved_config` identically on every iteration.

---

## 4. The design question R1 actually surfaces

Fixing the defects above still leaves the central question unanswered, and it
should be decided before any code is written.

**Restore currently points the DR instance at the source account's buckets.**
That is a deliberate choice, and it is correct for exactly one failure mode.

| Failure mode | Does pointing at source buckets work? |
|---|---|
| Single instance lost or corrupted, account and region healthy | **Yes** |
| Regional outage | **No** — the bucket is in the failed region |
| Account compromise, malicious deletion | **No** — the source is untrusted |
| Cross-account migration | Only if bucket and key policies are opened to the target account |

The toolkit's stated purpose is cross-account and regional recovery, so the
default is aligned to the least likely reason to invoke it.

Three possible targets:

| Option | Recordings work in DR? | History reachable? | Needs |
|---|---|---|---|
| **A** Source buckets *(current)* | Only if source survives | Yes | Cross-account bucket + KMS policy |
| **B** Replicated buckets in the DR region | Yes | Yes, up to replication lag | S3 replication, destination KMS key, a bucket mapping |
| **C** Fresh DR buckets | Yes | No | Nothing extra |

**Option B is the only one consistent with the regional-disaster premise.** It
requires something the toolkit does not currently have: the ability to rewrite
the bucket and KMS key when restoring.

There is clean precedent for how to express that. `connect_plan` already accepts
`-l a=b` for Lambda prefix remapping and `-b a=b` for Lex bot prefix remapping.
A storage equivalent fits the existing interface.

So R1 is not only "add validation". It is **choose where DR storage points, make
that expressible, then verify it.**

---

## 5. Proposed scope

### D1 — Single source of truth for storage types

Move the type list into `common.sh` as one constant consumed by backup, restore
and validate. Add `EMAIL_MESSAGES` and
`REAL_TIME_CONTACT_ANALYSIS_VOICE_SEGMENTS`.

Add a test that fails if the constant drifts from a documented expected set, so
the next API addition is caught rather than silently missed.

*Small. No behavioural risk.*

### D2 — Honest restore reporting

- Branch on exit status, not empty output.
- Drop `2>/dev/null` so the wrapper's error text reaches the operator.
- Never print success unless the call returned zero.
- On failure: a `✗` line naming the resource type and a `manual_action` entry.
- Keep the non-zero status away from `test $? -eq 0 || error`, exactly as the
  B5 fix does, so a storage failure does not abort the whole restore.

*Small. This is the critical correctness fix.*

### D3 — Storage target remapping

Add a bucket and key mapping, following the existing `-l` / `-b` convention:

```
connect_plan -S source-bucket=dr-bucket [-S ...] alias_a alias_b helper
connect_plan --storage-map FILE          # for many mappings, or KMS keys
```

Applied when the restore builds the storage payload. Unmapped configs keep
current behaviour, so this is additive and the default is unchanged.

Record the chosen option (A, B or C) in the helper directory so validation knows
what to assert against.

*Medium. Needs a decision from Section 4 first.*

### D4 — Deep validation

Rewrite test 1.4 to compare, per type: presence, `BucketName`, `BucketPrefix`,
`StorageType`, `EncryptionType` and KMS `KeyId` — accounting for the remapping
from D3 so an intentional change reads as a pass and an accidental one as a
fail.

Report encryption downgrade (source KMS, target none) as a **FAIL**, not a
warning. For this instance, all three configs are KMS-encrypted, so a silent
downgrade would be a compliance regression.

*Medium. Replaces the dead `saved_config` path.*

### D5 — Reachability probe: the actual "attach validation"

A new validation layer, or an extension of 1.4, that tests whether the target
can really use the storage it is pointed at. Read-only by default:

| Check | Method | Proves |
|---|---|---|
| Bucket exists and is reachable from the target | `s3api head-bucket` under the target profile | Name resolves, credentials permitted |
| Bucket region | `s3api get-bucket-location` | Flags a cross-region dependency |
| KMS key usable | `kms generate-data-key` under the target profile | Encrypt/decrypt capability — **non-destructive, persists nothing** |
| Bucket policy admits Connect for the target account | `s3api get-bucket-policy`, inspect principals | Heuristic, surfaces the common cross-account blocker |
| Replication configured | `s3api get-bucket-replication` | Relevant when Option B is chosen |
| End-to-end write *(opt-in)* | `--probe-writes`: put then delete one small object under a dedicated probe prefix | The only true proof of writability |

`kms generate-data-key` is the useful one: it is the real authorisation path for
an encrypted write and it leaves nothing behind.

Writes stay behind an explicit flag, and the probe prefix is clearly named so
anything left by an interrupted run is obvious.

*Medium. This is the deliverable that gives R1 its name.*

### D6 — Tests

- Fixtures covering: all 13 types; a bucket mismatch; an encryption downgrade;
  a remapped bucket; a missing `EMAIL_MESSAGES` config.
- Mutation tests, as used for B5: reintroduce the false-success path and assert
  a test fails.
- Assert the type constant is not duplicated anywhere.

*Small, and non-negotiable given that D1 and D2 are correctness fixes.*

---

## 6. Out of scope

- Creating buckets, KMS keys or replication. That is infrastructure work, and
  the toolkit should verify it rather than own it.
- Copying S3 objects. Attach, do not move — see
  [DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md) section 9.
- Kinesis and Firehose destinations. `STORAGE_TYPE` can be
  `KINESIS_STREAM`, `KINESIS_FIREHOSE` or `KINESIS_VIDEO_STREAM`; this instance
  uses S3 only for all three configs. Worth a follow-up, not worth blocking on.
- Object Lock and lifecycle policy verification. Belongs with R6.

---

## 7. Risk

| Change | Risk | Mitigation |
|---|---|---|
| D1 add two types | Backup calls two more APIs; may 404 on older instances | Already tolerant of empty responses |
| D2 honest reporting | Previously "passing" restores will now report storage failures | That is the point. Expect first run after this to look worse and be more truthful. |
| D3 remapping | Mis-set mapping points DR at the wrong bucket | Validate the mapping in preflight; echo resolved target per config in dry run |
| D4 strict comparison | Existing instances may fail 1.4 where they passed | Correct outcome; stage as WARN for one release if that is too abrupt |
| D5 probe | `generate-data-key` and `head-bucket` need extra target permissions | Document the additional IAM actions; degrade to SKIP when denied rather than FAIL |

The notable one is **D2 and D4 will make current results look worse.** Nothing
will have regressed; the tools will simply stop over-reporting. Worth saying
out loud before someone reads the first post-fix run as a regression.

---

## 8. Suggested sequence

1. **D1 + D2** together. Small, self-contained, fixes the false green and the
   email gap. Deliverable on its own.
2. **Decide Section 4.** Needs a person, not code.
3. **D3** once that decision exists.
4. **D4 + D5** last, since both depend on knowing what the target *should* be.
5. **D6** alongside each step, not at the end.

Steps 1 and 2 can run in parallel — one is engineering, one is a decision.

---

## 9. What I need from you

**The Section 4 decision: where should DR storage point?**

My recommendation is **Option B** — replicated buckets in the DR region — on the
grounds that Sydney has no Global Resiliency, so this toolkit is the recovery
path for a regional event, and Option A cannot survive one.

That decision has a prerequisite you may not have yet: cross-region replication
on the three recording and transcript buckets, with a destination-region KMS
key. If that replication does not exist, Option A is the only thing available
today, and the honest position is that recordings would be unavailable in a
regional DR — which is itself a finding worth taking to the workshop.

A secondary question: should D4 treat an encryption downgrade as FAIL
immediately, or WARN for one release? FAIL is correct; WARN is kinder to
whatever currently passes.
