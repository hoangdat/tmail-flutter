# Phase 02 — JMAP Cleanup Mixin (Clean-inbox Tests)

**Priority**: High
**Status**: Todo
**Depends on**: Phase 01

## Overview

Some tests require a clean inbox (zero pre-existing emails after setup). Rather than restarting Docker (~90s), these tests track emails they create and destroy them via JMAP `Email/set {destroy: [ids]}` in `tearDown`. Cost: ~200ms per cleanup.

## Related Files

- `integration_test/mixin/scenario_utils_mixin.dart` — **modify** (add tracking helpers)
- `integration_test/base/base_test_scenario.dart` — **modify** (tearDown hook)
- `integration_test/base/test_base.dart` — **modify** (wire tearDown)
- New: `integration_test/mixin/clean_inbox_mixin.dart`

## How It Works

```
Test with clean inbox need:
  setUp  → provisioned user has empty inbox (EML slot is clean, no pre-import)
  test   → creates emails via send / JMAP API
         → tracks created email IDs in _createdEmailIds list
  tearDown → JMAP Email/set {destroy: _createdEmailIds}
           → inbox back to empty, ready for next run
           → cost: ~200ms
```

No Docker interaction. No proxy needed. All via JMAP HTTP from inside the test.

## JMAP Cleanup API Call

```dart
// JMAP request to destroy tracked emails
final request = {
  'using': ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'],
  'methodCalls': [
    ['Email/set', {
      'accountId': accountId,
      'destroy': _createdEmailIds,
    }, '0']
  ]
};
await http.post(Uri.parse('$baseUrl/jmap'), body: jsonEncode(request), headers: {...});
```

## Implementation Steps

1. **Create `CleanInboxMixin`** (`integration_test/mixin/clean_inbox_mixin.dart`):
   - `List<String> _createdEmailIds = []`
   - `void trackCreatedEmail(String id)` — called by robots after send
   - `Future<void> cleanInbox()` — calls JMAP destroy on tracked IDs
   - Uses `BASIC_AUTH_URL`, `BASIC_AUTH_EMAIL`, `PASSWORD` dart-defines for auth

2. **Integrate into `ScenarioUtilsMixin`** or as separate opt-in mixin — scenarios that need clean inbox add `with CleanInboxMixin`

3. **Wire tearDown in `TestBase`**:
   ```dart
   patrolTearDown(() async {
     if (scenario is CleanInboxMixin) {
       await (scenario as CleanInboxMixin).cleanInbox();
     }
     await _tearDown();
   });
   ```

4. **Update robots that send emails** — after successful send, call `trackCreatedEmail(emailId)` on the scenario reference (pass via constructor or static registry)

5. **Write tests** for the mixin itself — verify destroy is called with correct IDs

## Acceptance Criteria

- [ ] `CleanInboxMixin.cleanInbox()` destroys all tracked emails in < 500ms
- [ ] Scenarios that opt in have empty inbox at start of each test run
- [ ] Scenarios that don't opt in are unaffected (no teardown overhead)
- [ ] No JMAP auth token hard-coded — uses dart-define credentials
- [ ] Mixin handles empty `_createdEmailIds` list (no-op, no HTTP call)

## Risk

| Risk | Mitigation |
|------|------------|
| JMAP session not available at tearDown time | Cache session token at login; reuse for cleanup |
| Email ID tracking missed in a robot | Provide a debug log + assertion in test mode to catch un-tracked creates |
| Some state can't be cleaned (identities, settings) | Those tests use dedicated users (Phase 01) — identity/settings changes are isolated by user namespace |
