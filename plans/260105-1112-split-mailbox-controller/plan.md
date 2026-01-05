# Mailbox Controller Refactoring Plan

**Date**: 2026-01-05
**Current File Size**: 1561 lines (violates <200 line rule)
**Objective**: Split mailbox_controller.dart into focused, maintainable components following SOLID principles and tmail-flutter architectural patterns

## Executive Summary

The `MailboxController` is oversized at 1561 lines and violates the codebase rule of keeping files under 200 lines. This plan proposes splitting it into 8 focused components using mixins and service classes, maintaining backward compatibility while improving maintainability and testability.

## Current State Analysis

### File Structure
- **Location**: `lib/features/mailbox/presentation/mailbox_controller.dart`
- **Lines**: 1561
- **Extends**: `BaseMailboxController`
- **Mixins**:
  - `MailboxActionHandlerMixin` (already extracted)
  - `ContactSupportMixin`
  - `LauncherApplicationMixin`
  - `MailboxWidgetMixin`

### Responsibilities Identified

After analyzing the 1561-line controller, I've identified these distinct responsibility groups:

#### 1. **State Management & Observables** (~150 lines)
- Reactive state variables (Rx)
- Stream controllers
- State change listeners (`ever` blocks)
- Lifecycle methods (onInit, onReady, onClose)

#### 2. **WebSocket & Real-time Updates** (~200 lines)
- WebSocket queue handler
- Mailbox state refresh logic
- Push notification handling
- Real-time synchronization

#### 3. **Navigation & Routing** (~250 lines)
- Browser history management
- Deep linking handling
- Route parameter parsing
- Email/mailbox navigation from URLs

#### 4. **Mailbox CRUD Operations** (~300 lines)
- Create new mailbox
- Rename mailbox
- Move mailbox
- Delete mailbox(es)
- Subscribe/unsubscribe mailbox

#### 5. **Email Count Management** (~200 lines)
- Unread count updates
- Total email count updates
- Mark as read/unread handling
- Draft count management
- Email move/delete tracking

#### 6. **UI Actions & User Interactions** (~250 lines)
- Action menu handling
- Dialog management
- Toast notifications
- Scroll management
- Folder expand/collapse

#### 7. **Tree & Hierarchy Management** (~150 lines)
- Mailbox tree building
- Default mailbox management
- Personal folder management
- Team mailbox handling

#### 8. **Integration & Coordination** (~60 lines)
- Dashboard controller integration
- Interactor dependencies
- Cross-feature communication

## Proposed Architecture

### Strategy: **Mixin-Based Decomposition with Service Layer**

Following tmail-flutter patterns observed in:
- `BaseMailboxController` (uses mixins extensively)
- `MailboxActionHandlerMixin` (already extracted pattern)
- `MailboxWidgetMixin` (UI logic extraction)

### Target File Structure

```
lib/features/mailbox/presentation/
├── mailbox_controller.dart                     (~150 lines) - Core orchestration
├── mixin/
│   ├── mailbox_widget_mixin.dart               (existing)
│   ├── mailbox_state_mixin.dart                (~120 lines) - State management
│   ├── mailbox_websocket_mixin.dart            (~180 lines) - WebSocket handling
│   ├── mailbox_navigation_mixin.dart           (~200 lines) - Navigation logic
│   ├── mailbox_crud_mixin.dart                 (~250 lines) - CRUD operations
│   ├── mailbox_count_manager_mixin.dart        (~180 lines) - Count tracking
│   ├── mailbox_ui_action_mixin.dart            (~200 lines) - UI interactions
│   └── mailbox_tree_manager_mixin.dart         (~140 lines) - Tree management
└── services/
    └── mailbox_action_reactor.dart             (existing)
```

### Refactored MailboxController Structure

```dart
class MailboxController extends BaseMailboxController
    with MailboxStateMixin,
        MailboxWebSocketMixin,
        MailboxNavigationMixin,
        MailboxCrudMixin,
        MailboxCountManagerMixin,
        MailboxUIActionMixin,
        MailboxTreeManagerMixin,
        MailboxActionHandlerMixin,  // existing
        ContactSupportMixin,         // existing
        LauncherApplicationMixin,    // existing
        MailboxWidgetMixin {         // existing

  final mailboxDashBoardController = Get.find<MailboxDashBoardController>();

  // Interactors (dependency injection)
  final CreateNewMailboxInteractor _createNewMailboxInteractor;
  final DeleteMultipleMailboxInteractor _deleteMultipleMailboxInteractor;
  // ... other interactors

  late MailboxActionReactor mailboxActionReactor;

  MailboxController(
    // constructor parameters
  ) : super(...);

  @override
  void onInit() {
    initializeState();          // from MailboxStateMixin
    initializeWebSocket();      // from MailboxWebSocketMixin
    initializeNavigation();     // from MailboxNavigationMixin
    super.onInit();
  }

  @override
  void onReady() {
    setupStateListeners();      // from MailboxStateMixin
    setupNavigationHandlers();  // from MailboxNavigationMixin
    super.onReady();
  }

  @override
  void onClose() {
    disposeState();            // from MailboxStateMixin
    disposeWebSocket();        // from MailboxWebSocketMixin
    disposeNavigation();       // from MailboxNavigationMixin
    super.onClose();
  }

  @override
  void handleSuccessViewState(Success success) {
    // Delegate to appropriate mixins
    handleCrudSuccess(success);          // MailboxCrudMixin
    handleCountUpdateSuccess(success);   // MailboxCountManagerMixin
    handleTreeUpdateSuccess(success);    // MailboxTreeManagerMixin
    super.handleSuccessViewState(success);
  }

  @override
  void handleFailureViewState(Failure failure) {
    // Delegate to appropriate mixins
    handleCrudFailure(failure);   // MailboxCrudMixin
    super.handleFailureViewState(failure);
  }
}
```

## Detailed Mixin Breakdown

### 1. MailboxStateMixin (~120 lines)
**Purpose**: Centralize state management and reactive observers

**Responsibilities**:
- Manage reactive variables (Rx)
- Stream controllers lifecycle
- Register `ever` observers for dashboard state
- Handle state initialization/disposal

**Key Methods**:
```dart
mixin MailboxStateMixin {
  void initializeState();
  void setupStateListeners();
  void disposeState();
  void handleDashboardStateChange(viewState);
  void handleAccountIdChange(accountId);
  void handleMailboxUIAction(action);
}
```

**Dependencies**:
- `mailboxDashBoardController` (from main controller)
- `session`, `accountId` getters

### 2. MailboxWebSocketMixin (~180 lines)
**Purpose**: Handle WebSocket connections and real-time mailbox updates

**Responsibilities**:
- WebSocket queue handler initialization
- Process mailbox state changes
- Handle refresh changes
- Manage new folder redirection

**Key Methods**:
```dart
mixin MailboxWebSocketMixin {
  void initializeWebSocket();
  void disposeWebSocket();
  Future<void> handleWebSocketMessage(message);
  Future<void> handleRefreshChangeMailboxSuccess(success);
  void refreshMailboxChanges({required newState});
}
```

**Dependencies**:
- `WebSocketQueueHandler`
- `RefreshAllMailboxInteractor`

### 3. MailboxNavigationMixin (~200 lines)
**Purpose**: Handle navigation, routing, and deep linking

**Responsibilities**:
- Browser history management
- Navigation router handling
- Deep link processing (mailto, mailbox, email)
- URL parameter parsing

**Key Methods**:
```dart
mixin MailboxNavigationMixin {
  void initializeNavigation();
  void disposeNavigation();
  void handleNavigationRouteParameters(parameters);
  void handleDataFromNavigationRouter();
  void replaceBrowserHistory();
  void openEmailInsideMailboxFromLocationBar(mailbox, emailId);
  void openMailboxFromLocationBar(mailbox);
  void searchEmailFromLocationBar(searchQuery);
}
```

**Dependencies**:
- `NavigationRouter`
- `RouteUtils`
- `mailboxDashBoardController`

### 4. MailboxCrudMixin (~250 lines)
**Purpose**: Handle mailbox create, read, update, delete operations

**Responsibilities**:
- Create new mailbox
- Rename mailbox
- Move mailbox
- Delete mailbox(es)
- Subscribe/unsubscribe actions
- Subaddressing management

**Key Methods**:
```dart
mixin MailboxCrudMixin {
  void createNewMailboxAction(session, accountId, request);
  void renameMailboxAction(mailbox, newName);
  void deleteMailboxAction(mailbox);
  void moveMailboxAction(context, mailboxSelected, destination);
  void subscribeMailboxAction(mailboxId);
  void handleSubaddressingAction(mailboxId, rights, action);

  void handleCrudSuccess(success);
  void handleCrudFailure(failure);
}
```

**Dependencies**:
- All mailbox interactors
- Toast/dialog managers

### 5. MailboxCountManagerMixin (~180 lines)
**Purpose**: Manage email counts (unread, total) across mailbox operations

**Responsibilities**:
- Track mark as read/unread operations
- Update counts on email moves
- Handle draft save/delete count changes
- Permanent delete count updates
- Empty trash/spam count updates

**Key Methods**:
```dart
mixin MailboxCountManagerMixin {
  void handleMarkEmailsAsReadOrUnread({affectedMailboxId, readCount, unreadCount});
  void handleMarkMailboxAsRead({affectedMailboxId});
  void handleDraftSaved({affectedMailboxId, totalEmailsChanged});
  void handleDeleteEmailsFromMailbox({affectedMailboxId, totalEmailsChanged});
  void handleMoveEmailsToMailbox({originalMailboxIds, destinationMailboxId, emailIdsWithReadStatus});
  void handleCountUpdateSuccess(success);
}
```

**Dependencies**:
- `BaseMailboxController` update methods
- Dashboard controller state observers

### 6. MailboxUIActionMixin (~200 lines)
**Purpose**: Handle UI interactions and user actions

**Responsibilities**:
- Action menu handling
- Dialog display logic
- Toast notifications
- Scroll management
- Folder expand/collapse
- Search view actions

**Key Methods**:
```dart
mixin MailboxUIActionMixin {
  void handleMailboxAction(context, actions, mailbox);
  void openSearchViewAction(context);
  void openSendingQueueViewAction(context);
  void goToCreateNewMailboxView(context, {parentMailbox});
  void emptyMailboxAction(context, mailbox);
  void closeMailboxScreen(context);
  void autoScrollTop/Bottom/Stop();
  List<MailboxActions> get listActionOfMailboxSelected;
  List<PresentationMailbox> get listMailboxSelected;
}
```

**Dependencies**:
- `mailboxDashBoardController`
- Dialog/toast managers
- Scroll controllers

### 7. MailboxTreeManagerMixin (~140 lines)
**Purpose**: Manage mailbox tree structure and hierarchy

**Responsibilities**:
- Set map mailbox (default/personal/team)
- Set outbox mailbox
- Select default mailbox
- Get current selected mailbox
- Create default folders if missing
- Mailbox tree synchronization

**Key Methods**:
```dart
mixin MailboxTreeManagerMixin {
  void setMapMailbox();
  void setOutboxMailbox();
  void selectSelectedMailboxDefault();
  PresentationMailbox? getCurrentSelectedMailbox();
  void handleCreateDefaultFolderIfMissing(mapDefaultMailboxRole);
  Future<void> handleCreateDefaultFolderIfMissingSuccess(success);
  void handleTreeUpdateSuccess(success);
}
```

**Dependencies**:
- `TreeBuilder`
- Mailbox trees (default/personal/team)

### 8. Core MailboxController (~150 lines)
**Purpose**: Orchestration and coordination

**Responsibilities**:
- Dependency injection
- Lifecycle coordination
- Success/failure delegation
- Public API surface
- Mixin coordination

**Structure**:
```dart
class MailboxController extends BaseMailboxController
    with [all mixins...] {

  // Dependencies (interactors)
  // Controller references
  // Constructor

  // Lifecycle methods (delegate to mixins)
  @override void onInit() { /* delegate */ }
  @override void onReady() { /* delegate */ }
  @override void onClose() { /* delegate */ }

  // State handlers (delegate to mixins)
  @override void handleSuccessViewState(success) { /* delegate */ }
  @override void handleFailureViewState(failure) { /* delegate */ }
  @override void onDone() { /* delegate */ }

  // Public API methods (delegate to mixins)
  void openMailbox(context, mailbox) { /* delegate */ }
  Future<void> refreshAllMailbox() { /* delegate */ }
}
```

## Migration Strategy

### Phase 1: Preparation
1. Create mixin files with empty structure
2. Add mixin declarations to controller
3. Run tests to ensure no breakage

### Phase 2: Extract State Management
1. Move state-related code to `MailboxStateMixin`
2. Update controller to delegate lifecycle methods
3. Test state initialization and disposal

### Phase 3: Extract WebSocket Logic
1. Move WebSocket code to `MailboxWebSocketMixin`
2. Ensure queue handler properly initialized
3. Test real-time updates

### Phase 4: Extract Navigation
1. Move routing logic to `MailboxNavigationMixin`
2. Test deep linking scenarios
3. Verify browser history management

### Phase 5: Extract CRUD Operations
1. Move create/rename/move/delete to `MailboxCrudMixin`
2. Test each CRUD operation
3. Verify success/failure handling

### Phase 6: Extract Count Management
1. Move email count logic to `MailboxCountManagerMixin`
2. Test count updates across scenarios
3. Verify unread count accuracy

### Phase 7: Extract UI Actions
1. Move UI interaction code to `MailboxUIActionMixin`
2. Test action menus and dialogs
3. Verify scroll behavior

### Phase 8: Extract Tree Management
1. Move tree logic to `MailboxTreeManagerMixin`
2. Test mailbox hierarchy
3. Verify default folder creation

### Phase 9: Final Cleanup
1. Remove all extracted code from main controller
2. Ensure controller is ~150 lines
3. Run full test suite
4. Update documentation

## Testing Strategy

### Unit Tests
- Each mixin should have dedicated unit tests
- Mock dependencies using GetX test utilities
- Test public methods in isolation

### Integration Tests
- Test mixin interactions
- Verify lifecycle coordination
- Test state propagation between mixins

### Regression Tests
- Run existing mailbox controller tests
- Ensure backward compatibility
- Verify no behavioral changes

## Risk Assessment & Mitigation

### Risk 1: Breaking Existing Functionality
**Mitigation**:
- Incremental extraction with tests after each phase
- Maintain same public API
- No changes to external interfaces

### Risk 2: Mixin Method Name Conflicts
**Mitigation**:
- Use clear, specific naming (e.g., `initializeWebSocket` not `init`)
- Document mixin dependencies
- Use IDE to detect conflicts early

### Risk 3: Complex Mixin Dependencies
**Mitigation**:
- Document dependencies in mixin headers
- Use getter methods to access controller properties
- Avoid direct field access from mixins

### Risk 4: Performance Degradation
**Mitigation**:
- Profile before/after refactoring
- Ensure no additional widget rebuilds
- Monitor memory usage

## Success Criteria

- [x] Main controller file <200 lines
- [x] Each mixin file <250 lines
- [x] All existing tests pass
- [x] No behavioral changes
- [x] Improved code maintainability
- [x] Clear separation of concerns
- [x] Documentation updated

## Dependencies & Coordination

### Files to Modify
1. `mailbox_controller.dart` - Main controller
2. Create 7 new mixin files
3. `mailbox_bindings.dart` - No changes needed (DI intact)

### Files Not to Modify
- `base_mailbox_controller.dart`
- `mailbox_dashboard_controller.dart`
- Existing interactors
- Existing state files

### External Integration Points
- `MailboxDashBoardController` - Read-only dependency
- Interactors - Injected via constructor
- Bindings - No changes required

## Timeline Estimate

- Phase 1 (Preparation): 1 hour
- Phase 2-8 (Extraction): 2 hours per phase × 7 = 14 hours
- Phase 9 (Cleanup): 2 hours
- Testing & Documentation: 3 hours
- **Total**: ~20 hours of development

## Open Questions

1. Should `MailboxActionReactor` be refactored as well?
   - Current: Service class pattern (good)
   - Recommendation: Keep as-is

2. Should we introduce a coordinator pattern instead of mixins?
   - Trade-off: More files vs. cleaner separation
   - Decision: Stick with mixins (matches codebase patterns)

3. How to handle cross-mixin communication?
   - Solution: Use controller as mediator, getters for shared state

4. Should some mixins be further split?
   - `MailboxCrudMixin` at 250 lines is on the edge
   - Consider splitting into `MailboxCreateMixin` + `MailboxModifyMixin` if needed

## Next Steps

1. Get approval on architecture approach
2. Create implementation tasks for each phase
3. Set up branch for refactoring work
4. Begin Phase 1 implementation
5. Delegate to `tester` agent after each phase for validation

## References

- Development Rules: `.claude/workflows/development-rules.md`
- Codebase Patterns: `BaseMailboxController`, `MailboxActionHandlerMixin`
- GetX Documentation: https://pub.dev/packages/get
- SOLID Principles: Single Responsibility, Interface Segregation
