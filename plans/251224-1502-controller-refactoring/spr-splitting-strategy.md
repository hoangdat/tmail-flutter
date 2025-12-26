# SPR Controller Splitting Strategy

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Single Responsibility Principle Applied

Each controller = one screen OR one feature concern, max 200 lines.

---

## Split Strategy for Critical Controllers

### 1. ComposerController (2370 lines → 5 controllers)

**Current Responsibilities**: Composition, upload, autocomplete, AI, drafts, templates, formatting

#### Split Plan

```
ComposerController (2370 lines)
    ↓
├── ComposerController (180 lines) - Core composition UI
│   ├── Form state (to/cc/bcc/subject/body)
│   ├── Send/save actions
│   └── Lifecycle management
│
├── AttachmentController (150 lines) - File attachments
│   ├── Upload/download
│   ├── Drag-drop handling
│   └── Progress tracking
│
├── RecipientController (120 lines) - Recipient management
│   ├── Autocomplete search
│   ├── Contact suggestions
│   └── Validation
│
├── EditorController (180 lines) - Rich text editing
│   ├── Formatting toolbar
│   ├── HTML/Markdown handling
│   └── Image insertion
│
└── DraftController (100 lines) - Draft management
    ├── Auto-save
    ├── Draft recovery
    └── Template handling
```

#### Communication Pattern

```dart
// All controllers share ComposerStateRepository
class ComposerStateRepository {
  final draft = Rxn<Draft>();
  final recipients = <EmailAddress>[].obs;
  final attachments = <Attachment>[].obs;
  final editorContent = ''.obs;

  Stream<Draft> get draftStream => _draftController.stream;
}

// Each controller focuses on one concern
class ComposerController {
  final ComposerStateRepository _state;
  final SendEmailUseCase _sendUseCase;

  void send() => _sendUseCase.execute(_state.buildEmail());
}

class AttachmentController {
  final ComposerStateRepository _state;
  final UploadAttachmentUseCase _uploadUseCase;

  void addAttachment(File file) async {
    final attachment = await _uploadUseCase.execute(file);
    _state.attachments.add(attachment);
  }
}
```

---

### 2. MailboxDashBoardController (2000+ lines → 4 controllers)

**Current Responsibilities**: Mailbox state, email list, selection, routes, integrations

#### Split Plan

```
MailboxDashBoardController (2000+ lines)
    ↓
├── NavigationController (150 lines) - Route coordination
│   ├── Route stack management
│   ├── Deep link handling
│   └── Back navigation
│
├── SelectionController (100 lines) - Multi-selection
│   ├── Select/deselect items
│   ├── Select all/none
│   └── Bulk actions
│
├── FilterController (120 lines) - Email filtering
│   ├── Filter state (read/unread/starred)
│   ├── Sort order
│   └── Search query
│
└── SyncController (150 lines) - Background sync
    ├── WebSocket handling
    ├── State reconciliation
    └── Offline queue
```

#### Shared State

```dart
// State repositories replace monolithic controller
class MailboxStateRepository {
  final selectedMailbox = Rxn<Mailbox>();
  Stream<Mailbox?> get selectedMailboxStream => _mailboxController.stream;
}

class EmailStateRepository {
  final emails = <Email>[].obs;
  final selectedEmails = <Email>[].obs;
  final filter = EmailFilter.all.obs;
  final sortOrder = SortOrder.newest.obs;
}

class NavigationStateRepository {
  final currentRoute = DashboardRoute.mailbox.obs;
  final routeStack = <DashboardRoute>[].obs;
}
```

---

### 3. MailboxController (1561 lines → 3 controllers)

**Current Responsibilities**: Tree, operations, subscription, WebSocket, UI actions

#### Split Plan

```
MailboxController (1561 lines)
    ↓
├── MailboxTreeController (180 lines) - Tree display
│   ├── Build tree structure
│   ├── Expand/collapse
│   └── Tree navigation
│
├── MailboxActionsController (150 lines) - CRUD operations
│   ├── Create/rename/delete
│   ├── Move/subscribe
│   └── Mark as read
│
└── MailboxSyncController (120 lines) - State sync
    ├── WebSocket listener
    ├── State updates
    └── Cache invalidation
```

---

### 4. ThreadController (1547 lines → 3 controllers)

**Current Responsibilities**: Loading, pagination, search, selection, filtering, shortcuts

#### Split Plan

```
ThreadController (1547 lines)
    ↓
├── EmailListController (180 lines) - List display
│   ├── Load emails
│   ├── Pagination
│   └── Pull-to-refresh
│
├── EmailSearchController (120 lines) - Search
│   ├── Search query
│   ├── Search filters
│   └── Search pagination
│
└── EmailSelectionController (100 lines) - Selection
    ├── Select/deselect
    ├── Range selection
    └── Keyboard shortcuts
```

---

## Splitting Decision Matrix

| Question | Yes → Split | No → Keep |
|----------|------------|-----------|
| >200 lines? | Multiple concerns likely | Single concern |
| Multiple mixins (3+)? | Extract to separate controllers | Single feature |
| >10 dependencies? | Over-coupled | Focused |
| Hard to test? | Too many mocks needed | Testable |
| Frequent merge conflicts? | Shared by multiple features | Single owner |
| Multiple UI screens? | One controller per screen | Single screen |

---

## Extraction Patterns

### Pattern 1: Extract by Feature
Split by user-facing feature (upload, search, edit)

### Pattern 2: Extract by Layer
Split by concern (UI state, business logic, sync)

### Pattern 3: Extract Shared State
Move shared state to repository, create focused controllers

---

## Implementation Steps

1. **Identify split boundaries** - Map responsibilities
2. **Create state repository** - Extract shared state
3. **Create new controllers** - One per concern
4. **Inject state repository** - Share via DI
5. **Migrate functionality** - Move code incrementally
6. **Update bindings** - Register new controllers
7. **Test** - Verify behavior unchanged
8. **Remove old controller** - Delete after migration

---

## Example Migration

**Before**:
```dart
class ComposerController extends BaseController
    with DragDropMixin, AutocompleteMixin, EditorMixin {
  // 2370 lines of mixed concerns
}
```

**After**:
```dart
// Shared state
class ComposerStateRepository { /* 100 lines */ }

// Focused controllers
class ComposerController { /* 180 lines - core UI */ }
class AttachmentController { /* 150 lines - uploads */ }
class RecipientController { /* 120 lines - autocomplete */ }
class EditorController { /* 180 lines - formatting */ }
class DraftController { /* 100 lines - drafts */ }

// GetIt registration
getIt.registerSingleton<ComposerStateRepository>(ComposerStateRepository());
getIt.registerFactory(() => ComposerController(getIt()));
getIt.registerFactory(() => AttachmentController(getIt()));
// etc.
```

---

## Success Criteria

- [ ] All controllers <200 lines
- [ ] One controller per screen/feature
- [ ] Shared state in repositories
- [ ] Clear responsibility boundaries
- [ ] No overlapping concerns
- [ ] Independent testability
