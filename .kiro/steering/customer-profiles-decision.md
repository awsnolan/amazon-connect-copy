---
inclusion: manual
---

# Decision: Customer Profiles — Treat Same as Cases

**Date:** 2026-07-28

> **Status update (November 2026):** The config restore automation described
> below as "planned" was implemented the same day in Phase 4 (`81f7572`) and
> lives in `bin/lib/restore/supporting.sh`. The data-out-of-scope decision
> still stands and remains the governing rationale. This document is retained
> as the dated decision record; see
> [DR_RECOVERY_LAYERS.md](../../DR_RECOVERY_LAYERS.md) for the current view,
> including newer Cases and Profiles config types that are not yet covered
> (Cases Phases, event configuration, case rules, SLA config, Profiles domain
> layouts and segment definitions).

## Summary

Customer Profiles will be treated identically to Cases in the toolkit:
- **Config is backed up** (domain, object types, calculated attributes, identity resolution config)
- **Config restore automation is planned** (not yet implemented)
- **Data (actual profile records) is explicitly out of scope** — not backed up, not restored, never will be

## What "Config" Means for Each Feature

| Feature | Config (in scope) | Data (out of scope) |
|---------|-------------------|---------------------|
| **Cases** | Domain, custom fields, layouts, templates | Case records (individual cases filed by agents) |
| **Customer Profiles** | Domain, object type definitions, calculated attributes, identity resolution rules, integration definitions | Profile records (customer data, merged profiles, interaction history) |

## Rationale for Data Being Out of Scope (Both Features)

- **Volume:** Production profiles/cases can be millions of records — not a "minutes to failover" operation
- **Freshness:** Data changes constantly; any backup is immediately stale
- **Source of truth exists elsewhere:** Cases are operational artifacts; profiles typically originate from CRM systems (Salesforce, ServiceNow) via AppFlow and can be re-ingested
- **Identity resolution state is non-portable:** ML-based merge graphs are instance-specific
- **Design principle:** The toolkit optimizes for RTO (time to answer calls), not data completeness

## Operational Expectation During DR

- **Cases:** Agents take notes during DR, file new cases on failback. Historical cases remain accessible in the source instance.
- **Customer Profiles:** Flows referencing profiles will return empty/error but route via error paths. Once AppFlow integrations are reconnected on the DR instance, data re-ingests from source systems.

## Implementation Plan

1. **README.md** — Add Customer Profiles to "Backed up only" table and "NOT Restored" feature table
2. **DR_OPERATOR_GUIDE.md** — Add to manual steps checklist and feature status table (same pattern as Cases section 10)
3. **DR_VALIDATION_SPEC.md** — Add validation layer (domain exists, object types match, calculated attributes match)
4. **BACKLOG.md** — New item: "Cases & Customer Profiles Config Restore Automation" clarifying:
   - Automation covers config restoration only (schemas, field definitions, templates, layouts, object types, calculated attributes)
   - Data (case records, profile records) is permanently out of scope
   - External integrations (AppFlow OAuth connections) require manual reconnection even with config automation
5. **IAM permissions** — Add to backup profile: `profile:ListDomains`, `profile:GetDomain`, `profile:ListProfileObjectTypes`, `profile:GetProfileObjectType`, `profile:ListCalculatedAttributes`, `profile:GetCalculatedAttributeDefinition`

## Clarification on Existing Cases Entry

The current backlog/docs say "restore automation planned" for Cases. This should be clarified:
- The automation will restore **config** (domain creation, field definitions, layout structure, template definitions)
- It will **not** restore case records — that's operational data, not configuration
- Same principle applies to Customer Profiles when its automation is built

## Customer Profiles API Coverage (Config)

All needed for backup:
- `ListDomains` / `GetDomain`
- `ListProfileObjectTypes` / `GetProfileObjectType`
- `ListCalculatedAttributes` / `GetCalculatedAttributeDefinition`
- `ListIntegrations` (informational — can't restore OAuth tokens)

For validation on target:
- Same read APIs above against the target instance

## Relationship to Existing Toolkit Design

This fits the established pattern:
- **Tier 1 (core telephony):** Fully automated backup + restore + validation
- **Tier 2 (advanced features):** Config backed up, validation layer exists, restore is manual today with automation planned
- Cases and Customer Profiles are both Tier 2
