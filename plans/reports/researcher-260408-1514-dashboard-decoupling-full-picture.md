# Full Picture: Decoupling MailboxDashBoardController & Email Actions

**Date:** 2026-04-08 | **Branch:** architecture | **Status:** Analysis Complete

---

## 1. The God Object: MailboxDashBoardController

**3,506 lines** + **32 extension files** = ~5,000+ lines of effective responsibility.

### What It Owns Today

| Category | Count | Examples |
|----------|-------|---------|
| Constructor-injected interactors | 28 | MarkAsEmailRead, MoveToMailbox, SendEmail, EmptyTrash, RestoreDeleted, ... |
| Get.find() runtime deps | 14+ | SearchController, DownloadController, ComposerManager, ... |
| Lazy interactors | 10 | Vacation, AutoComplete, ServerSettings, AIScribe, ... |
| Rxn action streams (hidden bus) | 4 | `dashBoardAction`, `mailboxUIAction`, `emailUIAction`, `threadDetailUIAction` |
| Reactive state fields | 20+ | selectedMailbox, accountId, filterMessageOption, vacationResponse, ... |
| Extension files | 32 | move_emails, delete_emails, handle_keyboard, composer, ai_needs, ... |
| handleSuccessViewState types | 30+ | Giant if/else routing all interactor results |

### Controllers That Depend On It (17 files)

| Controller | Coupling Type | `_registerObxStreamListener` |
|------------|--------------|------------------------------|
| **ThreadController** | Get.find + 6 stream listeners | Yes — `dashBoardAction` (16 types), `emailUIAction` (2), `selectedMailbox`, `searchState`, `viewState`, `emailsInCurrentMailbox` |
| **MailboxController** | Get.find + 3 stream listeners | Yes — `accountId`, `mailboxUIAction` (7 types), `viewState`, `routerParameters` |
| **SingleEmailController** | Get.find + 3 stream listeners | Yes — `emailUIAction` (11 types), `viewState`, `downloadUIAction` |
| **SearchMailboxController** | Get.find + 2 stream listeners | Yes — `mailboxUIAction` (1 type), `viewState` |
| **IdentitiesController** | Get.find + 1 stream listener | Yes — `accountId` |
| **ManageAccountMenuController** | Get.find + 2 stream listeners | Yes — `accountId`, `octetsQuota` |
| **EmailActionController** (mixin) | Get.find | No |
| **ComposerController** | Get.find | No |
| **SpamReportController** | Get.find | No |
| **AdvancedFilterController** | Get.find | No |
| **QuotasController** | Get.find | No |
| **SendingQueueController** | Get.find | No |
| **ThreadDetailController** | Get.find | No (indirect via SingleEmailController) |
| **UploadController** | Get.find | No |
| **ThreadDetailManager** | Get.find | No |
| **SearchInputFormWidget** | Get.find (in widget!) | No |

---

## 2. The Hidden Event Bus: 4 Rxn Streams

### dashBoardAction (Rxn\<UIAction\>)

**Publisher:** Dashboard extensions via `dispatchDashBoardAction()`
**Listeners:** ThreadController (16 action types)

| Action Type | Listener | Handler |
|-------------|----------|---------|
| SelectionAllEmailAction | Thread | `setSelectAllEmailAction()` |
| CancelSelectionAllEmailAction | Thread | `cancelSelectAllEmail()` |
| FilterMessageAction | Thread | `filterMessagesAction()` |
| HandleEmailActionTypeAction | Thread | `pressEmailSelectionAction()` |
| OpenEmailDetailedFromSuggestionQuickSearch | Thread | navigate to email |
| StartSearchEmailAction | Thread | `_searchEmail()` |
| ClearAdvancedSearchFilterEmailAction | Thread | reset advanced filter |
| EmptyTrashAction | Thread | `_emptyTrashAction()` |
| OpenEmailInsideMailboxFromLocationBar | Thread | open email from URL |
| OpenEmailWithoutMailboxFromLocationBar | Thread | open email from URL |
| OpenEmailSearchedFromLocationBar | Thread | open searched email |
| SearchEmailFromLocationBar | Thread | search from URL bar |
| SelectDateRangeToAdvancedSearch | Thread | select date range filter |
| ClearDateRangeToAdvancedSearch | Thread | clear date range filter |
| ReclaimMailListKeyboardShortcutFocusAction | Thread | reclaim keyboard focus |
| ClearMailListKeyboardShortcutFocusAction | Thread | clear keyboard focus |

**Race condition:** ThreadController calls `clearDashBoardAction()` after handling — if any other listener exists, it misses the event.

### mailboxUIAction (Rxn\<MailboxUIAction\>)

**Publisher:** Dashboard extensions via `dispatchMailboxUIAction()`
**Listeners:** MailboxController (7 types), SearchMailboxController (1 type)

| Action Type | Listener | Handler |
|-------------|----------|---------|
| SelectMailboxDefaultAction | Mailbox | select default mailbox |
| RefreshChangeMailboxAction | Mailbox, SearchMailbox | refresh mailbox changes |
| OpenMailboxAction | Mailbox | open specific mailbox |
| SystemBackToInboxAction | Mailbox | navigate back to inbox |
| RefreshAllMailboxAction | Mailbox | refresh all mailboxes |
| AutoCreateActionRequiredFolderMailbox | Mailbox | auto-create folder |
| AutoRemoveActionRequiredFolderMailbox | Mailbox | auto-remove folder |

**Race condition:** Both MailboxController and SearchMailboxController listen — first to `clearMailboxUIAction()` blocks the other.

### emailUIAction (Rxn\<EmailUIAction\>)

**Publisher:** Dashboard extensions via `dispatchEmailUIAction()`
**Listeners:** SingleEmailController (11 types), ThreadController (2 types)

| Action Type | Listener | Handler |
|-------------|----------|---------|
| RefreshChangeEmailAction | Thread | refresh email changes |
| RefreshAllEmailAction | Thread | refresh all emails |
| HideEmailContentViewAction | SingleEmail | hide content |
| ShowEmailContentViewAction | SingleEmail | show content |
| PerformEmailActionInThreadDetail | SingleEmail | perform action |
| DisposePreviousExpandedEmail | SingleEmail | dispose previous |
| CloseEmailInThreadDetail | SingleEmail | close email |
| UnsubscribeFromThread | SingleEmail | unsubscribe |
| CollapseEmailInThreadDetail | SingleEmail | collapse email |
| OpenAttachmentList | SingleEmail | open attachments |
| TriggerMailViewKeyboardShortcut | SingleEmail | keyboard shortcut |
| RemoveLabelFromEmail | SingleEmail | remove label |
| SyncUpdateLabelForEmailOnMemory | SingleEmail | sync label update |

**Race condition:** Both SingleEmailController and ThreadController listen — same clear problem.

### threadDetailUIAction (Rxn\<ThreadDetailUIAction\>)

**Publisher/Listener:** Dashboard ↔ ThreadDetail communication (minor usage)

---

## 3. What We've Already Decoupled (PoC: markAsRead)

### Created Components

| Component | File | Purpose |
|-----------|------|---------|
| SessionStateProvider | `lib/features/base/state/session_state_provider.dart` | Holds session + accountId |
| EmailListStateProvider | `lib/features/base/state/email_list_state_provider.dart` | Holds email lists + flag updates |
| EmailFlagService | `lib/features/email/presentation/service/email_flag_service.dart` | Thin wrapper around read interactors |
| EmailServiceRegistry | `lib/features/email/presentation/service/email_service_registry.dart` | GetxService hosting EmailFlagService |
| consumeState() evolution | `lib/features/base/base_controller.dart` | Optional onSuccess/onFailure callbacks |

### Migrated Actions

| Action | In Mixin | Controllers Using It |
|--------|----------|---------------------|
| markAsEmailRead | EmailActionController | ThreadController, SearchEmailController |
| markAsReadSelectedMultipleEmail | EmailActionController | ThreadController, SearchEmailController |

### Remaining in Mixin (Still Delegates to Dashboard)

| Method | Lines | Still Coupled Via |
|--------|-------|-------------------|
| editDraftEmail | 55-61 | `dashboard.openComposer()` |
| editAsNewEmail | 63-73 | `dashboard.openComposer()` |
| previewEmail | 75-78 | `dashboard.openEmailDetailedView()` |
| moveToTrash | 80-136 | `dashboard.emitMoveToTrashFailure()`, `dashboard.getTrashMailboxIdAndPath()` |
| moveToSpam | 152-169 | `dashboard.sessionCurrent`, `dashboard.spamMailboxId`, `dashboard.moveToMailbox()` |
| unSpam | 171-189 | `dashboard.getMailboxIdByRole()`, `dashboard.moveToMailbox()` |
| moveToMailbox | 205-235 | `dashboard.sessionCurrent`, `dashboard.moveToMailbox()` |
| deleteEmailPermanently | 292-318 | `dashboard.deleteEmailPermanently()` |
| markAsStarEmail | 348-349 | `dashboard.markAsStarEmail()` |
| markAsStarSelectedMultiple | 383-385 | `dashboard.markAsStarSelectedMultipleEmail()` |
| moveEmailsToMailbox | 387-395 | `dashboard.moveEmailsToMailbox()` |
| moveEmailsToTrash | 397-403 | `dashboard.moveEmailsToFolder()` |
| moveEmailsToArchive | 404-409 | `dashboard.moveEmailsToFolder()` |
| moveEmailsToSpam | 411-416 | `dashboard.moveEmailsToFolder()` |
| unSpamSelectedMultiple | 418-420 | `dashboard.unSpamSelectedMultipleEmail()` |
| deleteSelectionPermanently | 422-437 | `dashboard.deleteSelectionEmailsPermanently()` |
| archiveMessage | 443-445 | `dashboard.archiveMessage()` |
| hasArchiveMailbox | 447-449 | `dashboard.getMailboxIdByRole()` |

**17 of 19 methods in EmailActionController still fully delegate to dashboard.**

---

## 4. Dependency Graph: What Blocks What

```
                    ┌─────────────────────────────────────────────┐
                    │        MailboxDashBoardController            │
                    │           (3,506 lines + 32 ext)            │
                    │                                              │
                    │  ┌─── State ────────────────────────────┐   │
                    │  │ selectedMailbox, accountId, session   │   │
                    │  │ emailsInCurrentMailbox (→ provider)   │   │
                    │  │ mapMailboxById, mapDefaultMailboxByRole│  │
                    │  │ filterMessageOption, vacationResponse │   │
                    │  │ listIdentities, dashboardRoute       │   │
                    │  │ octetsQuota, listSendingEmails       │   │
                    │  └──────────────────────────────────────┘   │
                    │                                              │
                    │  ┌─── Hidden Bus ───────────────────────┐   │
                    │  │ dashBoardAction    (16 action types)  │   │
                    │  │ mailboxUIAction    (7 action types)   │   │
                    │  │ emailUIAction      (13 action types)  │   │
                    │  │ threadDetailUIAction                   │   │
                    │  └──────────────────────────────────────┘   │
                    │                                              │
                    │  ┌─── Business Logic ────────────────────┐  │
                    │  │ 28 constructor interactors             │  │
                    │  │ 10 lazy interactors                    │  │
                    │  │ 30+ handleSuccessViewState types       │  │
                    │  └──────────────────────────────────────┘   │
                    └──────────┬────────┬────────┬────────────────┘
                               │        │        │
                 ┌─────────────┤        │        ├─────────────┐
                 │             │        │        │             │
          ┌──────┴──────┐ ┌───┴───┐ ┌──┴───┐ ┌─┴──────┐ ┌───┴────┐
          │  Thread     │ │Mailbox│ │Single│ │Search  │ │Composer│
          │  Controller │ │Ctrl   │ │Email │ │Mailbox │ │Ctrl    │
          │  (6 streams)│ │(4 str)│ │(3 str│ │(2 str) │ │        │
          └─────────────┘ └───────┘ └──────┘ └────────┘ └────────┘
                 │
          ┌──────┴──────┐
          │EmailAction  │
          │Mixin (17/19 │
          │still coupled│
          └─────────────┘
```

### Decoupling Order (By Impact)

| Priority | What to Decouple | Impact | Blocked By |
|----------|-----------------|--------|------------|
| **P0** | AppEventBus | Unblocks all _registerObxStreamListener migrations | Nothing |
| **P0** | MailboxStateProvider | Holds selectedMailbox, mapMailboxById — used by 5+ controllers | Nothing |
| **P1** | EmailFlagService (star) | Completes flag domain in service | P0 (event bus for notifications) |
| **P1** | EmailMoveService | Decouples 8 methods in mixin from dashboard | MailboxStateProvider (needs mailbox lookups) |
| **P1** | EmailDeleteService | Decouples 2 methods in mixin from dashboard | Nothing |
| **P2** | ThreadController._registerObxStreamListener | Largest listener (16 action types) | AppEventBus |
| **P2** | MailboxController._registerObxStreamListener | 7 mailbox action types | AppEventBus, MailboxStateProvider |
| **P2** | SingleEmailController._registerObxStreamListener | 11 email UI action types | AppEventBus |
| **P3** | ComposerServiceRegistry | Decouples composer methods from dashboard | SessionStateProvider (done) |
| **P3** | Navigation/routing decouple | Dashboard owns dashboardRoute, email detail open | AppEventBus |
| **P4** | Shrink dashboard to ~300 lines | Final goal — thin navigation shell only | All above |

---

## 5. Target State: What Each Layer Owns

### State Providers (Persistent Shared Data — Obx reads)

| Provider | Fields | Currently Lives In |
|----------|--------|--------------------|
| **SessionStateProvider** | session, accountId, ownEmailAddress | **Done** |
| **EmailListStateProvider** | emailsInCurrentMailbox, listResultSearch, isInSearchMode | **Done** |
| **MailboxStateProvider** | selectedMailbox, mapMailboxById, mapDefaultMailboxIdByRole | Dashboard (to extract) |
| **EmailSelectionStateProvider** | listEmailSelected, selectMode, currentSelectMode | Dashboard (to extract) |
| **NavigationStateProvider** | dashboardRoute, routerParameters, isEmailOpened | Dashboard (to extract) |

### Service Registries (Domain Logic — controllers call)

| Registry | Services | Interactors to Move |
|----------|----------|-------------------|
| **EmailServiceRegistry** | flag (done), move (new), delete (new), restore (new), unsubscribe (new) | 12 interactors from dashboard |
| **ComposerServiceRegistry** | draft, send | 5 interactors from dashboard |
| **MailboxServiceRegistry** | markAsRead, clear, empty | 4 interactors from dashboard |
| **DownloadServiceRegistry** | attachment | Already partially separate |
| **IdentityServiceRegistry** | getAll, create | 1 interactor from dashboard |

### App Event Bus (Transient Commands — controllers react)

| Current Rxn Stream | Events to Extract | Listener Count |
|-------------------|-------------------|----------------|
| `dashBoardAction` | 16 typed events | ThreadController only |
| `mailboxUIAction` | 7 typed events | MailboxController + SearchMailboxController |
| `emailUIAction` | 13 typed events | SingleEmailController + ThreadController |
| `threadDetailUIAction` | Minor usage | ThreadDetailController |
| `viewState` listening | NOT events — these are state reactions. Move to State Providers | Multiple controllers |

### Domain Mixins (Shared Action Logic — DRY)

| Mixin | Methods | Status |
|-------|---------|--------|
| **EmailFlagActionMixin** | markAsRead, markAsReadMultiple, markAsStar, markAsStarMultiple | Partial (read done, star pending) |
| **EmailMoveActionMixin** | moveToTrash, moveToSpam, unSpam, moveToMailbox, moveMultiple, archive | Not started |
| **EmailDeleteActionMixin** | deletePermanently, deleteMultiple, emptyTrash, emptySpam | Not started |
| **EmailComposeActionMixin** | editDraft, editAsNew, openComposer | Not started |

---

## 6. viewState Listening Problem (Special Case)

Multiple controllers listen to `dashboard.viewState` to react to operation results:

```dart
// MailboxController watches dashboard.viewState for:
// MarkAsMailboxRead, MoveToMailbox, Delete, etc. → updates unread counts

// ThreadController watches dashboard.viewState for:
// MarkAsMailboxRead, MoveToMailbox, Delete → updates email list
```

**This is different from the Rxn action streams.** `viewState` is the result of `consumeState()` — it's the interactor output.

**Solution:** When actions move to services, the callback handles the result directly. Cross-feature effects (e.g., "mark read → update mailbox unread count") go through Event Bus:

```
Service completes → callback in caller controller → publish event → other controllers react
```

This eliminates `viewState` listening entirely for migrated actions.

---

## 7. Migration Phases (Revised)

```
Phase 1: consumeState() with optional callbacks             ✅ DONE
Phase 2: SessionStateProvider + EmailListStateProvider       ✅ DONE  
Phase 3: EmailFlagService + markAsRead in mixin             ✅ DONE
Phase 4: AppEventBus (typed pub/sub GetxService)            ← NEXT
Phase 5: MailboxStateProvider (extract selectedMailbox, maps)
Phase 6: EmailMoveService + EmailDeleteService
Phase 7: Split mixin into domain mixins
Phase 8: Migrate _registerObxStreamListener (per controller)
Phase 9: Migrate remaining services (Composer, Mailbox)
Phase 10: Shrink dashboard to navigation shell (~300 lines)
Phase 11: Clean up BaseController
```

**Each phase is independently shippable.** No big-bang migration.

---

## 8. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Breaking existing behavior during migration | High | Keep dashboard forwarding during transition — both paths work simultaneously |
| Race conditions in event bus (replacing Rxn clear pattern) | Medium | Event bus uses broadcast stream — all listeners receive, no clear needed |
| Mixin becoming new God Object | Medium | Split at ~200 LOC threshold, track in this doc |
| GetX DI ordering issues | Medium | Boot → Login → Route lifecycle tiers (documented in plan) |
| Performance regression from multiple stream subscriptions | Low | Broadcast streams are lightweight; current Rxn listeners are already O(n) |

---

## 9. Metrics to Track

| Metric | Current | After Full Migration |
|--------|---------|---------------------|
| Dashboard LOC | 3,506 | ~300 (navigation shell) |
| Dashboard interactors | 38 | 0 (all in service registries) |
| Controllers with Get.find\<Dashboard\> | 17 | 0 |
| handleSuccessViewState types | 30+ | 0 (per-action callbacks) |
| _registerObxStreamListener methods | 7 | 0 (event bus subscriptions) |
| Rxn action streams | 4 | 0 (replaced by typed events) |

---

## Unresolved Questions

1. **viewState cross-listening**: When MailboxController listens to `dashboard.viewState` for `MoveToMailboxSuccess` to update unread counts — should this become an Event Bus event, or should the move service directly update MailboxStateProvider?
2. **Extension files**: 32 extension files on dashboard — should they migrate to services, or stay as helper functions on a thin dashboard?
3. **ComposerController coupling**: Composer has deep dashboard dependency (draft save, identity, send) — needs separate analysis.
4. **Navigation ownership**: Dashboard owns `dashboardRoute`, `openEmailDetailedView()`, `goToComposer()` — who owns navigation in target state?
5. **SearchController**: Tightly integrated with dashboard — separate analysis needed for search flow.
