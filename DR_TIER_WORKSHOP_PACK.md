# Business Recovery Tiers — Workshop Pack

Purpose: run an informed workshop with a senior leader on disaster-recovery tiers, and land an agreed recovery position for the Amazon Connect recovery solution.

Companion document: [CONNECT_CATASTROPHIC_RECOVERY_DATA_SCOPE.md](./CONNECT_CATASTROPHIC_RECOVERY_DATA_SCOPE.md)

---

## Contents

1. [How to use this pack](#1-how-to-use-this-pack)
2. [Reading list — canonical tier models](#2-reading-list--canonical-tier-models)
3. [Reading list — AWS strategy continuum](#3-reading-list--aws-strategy-continuum)
4. [Reading list — regulatory framing](#4-reading-list--regulatory-framing)
5. [Reading list — cost of downtime](#5-reading-list--cost-of-downtime)
6. [Reading list — Amazon Connect specifics](#6-reading-list--amazon-connect-specifics)
7. [Model cross-walk](#7-model-cross-walk)
8. [Hard constraints that pre-decide the answer](#8-hard-constraints-that-pre-decide-the-answer)
9. [The framing that makes the workshop succeed](#9-the-framing-that-makes-the-workshop-succeed)
10. [Facilitator agenda](#10-facilitator-agenda)
11. [Per-domain tier decision matrix](#11-per-domain-tier-decision-matrix)
12. [One-page pre-read for the leader](#12-one-page-pre-read-for-the-leader)
13. [Recommended landing point](#13-recommended-landing-point)
14. [Decision record template](#14-decision-record-template)

---

## 1. How to use this pack

Sections 2 to 6 are the evidence base. Send Section 12 as the pre-read. Run the workshop from Section 10, fill in Section 11 live, and capture the outcome in Section 14.

The single most important preparation step: read Section 8 before you schedule the workshop. One of those constraints likely determines your outcome regardless of budget appetite.

---

## 2. Reading list — canonical tier models

Use these for legitimacy, then set them aside. They give the tier vocabulary a senior leader has probably encountered.

| Source | Why it matters |
|---|---|
| [IBM: Six tiers of solutions for off-site recovery](https://www.ibm.com/docs/en/cics-ts/6.x?topic=availability-six-tiers-solutions-off-site-recovery) | Primary vendor documentation of the tier model, Tier 0 (local only, no off-site) through Tier 6 (minimal to zero data loss). States plainly that Tier 0–3 recovery can take days or weeks and is inherently incomplete. |
| [Business continuity planning — tiers of preparedness](https://en.wikipedia.org/wiki/Seven_tiers_of_disaster_recovery) | Documents that SHARE released the seven tiers in 1992, and IBM updated it to an eight-tier model in 2012, where Tier 7 adds automation and business integration. Good for a single all-tiers slide. |
| [NIST SP 800-34 Rev. 1, Contingency Planning Guide](https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final) | Standards anchor for cold/warm/hot site selection. Insists strategy is driven by business impact analysis output, not budget convenience. |
| ISO 22301:2019 | Introduces **maximum tolerable period of disruption (MTPD)** and requires defining minimum acceptable service levels. MTPD, not RTO, is the concept a leader should actually be agreeing to. |

### Tier reference (SHARE / IBM eight-tier model)

| Tier | Description |
|---|---|
| 0 | No off-site data. No plan, no backup hardware, no documentation. Recovery may not be possible. |
| 1 | Data backup, no hot site. Backups physically removed off-site. Days-to-weeks of data loss. |
| 2 | Data backup with hot site. Off-site facility and infrastructure available to restore onto. Hours-to-days of data loss. |
| 3 | Electronic vaulting. Mission-critical data vaulted electronically, so less data loss than shipping media. |
| 4 | Point-in-time copies. Disk-based, more frequent copies. Several hours of data loss still possible. |
| 5 | Transaction integrity. Consistency between production and recovery sites. Little to no data loss, but application-dependent. |
| 6 | Zero or little data loss. Highest data currency, no dependence on the application for consistency. |
| 7 | Highly automated, business-integrated. Tier 6 plus automated application recovery, faster and more reliable than manual procedures. |

### Critical caveat to state out loud

The SHARE/IBM tiers were built for mainframe and data-centre estates: tape, vaulting, two-phase commit, disk replication. They assume **you own the platform**.

You do not own Amazon Connect's control plane. Several tiers are therefore not purchasable at any price. Do not let the workshop conclude "we will be Tier 6" as though that were a procurement decision.

---

## 3. Reading list — AWS strategy continuum

This is the model your engineering decisions actually map to.

| Source | Why it matters |
|---|---|
| [Disaster recovery options in the cloud (AWS whitepaper)](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html) | Authoritative treatment of the four strategies. |
| [REL13-BP02 Use defined recovery strategies](https://docs.aws.amazon.com/wellarchitected/latest/framework/rel_planning_for_recovery_disaster_recovery.html) | Most workshop-ready page. Attaches indicative objectives to each strategy and names the anti-patterns. |
| [DR Architecture on AWS, Part I: Strategies for Recovery in the Cloud](https://aws.amazon.com/blogs/architecture/disaster-recovery-dr-architecture-on-aws-part-i-strategies-for-recovery-in-the-cloud/) | Contains the RTO/RPO-versus-cost trade-off curve. Best single diagram for a senior leader. |
| [Part III: Pilot Light and Warm Standby](https://aws.amazon.com/blogs/architecture/disaster-recovery-dr-architecture-on-aws-part-iii-pilot-light-and-warm-standby/) | Depth on the two middle strategies. |
| [Part IV: Multi-site Active/Active](https://aws.amazon.com/blogs/architecture/disaster-recovery-dr-architecture-on-aws-part-iv-multi-site-active-active) | Depth on the top strategy. |
| [Establishing RPO and RTO Targets for Cloud Applications](https://aws.amazon.com/blogs/mt/establishing-rpo-and-rto-targets-for-cloud-applications/) | Process guidance for eliciting the numbers. |

### Indicative objectives per strategy

Per REL13-BP02:

| AWS strategy | Indicative RPO | Indicative RTO |
|---|---|---|
| Backup and restore | Hours (as low as ~5 minutes with point-in-time recovery) | 24 hours or less |
| Pilot light | Minutes | Tens of minutes |
| Warm standby | Seconds | Minutes |
| Multi-site active/active | Near zero | Potentially zero |

### Three points worth quoting almost verbatim

These pre-empt the most common leadership errors.

1. **Do not over-engineer.** AWS explicitly advises against implementing a strategy more stringent than needed, because it incurs unnecessary cost.
2. **Doing nothing is a named high risk.** AWS lists "having no plan for disaster recovery" and "leaving the DR strategy to be implemented ad-hoc when a disaster occurs" as anti-patterns carrying a **high** level of risk.
3. **Replication is not backup.** AWS notes that continuous replication protects against some disasters but **not** against data corruption or destruction unless the strategy also includes versioning or point-in-time recovery.

Point 3 is the core argument for keeping this toolkit alongside Amazon Connect Global Resiliency rather than treating Global Resiliency as a replacement.

### Pilot light vs warm standby

AWS acknowledges this distinction is commonly misunderstood. Both maintain a recovery-Region environment with copies of primary assets. The difference:

- **Pilot light** cannot process requests without additional action first. You must switch on resources, possibly deploy non-core infrastructure, and scale up.
- **Warm standby** can handle traffic immediately at reduced capacity. You only need to scale up.
- **Hot standby** is warm standby provisioned at full production capacity.

---

## 4. Reading list — regulatory framing

If the organisation is APRA-regulated (bank, general or life insurer, private health insurer, or superannuation trustee), the tier decision is **not purely discretionary**.

| Source | Why it matters |
|---|---|
| [APRA CPS 230 Operational Risk Management](https://www.apra.gov.au/standards/cps-230) | Requires regulated entities to continue delivering critical operations **within tolerance levels** through severe disruptions, with a credible business continuity plan. |
| [CPG 230 Operational Risk Management (practice guide)](https://www.apra.gov.au/practice-guides/cpg-230) | APRA's supporting guidance. |
| [The importance of managing operational risk (APRA)](https://www.apra.gov.au/importance-managing-operational-risk) | Confirms CPS 230 came into force from 1 July 2025. |
| [CPS 230 in Practice: Operational Resilience (ACI, Oct 2025)](https://compliance.org.au/wp-content/uploads/2025/10/CPS230-in-Practice-Operational-Resilience-ACI-October-2025.pdf) | Practitioner interpretation. |
| [ACSA: CPS 230 Tolerance Levels](https://cdn.ymaws.com/acsa.com.au/resource/resmgr/files/122024_Tolerance_Levels_ACSA.pdf) | Practical guidance on setting tolerance levels. |
| [A practical guide to CPS 230 (Interactive)](https://www.interactive.com.au/insights/a-practical-guide-to-cps-230/) | Accessible summary for non-specialists. |

### The reframing to bring into the room

Under CPS 230 the question is **not** "what DR tier do we want to buy?"

It is: **"Is the contact centre a critical operation, and what Board-approved tolerance level applies to it?"**

If inbound telephony supports claims, hardship, payments, or complaints handling, it is very likely in scope. The tolerance level then sets your RTO floor, rather than the RTO being chosen from an appetite discussion.

If you are not APRA-regulated, the equivalent framing is impact tolerance under general operational-resilience practice, or simply MTPD under ISO 22301.

---

## 5. Reading list — cost of downtime

| Source | Why it matters |
|---|---|
| [Splunk: The Hidden Costs of Downtime](https://www.splunk.com/en_us/blog/cio-office/cost-of-downtime-from-global-executives.html) | Global 2000 executive survey. Per-minute cost plus measurable share-price impact. |
| [Splunk/Cisco downtime research announcement](https://newsroom.cisco.com/c/r/newsroom/en/us/a/y2026/m05/the-600-billion-wake-up-call-new-splunk-research-reveals-downtime-is-a-systemic-business-crisis.html) | Headline figures suitable for an executive slide. |
| [Calculating the cost of downtime (Atlassian)](https://www.atlassian.com/incident-management/kpis/cost-of-downtime) | Honest about the limits of industry averages. |
| [How often do contact centers fail, and what it really costs (CX Today)](https://www.cxtoday.com/service-management-connectivity/how-often-do-contact-centers-fail-and-what-it-really-costs/) | Contact-centre-specific framing. |
| [Calculate contact centre downtime costs (Voiso)](https://voiso.com/articles/contact-center-downtime-financial-impact-guide/) | Walks through a per-minute calculation method. |

### Caution, so you are not caught out

The frequently quoted "$5,600 per minute" figure traces to a **2014** Gartner study, and Gartner itself flagged it as an average with very wide variance. Published per-minute figures range from roughly a couple of thousand dollars to over $20,000 depending on organisation size and source.

**Do not build the business case on a borrowed industry average.** Derive your own figure from:

- Contacts per hour by channel, and time of day
- Average order, claim, or transaction value
- Conversion or resolution rate
- Fully loaded agent cost for idle time
- Regulatory exposure, breach reporting, and remediation cost
- Reputational and complaint-volume follow-on

A defensible internal number survives scrutiny. A blog average does not.

---

## 6. Reading list — Amazon Connect specifics

| Source | Why it matters |
|---|---|
| [Resilience in Amazon Connect](https://docs.aws.amazon.com/connect/latest/adminguide/disaster-recovery-resiliency.html) | A single instance already spans a minimum of three Availability Zones in an active-active-active configuration, with redundant multi-carrier telephony. |
| [Create a replica of your existing instance](https://docs.aws.amazon.com/connect/latest/adminguide/create-replica-connect-instance.html) | Documents exactly what `ReplicateInstance` mirrors, and that changes then synchronise bidirectionally in near real time. |
| [Amazon Connect Global Resiliency requirements](https://docs.aws.amazon.com/connect/latest/adminguide/connect-global-resiliency-requirements.html) | Prerequisites and constraints. |
| [Get started with Global Resiliency](https://docs.aws.amazon.com/connect/latest/adminguide/get-started-connect-global-resiliency.html) | Region eligibility and onboarding path. |
| [Single instance or multiple instances?](https://docs.aws.amazon.com/connect/latest/adminguide/single-instance-multiple-instances.html) | Architectural context for the instance-topology decision. |
| [Global Resiliency (AWS Marketplace listing)](https://aws.amazon.com/marketplace/pp/prodview-cclww4prr3fio) | Commercial framing of operator-driven regional failover. |

### The good news to lead with

You already have strong **in-Region** resilience at no additional cost. Connect propagates a single instance across at least three Availability Zones in active-active-active configuration, and takes failed nodes out of rotation without production impact. Telephony is integrated with multiple carriers across redundant network paths.

**Therefore the workshop is only about two things:** Region-scale events, and cyber or logical failure (accidental or malicious change, corruption, deletion).

---

## 8. Hard constraints that pre-decide the answer

Put these in front of the leader **before** any tier is chosen. All are from the AWS documentation linked in Section 6.

| Constraint | Consequence |
|---|---|
| Global Resiliency is available only for instances in **US East (N. Virginia), US West (Oregon), Asia Pacific (Osaka), Asia Pacific (Tokyo), Europe (Frankfurt), Europe (London)** | Fixed pairs only. Osaka is replica-only and cannot host a primary. |
| Source instance **must have SAML enabled** and must have an alias | `ReplicateInstance` fails otherwise. Non-SSO instances are ineligible. |
| Access requires engagement with your AWS Solutions Architect or Technical Account Manager | Not self-service. Adds lead time. |
| The replica is created in the **same AWS account** | Does not protect against account compromise or insider risk. |
| Replication **excludes** Lambda, Lex, and other third-party integrations | Routing can fail over while dependencies do not. |
| Synchronisation is **bidirectional** | A bad or malicious configuration change propagates. This is continuity, not backup. |
| Resource **name conflicts** cause `ResourceConflictException` | Manually pre-created resources in the replica can block replication. |
| Agents must be associated to a traffic distribution group via `AssociateTrafficDistributionGroupUser`, and must exist in **both** instances first | Extra provisioning step; not automatic. |

### The constraint most likely to decide your outcome

The existing workspace manifests reference **`ap-southeast-2` (Sydney)**.

**Sydney is not currently in the Global Resiliency Region list.**

If Sydney is your production Region, warm-standby-grade managed failover is **not currently available to you**. This single fact may determine the workshop outcome more than any cost discussion. Verify it before the session, and if confirmed, frame the choice as:

- Accept a Pilot Light / Backup-and-Restore RTO, **or**
- Fund a Region migration to a supported pair, **or**
- Build self-managed warm standby (high complexity, this toolkit plus substantial engineering)

---

## 7. Model cross-walk

One slide, three vocabularies reconciled.

| Classic SHARE/IBM | AWS strategy | Practical meaning for Amazon Connect | Available to you today? |
|---|---|---|---|
| Tier 0–1 | None / ad-hoc | No tested rebuild path | This is the current risk if restore is untested |
| Tier 2–3 | Backup and restore | This toolkit: export configuration, rebuild into a target instance | Yes — any Region, any account |
| Tier 4 | Pilot light | Target instance pre-created and kept current, numbers pre-claimed, users pre-provisioned | Yes — this toolkit plus operational discipline |
| Tier 5–6 | Warm standby | Global Resiliency replica with traffic distribution groups | **Only** in supported Region pairs, SAML enabled, same account |
| Tier 7 | Multi-site active/active plus automation | Continuous bidirectional sync, operator-driven traffic shift, regularly drilled | Approximates mature Global Resiliency |

---

## 9. The framing that makes the workshop succeed

**Do not try to land one tier for "the solution."** That produces a decision that cannot be delivered.

Amazon Connect spans domains with fundamentally different recoverability, as documented in the companion scope document. Ask the leader to agree a tier **per domain**.

### The slide that matters most

> **Restoring service, preserving records, and restoring history are three separate commitments with three separate costs.**
>
> **Amazon Connect does not let you buy them as one product.**

### The four domains

1. **Routing and telephony** — can agents answer contacts? The only genuine candidate for the most aggressive tier. This is where minutes matter.
2. **Live dependencies** — Lambda, DynamoDB, secrets, CRM, integrations. Usually must match domain 1, because restored flows that cannot look up a customer are only partly recovered. **Global Resiliency does not cover these.**
3. **Regulated interaction records** — recordings, transcripts, email, Cases, evaluations, consent. This is a *retention and immutability* requirement, not a failover one. It needs versioning and Object Lock, not a warm standby.
4. **Historical analytics and AI state** — accept days, and accept reconstruction rather than restoration. Some model state can only be retrained.

### Fidelity vocabulary to agree

Insist the leader understands that "restored" is not binary. Agree these labels:

| Label | Meaning |
|---|---|
| Native failover | Service continues or resumes in another Region with no rebuild |
| Exact native restore | Data returns byte-identical to its original store |
| Functionally reconstructed | Equivalent capability, but new identifiers, timestamps, or lineage |
| Archive / query access only | Evidence is preserved and searchable, but not live in Connect |
| Retrain / re-enrol | Must be rebuilt from source data or re-collected from users |
| Unavailable / manual | No automated path exists |

This prevents an overall "restore succeeded" claim when only configuration was restored.

---

## 10. Facilitator agenda

Suggested 90 minutes. Compress to 60 by pre-reading Sections 8 and 12.

| Time | Segment | Objective | Material |
|---|---|---|---|
| 0–10 | Frame the scope | Establish that in-Region resilience is already covered, so this is about Region-scale and cyber events only | Section 6 "good news" |
| 10–20 | Shared vocabulary | Agree RTO, RPO, MTPD / tolerance level, and the fidelity labels | Sections 3 and 9 |
| 20–30 | The tier landscape | Show the cross-walk; explain why classic tiers do not map cleanly to a managed service | Section 7 |
| 30–45 | **The constraints** | Present the hard gates, especially Region eligibility. This reframes the discussion from appetite to feasibility | Section 8 |
| 45–55 | Regulatory position | Is the contact centre a critical operation? What tolerance level applies? | Section 4 |
| 55–75 | **Per-domain decision** | Fill in the matrix live, domain by domain | Section 11 |
| 75–85 | Cost and trade-off | Test each choice against willingness to fund; identify where the leader wants to under-invest deliberately | Section 5 |
| 85–90 | Capture and actions | Complete the decision record, name owners and review date | Section 14 |

### Facilitation notes

- **Resist a single number.** If the leader pushes for "just tell me the tier," respond with the three-commitments slide.
- **Do not present a target you cannot deliver.** If Sydney is confirmed as ineligible, do not offer warm standby as though it were available.
- **Force the untested-restore question.** Ask directly: when did we last rebuild a Connect instance from backup and take a test call? If never, the current state is effectively Tier 0–1 regardless of documented intent.
- **Separate the cyber case from the outage case.** Bidirectional sync does not protect against a bad change. Make the leader choose an answer for that scenario specifically.
- **Record what is knowingly accepted.** Deliberate under-investment is a legitimate decision if it is minuted. Undocumented assumption is not.

---

## 11. Per-domain tier decision matrix

Fill in during the session. Leave nothing blank; "accepted loss" is a valid entry.

| # | Domain | What breaks if unavailable | Agreed RTO | Agreed RPO | Agreed AWS strategy | Fidelity accepted | Funded? | Owner |
|---|---|---|---|---|---|---|---|---|
| 1 | Voice / inbound telephony |  |  |  |  |  |  |  |
| 2 | Chat, task, email channels |  |  |  |  |  |  |  |
| 3 | Flows, queues, routing profiles, hours |  |  |  |  |  |  |  |
| 4 | Agent identity and access (SSO, users, security profiles) |  |  |  |  |  |  |  |
| 5 | Claimed phone numbers |  |  |  |  |  |  |  |
| 6 | Lambda and Lex dependencies |  |  |  |  |  |  |  |
| 7 | Runtime data stores (DynamoDB, RDS, secrets) |  |  |  |  |  |  |  |
| 8 | External CRM / ticketing integration |  |  |  |  |  |  |  |
| 9 | Call and screen recordings |  |  |  |  |  |  |  |
| 10 | Chat transcripts and email content |  |  |  |  |  |  |  |
| 11 | Attachments and files |  |  |  |  |  |  |  |
| 12 | Contact records (CTRs) |  |  |  |  |  |  |  |
| 13 | Cases records |  |  |  |  |  |  |  |
| 14 | Customer Profiles |  |  |  |  |  |  |  |
| 15 | Evaluations and quality records |  |  |  |  |  |  |  |
| 16 | Consent and suppression records |  |  |  |  |  |  |  |
| 17 | Historical analytics and dashboards |  |  |  |  |  |  |  |
| 18 | Forecasting and scheduling |  |  |  |  |  |  |  |
| 19 | Amazon Q knowledge bases |  |  |  |  |  |  |  |
| 20 | Voice ID enrolments |  |  |  |  |  |  |  |

### Prompt questions per row

- If this were unavailable for one hour, who notices and what do they do instead?
- If we permanently lost the last 24 hours of this, what is the consequence?
- Is there a regulatory, contractual, or legal retention requirement attached?
- Is there an authoritative source system we could rebuild this from?
- Is a functional reconstruction acceptable, or do original identifiers matter?

---

## 12. One-page pre-read for the leader

Send this alone, ahead of the session.

### What we are deciding

How much we invest to keep the contact centre running, and to preserve customer interaction records, when an event larger than a single data centre affects us.

### What is already covered, at no extra cost

Amazon Connect runs our instance across at least three physically separated Availability Zones simultaneously, and connects to multiple telephone carriers over redundant paths. Localised failures are already handled automatically without downtime.

**We are only deciding about two scenarios:**

1. An event affecting an entire AWS Region.
2. A cyber or human event — a bad change, a corruption, a malicious deletion.

### The three separate commitments

These are commonly conflated. They have different costs and cannot be bought as one product.

| Commitment | Question it answers | Rough cost driver |
|---|---|---|
| **Resume service** | Can agents answer customers again, and how fast? | Standby infrastructure and automation |
| **Preserve records** | Can we still produce recordings, transcripts, and case history for customers, auditors, and regulators? | Immutable storage and replication |
| **Restore history** | Do our historical dashboards and AI features work as before? | Data export and rebuild effort; some cannot be restored at all |

### The industry choices, simplified

| Approach | Service back in | Data loss | Relative cost |
|---|---|---|---|
| Backup and restore | Up to 24 hours | Hours | Lowest |
| Pilot light | Tens of minutes | Minutes | Low–moderate |
| Warm standby | Minutes | Seconds | High |
| Active/active | Near zero | Near zero | Highest, most complex |

### The constraint you need to know before the meeting

Amazon's managed cross-Region failover for Connect is available only in specific Region pairs. **Our production Region may not be eligible.** If confirmed, the fastest tiers are not currently purchasable for us without either migrating Regions or building it ourselves.

### What we need from you

1. Confirmation of whether the contact centre is a **critical operation**, and the **tolerance level** that applies to it.
2. A decision on how much service downtime is acceptable, separately from how much record loss is acceptable.
3. Agreement on where we will **deliberately under-invest** — for example, accepting that historical reporting takes days to rebuild.

---

## 13. Recommended landing point

Subject to confirming Region eligibility, this is the defensible position for most organisations:

### Recommendation

| Domain | Recommended position |
|---|---|
| Routing, telephony, identity | **Pilot light** (Tier 4 equivalent). Target instance pre-created, configuration continuously validated, numbers pre-claimed, users pre-provisioned. RTO in tens of minutes. |
| Live dependencies | **Match routing.** Multi-Region DynamoDB/secrets and redeployable Lambda/Lex. A restored flow that cannot look up a customer is not a restored service. |
| Regulated interaction records | **Immutable archive.** Versioning, cross-Region and cross-account replication, Object Lock where retention rules justify it. This addresses the cyber scenario that Global Resiliency does not. |
| Historical analytics and AI state | **Scheduled export, reconstruction accepted.** Recovery measured in days. Some model state retrained, not restored. |

### Why not warm standby everywhere

Three reasons, in order of force:

1. It may not be **available** in your Region pair.
2. It does not protect against the cyber scenario, because synchronisation is bidirectional.
3. It does not cover Lambda, Lex, or third-party integrations, so it delivers less end-to-end recovery than its RTO figure implies.

### The decision to force

Frame it as a choice with a named constraint, not as a capability gap:

> Either we accept a Pilot Light recovery time, **or** we fund a Region migration to a Global Resiliency-supported pair because the tolerance level demands warm standby.

Presenting it this way produces a decision. Presenting it as "we can't do warm standby" produces a deferral.

---

## 14. Decision record template

Complete before leaving the room.

```text
DR TIER DECISION RECORD

Date:
Workshop attendees:
Decision owner (senior leader):

1. IS THE CONTACT CENTRE A CRITICAL OPERATION?
   Yes / No
   Basis:
   Board-approved tolerance level (if applicable):

2. AGREED POSITION BY DOMAIN
   Service resumption (routing/telephony/identity):
     Strategy:            RTO:            RPO:
   Live dependencies:
     Strategy:            RTO:            RPO:
   Regulated records:
     Retention:           Immutability:   Replication scope:
   Historical analytics / AI:
     Strategy:            Accepted recovery time:

3. KNOWINGLY ACCEPTED RISKS
   (List each deliberate under-investment and who accepted it)

4. CONSTRAINTS ACKNOWLEDGED
   Production Region Global Resiliency eligible?  Yes / No
   SAML enabled on production instance?           Yes / No
   Cross-account protection required?             Yes / No

5. ACTIONS
   Action                                Owner        Due
   Derive internal cost-of-downtime figure
   Confirm Region eligibility with AWS SA/TAM
   Schedule first restore drill
   Document tolerance level in BCP

6. REVIEW DATE:
```

---

## Sources and attribution

All external references are linked inline above. Primary sources are AWS official documentation, IBM product documentation, NIST, APRA, and named industry research. Content drawn from public documentation was rephrased and summarised for compliance with licensing restrictions; refer to the linked originals as the authoritative text.

Figures attributed to third-party research (downtime cost per minute) are indicative industry averages with wide variance and should not be used in place of an internally derived figure.
