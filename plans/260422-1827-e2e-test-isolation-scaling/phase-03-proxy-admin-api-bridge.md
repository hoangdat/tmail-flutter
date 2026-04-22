# Phase 03 — Proxy Admin API Bridge (Complex Resets)

**Priority**: Medium (only for tests that can't be handled by Phase 01/02)
**Status**: Todo
**Depends on**: Phase 01

## Overview

A minimal HTTP sidecar running on the host exposes a `POST /reset-user/{email}` endpoint that calls the James Admin REST API (port 8000) to atomically reset a user's state. This is the **nuclear option** for tests that modify global state (quota, push tokens, identities) that JMAP `Email/set` can't undo.

**Important**: Most tests will NOT need this. Phase 01 (user isolation) + Phase 02 (JMAP cleanup) handle the vast majority. This proxy is only for edge cases.

## Architecture

```
Test (inside app/browser)
  │  HTTP POST http://localhost:9876/reset-user/test_007@example.com
  ▼
Proxy sidecar (host, port 9876)
  │  DELETE http://localhost:8000/users/test_007@example.com/mailboxes
  │  DELETE http://localhost:8000/users/test_007@example.com/quota
  ▼
James Admin REST API (Docker container, port 8000)
```

Mobile tests reach the proxy at `10.0.2.2:9876` (Android emulator host alias).
Web tests reach it at `localhost:9876`.

## Related Files

- New: `scripts/proxy-admin-bridge/` — the sidecar server
- `scripts/patrol-web-integration-test-with-docker.sh` — start proxy before tests
- `integration_test/mixin/scenario_utils_mixin.dart` — add `resetUser()` helper

## Proxy Implementation

Keep it minimal — a single-file Go or Node.js HTTP server:

```
scripts/proxy-admin-bridge/
├── main.go          (or server.js)
└── README.md
```

**Endpoints**:
```
POST /reset-user/:email
  → DELETE :8000/users/:email/mailboxes (drops all mailboxes + messages)
  → POST  :8000/usersQuota/:email  {count: 200, size: 50000000} (reset quota)
  → 200 OK when done

GET /health  → 200 OK (used by test wait-loop)
```

**Sample Go implementation** (single file, no dependencies):
```go
http.HandleFunc("/reset-user/", func(w http.ResponseWriter, r *http.Request) {
    email := strings.TrimPrefix(r.URL.Path, "/reset-user/")
    // call james admin DELETE /users/{email}/mailboxes
    // call james admin PUT /quota/users/{email} to reset
    w.WriteHeader(http.StatusOK)
})
http.ListenAndServe(":9876", nil)
```

## Implementation Steps

1. **Write proxy server** in Go (no deps) or Node.js (built-in http module) — keep under 80 lines
2. **Update run scripts** — start proxy before `patrol test`, kill after
   ```bash
   go run scripts/proxy-admin-bridge/main.go &
   PROXY_PID=$!
   # ... run tests ...
   kill $PROXY_PID
   ```
3. **Add `resetUser(String email)` to `ScenarioUtilsMixin`**:
   ```dart
   Future<void> resetUser(String email) async {
     final proxyUrl = kIsWeb ? 'http://localhost:9876' : 'http://10.0.2.2:9876';
     await http.post(Uri.parse('$proxyUrl/reset-user/$email'));
   }
   ```
4. **Add health-check wait** in run scripts before patrol starts (ensures proxy is ready)
5. **Re-provision after reset** — proxy optionally calls provisioning endpoint to re-import EML for that user slot

## Acceptance Criteria

- [ ] Proxy starts and responds to `/health` within 2s
- [ ] `POST /reset-user/{email}` completes in < 1s (James Admin REST is fast)
- [ ] Mobile tests can reach proxy at `10.0.2.2:9876`
- [ ] Web tests can reach proxy at `localhost:9876`
- [ ] Proxy process is killed cleanly on test suite completion (no orphan process in CI)
- [ ] Proxy source is < 80 lines, no external dependencies

## Risk

| Risk | Mitigation |
|------|------------|
| James Admin API port (8000) not exposed on host | Add `ports: - "8000:8000"` to docker-compose.yaml for test runs |
| Proxy orphaned in CI if patrol crashes | Trap EXIT signal in run script: `trap "kill $PROXY_PID" EXIT` |
| Android emulator can't reach 10.0.2.2:9876 | Verify with adb shell curl; standard emulator networking supports this |
