# E2E Test Isolation & Scaling Implementation Plan

**Date**: 2026-04-22
**Type**: Infrastructure / Testing
**Status**: Planning

## Executive Summary

Current E2E test setup (ADR-0053/0080) has zero isolation — all 120+ tests share one backend, data bleeds between runs. This plan implements a hybrid isolation strategy (user-per-test namespace + JMAP teardown for clean-inbox cases) and CI sharding to scale toward 500+ tests within the GitHub Actions free tier.

## Context Links

- **ADR-0053**: `docs/adr/0053-patrol-integration-test.md` — mobile Patrol foundation & known limitations
- **ADR-0080**: `docs/adr/0080-patrol-web-integration-test-setup.md` — web test setup & execution
- **ADR-0081**: `docs/adr/0081-patrol-web-test-architecture.md` — cross-platform architecture
- **Backend**: `backend-docker/docker-compose.yaml` — single-container memory James JMAP backend
- **Provisioning**: `provisioning/integration_test/provisioning.sh` — james-cli user + EML setup
- **Scripts**: `scripts/patrol-web-integration-test-with-docker.sh`

## Key Decision: Why NOT docker restart per test

James JMAP is an in-memory JVM server: startup 30–90s + provisioning 20–30s = 50–120s/restart.
At 500 tests: **500 × 90s ≈ 12.5 hours of overhead**. Not viable.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Docker Backend (starts once per CI job/shard)      │
│  James JMAP :memory  +  Admin REST API :8000        │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │  Proxy Sidecar      │  ← lightweight HTTP server on host
        │  POST /reset-user   │  → calls James Admin API
        │  (port 9876)        │  → used only for clean-inbox tests
        └──────────┬──────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
Test (Tier-1)  Test (Tier-2)  Test (Tier-1)
user isolation  clean-inbox    user isolation
 no teardown    JMAP destroy    no teardown
```

## Phases

| Phase | Title | Status |
|-------|-------|--------|
| [01](./phase-01-user-per-test-provisioning.md) | User-per-test provisioning | Todo |
| [02](./phase-02-jmap-cleanup-mixin.md) | JMAP cleanup mixin for clean-inbox tests | Todo |
| [03](./phase-03-proxy-admin-api-bridge.md) | Proxy admin API bridge (complex resets) | Todo |
| [04](./phase-04-ci-sharding.md) | CI sharding — 5 parallel GitHub Actions jobs | Todo |
| [05](./phase-05-adr-update.md) | ADR update (document final decision) | Todo |

## TODO Checklist

- [ ] Phase 1: Update provisioning.sh to generate N users per shard
- [ ] Phase 1: Pass per-test user via dart-define or test index mapping
- [ ] Phase 2: Add `CleanInboxMixin` with JMAP email destroy in tearDown
- [ ] Phase 2: Add opt-in to scenarios that need clean inbox
- [ ] Phase 3: Implement proxy sidecar (Go or Node — minimal HTTP server)
- [ ] Phase 3: Expose `POST /reset-user/{email}` calling James admin API
- [ ] Phase 4: Add matrix sharding to `.github/workflows/patrol-web-integration-test.yaml`
- [ ] Phase 4: Update patrol scripts to accept shard index + total
- [ ] Phase 5: Write ADR-0085 documenting final isolation decisions
