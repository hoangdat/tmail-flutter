# Phase 2: State Extraction - Move State to Repository

**Duration**: 3 days
**Goal**: Migrate state from controller to `MailboxStateRepository`

---

## Objectives

- Move all mailbox state to repository
- Update controller to delegate to repository
- Maintain backward compatibility
- Keep all tests green

**Success Criteria**: Same behavior, state managed by repository

---

## Current State (Before)

```dart
class MailboxController extends BaseMailboxController {
  // State scattered in controller
  PresentationMailbox? get selectedMailbox => mailboxDashBoardController.selectedMailbox.value;

  // From BaseMailboxController
  final personalMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final defaultMailboxTree = MailboxTree(MailboxNode.root()).obs;
  final teamMailboxesTree = MailboxTree(MailboxNode.root()).obs;

  List<PresentationMailbox> allMailboxes = <PresentationMailbox>[];
}
```

**Problems:**
- State ownership unclear (controller vs dashboard)
- Direct coupling to dashboard controller
- Hard to test state changes in isolation

---

## Target State (After)

```dart
class MailboxController extends BaseMailboxController {
  final MailboxStateRepository _state = Get.find();

  // Getters delegate to repository
  PresentationMailbox? get selectedMailbox => _state.selectedMailbox;
  MailboxTree get defaultMailboxTree => _state.defaultMailboxTree;
  MailboxTree get personalMailboxTree => _state.personalMailboxTree;
  List<PresentationMailbox> get allMailboxes => _state.allMailboxes;
}
```

**Benefits:**
- Clear ownership (repository owns state)
- Controller is facade (delegates)
- Easy to test (mock repository)
- Same public API (no breakage)

---

## Step 2.1: Move State to BaseMailboxController Delegation

**Currently**: `BaseMailboxController` owns trees directly

**Change**: Delegate to repository while maintaining compatibility

### Update BaseMailboxController

```dart
abstract class BaseMailboxController extends BaseController {
  // Inject repository
  MailboxStateRepository? _stateRepository;

  // Trees now delegate to repository
  Rx<MailboxTree> get personalMailboxTree {
    if (_stateRepository != null) {
      return _stateRepository!.personalMailboxTree.obs;
    }
    return _personalMailboxTreeFallback;
  }

  Rx<MailboxTree> get defaultMailboxTree {
    if (_stateRepository != null) {
      return _stateRepository!.defaultMailboxTree.obs;
    }
    return _defaultMailboxTreeFallback;
  }

  // Fallback for backwards compatibility
  final _personalMailboxTreeFallback = MailboxTree(MailboxNode.root()).obs;
  final _defaultMailboxTreeFallback = MailboxTree(MailboxNode.root()).obs;

  // All mailboxes delegate
  List<PresentationMailbox> get allMailboxes {
    return _stateRepository?.allMailboxes ?? _allMailboxesFallback;
  }

  List<PresentationMailbox> _allMailboxesFallback = <PresentationMailbox>[];

  // Setter methods now update repository
  Future<void> buildTree(List<PresentationMailbox> allMailbox, {MailboxId? mailboxIdSelected}) async {
    if (_stateRepository != null) {
      _stateRepository!.setAllMailboxes(allMailbox);
    } else {
      _allMailboxesFallback = allMailbox;
    }

    final recordTree = await _treeBuilder.generateMailboxTreeInUI(
      allMailboxes: allMailbox,
      currentDefaultTree: defaultMailboxTree.value,
      currentPersonalTree: personalMailboxTree.value,
      currentTeamMailboxTree: teamMailboxesTree.value,
      mailboxIdSelected: mailboxIdSelected,
    );

    if (_stateRepository != null) {
      _stateRepository!.setDefaultMailboxTree(recordTree.defaultMailboxTree);
      _stateRepository!.setPersonalMailboxTree(recordTree.personalMailboxTree);
      _stateRepository!.setTeamMailboxesTree(recordTree.teamMailboxTree);
    } else {
      _defaultMailboxTreeFallback.value = recordTree.defaultMailboxTree;
      _personalMailboxTreeFallback.value = recordTree.personalMailboxTree;
      // ...
    }
  }

  void injectStateRepository(MailboxStateRepository repository) {
    _stateRepository = repository;
  }
}
```

---

## Step 2.2: Update MailboxController to Use Repository

```dart
class MailboxController extends BaseMailboxController {
  final MailboxStateRepository _state = Get.find();

  MailboxController(...) : super(...) {
    // Inject repository into base controller
    injectStateRepository(_state);
  }

  // Delegate selectedMailbox to repository instead of dashboard
  PresentationMailbox? get selectedMailbox => _state.selectedMailbox;

  // Update methods to use repository
  void _setMapMailbox() {
    final mapDefaultMailboxIdByRole = {
      for (var mailboxNode in defaultMailboxTree.value.root.childrenItems ?? List<MailboxNode>.empty())
        mailboxNode.item.role!: mailboxNode.item.id
    };

    final mapMailboxById = {
      for (var presentationMailbox in allMailboxes)
        presentationMailbox.id: presentationMailbox
    };

    // Update repository
    _state.setMapDefaultMailboxIdByRole(mapDefaultMailboxIdByRole);
    _state.setMapMailboxById(mapMailboxById);

    // Also update dashboard for backward compatibility
    mailboxDashBoardController.setMapDefaultMailboxIdByRole(mapDefaultMailboxIdByRole);
    mailboxDashBoardController.setMapMailboxById(mapMailboxById);
  }

  void _setOutboxMailbox() {
    try {
      final outboxMailboxIdByRole = _state.mapDefaultMailboxIdByRole[PresentationMailbox.roleOutbox];
      if (outboxMailboxIdByRole == null) {
        final outboxMailboxByName = findNodeByNameOnFirstLevel(PresentationMailbox.outboxRole)?.item;
        _state.setOutboxMailbox(outboxMailboxByName);
      } else {
        _state.setOutboxMailbox(_state.mapMailboxById[outboxMailboxIdByRole]!);
      }

      // Update dashboard for compatibility
      mailboxDashBoardController.setOutboxMailbox(_state.outboxMailbox);
    } catch (e) {
      logError('MailboxController::_setOutboxMailbox: Not found outbox mailbox');
      _state.setOutboxMailbox(null);
      mailboxDashBoardController.setOutboxMailbox(null);
    }
  }

  void _selectSelectedMailboxDefault() {
    final mailboxSelected = _getCurrentSelectedMailbox();
    _state.selectMailbox(mailboxSelected);

    // Update dashboard for compatibility
    mailboxDashBoardController.setSelectedMailbox(mailboxSelected);
  }
}
```

---

## Step 2.3: Update State Setters Throughout Controller

Find all places that modify state and update repository:

### Current Mailbox State
```dart
// Before
currentMailboxState = success.currentMailboxState;

// After
_state.setCurrentMailboxState(success.currentMailboxState);
currentMailboxState = _state.currentMailboxState; // Getter from base
```

### All Mailboxes
```dart
// Before (in handleCreateDefaultFolderIfMissingSuccess)
allMailboxes.add(mailbox.toPresentationMailbox());

// After
final updated = List<PresentationMailbox>.from(_state.allMailboxes);
updated.add(mailbox.toPresentationMailbox());
_state.setAllMailboxes(updated);
```

### Selected Mailbox
```dart
// Before
mailboxDashBoardController.setSelectedMailbox(presentationMailboxSelected);

// After
_state.selectMailbox(presentationMailboxSelected);
mailboxDashBoardController.setSelectedMailbox(presentationMailboxSelected); // Keep for compatibility
```

---

## Step 2.4: Maintain Dashboard Synchronization (Temporary)

**During migration**, keep dashboard updated for backward compatibility:

```dart
void _syncStateToDashboard() {
  // Listen to repository changes and update dashboard
  _state.selectedMailboxStream.listen((mailbox) {
    mailboxDashBoardController.setSelectedMailbox(mailbox);
  });
}

@override
void onInit() {
  _syncStateToDashboard();
  super.onInit();
}
```

**Note**: This sync will be removed in future when dashboard also uses repositories

---

## Verification Steps

### 1. Check Getters Work
```dart
// Test that delegating getters return same values
test('selectedMailbox delegates to repository', () {
  final mailbox = PresentationMailbox(...);
  _state.selectMailbox(mailbox);

  expect(controller.selectedMailbox, equals(mailbox));
});
```

### 2. Check Setters Update Repository
```dart
test('_setMapMailbox updates repository', () {
  controller._setMapMailbox();

  expect(_state.mapDefaultMailboxIdByRole, isNotEmpty);
  expect(_state.mapMailboxById, isNotEmpty);
});
```

### 3. Manual Verification
- [ ] Select mailbox → Updates correctly
- [ ] Create folder → Tree updates
- [ ] Refresh → State persists
- [ ] Navigation → Selected mailbox maintained

---

## Testing Checklist

```bash
# Run tests
flutter test

# Expected results
✅ All existing tests pass
✅ No behavioral changes
✅ State accessible via controller (same API)
✅ State now managed by repository (internally)
```

---

## Rollback Plan

If issues arise:

1. **Keep repository code** (doesn't hurt)
2. **Revert controller changes**:
   ```dart
   // Temporarily comment out repository delegation
   // PresentationMailbox? get selectedMailbox => _state.selectedMailbox;

   // Restore original
   PresentationMailbox? get selectedMailbox => mailboxDashBoardController.selectedMailbox.value;
   ```
3. **Fix issues**
4. **Re-apply changes**

---

## Deliverables

- [x] State moved to repository
- [x] Controller delegates via getters
- [x] Setters update repository
- [x] Dashboard sync maintained
- [x] All tests green
- [x] No behavioral changes

**Next**: Phase 3 - Extract CRUD Operations
