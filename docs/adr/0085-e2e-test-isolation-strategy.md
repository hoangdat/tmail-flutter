# 85. E2E Test Isolation Strategy

Date: 2026-04-24

## Status

Accepted

## Related ADRs

- [ADR-0053](./0053-patrol-integration-test.md) — Patrol mobile foundation (problem statement)
- [ADR-0080](./0080-patrol-web-integration-test-setup.md) — Web test setup & execution
- [ADR-0081](./0081-patrol-web-test-architecture.md) — Cross-platform test architecture

---

## Context

[ADR-0053](./0053-patrol-integration-test.md) acknowledged two limitations:

1. **No data isolation** — all tests share one backend; state bleeds between runs.
2. **No Docker access from Patrol** — the APK bundles all tests; it cannot call `docker` from inside.

As test count grows toward 500+, these limitations cause intermittent failures that are hard to reproduce and slow to diagnose. A scalable isolation strategy is needed.

### Why not restart Docker per test

The backend image is `linagora/tmail-backend:memory-*` — an in-memory JVM JMAP server. A full restart (down + up + provision) costs **50–120 seconds per test**. At 500 tests that is 7–17 hours of overhead — not viable.

---

## Decision

### Core principle: test isolation without per-test Docker restarts

Isolation is achieved by assigning each test a **dedicated user account** or a **shared user whose data it does not mutate**. No Docker restart per test. No teardown required.

Three provisioning profiles (shards) cover all test types:

| Shard | Users provisioned | Test count capacity |
|-------|------------------|-------------------|
| `noProvision` | 2 shared users | Unlimited — tests create their own data via `provisionEmail()` at runtime |
| `preloadedEmails` | 1 shared user (slot 0) | All pre-loaded tests share slot 0; superset of all EML folders |
| `infra` | 1 user per test | Each test gets unique account-level configuration |

---

### Shard assignment: 3-question decision tree

```
Q1: Does the test configure account-level settings (quota, team mailbox)?
    YES ──► shard: infra, own userSlot (one slot per test)
    NO  ──► Q2

Q2: Does the test open an email that MUST already exist before the test runs,
    AND cannot be created with provisionEmail() at runtime?
    YES ──► shard: preloadedEmails, userSlot: 0  (shared slot)
    NO  ──► Q3

Q3: Everything else
         ──► shard: noProvision, userSlot: 0 or 1
```

#### When is Q2 "YES"?

Pre-loading is only needed when the email's **raw EML content** matters — specific headers (`Reply-To:`, `ICS` attachment, `Content-Disposition: inline`) that `provisionEmail()` cannot produce. If the test only cares that an email exists (subject, body, sender), use `provisionEmail()` and stay in `noProvision`.

| Test type | EML needed? | Shard |
|-----------|-------------|-------|
| Send email | — | `noProvision` |
| Search email (sort order, relevance) | No — `provisionEmail()` creates searchable emails | `noProvision` |
| Login, composer, draft, template | — | `noProvision` |
| Reply-To header behavior | Yes — needs `Reply-To:` header in EML | `preloadedEmails` |
| ICS calendar counter | Yes — needs `text/calendar` MIME part | `preloadedEmails` |
| `Content-Disposition: inline` | Yes — needs `inline` disposition header | `preloadedEmails` |
| Base64 image in email | Yes — needs specific `Content-Transfer-Encoding` | `preloadedEmails` |
| Quota enforcement | — (admin API) | `infra` |
| Team mailbox membership | — (admin API) | `infra` |

---

### Provisioning profile per shard

Provisioning runs **once at Docker startup**, before Patrol launches.

#### `noProvision`

```bash
james-cli AddUser "np_000@example.com" "np_000"
james-cli AddUser "np_001@example.com" "np_001"
```

2 users. Tests call `provisionEmail()` inside the test body to inject any emails they need. After the test the emails remain — this is safe because tests operate on the Inbox and other tests use their own user.

#### `preloadedEmails`

```bash
james-cli AddUser "pe_000@example.com" "pe_000"
# ALL EML folders for slot 0 — superset provisioning
james-cli CreateMailbox \#private "pe_000@example.com" "Forward Emails"
james-cli ImportEml \#private "pe_000@example.com" "Forward Emails" "forward.eml"
james-cli CreateMailbox \#private "pe_000@example.com" "Reply Emails"
james-cli ImportEml \#private "pe_000@example.com" "Reply Emails" "reply-all.eml"
james-cli ImportEml \#private "pe_000@example.com" "Reply Emails" "with-reply-to.eml"
# ... other reply EMLs
james-cli CreateMailbox \#private "pe_000@example.com" "Calendar"
james-cli ImportEml \#private "pe_000@example.com" "Calendar" "calendar_counter.eml"
james-cli CreateMailbox \#private "pe_000@example.com" "Disposition"
james-cli ImportEml \#private "pe_000@example.com" "Disposition" "no_disposition_inline.eml"
james-cli CreateMailbox \#private "pe_000@example.com" "MailBase64"
james-cli ImportEml \#private "pe_000@example.com" "MailBase64" "0.eml"
```

1 user. All `preloadedEmails` tests share `pe_000`. Because these tests open specific emails (read-only intent), they do not write to the same mailbox concurrently. If a test does mutate state (e.g., marks as read), the next run may be affected — add a dedicated slot only when this becomes a real problem.

#### `infra`

```bash
for i in 0 1 ...; do
  james-cli AddUser "si_${i}@example.com" "si_${i}"
  # slot 0: quota
  curl -X PUT http://admin:8000/quota/users/si_000@example.com -d '{"count":200,"size":50000000}'
  # slot 1: team mailbox
  curl -X PUT http://admin:8000/domains/example.com/team-mailboxes/si_001-guests
  curl -X PUT http://admin:8000/.../members/si_001@example.com?role=member
done
```

1 user per test. Each test requires unique account-level config that cannot be shared.

---

### Why not sub-shards inside `preloadedEmails`?

An earlier proposal created sub-shards (`preloadedEmails/forwardEmails`, `preloadedEmails/replyEmails`, etc.) to give each test its own EML copy. This was rejected because:

1. **Provisioning cost grows with test count** — 10 sub-shards × 20 tests × 5 EMLs = 1000 `ImportEml` calls.
2. **Complexity without benefit** — tests that open pre-loaded EMLs typically open them read-only. If a test does mutate the email, only that EML is affected; other-folder tests are unaffected regardless.
3. **Simple rule breaks** — authors would need to know which sub-shard covers their EML folder, turning a 3-question decision tree into a lookup table.
4. **Superset provisioning is cheaper** — 1 user with all folders costs ~1s vs N users × N folders × M EMLs.

The current rule: **all `preloadedEmails` tests share slot 0**. Add dedicated slots only when a specific test is proven to cause state pollution that breaks another test.

---

### Why `searchEmails` is not a separate shard

The original design had a dedicated `shard-search-emails` for search-sort-order tests, under the assumption that these tests needed pre-loaded EMLs in a `Search Emails` folder.

In practice, search tests use `provisionEmail()` at runtime to inject JMAP emails directly — no EML import needed. The tests are therefore stateless (they create their own data) and belong in `noProvision`. A separate shard with identical provisioning cost would add CI parallelism overhead for no isolation gain.

---

### Implementation: TestShard enum and UserCredentials

The framework injects credentials at runtime. Test authors do not read dart-defines.

```dart
// integration_test/models/test_shard.dart
enum TestShard {
  noProvision('shardNoProvision', 'np'),
  preloadedEmails('shardPreloadedEmails', 'pe'),
  infra('shardInfra', 'si');

  final String tagName;    // Patrol tag; used by --tags= CI flag
  final String userPrefix; // np_000, pe_000, si_001 etc.

  const TestShard(this.tagName, this.userPrefix);
}

// integration_test/models/user_credentials.dart
class UserCredentials {
  final String email;    // np_000@example.com
  final String username; // np_000
  final String password; // np_000 (James: same as username)
  final String hostUrl;  // from BASIC_AUTH_URL dart-define

  const UserCredentials({...});
}
```

`TestBase._resolveCredentials(shard, userSlot)` computes credentials from `DOMAIN` and `BASIC_AUTH_URL` dart-defines plus the shard's `userPrefix` and slot number.

---

### Two-layer shard filtering

Patrol bundles ALL tests into one APK. `--tags=X` alone is not reliable for on-device filtering.

**Layer 1 — Patrol tag** (`patrol test --tags=$PATROL_TAG`): controls which tests the Patrol CLI includes in the instrumentation bundle at generation time.

**Layer 2 — dart-define guard** (`--dart-define=SHARD=$SHARD`): `TestBase._runningShard` is baked in at compile time. At runtime, `runPatrolTest()` skips any test whose `shard.name != _runningShard`. This is the reliable layer.

Both layers are needed: layer 1 reduces bundle size; layer 2 guarantees correctness.

```dart
static const _runningShard = String.fromEnvironment('SHARD');

// in runPatrolTest():
if (_runningShard.isNotEmpty && shard != null && shard.name != _runningShard) {
  test(description, () {}, skip: 'Skipped: shard=${shard.name}, running=$_runningShard');
  return;
}
```

---

### What each test author must do

1. **Pick the shard** — answer the 3-question tree above.
2. **Declare shard + slot** in `runPatrolTest()`:

```dart
TestBase().runPatrolTest(
  description: 'Should see thread view after login',
  shard: TestShard.noProvision,
  userSlot: 1,          // 0 or 1 for noProvision; 0 for preloadedEmails; unique for infra
  scenarioBuilder: ($, robots, credentials) =>
      LoginWithBasicAuthScenario($, robots, credentials),
  tags: [TestTags.android, TestTags.ios, TestTags.web],
);
```

3. **Use injected `credentials`** — do not read dart-defines in scenario code:

```dart
class LoginWithBasicAuthScenario extends BaseTestScenario {
  const LoginWithBasicAuthScenario(super.$, super.robots, super.credentials);

  @override
  Future<void> runTestLogic() async {
    // credentials.email, credentials.username, credentials.hostUrl
    // are already used by BaseTestScenario.execute() to login
    await expectViewVisible($(ThreadView));
  }
}
```

4. **No teardown needed** — do not add `tearDown` to undo mutations.

---

### What test authors must NOT do

| Prohibited | Reason |
|------------|--------|
| Hard-code `bob@example.com` | Shared legacy user — breaks isolation |
| Read `String.fromEnvironment('BASIC_AUTH_EMAIL')` in scenarios | Credentials are injected via `UserCredentials`; dart-defines are compile-time only |
| Add `tearDown` to delete emails | Unnecessary; dedicated user is never reused by another test |
| Put a test in `preloadedEmails` when `provisionEmail()` works | Bloats superset provisioning unnecessarily |

---

### CI sharding

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [noProvision, preloadedEmails, infra]
```

Each matrix job sets `SHARD=<value>` and the run scripts map it to the correct `PATROL_TAG`.

**Splitting an oversized shard**: when a shard exceeds ~20 tests (> 15 min), split by test file list within the same matrix job (two jobs, same provisioning profile, different `--tags` subsets). The 3-question rule does not change.

---

## Consequences

- **3 shards instead of 4** — `searchEmails` removed; search tests move to `noProvision` since they use `provisionEmail()`.
- **6 users total** regardless of test count — 2 for `noProvision`, 1 for `preloadedEmails`, 1 per `infra` test. Adding a new test to `noProvision` or `preloadedEmails` adds 0 users.
- **No Docker restart per test** — provisioning is once per shard at startup (~75s total).
- **No teardown code** — simpler scenarios; no `CleanInboxMixin`.
- **Simple decision rule** — 3 yes/no questions, not a folder lookup table.
- **Sub-shards rejected** — superset provisioning for `preloadedEmails` is cheaper and simpler; dedicated slots added only when state pollution is proven.
- **Parallel CI** — 3 shards run concurrently; wall-clock ≈ max(shard_time).
