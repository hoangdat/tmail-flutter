# Phase 1: Foundation - Repository Infrastructure

**Duration**: 2 days
**Goal**: Create repository files and interfaces with zero functional change

---

## Objectives

- Create repository files structure
- Define repository interfaces
- Register in dependency injection
- Verify compilation and tests

**Success Criteria**: All tests green, no behavioral change

---

## Step 1.1: Create Repository Files

```bash
mkdir -p lib/features/mailbox/domain/repository

# Create files
touch lib/features/mailbox/domain/repository/mailbox_state_repository.dart
touch lib/features/mailbox/domain/repository/mailbox_crud_repository.dart
touch lib/features/mailbox/domain/repository/mailbox_sync_repository.dart
touch lib/features/mailbox/domain/repository/mailbox_count_repository.dart
touch lib/features/mailbox/domain/repository/mailbox_navigation_repository.dart
```

**File Structure:**
```
lib/features/mailbox/domain/repository/
├── mailbox_state_repository.dart
├── mailbox_crud_repository.dart
├── mailbox_sync_repository.dart
├── mailbox_count_repository.dart
└── mailbox_navigation_repository.dart
```

---

## Step 1.2: Define Repository Interfaces

### mailbox_state_repository.dart

```dart
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/core/state.dart' as jmap;
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_node.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree.dart';

abstract class MailboxStateRepository {
  // Selected mailbox
  Stream<PresentationMailbox?> get selectedMailboxStream;
  PresentationMailbox? get selectedMailbox;
  void selectMailbox(PresentationMailbox? mailbox);

  // Mailbox trees
  Stream<MailboxTree> get defaultMailboxTreeStream;
  Stream<MailboxTree> get personalMailboxTreeStream;
  Stream<MailboxTree> get teamMailboxesTreeStream;

  MailboxTree get defaultMailboxTree;
  MailboxTree get personalMailboxTree;
  MailboxTree get teamMailboxesTree;

  void setDefaultMailboxTree(MailboxTree tree);
  void setPersonalMailboxTree(MailboxTree tree);
  void setTeamMailboxesTree(MailboxTree tree);

  // Mailbox maps
  Map<Role, MailboxId> get mapDefaultMailboxIdByRole;
  Map<MailboxId, PresentationMailbox> get mapMailboxById;

  void setMapDefaultMailboxIdByRole(Map<Role, MailboxId> map);
  void setMapMailboxById(Map<MailboxId, PresentationMailbox> map);

  // Current state
  jmap.State? get currentMailboxState;
  void setCurrentMailboxState(jmap.State? state);

  // All mailboxes
  List<PresentationMailbox> get allMailboxes;
  void setAllMailboxes(List<PresentationMailbox> mailboxes);

  // Outbox
  PresentationMailbox? get outboxMailbox;
  void setOutboxMailbox(PresentationMailbox? mailbox);

  // Helpers
  PresentationMailbox? findMailboxById(MailboxId id);
  MailboxNode? findMailboxNodeById(MailboxId id);
}

class MailboxStateRepositoryImpl implements MailboxStateRepository {
  // State variables
  final _selectedMailbox = Rxn<PresentationMailbox>();
  final _defaultMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _personalMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final _teamMailboxesTree = MailboxTree(MailboxNode.root()).obs;

  final _mapDefaultMailboxIdByRole = <Role, MailboxId>{}.obs;
  final _mapMailboxById = <MailboxId, PresentationMailbox>{}.obs;

  jmap.State? _currentMailboxState;
  final _allMailboxes = <PresentationMailbox>[].obs;
  PresentationMailbox? _outboxMailbox;

  // Streams
  @override
  Stream<PresentationMailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  @override
  Stream<MailboxTree> get defaultMailboxTreeStream => _defaultMailboxTree.stream;

  @override
  Stream<MailboxTree> get personalMailboxTreeStream => _personalMailboxTree.stream;

  @override
  Stream<MailboxTree> get teamMailboxesTreeStream => _teamMailboxesTree.stream;

  // Getters
  @override
  PresentationMailbox? get selectedMailbox => _selectedMailbox.value;

  @override
  MailboxTree get defaultMailboxTree => _defaultMailboxTree.value;

  @override
  MailboxTree get personalMailboxTree => _personalMailboxTree.value;

  @override
  MailboxTree get teamMailboxesTree => _teamMailboxesTree.value;

  @override
  Map<Role, MailboxId> get mapDefaultMailboxIdByRole => _mapDefaultMailboxIdByRole;

  @override
  Map<MailboxId, PresentationMailbox> get mapMailboxById => _mapMailboxById;

  @override
  jmap.State? get currentMailboxState => _currentMailboxState;

  @override
  List<PresentationMailbox> get allMailboxes => _allMailboxes;

  @override
  PresentationMailbox? get outboxMailbox => _outboxMailbox;

  // Setters
  @override
  void selectMailbox(PresentationMailbox? mailbox) {
    _selectedMailbox.value = mailbox;
  }

  @override
  void setDefaultMailboxTree(MailboxTree tree) {
    _defaultMailboxTree.value = tree;
  }

  @override
  void setPersonalMailboxTree(MailboxTree tree) {
    _personalMailboxTree.value = tree;
  }

  @override
  void setTeamMailboxesTree(MailboxTree tree) {
    _teamMailboxesTree.value = tree;
  }

  @override
  void setMapDefaultMailboxIdByRole(Map<Role, MailboxId> map) {
    _mapDefaultMailboxIdByRole.assignAll(map);
  }

  @override
  void setMapMailboxById(Map<MailboxId, PresentationMailbox> map) {
    _mapMailboxById.assignAll(map);
  }

  @override
  void setCurrentMailboxState(jmap.State? state) {
    _currentMailboxState = state;
  }

  @override
  void setAllMailboxes(List<PresentationMailbox> mailboxes) {
    _allMailboxes.assignAll(mailboxes);
  }

  @override
  void setOutboxMailbox(PresentationMailbox? mailbox) {
    _outboxMailbox = mailbox;
  }

  // Helpers
  @override
  PresentationMailbox? findMailboxById(MailboxId id) {
    return _mapMailboxById[id];
  }

  @override
  MailboxNode? findMailboxNodeById(MailboxId id) {
    // Search in all trees
    var node = _defaultMailboxTree.value.findNode((node) => node.item.id == id);
    if (node != null) return node;

    node = _personalMailboxTree.value.findNode((node) => node.item.id == id);
    if (node != null) return node;

    node = _teamMailboxesTree.value.findNode((node) => node.item.id == id);
    return node;
  }
}
```

### Other Repository Interfaces (Simplified)

Create similar interface + implementation pattern for:

**mailbox_crud_repository.dart**:
```dart
abstract class MailboxCrudRepository {
  Stream<Either<Failure, Success>> createMailbox({
    required Session session,
    required AccountId accountId,
    required CreateNewMailboxRequest request,
  });

  Stream<Either<Failure, Success>> renameMailbox({
    required Session session,
    required AccountId accountId,
    required RenameMailboxRequest request,
  });

  Stream<Either<Failure, Success>> deleteMailbox({
    required Session session,
    required AccountId accountId,
    required Map<MailboxId, List<MailboxId>> mapDescendantIds,
    required List<MailboxId> mailboxIds,
  });

  Stream<Either<Failure, Success>> moveMailbox({
    required Session session,
    required AccountId accountId,
    required MoveMailboxRequest request,
  });

  Stream<Either<Failure, Success>> subscribeMailbox({
    required Session session,
    required AccountId accountId,
    required SubscribeMailboxRequest request,
  });
}

class MailboxCrudRepositoryImpl implements MailboxCrudRepository {
  final CreateNewMailboxInteractor _createInteractor;
  final RenameMailboxInteractor _renameInteractor;
  final DeleteMultipleMailboxInteractor _deleteInteractor;
  final MoveMailboxInteractor _moveInteractor;
  final SubscribeMailboxInteractor _subscribeInteractor;

  MailboxCrudRepositoryImpl(
    this._createInteractor,
    this._renameInteractor,
    this._deleteInteractor,
    this._moveInteractor,
    this._subscribeInteractor,
  );

  @override
  Stream<Either<Failure, Success>> createMailbox({
    required Session session,
    required AccountId accountId,
    required CreateNewMailboxRequest request,
  }) {
    return _createInteractor.execute(session, accountId, request);
  }

  // ... implement other methods
}
```

---

## Step 1.3: Register in Bindings

**File**: `lib/features/mailbox/presentation/mailbox_bindings.dart`

```dart
class MailboxBindings extends Bindings {
  @override
  void dependencies() {
    // NEW: Register repositories (parallel to existing controller)
    Get.lazyPut<MailboxStateRepository>(() => MailboxStateRepositoryImpl());

    Get.lazyPut<MailboxCrudRepository>(() => MailboxCrudRepositoryImpl(
      Get.find<CreateNewMailboxInteractor>(),
      Get.find<RenameMailboxInteractor>(),
      Get.find<DeleteMultipleMailboxInteractor>(),
      Get.find<MoveMailboxInteractor>(),
      Get.find<SubscribeMailboxInteractor>(),
    ));

    Get.lazyPut<MailboxSyncRepository>(() => MailboxSyncRepositoryImpl(
      Get.find<RefreshAllMailboxInteractor>(),
    ));

    Get.lazyPut<MailboxCountRepository>(() => MailboxCountRepositoryImpl());

    Get.lazyPut<MailboxNavigationRepository>(() => MailboxNavigationRepositoryImpl());

    // EXISTING: Keep all existing bindings unchanged
    Get.lazyPut(() => MailboxController(
      Get.find<CreateNewMailboxInteractor>(),
      Get.find<DeleteMultipleMailboxInteractor>(),
      Get.find<RenameMailboxInteractor>(),
      Get.find<MoveMailboxInteractor>(),
      Get.find<SubscribeMailboxInteractor>(),
      Get.find<SubscribeMultipleMailboxInteractor>(),
      Get.find<SubaddressingInteractor>(),
      Get.find<CreateDefaultMailboxInteractor>(),
      Get.find<MoveFolderContentInteractor>(),
      Get.find<TreeBuilder>(),
      Get.find<VerifyNameInteractor>(),
      Get.find<GetAllMailboxInteractor>(),
      Get.find<RefreshAllMailboxInteractor>(),
    ));
  }
}
```

**Key Points:**
- Repositories registered but not used yet
- Controller unchanged
- Both coexist (Strangler Fig pattern)

---

## Verification Checklist

### Compilation
```bash
flutter pub get
flutter analyze

# Expected: No errors
```

### Tests
```bash
flutter test

# Expected: All tests pass (100%)
```

### Manual Check
- [ ] App compiles
- [ ] App runs
- [ ] Mailbox list displays
- [ ] Can select mailbox
- [ ] No crashes

---

## Deliverables

- [x] 5 repository files created
- [x] Interfaces defined
- [x] Implementations scaffolded
- [x] Bindings updated
- [x] Tests green
- [x] No functional changes

**Next**: Phase 2 - Extract State Management
