# 0071 - Enable collapseThreads in Email/query

Date: 2026-03-12

## Status

Proposed

## Context

JMAP `Email/query` supports a `collapseThreads` parameter (RFC 8621 §4.4.2). When `true`, the server returns only the **latest email per thread** in query results, avoiding duplicate display of emails belonging to the same conversation.

Currently, our app does **not** set `collapseThreads`. When thread support is enabled on the server, the email list may show multiple emails from the same thread as separate rows — confusing for users expecting a conversation-grouped view.

### Goal

When thread is enabled, automatically enable `collapseThreads: true` in `Email/query` so users see one entry per thread in the mail list.

### The Two Query Paths

The app has two email-fetching strategies controlled by `FORCE_EMAIL_QUERY` (see ADR-0070):

| Path | Flag | Method | Cache Used |
|------|------|--------|------------|
| **Force query** | `FORCE_EMAIL_QUERY=true` | `forceQueryAllEmailsForWeb()` | Server-only, no local cache for list display |
| **Cache-first** | `FORCE_EMAIL_QUERY=false` | `getAllEmail()` in `ThreadRepositoryImpl` | Local DB first, then sync with server |

Routing logic is in `GetEmailsInMailboxInteractor.execute()`.

### Problem: Cache Inconsistency on Cache-First Path

The cache-first path (`FORCE_EMAIL_QUERY=false`) works as follows (see `ThreadRepositoryImpl.getAllEmail()`):

1. Load emails from local DB cache
2. If cache is empty or insufficient → query server → yield server result → update cache
3. Sync cache with server changes → yield updated cache

**The inconsistency scenario:**

1. User has been using the app **without thread enabled** → local DB stores **all individual emails** (e.g., 5 emails in a 3-message thread = 5 cached rows)
2. Server enables thread support → app enables `collapseThreads: true` in `Email/query`
3. Server now returns **3 emails** (one per thread) instead of 5
4. But local DB still has **5 emails** from pre-thread era
5. On next app open, cache-first path yields the **stale 5 emails** first → UI shows un-collapsed list
6. After sync, cache gets updated, but the first yield already showed wrong data

For the force-query path (`FORCE_EMAIL_QUERY=true`), there is **no problem** — it always queries the server directly with `collapseThreads: true` and never shows stale cache.

### Problem: Cache Inconsistency When Thread Is Disabled Again

The reverse scenario also causes inconsistency:

1. User has been using the app **with thread enabled** → local DB stores **collapsed emails** (one per thread, e.g., 3 cached rows representing 3 threads)
2. Server/user disables thread → app stops sending `collapseThreads: true`
3. Server now returns **all individual emails** (e.g., 5 emails across those 3 threads)
4. But local DB still has only **3 collapsed entries**
5. On next app open, cache-first path yields **3 emails** → user sees missing emails that should now be visible as individual rows
6. After sync, new individual emails may arrive via changes, but the cache was never built to hold per-email entries — stale/incomplete display

**Same root cause**: cache was built under a different `collapseThreads` mode than the current one.

## Decision

### 1. Add `collapseThreads: true` to Email/query When Thread Is Enabled

In `QueryEmailMethod` construction (in `MailAPIMixin.fetchAllEmail()` and `ThreadAPI.searchEmails()`), set `collapseThreads: true` when Thread enabled.

### 2. Clear Email Cache on Thread Setting Toggle

The existing thread-enabled flag in settings already tracks the current mode. **No additional flag needed.**

When the thread setting is toggled (enable ↔ disable), **clear the email cache immediately** as part of the toggle action. This forces a fresh server query on the next `getAllEmail()` call, ensuring the cache is rebuilt under the correct `collapseThreads` mode.

- **Thread OFF → ON**: Cache has too many emails (un-collapsed) → clear → reload with collapsed results
- **Thread ON → OFF**: Cache has too few emails (collapsed) → clear → reload with all individual emails

This is a **one-time cost per toggle** — subsequent loads will have a cache consistent with the current query mode.

### 3. No Change Needed for Force-Query Path

`forceQueryAllEmailsForWeb()` always queries the server. Simply passing `collapseThreads: true` in the query is sufficient.

## Consequences

### Positive

1. **Correct thread display**: Mail list shows one entry per thread, matching user expectation
2. **Reduced data**: Server returns fewer results per page → faster response
3. **Consistent with JMAP spec**: Proper use of `collapseThreads` per RFC 8621

### Negative

1. **Cache clear on toggle**: Users on cache-first path will experience a full reload each time thread mode changes (enable ↔ disable)
2. **Toggle handler change**: Thread setting toggle handler must also clear email cache — couples setting change with cache management

## Implementation Steps

1. Add `collapseThreads` parameter to `QueryEmailMethod` construction in `MailAPIMixin.fetchAllEmail()` and `ThreadAPI.searchEmails()`
2. Pass thread-enabled status from `Session` down to the query builder
3. In the thread setting toggle handler: clear email cache when thread is enabled or disabled
4. Update `GetEmailsInMailboxInteractor` and related interactors to propagate thread status

## References

- [RFC 8621 §4.4.2 — Email/query](https://www.rfc-editor.org/rfc/rfc8621#section-4.4.2)
- [ADR-0070 — Sync Strategy & FORCE_EMAIL_QUERY](./0070-sync-strategy-disappearing-emails.md)
- `lib/features/thread/data/repository/thread_repository_impl.dart` — `getAllEmail()`, `forceQueryAllEmailsForWeb()`
- `lib/features/thread/domain/usecases/get_emails_in_mailbox_interactor.dart` — routing logic
- `lib/features/base/mixin/mail_api_mixin.dart` — `fetchAllEmail()` builds `QueryEmailMethod`
