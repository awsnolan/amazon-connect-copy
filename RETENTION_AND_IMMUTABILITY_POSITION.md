# Retention and Immutability: Position and Rationale

Why the recording-storage design is what it is, and what would have to change
for it to be different.

Written November 2026. Companion to [R1_STORAGE_SCOPE.md](./R1_STORAGE_SCOPE.md),
[DR_RECOVERY_LAYERS.md](./DR_RECOVERY_LAYERS.md) and
[DR_TIER_WORKSHOP_PACK.md](./DR_TIER_WORKSHOP_PACK.md).

---

> ## Not legal advice
>
> This records a technical position and the regulatory questions that shape it.
> It does **not** determine any obligation. Retention periods are a legal
> determination for the organisation's compliance, legal and privacy functions,
> and they vary by jurisdiction, industry, licence and contract.
>
> Everything below is a prompt for that conversation, with sources so the
> reasoning can be checked. Where a source is third-party rather than the
> regulator or AWS, it is marked.

---

## Contents

1. [The question that prompted this](#1-the-question-that-prompted-this)
2. [The core finding](#2-the-core-finding)
3. [Obligations to retain](#3-obligations-to-retain)
4. [Obligations to delete](#4-obligations-to-delete)
5. [Where Connect data actually sits](#5-where-connect-data-actually-sits)
6. [The Object Lock trap](#6-the-object-lock-trap)
7. [Governance mode versus Compliance mode](#7-governance-mode-versus-compliance-mode)
8. [Position](#8-position)
9. [What compliance needs to tell us](#9-what-compliance-needs-to-tell-us)
10. [Decision record](#10-decision-record)
11. [Correction log](#11-correction-log)
12. [Sources](#12-sources)

---

## 1. The question that prompted this

"Which compliance regulation requires call recordings to be retained?"

It was asked while deciding whether to put S3 Object Lock on the Amazon Connect
recordings bucket as protection against malicious deletion. The answer turned
out to change the design, so it is worth recording rather than re-deriving.

---

## 2. The core finding

**No regulation universally requires call recordings to be retained.**

Three things are commonly conflated and should be kept apart:

| | What it governs | Typical source |
|---|---|---|
| **An obligation to record** | You must capture the call in the first place | Rare. Mainly financial-services trading |
| **An obligation to retain** | Records you hold must be kept for N years | Common, but usually about *records*, not recordings specifically |
| **An obligation to protect or delete** | How you secure it, and when you must destroy it | Privacy and payment-card regimes |

Most regimes sit in the third category. They regulate recordings you have
*chosen* to keep. That means the default posture is not "keep forever" — it is
"keep for a defined period with a stated basis, then destroy."

Two opposing pressures therefore apply at once, and the design has to satisfy
both:

```
      retain longer                            delete sooner
   <------------------                      ------------------>
   record-keeping rules                     privacy law
   dispute evidence                         payment card rules
   licence conditions                       data minimisation
```

The retention period is the **intersection** of the two, not the maximum of
either.

---

## 3. Obligations to retain

### The clearest genuine recording mandate

**UK / EU financial services.** MiFID II Article 16(7), implemented in the UK
as [FCA SYSC 10A](https://handbook.fca.org.uk/handbook/sysc10a), requires
recording of telephone conversations intended to lead to a transaction. The
FCA's own [MiFID II taping impact assessment](https://www.fca.org.uk/publication/impact-assessments/mifid-ii-taping.pdf)
states records must be kept for **at least five years**.

If any part of the business is in scope for this, it is a real taping
obligation and not discretionary.

### Australia

There is **no general call-recording mandate.** What exists are record-keeping
obligations that a recording may help satisfy:

| Obligation | Period | Source |
|---|---|---|
| Company financial records | At least **7 years** | [ASIC: company record keeping](https://www.asic.gov.au/for-business-and-companies/companies/company-building-blocks/company-record-keeping) (Corporations Act s286) |
| AFS licensee records evidencing the best-interests duty for personal advice | At least **7 years** from when advice was given | [Explanatory statement, ASIC Instrument 2016/1006](https://www.legislation.gov.au/F2016L01647/asmade/2016-10-26/es/original/pdf) (s912G) |
| Complaint and dispute-resolution evidence | Per the relevant scheme | Internal dispute resolution obligations; external scheme rules |

**APRA CPS 230 does not require call recording.** It requires maintaining
critical operations within Board-approved tolerance levels and holding a
credible BCP — see [CPS 230](https://www.apra.gov.au/standards/cps-230).
Recordings are in scope only where they are a dependency of a critical
operation. That is a different argument from a retention mandate, and it should
be made on its own terms.

### A distinction worth preserving

**SEC Rule 17a-4** is frequently cited in this context, including by us. It is a
**records retention and immutability** rule for broker-dealers. It governs
*how* retained records must be stored — write-once-read-many — not *that* calls
must be recorded.

It matters here only because S3 Object Lock has been assessed against it, which
is evidence of the strength of the WORM control rather than evidence of an
obligation to record. See the
[Cohasset Associates assessment](https://d1.awsstatic.com/r2018/b/S3-Object-Lock/Amazon-S3-Compliance-Assessment.pdf)
referenced from the AWS Object Lock documentation.

---

## 4. Obligations to delete

These are the ones most likely to be missed when the framing is "how do we keep
recordings safe forever."

### Privacy — Australia

**Australian Privacy Principle 11.2.** An APP entity must take such steps as
are reasonable in the circumstances to **destroy or de-identify** personal
information once it is no longer needed for any purpose for which it may be
used or disclosed. See the OAIC
[Guide to securing personal information](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/guide-to-securing-personal-information)
and [APP Guidelines Chapter 11](https://www.oaic.gov.au/__data/assets/pdf_file/0035/256958/APP-Guidelines-Chapter-11-Security-of-personal-information-October-2025-v1.3.PDF).

A call recording is personal information. Indefinite retention is a compliance
exposure, not a conservative default.

### Payment cards

**PCI DSS prohibits retaining sensitive authentication data after
authorisation** — card verification codes and values (CVV2, CVC2, CID, CAV2),
full track data and PIN blocks — **even encrypted**. The PCI SSC
[FAQ on card verification code storage](https://blog.pcisecuritystandards.org/faq-can-cvc-be-stored-for-card-on-file-or-recurring-transactions)
is explicit that retention after authorisation is not permitted.

The PCI SSC publishes dedicated guidance for this exact situation, including a
decision process for voice recordings:
[Protecting Telephone-based Payment Card Data](https://listings.pcisecuritystandards.org/documents/protecting_telephone-based_payment_card_data.pdf).

**The implication is sharp: if agents take card details by phone, the recording
itself can be the violation.** No retention policy fixes that. The data has to
not be there — which is what Connect's sensitive-data redaction is for.

### Other jurisdictions

If the contact centre serves customers in other jurisdictions, the equivalent
data-minimisation and erasure obligations need checking. Not assessed here.

---

## 5. Where Connect data actually sits

From the instance inspected locally, three storage configurations share one
bucket and differ only by prefix, all KMS-encrypted:

```
CALL_RECORDINGS    <bucket>  connect/<alias>/CallRecordings    KMS
CHAT_TRANSCRIPTS   <bucket>  connect/<alias>/ChatTranscripts   KMS
SCHEDULED_REPORTS  <bucket>  connect/<alias>/Reports           KMS
```

Email is enabled on the instance, so email message content is also
customer-owned S3 data — and `EMAIL_MESSAGES` is currently not captured by the
backup at all (finding F3 in [R1_STORAGE_SCOPE.md](./R1_STORAGE_SCOPE.md)).

**This matters for retention design.** Three data types with potentially three
different lawful retention periods are in one bucket. A bucket-wide default
retention policy would apply the same period to all three, which is almost
certainly wrong — operational reports and customer call recordings rarely share
a retention basis.

---

## 6. The Object Lock trap

**S3 Object Lock in COMPLIANCE mode cannot be shortened, overridden or removed
— not by an administrator, not by the root user, not by AWS.** That is the
point of it, and it is why it satisfies WORM requirements.

It is also the risk.

> If the retention period is set longer than the lawful basis for holding the
> data, the result is a system that **cannot comply with a deletion
> obligation**.

An APP 11.2 destruction requirement, a data-subject erasure request, or a PCI
finding would all be unsatisfiable for the duration of the lock. The control
intended to protect the data becomes the reason the organisation is
non-compliant.

Two further constraints from AWS's own
[Connect Object Lock guidance](https://docs.aws.amazon.com/connect/latest/adminguide/s3-object-lock-call-recordings.html):

- **Use a dedicated recordings bucket**, because a default retention policy
  locks every object in the bucket.
- **Object Lock cannot be removed once enabled** on a bucket.

And from the [S3 Object Lock documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-overview.html):
Object Lock requires versioning, and it protects the **object version**, not
the key. Retention and legal holds do not prevent new versions or delete
markers being added on top. So Object Lock prevents **destruction**, not
**concealment** — an object can be made to look deleted while the locked
version survives and remains recoverable. For recovery purposes that is
sufficient; it is worth knowing so the control is not over-claimed.

---

## 7. Governance mode versus Compliance mode

This is the decision that follows from Section 6.

| | COMPLIANCE | GOVERNANCE |
|---|---|---|
| Can a privileged user delete before expiry? | No. Nobody, including root | Yes, with `s3:BypassGovernanceRetention` |
| Satisfies true WORM / regulatory immutability | Yes | Not in the same sense |
| Protects against a compromised administrator | Yes | Partially — depends on who holds the bypass permission |
| Preserves ability to honour a deletion obligation | **No** | **Yes**, as a documented and audited exception |

**Compliance mode is correct when a regulation requires WORM.** Otherwise it
trades away an ability the organisation may legally need.

Governance mode still blocks routine and accidental deletion, and it still
blocks an attacker who does not hold the bypass permission. Combined with an
SCP denying `s3:BypassGovernanceRetention` to everyone except a break-glass
role, it gets most of the protection while remaining reversible under a
documented process.

---

## 8. Position

Adopted until compliance provides retention periods:

1. **Enable S3 versioning.** Reversible, required for replication and for
   Object Lock, and the foundational recovery control. No retention decision
   needed.
2. **Enable cross-region replication with `DeleteMarkerReplication` disabled**,
   and with SSE-KMS object replication configured. Reversible. This is what
   [`connect_storage_posture`](./bin/connect_storage_posture) verifies.
3. **Do not enable Object Lock yet.** It is irreversible at the bucket level
   and the correct retention period is unknown. Enabling it early risks
   creating the Section 6 conflict permanently.
4. **Separate the buckets before applying any retention policy**, so recordings,
   transcripts and reports can carry different periods.
5. **If card data is taken by phone, address redaction before retention.** No
   retention setting makes a stored CVV acceptable.
6. **Add SCP guardrails now** — denying `s3:DeleteBucket`,
   `s3:PutBucketVersioning` and `s3:DeleteObjectVersion` outside a break-glass
   role gives much of the anti-tamper benefit with none of the irreversibility.

### The argument that does not depend on any of this

Recordings need to be **recoverable** regardless of whether a regulation
compels their retention. Dispute resolution, external scheme evidence, quality
management and ordinary customer service all rely on them. The regional-recovery
work in R1 stands on that basis alone and should not wait on a retention
determination.

Keep the two arguments separate when presenting:

- *Recoverability* — a resilience argument, no legal input required
- *Immutability and retention period* — a compliance argument, blocked on legal input

---

## 9. What compliance needs to tell us

One question, asked per data type:

> For each of call recordings, chat transcripts, email content, attachments and
> screen recordings:
>
> 1. What is the **minimum** retention, and what is its legal or contractual basis?
> 2. What is the **maximum permitted** retention, and what is its basis?
> 3. Is there a **regulatory WORM requirement**, or only a retention period?
> 4. Does any of it contain **payment card data**?
> 5. Are there **jurisdictions** beyond Australia in scope?

Fill-in:

| Data type | Min retention | Basis | Max retention | Basis | WORM required? | Card data? |
|---|---|---|---|---|---|---|
| Call recordings | | | | | | |
| Chat transcripts | | | | | | |
| Email content | | | | | | |
| Attachments | | | | | | |
| Screen recordings | | | | | | |
| Contact records (CTRs) | | | | | | |
| Cases records | | | | | | |

Answers to 1 and 2 set the lifecycle policy. Answer 3 decides COMPLIANCE versus
GOVERNANCE mode. Answer 4 may force redaction before any of it matters.

---

## 10. Decision record

```text
RETENTION AND IMMUTABILITY DECISION

Date:
Decision owner (compliance/legal):
Technical owner:

1. RETENTION PERIODS (from section 9 table)
   Attached / recorded at: ______________________

2. OBJECT LOCK
   Enabled?            Yes / No
   Mode:               COMPLIANCE / GOVERNANCE / n/a
   Retention:          ______
   Basis for the mode choice:
   If COMPLIANCE — confirmed that no deletion obligation can arise
   within the retention period:   Yes / No   Confirmed by: ________

3. BUCKET SEPARATION
   Recordings in a dedicated bucket?   Yes / No
   If No, justification:

4. PAYMENT CARD DATA
   Taken by phone?                     Yes / No
   Redaction in place before storage?  Yes / No

5. ACCEPTED RISKS
   (e.g. "recordings are LOCAL_ONLY; regional outage means they are
    unavailable until the source region recovers" — accepted by ____)

6. REVIEW DATE:
```

---

## 11. Correction log

Kept because the reasoning changed, and the change is the useful part.

| Date | Earlier position | Revised position | Why |
|---|---|---|---|
| Nov 2026 | Replication does little against malicious deletion | Replication gives real protection: a delete specifying a **version ID** is never replicated to the destination. Only delete markers propagate, and that is configurable | Checked the S3 replication behaviour rather than assuming |
| Nov 2026 | "Put Object Lock on the recordings bucket" | Do not enable Object Lock until retention periods are known; prefer GOVERNANCE mode absent a WORM requirement | COMPLIANCE mode is irreversible and can make a deletion obligation unsatisfiable |
| Nov 2026 | Cited SEC 17a-4 in a way that implied a recording mandate | 17a-4 is a retention and immutability rule, not a taping obligation | Distinction matters when justifying the control |

---

## 12. Sources

**Regulators and standards bodies**

- [FCA Handbook SYSC 10A — recording telephone conversations](https://handbook.fca.org.uk/handbook/sysc10a)
- [FCA — MiFID II taping impact assessment](https://www.fca.org.uk/publication/impact-assessments/mifid-ii-taping.pdf) (at least five years)
- [ASIC — company record keeping](https://www.asic.gov.au/for-business-and-companies/companies/company-building-blocks/company-record-keeping) (7 years)
- [Explanatory statement, ASIC Instrument 2016/1006](https://www.legislation.gov.au/F2016L01647/asmade/2016-10-26/es/original/pdf) (s912G, 7 years)
- [APRA CPS 230 Operational Risk Management](https://www.apra.gov.au/standards/cps-230)
- [OAIC — Guide to securing personal information](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/handling-personal-information/guide-to-securing-personal-information)
- [OAIC — APP Guidelines Chapter 11](https://www.oaic.gov.au/__data/assets/pdf_file/0035/256958/APP-Guidelines-Chapter-11-Security-of-personal-information-October-2025-v1.3.PDF)
- [PCI SSC — Protecting Telephone-based Payment Card Data](https://listings.pcisecuritystandards.org/documents/protecting_telephone-based_payment_card_data.pdf)
- [PCI SSC — FAQ on storing card verification codes](https://blog.pcisecuritystandards.org/faq-can-cvc-be-stored-for-card-on-file-or-recurring-transactions)

**AWS**

- [S3 Object Lock overview](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-overview.html)
- [S3 Object Lock for Connect call recordings](https://docs.aws.amazon.com/connect/latest/adminguide/s3-object-lock-call-recordings.html)
- [Cohasset Associates compliance assessment of S3 Object Lock](https://d1.awsstatic.com/r2018/b/S3-Object-Lock/Amazon-S3-Compliance-Assessment.pdf)
- [AWS Backup logically air-gapped vault](https://docs.aws.amazon.com/aws-backup/latest/devguide/logicallyairgappedvault.html)
- [AWS Backup feature availability](https://docs.aws.amazon.com/aws-backup/latest/devguide/backup-feature-availability.html) — S3 is supported for logically air-gapped vaults
- [Replicating delete markers between buckets](https://docs.aws.amazon.com/AmazonS3/latest/userguide/delete-marker-replication.html)

Content drawn from these sources was summarised and rephrased for compliance
with licensing restrictions; refer to the originals as authoritative. Retention
periods and their applicability must be confirmed by the organisation's own
legal and compliance functions.
