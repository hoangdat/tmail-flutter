## MailboxDashboardController

### Cross-Controller References

All 7 non-paywall controllers are declared as **public `final` fields** at class level (lines 253–259), initialized eagerly via `Get.find<T>()` at field declaration time — they must be registered in the GetX container before this controller is created.

```dart
// Lines 253–259 — all eager Get.find at field level
final SearchController searchController = Get.find<search.SearchController>();
final DownloadController downloadController = Get.find<DownloadController>();
final AppGridDashboardController appGridDashboardController = Get.find<...>();
final SpamReportController spamReportController = Get.find<...>();
final NetworkConnectionController networkConnectionController = Get.find<...>();
final LabelController labelController = Get.find<LabelController>();
final ComposerManager composerManager = Get.find<ComposerManager>();
```

`PaywallController` is the odd one out — nullable and created imperatively during session setup:
```dart
PaywallController? paywallController; // Line 357 — nullable field
// Line 954 — constructed in _setUpComponentsFromSession()
paywallController = PaywallController(ownEmailAddress: ownEmailAddress.value);
```

### Usage Per Controller

| Controller | How used | Call sites |
|---|---|---|
| **`SearchController`** | Direct method/property calls throughout — filters, sort order, search state, quick search | ~30+ usages — most heavily used cross-controller dependency |
| **`DownloadController`** | Stream listener via `ever(downloadController.downloadUIAction)` [L837]; add/update/delete download tasks [L2165, 2172, 2178] | 4 direct calls + 1 stream listener |
| **`AppGridDashboardController`** | Called only in `_loadAppGrid()` [L3435–3437]: `loadAppDashboardConfiguration()` + `loadAppGridLinagraEcosystem()` | 2 call sites — narrowest usage |
| **`SpamReportController`** | Called in 3 places: session setup [L942], refresh [L2142], reconnect [L2224] — always `getSpamReportStateAction()`. Getter delegation [L2559, 2563, 2569] | 6 call sites |
| **`NetworkConnectionController`** | Field declared but **zero usages in main file** — exposed as public field for extensions/view | 0 direct calls in main controller |
| **`LabelController`** | Called after session setup [L959] and on refresh/reconnect [L2147, 2229]: `checkLabelSettingState()`. Getter `currentLabelList` [L3505] | 4 call sites |
| **`ComposerManager`** | **Not called in main file** — exposed as public field, accessed by view (`mailbox_dashboard_view_web.dart`) and extensions (`open_and_close_composer_extension.dart`) | 0 in main file; ~8 usages in extensions/view |
| **`PaywallController`** | Created in `_setUpComponentsFromSession()` [L954]; `onClose()` in dashboard's `onClose()` [L3486]; `navigateToPaywall()` called externally by `ComposerController` via `mailboxDashBoardController.paywallController?.navigateToPaywall()` | 2 in main file; accessed externally by Composer |

### Key Architectural Observations

1. **`SearchController` is the most entangled** — 30+ usages mean Dashboard directly manages search filter state instead of delegating. Prime extraction candidate.

2. **`NetworkConnectionController` and `ComposerManager` are pass-through fields** — Dashboard holds them purely so views and extensions can reach them via `controller.networkConnectionController` / `controller.composerManager`. Dashboard itself doesn't use them.

3. **`PaywallController` lifecycle is owned by Dashboard** — created and destroyed here, but *used* by `ComposerController` through the dashboard reference. Indirect dependency chain: `Composer → Dashboard.paywallController`.

4. **All 7 eager `Get.find()` at field declaration** — binding order matters. These controllers must all be registered before `MailboxDashboardController` is instantiated, constraining the binding setup order.

---

1. SearchController — 30+ call sites (hardest)

  Problem: Dashboard directly mutates search state — updateFilterEmail(), clearFilterSuggestion(), isSearchActive(), quickSearchEmails(), etc. This makes Dashboard responsible for search filter
  coordination logic.

  ---
  2. DownloadController — 1 stream listener + 4 task calls

  Problem: Dashboard manages download task lifecycle (addDownloadTask, updateDownloadTask, deleteDownloadTask) and reacts to download UI actions via ever().

  ---
  3. AppGridDashboardController — 2 call sites

  Problem: Dashboard calls loadAppDashboardConfiguration() and loadAppGridLinagraEcosystem() inside _loadAppGrid(), triggered after session is ready.

  ---
  4. SpamReportController — 6 call sites

  Problem: Dashboard calls getSpamReportStateAction() in 3 lifecycle hooks (session setup, refresh, reconnect) and delegates 3 getters. Same pattern as AppGrid.

  ---
  5. NetworkConnectionController — 0 direct usages

  Problem: Dashboard holds it purely as a pass-through field so views and extensions access it via controller.networkConnectionController.

  ---
  6. LabelController — 4 call sites

  Problem: Dashboard calls checkLabelSettingState(session, accountId) after session setup and on refresh/reconnect. Also delegates currentLabelList getter.

  ---
  7. ComposerManager — 0 usages in main file

  Problem: Identical to NetworkConnectionController — Dashboard holds it only so the view (mailbox_dashboard_view_web.dart) and extensions (open_and_close_composer_extension.dart) access it via controller.composerManager.

  ---
  8. PaywallController — Dashboard constructs it, Composer uses it

  Problem: Dashboard constructs PaywallController inside _setUpComponentsFromSession() and owns its onClose(). But ComposerController reaches it via
  mailboxDashBoardController.paywallController?.navigateToPaywall() — a leaky indirect reference.

---

## ComposerController

### Cross-Controller References

```dart
// L140 — eager Get.find
final mailboxDashBoardController = Get.find<MailboxDashBoardController>();
final networkConnectionController = Get.find<NetworkConnectionController>();
final _beforeReconnectManager = Get.find<BeforeReconnectManager>();

// L169 — constructor-injected
final UploadController uploadController;

// L228–229 — lazy via getBinding(tag: composerId)
RichTextWebController? richTextWebController;
RichTextMobileTabletController? richTextMobileTabletController;
```

### Usage Per Controller

| Controller | How used | Call sites |
|---|---|---|
| **`MailboxDashBoardController`** | Session/account context, max attachment size, mailbox map, paywall, drag state, close/consumeState signal | ~40+ usages — tightest coupling |
| **`NetworkConnectionController`** | Single getter delegation: `isNetworkConnectionAvailable` [L1915] | 1 call site |
| **`UploadController`** | `ever(uploadController.uploadInlineViewState)` [L442]; attachment state reads; upload/delete/validate actions | ~15 call sites + 1 stream listener |
| **`RichTextWebController`** | `insertImage`, `editorController.setFocus`, `updateFormattingOptions`, `isFormattingOptionsEnabled` — web-only | ~5 call sites |
| **`RichTextMobileTabletController`** | `insertImage`, `hideRichTextView`, `onCreateHTMLEditor`, `htmlEditorApi` — mobile-only | ~3 call sites |

**What Composer reads from Dashboard:**
- `sessionCurrent`, `accountId` — accessed in 10+ methods for every JMAP call
- `ownEmailAddress` — sender address
- `maxSizeAttachmentsPerEmail` — attachment size limit [L842]
- `mapMailboxById`, `templateMailboxId` — mailbox lookup [L1393–1395]
- `isTextFormattingMenuOpened` — formatting menu toggle [L669]
- `isPopupMenuOpened` — state check [L1874]
- `composerManager.getComposerIndex(composerId)` — composer z-index [L531]
- `paywallController?.navigateToPaywall()` — quota exceeded [L1077, 1360, 2307]
- `validatePremiumIsAvailable()` / `validateUserHasIsAlreadyHighestSubscription()` [L1053–1054, 2280–2281]

**What Composer writes to Dashboard:**
- `localFileDraggableAppState` — drag state [L457, 465, 473, 481, 2055, 2061]
- `closeComposer(...)` — result dispatch [L1480]
- `updateTextFormattingMenuState(...)` — persist formatting state [L1476]
- `consumeState(...)` — draft/send results [L1334, 1339]

### Key Architectural Observations

1. **Dashboard is used as a service locator** — Composer accesses `session`, `accountId`, `paywall`, `mailboxes`, `premium checks` all through the dashboard reference, making it impossible to test Composer in isolation.

2. **`networkConnectionController` is a trivial pass-through** — 1 getter delegation. Remove the field; call `Get.find<NetworkConnectionController>().isNetworkConnectionAvailable()` inline.

3. **`UploadController` is constructor-injected** — correctly scoped per composer instance (tagged). This is the right pattern; the others should follow it.

4. **Editor controllers are nullable** — initialized lazily via `getBinding(tag: composerId)` in `onInit`. Null checks scattered across methods. Platform branching duplicated at every call site.

### Decoupling Proposals

| Controller | Strategy | Effort | Impact |
|---|---|---|---|
| `MailboxDashBoardController` | Extract `ComposerSessionContext` interface exposing only what Composer needs | High | Breaks direct dashboard dependency |
| `NetworkConnectionController` | Inline `Get.find()` at the single call site, remove field | Trivial | Delete 1 line |
| `UploadController` | Already correct — constructor-injected per instance | None | — |
| `RichTextWebController` / `RichTextMobileTabletController` | Extract `RichTextEditorAdapter` interface; inject correct impl at construction | Medium | Eliminate 40+ platform branches |

#### `MailboxDashBoardController` — Extract `ComposerSessionContext`

Composer needs session, accountId, mailboxes, premium state. Extract a narrow interface:

```dart
abstract class ComposerSessionContext {
  Rxn<AccountId> get accountId;
  Session? get sessionCurrent;
  String get ownEmailAddress;
  int? get maxSizeAttachmentsPerEmail;
  Map<MailboxId, PresentationMailbox> get mapMailboxById;
  bool validatePremiumIsAvailable();
  void closeComposer(ComposerArguments result);
  void consumeState(Stream<Either<Failure, Success>> state);
}
// MailboxDashBoardController implements ComposerSessionContext
```

`paywallController` access moves out entirely — register `PaywallController` in bindings (see Dashboard notes).

#### `RichTextEditorAdapter` — Unify platform editors

```dart
abstract class RichTextEditorAdapter {
  void insertImage(InlineImage image);
  void setFocus();
  void updateFormattingOptions(FormattingOptions options);
  bool get isFormattingOptionsEnabled;
}
// WebRichTextEditorAdapter wraps RichTextWebController
// MobileRichTextEditorAdapter wraps RichTextMobileTabletController
```

Constructor-inject `RichTextEditorAdapter`; eliminate `if (PlatformInfo.isWeb)` at every editor call site.

---

## SingleEmailController

### Cross-Controller References

```dart
// L116 — eager Get.find
final mailboxDashBoardController = Get.find<MailboxDashBoardController>();

// L133 — lazy via getBinding (nullable)
ThreadDetailController? _threadDetailController;

// L202 in onInit — retrieved via getBinding
_threadDetailController = getBinding<ThreadDetailController>();
```

### Usage Per Controller

| Controller | How used | Call sites |
|---|---|---|
| **`MailboxDashBoardController`** | Session/account, identity list, mailbox map, action streams (ever), routing, move/trash email operations | ~74 call sites |
| **`ThreadDetailController`** (nullable) | Cache read/write, email map lookup, scroll trigger, read-status sync, thread close | ~15 call sites via `?.` |

**What SingleEmail reads from Dashboard:**
- `accountId`, `sessionCurrent`, `ownEmailAddress` — every JMAP call
- `listIdentities` — initialize selected identity [L411, 414]
- `mapMailboxById` — mailbox lookups [L560, 627, 683, 730–734]
- `emailUIAction` — `ever()` listener with 10+ action branches [L293–372]
- `viewState` — `ever()` for unsubscribe/download state [L375]
- `downloadController.downloadUIAction` — `ever()` for attachment download progress [L385]
- `searchController.isSearchEmailRunning` — move-to-trash path [L734]

**What SingleEmail writes to Dashboard:**
- `consumeState(...)` — interactor results
- `moveToMailbox(...)`, `emitMoveToTrashFailure(...)` — email move operations [L737, 751, 758, 766, 795]
- `clearEmailUIAction()` — reset after handling [L296, 299, 338, 340, 350, 361]
- `getMailboxContain(email)`, `getTrashMailboxIdAndPath(mailbox)` — mailbox resolution [L764, 773]
- `toggleLabelToEmail(...)` — label action [L355]

**Bidirectional sync with ThreadDetailController:**
- Reads: `emailIdsPresentation[emailId]` [L165], `cachedEmailLoaded[emailId]` [L488–489], `isThreadDetailEnabled` [L160, 185], `expandedEmailHtmlViewKey` [L182], `emailIdsPresentation.keys.length` [L638], `emailIdsPresentation.length` [L743]
- Writes: `currentEmailLoaded.value` [L542, 582], `cacheEmailLoaded(...)` [L620], `focusExpandedEmail(emailId)` [L645], `markCollapsedEmailReadSuccess(...)` [L704], `closeThreadDetailAction()` [L744]

### Key Architectural Observations

1. **`mailboxDashBoardController` used as a global state store** — 74 call sites. SingleEmail directly reads and writes Dashboard state instead of receiving it via constructor or a narrow interface.

2. **`ThreadDetailController` nullable coupling is fragile** — 15 calls all via `?.` with inconsistent guards. Some paths check `isThreadDetailEnabled`, others don't. Represents a hidden state sync contract between two sibling controllers.

3. **Three `ever()` listeners** in `_registerObxStreamListener()` [L293–392] subscribe to Dashboard-owned streams. When Dashboard changes these streams, all SingleEmail instances are affected simultaneously.

4. **`downloadController` accessed indirectly** via `mailboxDashBoardController.downloadController` — two-hop dependency.

### Decoupling Proposals

| Dependency | Strategy | Effort | Impact |
|---|---|---|---|
| `MailboxDashBoardController` | Extract `EmailViewContext` interface | High | Removes 74 call sites on Dashboard |
| `ThreadDetailController` (nullable) | Unify ownership of `currentEmailLoaded`; SingleEmail becomes read-only consumer | Medium | Eliminates bidirectional sync |

#### `MailboxDashBoardController` — Extract `EmailViewContext`

```dart
abstract class EmailViewContext {
  Rxn<AccountId> get accountId;
  Session? get sessionCurrent;
  String get ownEmailAddress;
  List<Identity> get listIdentities;
  Map<MailboxId, PresentationMailbox> get mapMailboxById;
  Rxn<EmailUIAction> get emailUIAction;
  void clearEmailUIAction();
  void moveToMailbox(MoveToMailboxRequest request);
  void consumeState(Stream<Either<Failure, Success>> state);
}
```

#### `ThreadDetailController` — Make SingleEmail read-only consumer

`currentEmailLoaded` should be owned by `ThreadDetailController` only. SingleEmail notifies ThreadDetail of loaded content via a callback; ThreadDetail updates its own state:

```dart
// SingleEmail calls:
onEmailLoaded(emailId, emailLoaded); // callback, not direct write

// ThreadDetailController:
void onEmailLoaded(EmailId id, EmailLoaded loaded) {
  cacheEmailLoaded(id, loaded);
  currentEmailLoaded.value = loaded;
  focusExpandedEmail(id);
}
```

---

## ThreadDetailController

### Cross-Controller References

```dart
// L121–125 — all eager Get.find
final mailboxDashBoardController = Get.find<MailboxDashBoardController>();
final searchEmailController = Get.find<SearchEmailController>();
final networkConnectionController = Get.find<NetworkConnectionController>();
final threadDetailManager = Get.find<ThreadDetailManager>();
final downloadManager = Get.find<DownloadManager>();
```

### Usage Per Controller

| Controller | How used | Call sites |
|---|---|---|
| **`MailboxDashBoardController`** | Session/account getters, selectedEmail/threadDetailUIAction/emailUIAction streams (ever), dispatch actions back | ~15 call sites + 4 `ever()` listeners |
| **`SearchEmailController`** | `searchController.isSearchEmailRunning` — via Dashboard proxy [L145–146] | 1 call site |
| **`NetworkConnectionController`** | `isNetworkConnectionAvailable()` getter [L154] | 1 call site |
| **`ThreadDetailManager`** | `isThreadDetailEnabled` flag [L156] | 1 call site |
| **`DownloadManager`** | Passed to `EmailActionReactor` at construction | 1 call site |

**What ThreadDetail reads from Dashboard:**
- `accountId`, `sessionCurrent`, `sentMailboxId`, `ownEmailAddress` — exposed as getters [L135–142]
- `selectedEmail` — `ever()` listener triggers `onSelectedEmailUpdated()` [L177]
- `threadDetailUIAction` — `ever()` dispatches thread-level actions [L183]
- `emailUIAction` — `ever()` handles refresh [L216]
- `searchController.isSearchEmailRunning` — routed through Dashboard [L145–146]

**What ThreadDetail writes to Dashboard:**
- `dispatchThreadDetailUIAction(...)` — resets action after handling [L212]
- `dispatchEmailUIAction(EmailUIAction())` — notify email closure [L218]
- `consumeState(...)` — bulk read results

### Key Architectural Observations

1. **`SearchEmailController` accessed via Dashboard proxy** — `mailboxDashBoardController.searchController` [L146]. ThreadDetail has a direct `Get.find<SearchEmailController>()` field but accesses it indirectly. Redundant field.

2. **`NetworkConnectionController` and `ThreadDetailManager`** — each used exactly once. These are injected solely for single boolean checks. Pass the value at construction or observe the relevant Rx variable instead.

3. **`DownloadManager`** — injected but only passed to `EmailActionReactor`. Never used directly. `EmailActionReactor` should receive it via its own constructor.

4. **All session/account getters delegate to Dashboard** — `accountId`, `session`, `sentMailboxId`, `ownEmailAddress` are all one-liner getters forwarding to `mailboxDashBoardController`. Same `MailboxSessionObservable` interface proposed for Dashboard would solve this.

### Decoupling Proposals

| Dependency | Strategy | Effort | Impact |
|---|---|---|---|
| `MailboxDashBoardController` | Inject `MailboxSessionObservable` + `ThreadActionBus` interfaces | Medium | Removes direct Dashboard dependency |
| `SearchEmailController` | Remove redundant proxy; inject directly if needed | Trivial | Delete the indirection |
| `NetworkConnectionController` | Pass `isConnected` as `Rx<bool>` at construction | Trivial | Remove field |
| `ThreadDetailManager` | Pass `isEnabled` as `bool` at construction time | Trivial | Remove field |
| `DownloadManager` | Inject directly into `EmailActionReactor` | Trivial | Remove field |

#### `MailboxDashBoardController` — Inject `MailboxSessionObservable` + `ThreadActionBus`

```dart
abstract class MailboxSessionObservable {
  Rxn<AccountId> get accountId;
  Session? get sessionCurrent;
  MailboxId? get sentMailboxId;
  String get ownEmailAddress;
  Rxn<PresentationEmail> get selectedEmail;
}

abstract class ThreadActionBus {
  Rxn<ThreadDetailUIAction> get threadDetailUIAction;
  Rxn<EmailUIAction> get emailUIAction;
  void dispatchThreadDetailUIAction(ThreadDetailUIAction action);
  void dispatchEmailUIAction(EmailUIAction action);
}
// MailboxDashBoardController implements both interfaces
```

---

## ThreadController

### Cross-Controller References

```dart
// L85 — eager Get.find (only explicit injection)
final networkConnectionController = Get.find<NetworkConnectionController>();

// mailboxDashBoardController comes from BaseController or EmailActionController mixin
// accessed as: mailboxDashBoardController.*
// searchController accessed via: mailboxDashBoardController.searchController
```

### Usage Per Controller

| Controller | How used | Call sites |
|---|---|---|
| **`MailboxDashBoardController`** | Email list state, mailbox selection, select mode, filter, sort order, action streams (5 `ever()` listeners), routing | **~126 call sites** — highest coupling in the codebase |
| **`SearchController`** (via Dashboard) | `searchController.searchState` (ever), `searchEmailFilter`, `searchQuery` | ~5 call sites via `mailboxDashBoardController.searchController` |
| **`NetworkConnectionController`** | Single getter: `isNetworkConnectionAvailable()` | 1 call site |

**What ThreadController reads from Dashboard:**
- `accountId`, `sessionCurrent` — every JMAP call [L115–117]
- `selectedMailbox` — `ever()` triggers email list load [L119, 269]
- `emailsInCurrentMailbox` — primary email list state; read + modified [L893, 938, 954, 987, 1000, 1029…]
- `mapMailboxById` — mailbox lookups [L971, 1150, 1181, 1188, 1258, 1304]
- `filterMessageOption` — email filter state [L897, 912, 1086, 1090]
- `currentSelectMode`, `listEmailSelected` — multi-select state [L1047–1082]
- `trashSpamMailboxIds` — trash/spam detection [L1150, 1237]
- `currentEmailState`, `currentSortOrder` — JMAP sync state + sort [L809, 1593, 1611]
- `isFirstSessionLoad` — first-load flag [L277, 280]
- `dashBoardAction` — `ever()` with 10+ action branches [L293–354]
- `emailUIAction` — `ever()` for unread/move handling [L355–363]
- `viewState` — `ever()` for move/flag results [L364–391]
- `emailsInCurrentMailbox` — `ever()` for email count tracking [L413]

**What ThreadController writes to Dashboard:**
- `emailsInCurrentMailbox.clear()` / `.addAll()` — direct list mutation [L207, 345, 954, 1128, 1263]
- `updateEmailList(newList)` [L1015, 1037, 1062, 1080, 1193]
- `updateRefreshAllEmailState(...)` [L204, 219, 1177]
- `updateEmailFlagByEmailIds(...)` [L370]
- `handleMoveEmailsToMailbox(...)` [L375, 381, 387]
- `currentSelectMode.value` [L1048, 1052, 1063, 1081]
- `listEmailSelected.value` / `.clear()` [L1054, 1064, 1082, 1195]
- `filterMessageOption.value` [L1090]
- `clearDashBoardAction()` [L296–354, 1602, 1618]
- `clearEmailUIAction()` [L360]
- `openComposer(...)` [L1328]
- `dispatchRoute(DashboardRoutes.searchEmail)` [L1409]
- `openMailboxMenuDrawer()` [L1402]
- `setSelectedMailbox(mailbox)` [L1491]
- `onDragMailbox(isDrag)` [L1544]
- `setIsFirstSessionLoad(false)` [L280]

### Key Architectural Observations

1. **126 call sites — worst coupling in the codebase.** `ThreadController` directly mutates Dashboard-owned state (`emailsInCurrentMailbox`, `currentSelectMode`, `listEmailSelected`, `filterMessageOption`). This means Dashboard state can be changed by ThreadController at any time with no encapsulation.

2. **`emailsInCurrentMailbox` is shared mutable state** — Dashboard owns it, ThreadController reads and writes it freely. This is the core source of the coupling. Any future controller that displays emails must also reach into Dashboard to get and mutate this list.

3. **`SearchController` accessed via Dashboard proxy** — `mailboxDashBoardController.searchController`. ThreadController already calls `Get.find<NetworkConnectionController>()` directly; there's no reason it can't call `Get.find<SearchController>()` directly too.

4. **5 `ever()` listeners on Dashboard streams** — `selectedMailbox`, `dashBoardAction` (10+ branches), `emailUIAction`, `viewState`, `emailsInCurrentMailbox`. ThreadController reacts to almost every significant Dashboard event.

### Decoupling Proposals

| Dependency | Strategy | Effort | Impact |
|---|---|---|---|
| `MailboxDashBoardController` — email list | Introduce `EmailListStore` owned by ThreadController; Dashboard observes it | High | Eliminates 100+ direct state mutations |
| `MailboxDashBoardController` — actions | Replace 5 `ever()` listeners with `ThreadActionBus` interface | Medium | Narrows Dashboard surface |
| `SearchController` (via Dashboard) | Inject `SearchController` directly via `Get.find` | Trivial | Removes proxy indirection |
| `NetworkConnectionController` | Pass `Rx<bool>` at construction | Trivial | Remove field |

#### Core proposal: Invert email list ownership

The fundamental problem is that Dashboard owns `emailsInCurrentMailbox` but ThreadController is its primary writer. Flip the ownership:

```dart
// ThreadController owns the list
class ThreadController {
  final emailsInCurrentMailbox = <PresentationEmail>[].obs;

  // Notify Dashboard when list changes (one-way)
  void _onEmailListChanged(List<PresentationEmail> emails) {
    _emailListBus.dispatch(EmailListUpdatedEvent(emails));
  }
}

// Dashboard observes via bus — no direct reference to ThreadController
ever(_emailListBus.emailListUpdated, (event) {
  // update its own derived state
});
```

This eliminates the need for Dashboard to hold `emailsInCurrentMailbox` as a mutable field that any controller can freely mutate.

#### Replace 5 `ever()` listeners with `ThreadActionBus`

Same `ThreadActionBus` interface proposed for `ThreadDetailController` applies here. ThreadController subscribes to typed events rather than raw Dashboard observables.

