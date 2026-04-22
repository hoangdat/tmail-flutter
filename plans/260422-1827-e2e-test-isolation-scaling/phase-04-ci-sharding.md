# Phase 04 — CI Sharding (Parallel GitHub Actions Jobs)

**Priority**: High (biggest wall-clock improvement)
**Status**: Todo
**Depends on**: Phase 01

## Overview

Split the test suite across N parallel GitHub Actions jobs. Each job = its own runner = its own Docker backend. No shared state between shards. Reduces wall-clock time by Nx.

**Target**: 5 shards for web + 5 for mobile (10 concurrent jobs, within GitHub's free-tier 20-job limit for public repos).

## Wall-clock Impact

| Scenario | Sequential | 5 Shards |
|----------|-----------|----------|
| 120 tests (today) | ~60 min | ~14 min |
| 500 tests (target) | ~4.2 hr | ~52 min |

(Assumes ~30s avg per test + 90s Docker startup amortized per shard)

## Related Files

- `.github/workflows/patrol-web-integration-test.yaml` — **modify**
- `.github/workflows/patrol-integration-test.yaml` — **modify** (mobile)
- `scripts/patrol-web-integration-test-with-docker.sh` — **modify** (accept shard args)
- `scripts/patrol-integration-test-with-docker.sh` — **modify** (accept shard args)

## Sharding Strategy: Directory-based

Group tests by feature directory. Static — no dynamic discovery needed.

```yaml
strategy:
  matrix:
    shard:
      - name: composer
        dirs: "integration_test/tests/composer"
      - name: thread
        dirs: "integration_test/tests/thread integration_test/tests/mailbox"
      - name: search
        dirs: "integration_test/tests/search"
      - name: settings
        dirs: "integration_test/tests/settings integration_test/tests/identity"
      - name: misc
        dirs: "integration_test/tests/login integration_test/tests/calendar"
```

## GitHub Actions Matrix Configuration

```yaml
# .github/workflows/patrol-web-integration-test.yaml
jobs:
  patrol-web-test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false          # don't cancel all shards if one fails
      matrix:
        shard:
          - { name: composer, dirs: "integration_test/tests/composer" }
          - { name: thread,   dirs: "integration_test/tests/thread integration_test/tests/mailbox" }
          - { name: search,   dirs: "integration_test/tests/search" }
          - { name: settings, dirs: "integration_test/tests/settings" }
          - { name: misc,     dirs: "integration_test/tests/login integration_test/tests/calendar" }
    name: patrol-web-${{ matrix.shard.name }}
    steps:
      - uses: actions/checkout@v4
      - name: Run shard
        run: |
          ./scripts/patrol-web-integration-test-with-docker.sh \
            --shard-name "${{ matrix.shard.name }}" \
            --test-dirs "${{ matrix.shard.dirs }}"
```

## Script Changes

Update `patrol-web-integration-test-with-docker.sh` to accept `--test-dirs`:

```bash
# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --shard-name) SHARD_NAME="$2"; shift 2 ;;
    --test-dirs)  TEST_DIRS="$2";  shift 2 ;;
    *) shift ;;
  esac
done

# Build patrol -t flags from dirs
PATROL_TEST_FLAGS=""
for dir in $TEST_DIRS; do
  PATROL_TEST_FLAGS="$PATROL_TEST_FLAGS -t $dir"
done

# Run patrol with test subset
patrol test -v \
  --tags=web \
  --device=chrome \
  --web-headless=true \
  $PATROL_TEST_FLAGS \
  ...
```

## NUM_USERS Per Shard

Each shard provisions only the users it needs:
```bash
# Count test files in this shard's dirs
NUM_USERS=$(find $TEST_DIRS -name "*_test.dart" | wc -l)
export NUM_USERS
```

## PR Gate

All shard jobs must pass for the PR check to be green. Use `needs` with all shard job names, or configure branch protection to require the matrix job.

## Acceptance Criteria

- [ ] All 5 web shards run in parallel on PR push
- [ ] Each shard starts its own Docker backend (no port conflicts — runners are isolated VMs)
- [ ] `fail-fast: false` — one shard failure doesn't cancel others
- [ ] Total wall-clock time < 15 min for current test count (120 tests)
- [ ] PR is gated on all shards passing
- [ ] Local run still works without shard args (defaults to all tests)

## Risk

| Risk | Mitigation |
|------|------------|
| Uneven shard sizes (one shard much slower) | Monitor shard times after first run; rebalance dirs |
| GitHub Actions concurrency limit hit | Public repos get 20 concurrent — 10 jobs (5 web + 5 mobile) is within limit |
| Docker startup cost still significant per shard | 90s startup / 24 tests per shard = 3.75s overhead per test — acceptable |
