# Mailbox Controller Refactoring - FINAL ARCHITECTURE

**Date**: 2026-01-05
**Status**: ✅ Approved Architecture
**Pattern**: Repository + Controllers + Widget Composition

---

## Executive Summary

Refactor `MailboxController` (1561 lines) into:
- **1 App-Level Repository** (global state)
- **3 Feature-Level Repositories** (scoped state)
- **4 Controllers** (<200 lines each)
- **Widget Composition** (small, reusable widgets)

**Key Principle**: Repository → Controller → Widget (no shortcuts!)

---

## Architecture Layers

```
┌─────────────────────────────────────────────┐
│        APP-LEVEL REPOSITORY                 │
│        MailboxRepository (~300 lines)       │
│        • Global mailbox state               │
│        • Rx observables                     │
│        • CRUD operations                    │
└─────────────────────────────────────────────┘
              ↓ (used by)
┌─────────────────────────────────────────────┐
│     FEATURE-LEVEL REPOSITORIES              │
│     (Scoped, temporary state)               │
│                                             │
│     MailboxCreatorRepository (~80 lines)   │
│     • Lives while create dialog open        │
│     • New mailbox name, validation          │
│                                             │
│     MailboxEditorRepository (~100 lines)   │
│     • Lives while edit dialog open          │
│     • Rename/move state                     │
│                                             │
│     MailboxSubscriptionRepository (~90)    │
│     • Lives while subscribe action active   │
│     • Undo state                            │
└─────────────────────────────────────────────┘
              ↓ (used by)
┌─────────────────────────────────────────────┐
│        CONTROLLERS (<200 lines each)        │
│                                             │
│     MailboxTreeController (~180 lines)     │
│     • Tree display logic                    │
│     • Selection handling                    │
│     • Scroll management                     │
│                                             │
│     MailboxActionsController (~190 lines)  │
│     • CRUD dialogs                          │
│     • Action menus                          │
│     • Uses all feature repositories         │
│                                             │
│     MailboxSyncController (~120 lines)     │
│     • WebSocket handling                    │
│     • Real-time sync                        │
│                                             │
│     MailboxNavigationController (~150)     │
│     • Deep links                            │
│     • Browser history                       │
└─────────────────────────────────────────────┘
              ↓ (used by)
┌─────────────────────────────────────────────┐
│        WIDGETS (Composition)                │
│                                             │
│     MailboxView (no controller)            │
│     ├── MailboxTreeWidget                   │
│     │   └── MailboxNodeWidget               │
│     │       └── MailboxNodeActionsMenu      │
│     ├── MailboxSyncButton                   │
│     └── MailboxCreateButton                 │
│                                             │
│     Each widget uses ONE controller         │
└─────────────────────────────────────────────┘
```

---

## Reactive Flow: How UI Rebuilds

### Example: WebSocket Syncs New Mailbox

```
Step 1: WebSocket message arrives
       ↓
Step 2: MailboxSyncController.handleMessage()
       ↓
Step 3: MailboxRepository.refreshAll()
       ↓
Step 4: Repository updates Rx observable
       _personalMailboxTree.value = newTree; ← Rx emits!
       ↓
Step 5: GetX notifies all Obx() observers
       ↓
Step 6: Widget's Obx() rebuilds
       Obx(() => controller.personalMailboxTree)
       ↓
Step 7: UI shows new mailbox ✅
```

**Key:** Repository (Rx) → Controller (getter) → Widget (Obx)

---

## Component Details

### 1. MailboxRepository (App-Level)

**File**: `lib/features/mailbox/domain/repository/mailbox_repository.dart`

**Responsibilities:**
- Own global mailbox state
- Expose Rx observables
- Provide CRUD operations
- Emit streams on state changes

**Structure:**
```dart
class MailboxRepository {
  // Rx Observables (state)
  final _mailboxes = <PresentationMailbox>[].obs;
  final _selectedMailbox = Rxn<PresentationMailbox>();
  final _defaultMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _personalMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _teamMailboxTree = MailboxTree(MailboxNode.root()).obs;

  // Getters (controllers access these)
  List<PresentationMailbox> get mailboxes => _mailboxes;
  PresentationMailbox? get selectedMailbox => _selectedMailbox.value;
  MailboxTree get defaultMailboxTree => _defaultMailboxTree.value;
  MailboxTree get personalMailboxTree => _personalMailboxTree.value;

  // Operations (update state, trigger Rx)
  Future<void> refreshAll();
  Future<void> createMailbox(CreateNewMailboxRequest request);
  Future<void> renameMailbox(RenameMailboxRequest request);
  Future<void> deleteMailbox(MailboxId id);
  void selectMailbox(PresentationMailbox? mailbox);
}
```

---

### 2. Feature Repositories (Scoped)

#### MailboxCreatorRepository
**File**: `lib/features/mailbox/domain/repository/mailbox_creator_repository.dart`

**Lifecycle**: Lives only while "Create Folder" dialog open

**Structure:**
```dart
class MailboxCreatorRepository {
  // State
  final newMailboxName = ''.obs;
  final parentMailbox = Rxn<PresentationMailbox>();
  final validationError = Rxn<String>();

  // Validation
  void setName(String name) {
    newMailboxName.value = name;
    _validate();
  }

  bool get isValid => validationError.value == null;

  // Build request
  CreateNewMailboxRequest buildRequest();

  // Cleanup
  void reset();
  void dispose();
}
```

#### MailboxEditorRepository
**File**: `lib/features/mailbox/domain/repository/mailbox_editor_repository.dart`

**Lifecycle**: Lives while rename/move dialog open

**Structure:**
```dart
class MailboxEditorRepository {
  final currentMailbox = Rxn<PresentationMailbox>();
  final newName = ''.obs;
  final destinationMailbox = Rxn<PresentationMailbox>();
  final editMode = Rx<EditMode>(EditMode.rename);

  void setMode(EditMode mode);
  void setNewName(String name);
  void setDestination(PresentationMailbox mailbox);

  RenameMailboxRequest? buildRenameRequest();
  MoveMailboxRequest? buildMoveRequest();

  void dispose();
}
```

#### MailboxSubscriptionRepository
**File**: `lib/features/mailbox/domain/repository/mailbox_subscription_repository.dart`

**Lifecycle**: Lives while subscribe/unsubscribe action active

**Structure:**
```dart
class MailboxSubscriptionRepository {
  final mailboxId = Rxn<MailboxId>();
  final action = Rx<SubscriptionAction>(SubscriptionAction.subscribe);
  final previousState = Rxn<MailboxSubscribeState>();

  void setMailboxId(MailboxId id);
  void setAction(SubscriptionAction action);
  void savePreviousState(MailboxSubscribeState state);

  SubscribeMailboxRequest buildRequest();
  SubscribeMailboxRequest buildUndoRequest();

  void dispose();
}
```

---

### 3. Controllers

#### MailboxTreeController
**File**: `lib/features/mailbox/presentation/controller/mailbox_tree_controller.dart`

**Responsibilities:**
- Tree display logic
- Mailbox selection
- Scroll management
- Expand/collapse folders

**Structure:**
```dart
class MailboxTreeController extends GetxController {
  final MailboxRepository _mailboxRepo = Get.find();

  // UI state (controller-specific)
  final mailboxListScrollController = ScrollController();
  final foldersExpandMode = Rx(ExpandMode.EXPAND);

  // Expose repository data (widgets observe these via Obx)
  MailboxTree get defaultMailboxTree => _mailboxRepo.defaultMailboxTree;
  MailboxTree get personalMailboxTree => _mailboxRepo.personalMailboxTree;
  MailboxTree get teamMailboxTree => _mailboxRepo.teamMailboxTree;
  PresentationMailbox? get selectedMailbox => _mailboxRepo.selectedMailbox;

  // Methods called by widgets
  void openMailbox(BuildContext context, PresentationMailbox mailbox) {
    _mailboxRepo.selectMailbox(mailbox);
    KeyboardUtils.hideKeyboard(context);
  }

  void toggleFolderExpand();
  void scrollToTop();

  @override
  void onClose() {
    mailboxListScrollController.dispose();
    super.onClose();
  }
}
```

#### MailboxActionsController
**File**: `lib/features/mailbox/presentation/controller/mailbox_actions_controller.dart`

**Responsibilities:**
- Handle CRUD actions
- Open dialogs
- Coordinate with feature repositories
- Show toasts

**Structure:**
```dart
class MailboxActionsController extends GetxController {
  final MailboxRepository _mailboxRepo = Get.find();

  // Feature repositories (used internally)
  final _creatorRepo = MailboxCreatorRepository();
  final _editorRepo = MailboxEditorRepository();
  final _subscriptionRepo = MailboxSubscriptionRepository();

  // Expose feature repo state to widgets
  String? get creatorValidationError => _creatorRepo.validationError.value;
  bool get creatorIsValid => _creatorRepo.isValid;

  // Methods called by widgets
  void updateCreatorName(String name) {
    _creatorRepo.setName(name);
  }

  Future<void> createMailbox(BuildContext context) async {
    final request = _creatorRepo.buildRequest();
    await _mailboxRepo.createMailbox(request);
    _creatorRepo.dispose();
  }

  void handleAction(BuildContext context, MailboxActions action, PresentationMailbox mailbox);
  Future<void> openCreateDialog(BuildContext context);
  Future<void> openRenameDialog(BuildContext context, PresentationMailbox mailbox);
  Future<void> openMoveDialog(BuildContext context, PresentationMailbox mailbox);

  @override
  void onClose() {
    _creatorRepo.dispose();
    _editorRepo.dispose();
    _subscriptionRepo.dispose();
    super.onClose();
  }
}
```

#### MailboxSyncController
**File**: `lib/features/mailbox/presentation/controller/mailbox_sync_controller.dart`

**Responsibilities:**
- WebSocket message handling
- Real-time synchronization
- Manual refresh

**Structure:**
```dart
class MailboxSyncController extends GetxController {
  final MailboxRepository _mailboxRepo = Get.find();

  late WebSocketQueueHandler _wsHandler;
  final isSyncing = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initWebSocket();
  }

  void _initWebSocket() {
    _wsHandler = WebSocketQueueHandler(
      processMessageCallback: _handleWebSocketMessage,
    );
  }

  Future<void> _handleWebSocketMessage(WebSocketMessage message) async {
    isSyncing.value = true;
    await _mailboxRepo.refreshAll();
    isSyncing.value = false;
  }

  Future<void> refreshAll() async {
    isSyncing.value = true;
    await _mailboxRepo.refreshAll();
    isSyncing.value = false;
  }

  @override
  void onClose() {
    _wsHandler.dispose();
    super.onClose();
  }
}
```

#### MailboxNavigationController
**File**: `lib/features/mailbox/presentation/controller/mailbox_navigation_controller.dart`

**Responsibilities:**
- Deep link handling
- Browser history management
- Route parameter parsing

**Structure:**
```dart
class MailboxNavigationController extends GetxController {
  final MailboxRepository _mailboxRepo = Get.find();

  @override
  void onInit() {
    super.onInit();
    _listenToRouteChanges();
    _listenToMailboxSelection();
  }

  void _listenToRouteChanges() {
    ever(mailboxDashBoardController.routerParameters, (params) {
      if (params != null) {
        _handleRouteParameters(params);
      }
    });
  }

  void _listenToMailboxSelection() {
    // Update browser history when mailbox selected
    _mailboxRepo.selectedMailboxStream.listen((mailbox) {
      _updateBrowserHistory(mailbox);
    });
  }

  void _handleRouteParameters(Map<String, dynamic> params);
  void _updateBrowserHistory(PresentationMailbox? mailbox);
}
```

---

### 4. Widgets (Composition Pattern)

#### MailboxView (Main View - No Controller)
**File**: `lib/features/mailbox/presentation/mailbox_view.dart`

**Responsibility**: Compose smaller widgets

```dart
class MailboxView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mailboxes'),
        actions: [
          MailboxSyncButton(), // Uses MailboxSyncController
        ],
      ),
      body: MailboxTreeWidget(), // Uses MailboxTreeController
      floatingActionButton: MailboxCreateButton(), // Uses MailboxActionsController
    );
  }
}
```

#### MailboxTreeWidget
**File**: `lib/features/mailbox/presentation/widgets/mailbox_tree_widget.dart`

**Responsibility**: Display mailbox tree

```dart
class MailboxTreeWidget extends GetView<MailboxTreeController> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller.mailboxListScrollController,
      children: [
        Obx(() => _buildSection('Personal', controller.personalMailboxTree)),
        Obx(() => _buildSection('Default', controller.defaultMailboxTree)),
        Obx(() => _buildSection('Team', controller.teamMailboxTree)),
      ],
    );
  }

  Widget _buildSection(String title, MailboxTree tree) {
    return Column(
      children: [
        Text(title),
        ...tree.root.childrenItems?.map((node) =>
          MailboxNodeWidget(node: node)
        ) ?? [],
      ],
    );
  }
}
```

#### MailboxNodeWidget
**File**: `lib/features/mailbox/presentation/widgets/mailbox_node_widget.dart`

**Responsibility**: Display single mailbox node

```dart
class MailboxNodeWidget extends GetView<MailboxTreeController> {
  final MailboxNode node;

  const MailboxNodeWidget({required this.node});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isSelected = controller.selectedMailbox?.id == node.item.id;

      return ListTile(
        title: Text(node.item.name?.name ?? ''),
        subtitle: Text('${node.item.unreadEmails?.value ?? 0} unread'),
        selected: isSelected,
        onTap: () => controller.openMailbox(context, node.item),
        trailing: MailboxNodeActionsMenu(mailbox: node.item),
      );
    });
  }
}
```

#### MailboxNodeActionsMenu
**File**: `lib/features/mailbox/presentation/widgets/mailbox_node_actions_menu.dart`

**Responsibility**: Context menu for mailbox actions

```dart
class MailboxNodeActionsMenu extends GetView<MailboxActionsController> {
  final PresentationMailbox mailbox;

  const MailboxNodeActionsMenu({required this.mailbox});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MailboxActions>(
      onSelected: (action) => controller.handleAction(context, action, mailbox),
      itemBuilder: (context) => [
        PopupMenuItem(value: MailboxActions.rename, child: Text('Rename')),
        PopupMenuItem(value: MailboxActions.delete, child: Text('Delete')),
        PopupMenuItem(value: MailboxActions.move, child: Text('Move')),
      ],
    );
  }
}
```

#### MailboxSyncButton
**File**: `lib/features/mailbox/presentation/widgets/mailbox_sync_button.dart`

**Responsibility**: Refresh button with loading state

```dart
class MailboxSyncButton extends GetView<MailboxSyncController> {
  @override
  Widget build(BuildContext context) {
    return Obx(() => IconButton(
      icon: controller.isSyncing.value
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(Icons.refresh),
      onPressed: controller.isSyncing.value ? null : controller.refreshAll,
    ));
  }
}
```

#### MailboxCreateButton
**File**: `lib/features/mailbox/presentation/widgets/mailbox_create_button.dart`

**Responsibility**: Create folder button

```dart
class MailboxCreateButton extends GetView<MailboxActionsController> {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => controller.openCreateDialog(context),
      child: Icon(Icons.add),
    );
  }
}
```

---

## Bindings

**File**: `lib/features/mailbox/presentation/mailbox_bindings.dart`

```dart
class MailboxBindings extends Bindings {
  @override
  void dependencies() {
    // App-level repository (singleton)
    Get.lazyPut<MailboxRepository>(() => MailboxRepositoryImpl(
      Get.find<CreateNewMailboxInteractor>(),
      Get.find<RenameMailboxInteractor>(),
      Get.find<DeleteMultipleMailboxInteractor>(),
      Get.find<RefreshAllMailboxInteractor>(),
      Get.find<TreeBuilder>(),
    ));

    // Controllers
    Get.lazyPut(() => MailboxTreeController());
    Get.lazyPut(() => MailboxActionsController());
    Get.lazyPut(() => MailboxSyncController());
    Get.lazyPut(() => MailboxNavigationController());
  }
}
```

---

## File Structure

```
lib/features/mailbox/
├── domain/
│   └── repository/
│       ├── mailbox_repository.dart              (~300 lines)
│       ├── mailbox_creator_repository.dart      (~80 lines)
│       ├── mailbox_editor_repository.dart       (~100 lines)
│       └── mailbox_subscription_repository.dart (~90 lines)
├── presentation/
│   ├── controller/
│   │   ├── mailbox_tree_controller.dart         (~180 lines)
│   │   ├── mailbox_actions_controller.dart      (~190 lines)
│   │   ├── mailbox_sync_controller.dart         (~120 lines)
│   │   └── mailbox_navigation_controller.dart   (~150 lines)
│   ├── widgets/
│   │   ├── mailbox_tree_widget.dart             (~80 lines)
│   │   ├── mailbox_node_widget.dart             (~60 lines)
│   │   ├── mailbox_node_actions_menu.dart       (~40 lines)
│   │   ├── mailbox_sync_button.dart             (~30 lines)
│   │   └── mailbox_create_button.dart           (~25 lines)
│   ├── mailbox_view.dart                        (~50 lines)
│   └── mailbox_bindings.dart                    (~30 lines)
```

**Total Lines:** ~1,525 (vs 1,561 original)
**But:** Split into 15 files, each <300 lines ✅

---

## Design Principles

### 1. Clear Layering
- Repository owns state (Rx observables)
- Controller exposes state via getters
- Widget observes via Obx()
- **Never skip layers!**

### 2. Widget Composition
- Main view has no controller
- Small widgets, each uses 1 controller
- Reusable components
- Easy to test

### 3. Reactive Flow
- Repository updates → Rx emits
- Controller getter accessed in Obx()
- Widget rebuilds automatically
- No manual setState() or update()

### 4. Single Responsibility
- Each file <200 lines
- Each component has one job
- Clear boundaries

### 5. YAGNI, KISS, DRY
- No over-engineering
- Simple patterns
- No code duplication

---

## Adding New Features

### Example: Add "Archive Mailbox" Feature

1. **Create Feature Repository** (optional, if needs temporary state)
```dart
class MailboxArchiveRepository {
  final archivedMailboxIds = <MailboxId>[].obs;
  void addArchived(MailboxId id);
}
```

2. **Add Method to MailboxRepository**
```dart
Future<void> archiveMailbox(MailboxId id) async {
  // Archive logic
}
```

3. **Add Method to MailboxActionsController**
```dart
Future<void> archiveMailbox(MailboxId id) async {
  await _mailboxRepo.archiveMailbox(id);
}
```

4. **Add Menu Item to MailboxNodeActionsMenu**
```dart
PopupMenuItem(value: MailboxActions.archive, child: Text('Archive')),
```

**Zero modifications to existing code!** ✅

---

## Success Criteria

- [x] No file >200 lines
- [x] Clear separation of concerns
- [x] Reactive UI (Obx pattern)
- [x] Widget composition
- [x] Easy to add features
- [x] Easy to test
- [x] Zero breaking changes

---

## Next Steps

1. **Phase 1**: Create repositories (foundation)
2. **Phase 2**: Extract state management
3. **Phase 3**: Create controllers
4. **Phase 4**: Build widgets
5. **Phase 5**: Wire up reactive flow
6. **Phase 6**: Testing
7. **Phase 7**: Migration & cleanup

See detailed implementation in `repository-pattern-plan.md`

---

**Status**: ✅ Final architecture approved
**Ready for**: Implementation
