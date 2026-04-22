# Phase 05 — ADR Update

**Priority**: Low (document after implementation)
**Status**: Todo
**Depends on**: All phases complete

## Overview

Write ADR-0085 documenting the final isolation and scaling decisions. Update ADR-0053 status to reflect the limitations being addressed.

## Related Files

- `docs/adr/0053-patrol-integration-test.md` — **update** Limitations section
- New: `docs/adr/0085-e2e-test-isolation-and-scaling.md`

## ADR-0085 Structure

```markdown
# 85. E2E Test Isolation & Scaling Strategy

Date: 2026-04-22

## Status: Accepted

## Related ADRs
- ADR-0053 — Patrol mobile foundation (acknowledged limitations)
- ADR-0080 — Web test setup
- ADR-0081 — Cross-platform architecture

## Context
[ADR-0053] identified no data isolation between tests and confirmed
the APK cannot access Docker directly. This ADR records the chosen
solution as test count grows toward 500+.

## Decision: Hybrid Isolation

### Tier 1 — User-per-test namespace (all tests)
One James user provisioned per test scenario at Docker startup.
Tests operate in their own email namespace.

### Tier 2 — JMAP Email/set destroy in tearDown (clean-inbox tests)
Opt-in via CleanInboxMixin. Tracks and destroys emails created during
the test. Cost: ~200ms. No Docker restart.

### Tier 3 — Proxy Admin API bridge (complex resets only)
For quota/identity/push-token resets that JMAP can't handle.
Sidecar HTTP server calls James Admin REST API.
NOT used for Docker lifecycle (too slow).

## Rejected: docker compose down/up per test
At 500 tests × 90s = 12.5 hours of overhead. Impractical.

## CI Sharding
5 parallel GitHub Actions jobs per platform. Each job has its own
runner and Docker backend. No shared state between shards.
Target wall-clock: < 15 min for 500 tests (was 4+ hours sequential).

## Consequences
- Provisioning script must create N users per shard at startup
- Clean-inbox tests must opt in to CleanInboxMixin and track email IDs
- CI matrix requires all shards to pass for PR gate
```

## Implementation Steps

1. **Write ADR-0085** at `docs/adr/0085-e2e-test-isolation-and-scaling.md`
2. **Update ADR-0053 Limitations** section — mark each limitation as "Addressed by ADR-0085"
3. **Update ADR-0080 Consequences** — note sharding and isolation changes

## Acceptance Criteria

- [ ] ADR-0085 written and accurate to implemented solution
- [ ] ADR-0053 Limitations section updated with "Addressed in ADR-0085" annotation
- [ ] No contradictions between ADR-0080/0081 and the new ADR
