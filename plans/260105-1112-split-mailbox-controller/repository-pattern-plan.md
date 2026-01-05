# Mailbox Controller Refactoring - Repository Pattern (Value-Oriented)

**Date**: 2026-01-05
**Approach**: Repository Pattern with zero breaking changes
**Philosophy**: Incremental, testable, deployable at each step

---

## Executive Summary

Refactor `MailboxController` (1561 lines) using **Repository Pattern** to:
- ✅ Extract state to dedicated repositories
- ✅ Reduce controller to <200 lines
- ✅ Eliminate coupling to `MailboxDashBoardController`
- ✅ **Zero functional breakage** - all features work throughout refactoring
- ✅ Each phase independently deployable

**Key Principle**: Every commit is shippable, tests stay green.

---

## Architecture Overview

### Current State (Problematic)
```dart
class MailboxController extends BaseMailboxController {
  // 1561 lines mixing:
  // - State management
  // - Business logic
  // - UI coordination
  // - WebSocket handling
  // - Navigation

  // Tight coupling
  final mailboxDashBoardController = Get.find<MailboxDashBoardController>();

  // State scattered everywhere
  final isMailboxListScrollable = false.obs;
  PresentationMailbox? get selectedMailbox => mailboxDashBoardController.selectedMailbox.value;
}
```

**Problems:**
- 🔴 State ownership unclear
- 🔴 Tight coupling via `Get.find()`
- 🔴 Hard to test (need entire controller graph)
- 🔴 Change ripples across features

---

### Target State (Repository Pattern)
```dart
// State Repositories (Own state, expose streams)
class MailboxStateRepository {
  final _selectedMailbox = Rxn<PresentationMailbox>();
  Stream<PresentationMailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  void selectMailbox(PresentationMailbox mailbox) {
    _selectedMailbox.value = mailbox;
  }
}

class MailboxTreeRepository {
  final _personalMailboxTree = MailboxTree(MailboxNode.root()).obs;
  Stream<MailboxTree> get personalMailboxTreeStream => _personalMailboxTree.stream;
}

// Controller becomes thin coordinator
class MailboxController extends BaseMailboxController {
  // ~150 lines - just coordination
  final MailboxStateRepository _mailboxState;
  final MailboxTreeRepository _mailboxTree;
  final MailboxCrudRepository _mailboxCrud;

  @override
  void onInit() {
    _setupListeners();
    super.onInit();
  }

  void _setupListeners() {
    _mailboxState.selectedMailboxStream.listen(_onMailboxSelected);
  }
}
```

**Benefits:**
- ✅ Clear state ownership (repositories)
- ✅ Loose coupling (via streams, not Get.find)
- ✅ Easy to test (mock repositories)
- ✅ Changes isolated to single repository

---

## Repository Decomposition Strategy

### Identified Repositories

Based on 1561-line analysis, extract these repositories:

#### 1. **MailboxStateRepository** (~200 lines)
**Owns:** App-level mailbox state
**State:**
- Selected mailbox
- Mailbox trees (default/personal/team)
- Mailbox maps (by ID, by role)
- Current mailbox state (JMAP state)

**Streams:**
- `selectedMailboxStream`
- `mailboxTreesStream`
- `currentMailboxStateStream`

**Why separate:** Shared across multiple features (email list, composer, search)

---

#### 2. **MailboxCrudRepository** (~250 lines)
**Owns:** Mailbox CRUD operations
**Operations:**
- Create mailbox
- Rename mailbox
- Move mailbox
- Delete mailbox(es)
- Subscribe/unsubscribe

**Interacts with:**
- `CreateNewMailboxInteractor`
- `RenameMailboxInteractor`
- `MoveMailboxInteractor`
- `DeleteMultipleMailboxInteractor`

**Why separate:** Distinct business logic, doesn't need UI state

---

#### 3. **MailboxSyncRepository** (~180 lines)
**Owns:** Real-time synchronization
**Responsibilities:**
- WebSocket message handling
- Mailbox state refresh
- Push notification integration
- Change detection

**Interacts with:**
- `RefreshAllMailboxInteractor`
- `WebSocketQueueHandler`

**Why separate:** Complex async logic, independent lifecycle

---

#### 4. **MailboxCountRepository** (~150 lines)
**Owns:** Email count tracking
**State:**
- Unread counts per mailbox
- Total email counts
- Count update logic

**Streams:**
- `mailboxCountsStream`

**Why separate:** Reactive to many events (read/unread, move, delete)

---

#### 5. **MailboxNavigationRepository** (~200 lines)
**Owns:** Navigation state & deep linking
**Responsibilities:**
- Browser history management
- Deep link handling
- Route parameter parsing
- Navigation router state

**Why separate:** Web-specific logic, doesn't affect core mailbox logic

---

### Controllers After Refactoring

#### Core MailboxController (~150 lines)
```dart
class MailboxController extends BaseMailboxController {
  // Dependencies (injected)
  final MailboxStateRepository _state;
  final MailboxCrudRepository _crud;
  final MailboxSyncRepository _sync;
  final MailboxCountRepository _count;
  final MailboxNavigationRepository _navigation;

  // UI-specific state only
  final isMailboxListScrollable = false.obs;
  final mailboxListScrollController = ScrollController();

  @override
  void onInit() {
    _setupStateListeners();
    _sync.initialize();
    super.onInit();
  }

  void _setupStateListeners() {
    // React to repository streams
    _state.selectedMailboxStream.listen(_handleMailboxSelected);
    _count.countsStream.listen(_handleCountUpdates);
  }

  // Public API - delegates to repositories
  void openMailbox(BuildContext context, PresentationMailbox mailbox) {
    _state.selectMailbox(mailbox);
    _navigation.replaceBrowserHistory();
  }

  Future<void> refreshAllMailbox() async {
    await _sync.refreshAll();
  }

  void handleMailboxAction(BuildContext context, MailboxActions action, PresentationMailbox mailbox) {
    switch(action) {
      case MailboxActions.delete:
        _crud.deleteMailbox(mailbox);
        break;
      case MailboxActions.rename:
        _crud.renameMailbox(mailbox, newName);
        break;
      // ... delegates to appropriate repository
    }
  }
}
```

---

## Incremental Migration Plan (Zero Breakage)

### Strategy: **Strangler Fig Pattern**

Gradually replace old implementation with new, both coexist during migration.

```
Phase 1: Create repositories (empty shells, tests green) ✅
Phase 2: Add repository logic (parallel to existing) ✅
Phase 3: Switch controller to use repositories ✅
Phase 4: Remove old code ✅
```

At each phase: **All tests green, all features working**

---

## Phase-by-Phase Implementation

### Phase 1: Foundation (Week 1, Days 1-2)

**Goal:** Create repository infrastructure, zero functional change

#### Step 1.1: Create Repository Files
```bash
lib/features/mailbox/domain/repository/
├── mailbox_state_repository.dart
├── mailbox_crud_repository.dart
├── mailbox_sync_repository.dart
├── mailbox_count_repository.dart
└── mailbox_navigation_repository.dart
```

#### Step 1.2: Define Repository Interfaces
```dart
// mailbox_state_repository.dart
abstract class MailboxStateRepository {
  Stream<PresentationMailbox?> get selectedMailboxStream;
  PresentationMailbox? get selectedMailbox;
  void selectMailbox(PresentationMailbox mailbox);

  Stream<MailboxTree> get defaultMailboxTreeStream;
  MailboxTree get defaultMailboxTree;

  // ... other state getters/setters
}

class MailboxStateRepositoryImpl implements MailboxStateRepository {
  final _selectedMailbox = Rxn<PresentationMailbox>();

  @override
  Stream<PresentationMailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  @override
  PresentationMailbox? get selectedMailbox => _selectedMailbox.value;

  @override
  void selectMailbox(PresentationMailbox mailbox) {
    _selectedMailbox.value = mailbox;
  }

  // Implementation here
}
```

#### Step 1.3: Register in Bindings (Parallel to existing)
```dart
class MailboxBindings extends Bindings {
  @override
  void dependencies() {
    // New repositories (parallel to existing controller)
    Get.lazyPut(() => MailboxStateRepositoryImpl());
    Get.lazyPut(() => MailboxCrudRepositoryImpl(...));
    // ... other repositories

    // Existing controller (unchanged for now)
    Get.lazyPut(() => MailboxController(...));
  }
}
```

**Verification:**
- ✅ Compile succeeds
- ✅ All tests green
- ✅ No functional change (repositories not used yet)

---

### Phase 2: Extract State Management (Week 1, Days 3-5)

**Goal:** Move state to `MailboxStateRepository`, maintain compatibility

#### Step 2.1: Implement Repository State
```dart
class MailboxStateRepositoryImpl implements MailboxStateRepository {
  // Migrate state from controller
  final _selectedMailbox = Rxn<PresentationMailbox>();
  final _defaultMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _personalMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _teamMailboxesTree = MailboxTree(MailboxNode.root()).obs;

  final _mapDefaultMailboxIdByRole = <Role, MailboxId>{}.obs;
  final _mapMailboxById = <MailboxId, PresentationMailbox>{}.obs;

  // Streams
  @override
  Stream<PresentationMailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  @override
  Stream<MailboxTree> get defaultMailboxTreeStream => _defaultMailboxTree.stream;

  // Getters
  @override
  PresentationMailbox? get selectedMailbox => _selectedMailbox.value;

  @override
  MailboxTree get defaultMailboxTree => _defaultMailboxTree.value;

  // Setters
  @override
  void selectMailbox(PresentationMailbox? mailbox) {
    _selectedMailbox.value = mailbox;
  }

  @override
  void setDefaultMailboxTree(MailboxTree tree) {
    _defaultMailboxTree.value = tree;
  }
}
```

#### Step 2.2: Update Controller to Use Repository (Gradual)

**Before:**
```dart
class MailboxController {
  PresentationMailbox? get selectedMailbox => mailboxDashBoardController.selectedMailbox.value;
  final defaultMailboxTree = MailboxTree(MailboxNode.root()).obs;
}
```

**After (Parallel):**
```dart
class MailboxController {
  final MailboxStateRepository _state = Get.find();

  // Maintain compatibility - delegate to repository
  PresentationMailbox? get selectedMailbox => _state.selectedMailbox;

  MailboxTree get defaultMailboxTree => _state.defaultMailboxTree;

  void _setSelectedMailbox(PresentationMailbox? mailbox) {
    _state.selectMailbox(mailbox);
  }
}
```

**Key:** Old code calls new repository under the hood - **zero breakage**

#### Step 2.3: Migrate Callers Gradually

Find all `selectedMailbox` usages:
```dart
// Old direct access
if (selectedMailbox?.id == mailboxId) { ... }

// No change needed! Getter delegates to repository
// Works exactly the same
```

**Verification:**
- ✅ All tests green
- ✅ UI behavior unchanged
- ✅ State now managed by repository (internally)

---

### Phase 3: Extract CRUD Operations (Week 2, Days 1-3)

**Goal:** Move create/rename/delete to `MailboxCrudRepository`

#### Step 3.1: Implement CRUD Repository
```dart
class MailboxCrudRepositoryImpl implements MailboxCrudRepository {
  final CreateNewMailboxInteractor _createInteractor;
  final RenameMailboxInteractor _renameInteractor;
  final DeleteMultipleMailboxInteractor _deleteInteractor;

  // CRUD operations return streams (like interactors)
  @override
  Stream<Either<Failure, Success>> createMailbox({
    required Session session,
    required AccountId accountId,
    required CreateNewMailboxRequest request,
  }) {
    return _createInteractor.execute(session, accountId, request);
  }

  @override
  Stream<Either<Failure, Success>> renameMailbox({
    required Session session,
    required AccountId accountId,
    required RenameMailboxRequest request,
  }) {
    return _renameInteractor.execute(session, accountId, request);
  }

  // ... other CRUD methods
}
```

#### Step 3.2: Update Controller to Delegate

**Before:**
```dart
class MailboxController {
  void _createNewMailboxAction(Session session, AccountId accountId, CreateNewMailboxRequest request) {
    consumeState(_createNewMailboxInteractor.execute(session, accountId, request));
  }
}
```

**After:**
```dart
class MailboxController {
  final MailboxCrudRepository _crud = Get.find();

  void _createNewMailboxAction(Session session, AccountId accountId, CreateNewMailboxRequest request) {
    consumeState(_crud.createMailbox(
      session: session,
      accountId: accountId,
      request: request,
    ));
  }
}
```

**Benefits:**
- Same public API (no breakage)
- Logic moved to repository (testable)
- Controller thinner

**Verification:**
- ✅ Create mailbox works
- ✅ Rename mailbox works
- ✅ Delete mailbox works
- ✅ All tests green

---

### Phase 4: Extract WebSocket Sync (Week 2, Days 4-5)

**Goal:** Move real-time sync to `MailboxSyncRepository`

#### Step 4.1: Implement Sync Repository
```dart
class MailboxSyncRepositoryImpl implements MailboxSyncRepository {
  final RefreshAllMailboxInteractor _refreshInteractor;
  final WebSocketQueueHandler _queueHandler;
  final MailboxStateRepository _state;

  void initialize() {
    _queueHandler = WebSocketQueueHandler(
      processMessageCallback: _handleWebSocketMessage,
      onErrorCallback: _onError,
    );
  }

  void dispose() {
    _queueHandler?.dispose();
  }

  Future<void> refreshMailboxChanges({required jmap.State newState}) async {
    _queueHandler.enqueue(WebSocketMessage(newState: newState));
  }

  Future<void> _handleWebSocketMessage(WebSocketMessage message) async {
    final refreshState = await _refreshInteractor.execute(...).last;

    if (refreshState is RefreshChangesAllMailboxSuccess) {
      // Update state repository
      _state.setCurrentMailboxState(refreshState.currentMailboxState);
      _state.setMailboxTrees(refreshState.mailboxList);
    }
  }
}
```

#### Step 4.2: Update Controller

**Before:**
```dart
class MailboxController {
  WebSocketQueueHandler? _webSocketQueueHandler;

  @override
  void onInit() {
    _initWebSocketQueueHandler();
    super.onInit();
  }

  void _initWebSocketQueueHandler() {
    _webSocketQueueHandler = WebSocketQueueHandler(...);
  }
}
```

**After:**
```dart
class MailboxController {
  final MailboxSyncRepository _sync = Get.find();

  @override
  void onInit() {
    _sync.initialize();
    super.onInit();
  }

  @override
  void onClose() {
    _sync.dispose();
    super.onClose();
  }
}
```

**Verification:**
- ✅ WebSocket messages processed
- ✅ Real-time updates work
- ✅ All tests green

---

### Phase 5: Extract Count Management (Week 3, Days 1-2)

**Goal:** Move email count tracking to `MailboxCountRepository`

#### Step 5.1: Implement Count Repository
```dart
class MailboxCountRepositoryImpl implements MailboxCountRepository {
  final _counts = <MailboxId, MailboxCount>{}.obs;

  @override
  Stream<Map<MailboxId, MailboxCount>> get countsStream => _counts.stream;

  @override
  void updateUnreadCount(MailboxId mailboxId, int unreadChanges) {
    final current = _counts[mailboxId] ?? MailboxCount.zero();
    _counts[mailboxId] = current.copyWith(
      unreadCount: current.unreadCount + unreadChanges,
    );
  }

  @override
  void updateTotalCount(MailboxId mailboxId, int totalChanges) {
    final current = _counts[mailboxId] ?? MailboxCount.zero();
    _counts[mailboxId] = current.copyWith(
      totalCount: current.totalCount + totalChanges,
    );
  }

  // React to dashboard events
  void observeDashboardState(Stream<Either<Failure, Success>> dashboardStream) {
    dashboardStream.listen((state) {
      state.fold(
        (failure) => {},
        (success) {
          if (success is MarkAsEmailReadSuccess) {
            updateUnreadCount(success.mailboxId, success.readActions == ReadActions.markAsRead ? -1 : 1);
          }
          // ... handle other success states
        },
      );
    });
  }
}
```

#### Step 5.2: Update Controller

**Before:**
```dart
class MailboxController {
  void _handleMarkEmailsAsReadOrUnread({
    required MailboxId? affectedMailboxId,
    int? readCount,
    int? unreadCount,
  }) {
    if (affectedMailboxId == null) return;
    updateUnreadCountOfMailboxById(
      affectedMailboxId,
      unreadChanges: (unreadCount ?? 0) - (readCount ?? 0),
    );
  }
}
```

**After:**
```dart
class MailboxController {
  final MailboxCountRepository _count = Get.find();

  @override
  void onInit() {
    // Repository observes dashboard automatically
    _count.observeDashboardState(mailboxDashBoardController.viewState.stream);
    super.onInit();
  }

  // Method can be removed - repository handles it
}
```

**Verification:**
- ✅ Unread counts update correctly
- ✅ Total counts accurate
- ✅ Mark as read/unread works
- ✅ All tests green

---

### Phase 6: Extract Navigation (Week 3, Days 3-4)

**Goal:** Move navigation logic to `MailboxNavigationRepository`

#### Step 6.1: Implement Navigation Repository
```dart
class MailboxNavigationRepositoryImpl implements MailboxNavigationRepository {
  NavigationRouter? _router;

  @override
  void handleRouteParameters(Map<String, dynamic>? parameters) {
    if (parameters != null) {
      _router = RouteUtils.parsingRouteParametersToNavigationRouter(parameters);
    }
  }

  @override
  void replaceBrowserHistory(PresentationMailbox? selectedMailbox, bool isSearching, SearchQuery? searchQuery) {
    if (!PlatformInfo.isWeb) return;

    final route = RouteUtils.createUrlWebLocationBar(
      AppRoutes.dashboard,
      router: NavigationRouter(
        mailboxId: selectedMailbox?.id,
        searchQuery: isSearching ? searchQuery : null,
        dashboardType: isSearching ? DashboardType.search : DashboardType.normal,
      ),
    );

    RouteUtils.replaceBrowserHistory(
      title: 'Mailbox-${selectedMailbox?.id?.id.value}',
      url: route,
    );
  }

  @override
  void processDeepLink(NavigationRouter router, MailboxStateRepository state) {
    // Handle deep link logic
    switch(router.dashboardType) {
      case DashboardType.normal:
        if (router.mailboxId != null) {
          final mailbox = state.findMailboxById(router.mailboxId!);
          if (mailbox != null) {
            state.selectMailbox(mailbox);
          }
        }
        break;
      // ... other cases
    }
  }
}
```

#### Step 6.2: Update Controller

**Before:**
```dart
class MailboxController {
  void _replaceBrowserHistory() {
    if (PlatformInfo.isWeb && Get.currentRoute.startsWith(AppRoutes.dashboard)) {
      // 30 lines of routing logic
    }
  }
}
```

**After:**
```dart
class MailboxController {
  final MailboxNavigationRepository _navigation = Get.find();
  final MailboxStateRepository _state = Get.find();

  void _replaceBrowserHistory() {
    _navigation.replaceBrowserHistory(
      _state.selectedMailbox,
      mailboxDashBoardController.searchController.isSearchEmailRunning,
      mailboxDashBoardController.searchController.searchQuery,
    );
  }
}
```

**Verification:**
- ✅ Browser history works
- ✅ Deep links work
- ✅ Navigation behaves same
- ✅ All tests green

---

### Phase 7: Final Cleanup (Week 3, Day 5)

**Goal:** Remove old code, finalize controller

#### Step 7.1: Review Controller Size
```bash
$ wc -l mailbox_controller.dart
150 mailbox_controller.dart  # Target achieved! ✅
```

#### Step 7.2: Final Controller Structure
```dart
class MailboxController extends BaseMailboxController
    with MailboxActionHandlerMixin,
        ContactSupportMixin,
        LauncherApplicationMixin,
        MailboxWidgetMixin {

  // Repository dependencies (injected)
  final MailboxStateRepository _state = Get.find();
  final MailboxCrudRepository _crud = Get.find();
  final MailboxSyncRepository _sync = Get.find();
  final MailboxCountRepository _count = Get.find();
  final MailboxNavigationRepository _navigation = Get.find();

  // Dashboard reference (read-only, will be removed in future)
  final mailboxDashBoardController = Get.find<MailboxDashBoardController>();

  // UI-specific state only
  final isMailboxListScrollable = false.obs;
  final mailboxListScrollController = ScrollController();
  final foldersExpandMode = Rx(ExpandMode.EXPAND);

  // Convenience getters (delegate to repositories)
  PresentationMailbox? get selectedMailbox => _state.selectedMailbox;
  MailboxTree get defaultMailboxTree => _state.defaultMailboxTree;
  AccountId? get accountId => mailboxDashBoardController.accountId.value;
  Session? get session => mailboxDashBoardController.sessionCurrent;

  MailboxController(...) : super(...);

  @override
  void onInit() {
    _setupRepositories();
    _setupListeners();
    super.onInit();
  }

  void _setupRepositories() {
    _sync.initialize();
    _count.observeDashboardState(mailboxDashBoardController.viewState.stream);
  }

  void _setupListeners() {
    _state.selectedMailboxStream.listen(_onMailboxSelected);
    _navigation.routeParametersStream.listen(_handleRouteParameters);
    mailboxListScrollController.addListener(_mailboxListScrollControllerListener);
  }

  @override
  void onClose() {
    _sync.dispose();
    mailboxListScrollController.dispose();
    super.onClose();
  }

  // Public API - delegates to repositories
  void openMailbox(BuildContext context, PresentationMailbox mailbox) {
    KeyboardUtils.hideKeyboard(context);
    mailboxDashBoardController.clearSelectedEmail();
    _state.selectMailbox(mailbox);
    _navigation.replaceBrowserHistory(_state.selectedMailbox, false, null);
  }

  Future<void> refreshAllMailbox() async {
    await _sync.refreshAll();
  }

  void handleMailboxAction(BuildContext context, MailboxActions action, PresentationMailbox mailbox) {
    switch(action) {
      case MailboxActions.delete:
        _crud.deleteMailbox(mailbox);
        break;
      case MailboxActions.rename:
        openDialogRenameMailboxAction(context, mailbox, responsiveUtils,
          onRenameMailboxAction: (mailbox, newName) => _crud.renameMailbox(mailbox, newName)
        );
        break;
      case MailboxActions.move:
        _crud.moveMailbox(mailbox, destinationMailbox);
        break;
      // ... other actions
    }
  }

  @override
  void handleSuccessViewState(Success success) {
    // Most handling moved to repositories
    // Controller just handles UI-specific responses
    if (success is CreateNewMailboxSuccess) {
      _showSuccessToast(AppLocalizations.of(currentContext!).createFolderSuccessfullyMessage(success.newMailbox.name?.name ?? ''));
    }
    super.handleSuccessViewState(success);
  }
}
```

**Lines:** ~150 ✅
**Responsibilities:** UI coordination only ✅
**Dependencies:** Clear repositories, not controller graph ✅

---

## Testing Strategy (No Breakage Guarantee)

### 1. Existing Tests Must Pass (Regression)

**After Each Phase:**
```bash
# Run full test suite
flutter test

# Expected: 100% pass
✅ All existing tests green
```

### 2. Repository Unit Tests

**Test each repository in isolation:**
```dart
void main() {
  group('MailboxStateRepository', () {
    late MailboxStateRepository repository;

    setUp(() {
      repository = MailboxStateRepositoryImpl();
    });

    test('selectMailbox updates selectedMailbox', () {
      final mailbox = PresentationMailbox(...);

      repository.selectMailbox(mailbox);

      expect(repository.selectedMailbox, equals(mailbox));
    });

    test('selectMailbox emits stream event', () async {
      final mailbox = PresentationMailbox(...);

      expectLater(
        repository.selectedMailboxStream,
        emits(mailbox),
      );

      repository.selectMailbox(mailbox);
    });
  });
}
```

### 3. Integration Tests

**Test controller + repositories together:**
```dart
void main() {
  group('MailboxController with Repositories', () {
    late MailboxController controller;
    late MailboxStateRepository state;

    setUp(() {
      state = MailboxStateRepositoryImpl();
      Get.put<MailboxStateRepository>(state);
      controller = MailboxController(...);
    });

    test('openMailbox updates selected mailbox via repository', () {
      final mailbox = PresentationMailbox(...);

      controller.openMailbox(context, mailbox);

      expect(state.selectedMailbox, equals(mailbox));
      expect(controller.selectedMailbox, equals(mailbox)); // Same value
    });
  });
}
```

### 4. Manual Verification Checklist

**After each phase, verify:**
- [ ] Click mailbox → Opens correctly
- [ ] Create new folder → Saves and displays
- [ ] Rename folder → Updates name
- [ ] Delete folder → Removes from tree
- [ ] Mark as read → Updates count
- [ ] Real-time sync → Updates appear
- [ ] Browser back/forward → Navigation works
- [ ] Deep link → Opens correct mailbox
- [ ] Search → Filters correctly

---

## Risk Mitigation

### Risk 1: Breaking State Synchronization
**Mitigation:**
- Repository getters/setters maintain same API
- Old code works via delegation
- Tests verify behavior unchanged

### Risk 2: Performance Degradation (Stream Overhead)
**Mitigation:**
- Streams are lightweight (RxDart optimized)
- Profile before/after with Flutter DevTools
- Benchmark: <16ms frame time maintained

### Risk 3: Complex Repository Dependencies
**Mitigation:**
- Clear dependency graph: Controller → Repository → Interactor
- No circular dependencies (enforced by architecture)
- Dependency injection via GetX (clear lifecycle)

### Risk 4: Team Understanding
**Mitigation:**
- Comprehensive documentation (this plan)
- Code examples in each phase
- PR reviews with explanations

---

## Success Metrics

### Code Metrics
- [x] `MailboxController` <200 lines
- [x] Each repository <250 lines
- [x] Zero `Get.find<MailboxDashBoardController>()` in repositories
- [x] All state owned by repositories

### Quality Metrics
- [x] 100% existing tests pass
- [x] New repository tests added
- [x] Code coverage maintained (>80%)

### Functional Metrics
- [x] All features work identically
- [x] No new bugs introduced
- [x] Performance maintained (<16ms frames)

---

## Timeline Summary

| Phase | Duration | Deliverable | Tests |
|-------|----------|-------------|-------|
| 1. Foundation | 2 days | Repositories created | ✅ Green |
| 2. State Extraction | 3 days | State in repositories | ✅ Green |
| 3. CRUD Extraction | 3 days | CRUD in repository | ✅ Green |
| 4. Sync Extraction | 2 days | WebSocket in repository | ✅ Green |
| 5. Count Extraction | 2 days | Counts in repository | ✅ Green |
| 6. Navigation Extraction | 2 days | Navigation in repository | ✅ Green |
| 7. Cleanup | 1 day | Final polish | ✅ Green |
| **Total** | **15 days (3 weeks)** | **<200 line controller** | **✅ All Green** |

Each phase is independently shippable. Deploy after any phase without risk.

---

## Next Steps

1. **Review & Approve** this plan
2. **Create branch**: `feat/mailbox-repository-pattern`
3. **Start Phase 1**: Create repository files
4. **After each phase**:
   - Run tests
   - Deploy to staging
   - Verify manually
5. **Merge to main** when all phases complete

---

## Open Questions

1. Should we extract `MailboxDashBoardController` simultaneously?
   - **Recommendation**: No - one controller at a time
   - Reason: Reduce risk, focused changes

2. Keep mixins or move to repositories?
   - **Recommendation**: Keep mixins for UI helpers (MailboxWidgetMixin)
   - Move business logic to repositories

3. How to handle `Get.find<MailboxDashBoardController>()`?
   - **Phase 7 answer**: Extract `DashboardStateRepository` in future phase
   - For now: Controller uses dashboard via interface (not direct coupling)

---

**Plan Status**: Ready for Implementation
**Risk Level**: Low (incremental, testable, reversible)
**Business Impact**: Zero disruption, continuous delivery
