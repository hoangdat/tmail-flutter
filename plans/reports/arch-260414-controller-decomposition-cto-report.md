# Architecture Refactoring Report: Controller Decomposition via EventBus + BusHandler Pattern

**Date:** 2026-04-14  
**Branch:** `architecture`  
**Author:** Engineering Team  
**Audience:** CTO / Technical Leadership

---

## Executive Summary

TMail's two core controllers — `MailboxDashBoardController` (3,508 lines) and `ThreadController` (1,723 lines) — have grown into God Objects that violate the Open/Closed Principle: every new email feature requires editing these files directly. This report describes the planned decomposition, its measurable improvements, trade-offs, and realistic migration path.

---

## The Problem Today

### God Controller Metrics

| File | Lines | Role |
|---|---|---|
| `MailboxDashBoardController` | 3,508 | App shell — owns session, mailbox, email list, compose, settings, search |
| `ThreadController` | 1,723 | Email list — owns fetch, pagination, search, all email actions |
| **Total** | **5,231** | Two files doing the job of ~15 focused classes |

### Root Cause: `consumeState` as a Design Pattern

Every email action is wired through `consumeState`:

```dart
// ThreadController — 17 such blocks
consumeState(_markAsEmailReadInteractor.execute(...), onSuccess: (s) {
  if (s is MarkAsEmailReadSuccess) { ... }
});
```

`consumeState` fused three responsibilities into one call:
1. Execute the interactor stream
2. Route success types to state mutations
3. Trigger UI reactions (toast, navigation)

**Consequence:** Adding any new email action (move, snooze, schedule) requires:
- Adding an `_interactor` field to the controller
- Adding a `consumeState` block in the controller
- Adding a branch to `handleSuccessViewState()`
- Injecting the interactor via constructor/bindings

Every developer touches the same 3,500-line file. Every PR is a merge conflict waiting to happen.

### The `handleSuccessViewState` Cascade

```dart
// BEFORE — grows by one branch per feature
void handleSuccessViewState(Success success) {
  if (success is MarkAsEmailReadSuccess) { ... }
  else if (success is MarkAsStarEmailSuccess) { ... }
  else if (success is ArchiveEmailSuccess) { ... }
  else if (success is MoveEmailSuccess) { ... }
  // ... 30+ more branches
}
```

This is a classic OCP violation — the class is never closed for modification.

---

## The Proposed Architecture

### Three-Layer Decomposition

```
UI Widget
  │  (Obx watches)
  ▼
StateProvider          ← pure observable data store, zero business logic
  ▲
  │  (mutates via method calls)
BusHandler             ← one GetxService per event type, subscribes to bus
  ▲
  │  (fires typed event)
AppEventBus            ← lightweight broadcast stream, app lifecycle scope
  ▲
  │  (fires result)
EmailActionQueue       ← executes any EmailAction, one at a time
  ▲
  │  (submits)
Controller             ← UI trigger only: calls submit(), handles onSuccess UI reactions
```

### Two Channels Replace `consumeState`

**Channel 1 — AppEventBus → BusHandler → StateProvider (domain state)**

Handles shared, cross-cutting state that multiple screens care about.

```
submit(MarkAsReadEmailAction)
  → action.execute() → Stream
    → eventBus.fire(MarkAsEmailReadSuccess)    ← always fires regardless of which screen triggered it
        ↓
    MarkAsReadBusHandler.on<MarkAsEmailReadSuccess>()
        ↓
    EmailListStateProvider.updateEmailFlagByEmailIds(...)
        ↓
    Obx(EmailTile)  ← re-renders automatically
```

**Channel 2 — `onSuccess` callback (UI reactions)**

Handles screen-specific, ephemeral reactions: toasts, snackbars, navigation.

```dart
_actionQueue.submit(
  MarkAsReadEmailAction(...),
  onSuccess: (s) {
    if (s is MarkAsEmailReadSuccess) _showToast('Marked as read');
  },
);
```

### OCP Compliance: Adding a New Email Action

| Step | File | Touch type |
|---|---|---|
| Define action | `x_email_action.dart` | **new file** |
| Define handler | `x_bus_handler.dart` | **new file** |
| Register in bindings | `mailbox_dashboard_bindings.dart` | 1-line `Get.put(...)` |
| Add submit call in controller | calling controller | 1 new method |
| `EmailListStateProvider` | — | **zero edits** |
| Existing handlers | — | **zero edits** |

Zero edits to the God Controller for domain state. The controller only adds a trigger method.

---

## Current Progress (Branch: `architecture`)

### Completed (Phase 1 & 2)

| Component | Status |
|---|---|
| `AppEventBus` — broadcast event bus with `logDebug` tracing | Done |
| `EmailActionQueue` — executes `EmailAction`, fires results to bus | Done |
| `EmailAction` / `CancellationToken` abstractions | Done |
| `MarkAsReadEmailAction`, `MarkAsReadMultipleEmailAction` | Done |
| `EmailListStateProvider` — refactored to pure state store | Done |
| `MarkAsReadBusHandler` — focused handler for read events | Done |
| `GetAllEmailBusHandler` — focused handler for email list fetch | Done |
| `MailboxDashBoardController` — mark-as-read now via `submit()` | Done |

### Remaining (Phase 3)

- Remove `handleSuccessViewState` email action branches from `ThreadController` and `MailboxDashBoardController` — these are now dead code since BusHandlers own state mutations
- Migrate remaining `consumeState` blocks in `ThreadController` (17 remaining) to the two-channel pattern
- Evaluate and delete `EmailFlagService` (likely superseded)

---

## Pros

### 1. True Open/Closed Compliance
New email features do not require editing existing handlers or the state provider. Feature isolation is structural, not just a convention.

### 2. Elimination of God Controller Growth
`MailboxDashBoardController` stops accumulating responsibilities. Each action, handler, and state fragment lives in its own focused file.

### 3. Zero Merge Conflicts on Feature Branches
When two engineers add two different email actions in parallel, they touch zero shared files (only their own new `XEmailAction` and `XBusHandler` files, plus the bindings registration).

### 4. Cross-Screen State Consistency
`AppEventBus` fires events at app lifecycle scope. Any screen can react to any event without the event having to pass through a parent controller or shared method. Mark-as-read from the email detail view automatically reflects in the thread list.

### 5. Testability
- `EmailActionQueue`: unit-testable with a fake bus
- `BusHandler`: unit-testable in isolation (subscribe, fire event, assert provider mutation)
- `StateProvider`: pure data class, trivially testable
- Controllers: reducible to thin trigger wrappers

### 6. Observability
`AppEventBus.fire()` logs every event by type (`logDebug` with web console flag). The entire flow — action execute → bus fire → handler receive → provider update → widget rebuild — is traceable at runtime without a debugger.

### 7. Incremental Migration
The bus architecture coexists with `consumeState`. Old paths continue to work. New features use the new pattern immediately. Migration is feature-by-feature, not a big bang.

---

## Cons and Risks

### 1. Indirection Overhead
The data flow is: controller → queue → action → bus → handler → provider → widget. Five hops vs. the original two (`consumeState` → widget). Debugging a regression now requires understanding which layer misbehaved.

**Mitigation:** `logDebug` at each hop. The flow is deterministic and typed.

### 2. File Proliferation
Each email action eventually has: `XEmailAction`, `XBusHandler`, possibly `XStateProvider` mutation method. For 30 email action types, this is ~60 new files. This is intentional (SOLID) but requires good directory conventions.

**Mitigation:** Consistent naming (`x_email_action.dart`, `x_bus_handler.dart`) and directory grouping (`event_bus/`, `action/`). File names are self-documenting.

### 3. Handler Registration Discipline
Every new `BusHandler` must be registered in bindings. Forgetting it is a silent failure — the handler never subscribes, the state never updates, no compile error.

**Mitigation:** Code review convention — PR checklist item: "Is the handler registered in bindings?". Future: a registration test that asserts all BusHandler subclasses appear in bindings.

### 4. Event Order / Race Conditions
If two actions fire events in rapid succession (e.g., mark-as-read + move to trash), handlers process them on the bus stream in order. But if provider mutations are async, order may not be guaranteed.

**Mitigation:** `EmailListStateProvider` mutations are synchronous Rx operations (no `await`). Dart's single-threaded event loop preserves ordering for synchronous stream listeners.

### 5. Migration Cost (Phase 3)
`ThreadController` has 17 `consumeState` blocks, `MailboxDashBoardController` has 90 `if/else if (success is ...)` branches to evaluate. Full migration is non-trivial — estimate 3–5 engineering days for systematic cleanup.

**Mitigation:** Prioritize high-traffic actions (mark-as-read, move, delete) and migrate the rest feature-by-feature as each is touched.

### 6. GetX Dependency Remains
The pattern is built on GetX DI (`Get.find<>`, `Get.put<>`, `GetxService`). If the team later migrates to Riverpod or another DI system, the handler registrations and `Get.find<>` calls throughout handlers would need replacement.

**Note:** This is a known trade-off. The bus + handler pattern is DI-agnostic in concept — the GetX bindings are the only coupling point. A future migration would swap `Get.find/put` for `ref.read/watch` in handlers and bindings, leaving the action/bus/provider logic intact.

---

## Consequences

### Short-Term (Phase 3 migration)
- Controllers slim down as `handleSuccessViewState` branches are removed
- Some temporary duplication during migration (both old consumeState path and new bus path active)
- Developers must learn the two-channel mental model (bus for state, callback for UI)

### Medium-Term (6 months)
- All new features added without editing God Controllers
- `MailboxDashBoardController` and `ThreadController` approach reasonable size (~1,000 lines each) as responsibilities migrate out
- Test coverage improves because units are smaller and isolated

### Long-Term (12+ months)
- Controllers become thin coordinators — they receive UI events, submit to the queue, handle `onSuccess` UI reactions. Business logic lives in `EmailAction`, domain knowledge lives in `StateProvider`, wiring lives in `BusHandler`.
- Onboarding: new engineer adds a feature by following the 4-step pattern without reading 3,500 lines of controller
- The architecture supports future: adding push notifications that trigger the same bus events as user actions, with zero controller changes

---

## Recommendation

**Proceed with the refactoring.** The current God Controller state is a compounding liability — every feature adds cost. The bus/handler/action pattern has been validated with two working features (get-all-email, mark-as-read) on the `architecture` branch.

**Suggested sequencing:**
1. **Complete Phase 3** — `handleSuccessViewState` cleanup (highest leverage, makes controllers obviously smaller)
2. **Migrate next 3–5 high-frequency actions** — move, delete, mark-as-star (proves the pattern at scale)
3. **Establish PR checklist** — handler registration, file naming, logDebug at hop points
4. **Migrate remaining actions** — feature-by-feature as each area is touched

The refactoring does not require a feature freeze. Old and new patterns coexist during migration.

---

## Appendix: File Structure (Target State)

```
lib/features/
├── base/
│   ├── event_bus/
│   │   ├── app_event_bus.dart             ← broadcast bus
│   │   ├── get_all_email_bus_handler.dart ← handles email list fetch results
│   │   ├── mark_as_read_bus_handler.dart  ← handles read flag updates
│   │   ├── mark_as_star_bus_handler.dart  ← (next: star flag updates)
│   │   └── move_email_bus_handler.dart    ← (next: move results)
│   └── state/
│       ├── email_list_state_provider.dart ← pure observable email list store
│       ├── mailbox_state_provider.dart    ← pure observable mailbox store
│       └── session_state_provider.dart   ← pure observable session store
│
└── email/presentation/action/
    ├── email_action.dart                  ← abstract base
    ├── email_action_queue.dart            ← executor service
    ├── cancellation_token.dart            ← controller-scoped cancel
    ├── mark_as_read_email_action.dart
    ├── mark_as_read_multiple_email_action.dart
    └── (one file per action type)
```

**Current:** 3,508 + 1,723 = 5,231 lines across 2 files  
**Target:** ~1,000 lines in each controller + ~60 focused files of 50–150 lines each  
**Net result:** Same functionality, 10× more modular, O(1) edit cost per new feature instead of O(n)
