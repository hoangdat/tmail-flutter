# Plan: OCP-Compliant State Propagation via AppEventBus

**Date:** 2026-04-13  
**Branch:** architecture  
**Status:** In Progress  

## The Core Question

> "How does state update after an interactor executes via `EmailAction` and `EmailActionQueue`?  
> We don't want `consumeState` anymore, and we don't want to edit existing files when adding new features."

---

## What `consumeState` Was Doing (and What Replaces Each Part)

`consumeState(stream, onSuccess: ...)` did **3 things**:

| Responsibility | Old: `consumeState` | New: `EmailActionQueue` |
|---|---|---|
| Execute stream & dispatch to `viewState` | `viewState.value = result` | **Removed** — `viewState` not used for email actions |
| Route success type to handler | `handleSuccessViewState(success)` if/else chain | **`AppEventBus.fire(success)` → `StateProvider.on<X>()`** |
| Controller-local UI reactions (toast, nav) | `onSuccess: (s) { ... }` callback | **Same: `onSuccess` callback in `submit()`** |

---

## The Two Channels (Replace consumeState)

### Channel 1: AppEventBus → StateProvider (Domain State)

Handles **shared, cross-cutting state** — data that multiple screens care about.

```
EmailActionQueue.submit(action)
  → action.execute() → Stream
    → .listen()
      → eventBus.fire(MarkAsEmailReadSuccess)    ← always fires, app lifecycle
                ↓
        EmailListStateProvider.on<MarkAsEmailReadSuccess>()
                ↓
        updateEmailFlagByEmailIds(...)            ← mutates emailsInCurrentMailbox.obs
                ↓
        Obx(() => EmailTile(...))                ← re-renders automatically
```

**OCP compliance:** Add new action type → add new `StateProvider` subscriber.  
Zero existing files modified.

### Channel 2: `onSuccess` Callback (UI Reactions)

Handles **controller-local, screen-specific** reactions: toasts, snackbars, navigation.

```dart
_actionQueue.submit(
  MarkAsReadEmailAction(...),
  token: _cancelToken,                          // optional: cancelled on controller close
  onSuccess: (success) {
    if (success is MarkAsEmailReadSuccess) {
      _showToast('Marked as read');             // controller-local UI only
    }
  },
);
```

**Not OCP** — but these are trivially small (no state machine). The callback is at the call site.

---

## The `handleSuccessViewState` Problem (OCP Violation)

```dart
// BEFORE: every new action required editing this method
void handleSuccessViewState(Success success) {
  if (success is MarkAsEmailReadSuccess) { ... }
  else if (success is MarkAsStarEmailSuccess) { ... }
  else if (success is ArchiveEmailSuccess) { ... }  // edit needed!
}
```

**Solution:** `handleSuccessViewState` must no longer handle email action results.  
It should only handle **controller-lifecycle states** (loading data, searching, paginating).

```dart
// AFTER: clean separation
void handleSuccessViewState(Success success) {
  // Only controller-lifecycle states — these don't change when adding email actions
  if (success is GetAllEmailLoading) { ... }
  else if (success is LoadMoreEmailsSuccess) { ... }
  // Mark-as-read, mark-as-star, archive → handled by their StateProviders via bus
}
```

---

## Loading State Strategy

Email flag operations (mark-as-read, star, archive) are **optimistic** — no loading spinner needed.

For operations that DO need loading UI (e.g., fetching emails, searching):
- `viewState` stays for controller-lifecycle loading: `dispatchState(Right(GetAllEmailLoading()))`
- `EmailActionQueue` actions that need loading can fire a `XLoadingState` on the bus:

```dart
class EmailActionQueue extends GetxService {
  void submit(EmailAction action, ...) {
    eventBus.fire(ActionLoadingState(action.tag));  // optional: if action has loading
    sub = action.execute(...).listen(
      (result) => result.fold(
        (failure) { eventBus.fire(failure); ... },
        (success) { eventBus.fire(success); ... },
      ),
      onDone: () => eventBus.fire(ActionDoneState(action.tag)),
    );
  }
}
```

---

## OCP Compliance Boundary

| Adding new email action | Files to edit | Files to create |
|---|---|---|
| New `EmailAction` subclass | none | `x_email_action.dart` |
| New `BusHandler` subscriber | none | `x_bus_handler.dart` |
| `EmailListStateProvider` | none (handler calls existing mutations) | — |
| Register in bindings | `mailbox_dashboard_bindings.dart` (1-line each) | — |
| Call `_actionQueue.submit(...)` in controller | the calling controller | — |

**Bindings always need 1-line edit** — this is unavoidable with GetX DI.  
**Calling controller always needs 1 new method** — the trigger point.

**True OCP unlock** (future): Route actions from UI via `AppEventBus` itself → controllers become pure subscribers, never callers. But this is a bigger change.

---

## Phases

| # | Phase | Status |
|---|-------|--------|
| 1 | Architecture understanding & `consumeState` replacement | Done |
| 2 | Split `EmailListStateProvider` into pure store + bus handlers | Done |
| 2a | Fix: BusHandler registry — eliminate silent registration failure | Done |
| 2b | Fix: Double state update — strip state mutations from `onSuccess` callbacks | Done |
| 3 | `handleSuccessViewState` cleanup (remove email action dispatching) | Todo |
| 4 | Loading state via `ActionLoadingState` on EventBus | Optional |

### Phase 2b — Double State Update Fix (Done)

**Problem:** After Phase 2, mark-as-read triggered two state updates:
1. `MarkAsReadBusHandler` → `EmailListStateProvider.updateEmailFlagByEmailIds()` (new path)
2. `onSuccess` callback → controller `_markAsReadEmailSuccess()` → same mutation (old leftover)

**Also found:** `MarkAsReadBusHandler` only handled `MarkAsMultipleEmailReadAllSuccess` but not `MarkAsMultipleEmailReadHasSomeEmailFailure` — partial success left some emails with stale flags.

**Fix:**
- `MarkAsReadBusHandler` — added `_readPartialSuccessSub` for `MarkAsMultipleEmailReadHasSomeEmailFailure`, using `s.successEmailIds`
- `MailboxDashBoardController` — renamed `_markAsReadEmailSuccess` → `_showMarkAsReadEmailToast` (UI only), renamed `_markAsReadSelectedMultipleEmailSuccess` → `_showMarkAsMultipleReadToast` (UI only). State mutation removed from both.
- `onSuccess` callbacks now call toast-only methods — zero state mutations

**Rule established:** `onSuccess` callbacks = UI reactions only (toast, navigation, undo). State mutations = BusHandler only. Enforced by naming convention (`_show*Toast`).

### Phase 2a — BusHandler Registry (Done)

**Problem:** Adding a new `BusHandler` required manually adding `Get.put(XBusHandler())` in bindings — forgetting was a silent failure (handler never subscribes, state never updates, no error).

**Fix:** Central registry at `lib/features/base/event_bus/bus_handler_registry.dart`. Bindings loop over `busHandlerFactories`. Adding a handler = one entry in the registry.

### Phase 2 — Bus Handler Pattern (Done)

**Before:** `EmailListStateProvider` subscribed to bus events directly → growing God object.

**After:** Pure state store + focused handlers:

```
lib/features/base/
├── event_bus/
│   ├── app_event_bus.dart
│   ├── bus_handler_registry.dart         ← central registry, prevents silent failure
│   ├── mark_as_read_bus_handler.dart     ← subscribes to read events (single + multiple + partial)
│   └── get_all_email_bus_handler.dart    ← subscribes to get-all-email
└── state/
    └── email_list_state_provider.dart    ← pure state store, zero bus knowledge
```

**Adding a new feature (e.g., Mark as Star):**
1. `MarkAsStarEmailAction extends EmailAction` → new file
2. `MarkAsStarBusHandler extends GetxService` → new file, calls `provider.updateEmailFlagByEmailIds(..., markStarAction:)`
3. Add to `busHandlerFactories` in registry → 1 entry (cannot be forgotten)
4. Zero edits to `EmailListStateProvider`, zero edits to existing handlers

---

## Summary Mental Model

```
New Email Action Type:
  1. Create XEmailAction extends EmailAction     → stream execution
  2. Create XBusHandler extends GetxService       → subscribes to XSuccess on bus
  3. XBusHandler calls EmailListStateProvider     → mutates shared state
  4. Register action + handler in bindings        → 1-line edit each
  5. Widget Obx watches provider                  → re-renders automatically
  6. Controller onSuccess callback (optional)     → UI-only reactions (toast, nav)

Result: handleSuccessViewState in controller = EMPTY for email actions
        viewState = only for controller-lifecycle (loading, errors on data fetching)
```
