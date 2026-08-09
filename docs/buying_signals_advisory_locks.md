# Buying Signals Advisory Locks

Buying-signal generation is serialized per `(agent_id, company_id)` using `BuyingSignals::CompanyAdvisoryLock`.

Participants:

- `BuyingSignals::Resolver` for just-in-time sample/message generation.
- `BuyingSignals::EnrichLeadJob` for lead-level manual enrichment.
- `BuyingSignals::EnrichCompanyJob` for batch/company enrichment.

All participants must use the shared helper instead of calling `pg_try_advisory_lock` or `pg_advisory_lock` directly. The helper uses bounded polling with PostgreSQL advisory locks so concurrent work for the same agent/company waits briefly, then either reuses a fresh completed summary or raises a retryable timeout.

When adding a new participant:

1. Lock by `agent_id` and `company_id` with `BuyingSignals::CompanyAdvisoryLock.with_lock`.
2. Recheck the `BuyingSignalsSummary` inside the lock before generating.
3. Release the lock with the helper's `ensure` path; do not manage unlocks manually.
