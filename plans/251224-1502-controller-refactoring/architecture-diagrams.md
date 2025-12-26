# Architecture Diagrams - Visual Verification

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Diagram 1: Overall Architecture (4 Layers)

```
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Controller A │  │ Controller B │  │ Controller C │          │
│  │  <200 lines  │  │  <200 lines  │  │  <200 lines  │          │
│  │              │  │              │  │              │          │
│  │ • UI events  │  │ • UI events  │  │ • UI events  │          │
│  │ • View state │  │ • View state │  │ • View state │          │
│  │ • Subscribe  │  │ • Subscribe  │  │ • Subscribe  │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            ↓                                     │
└────────────────────────────────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │  Constructor    │
                    │  Injection via  │
                    │  GetX Binding   │
                    └────────┬────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              State Repository (Singleton)                  │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │ • Owns canonical state (selectedMailbox, emails)     │  │  │
│  │  │ • Exposes Stream<State> (broadcast)                  │  │  │
│  │  │ • Coordinates use cases                              │  │  │
│  │  │ • NO UI knowledge                                    │  │  │
│  │  │ • permanent: true (app lifetime)                     │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            ↓                                     │
│              StreamController<State>.broadcast()                 │
│                            ↓                                     │
│              stream.listen() ← Controllers subscribe             │
└─────────────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                       DOMAIN LAYER                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Use Case 1  │  │  Use Case 2  │  │  Use Case 3  │          │
│  │              │  │              │  │              │          │
│  │ • Business   │  │ • Business   │  │ • Business   │          │
│  │   logic      │  │   logic      │  │   logic      │          │
│  │ • Validation │  │ • Validation │  │ • Validation │          │
│  │ • Returns    │  │ • Returns    │  │ • Returns    │          │
│  │   Either     │  │   Either     │  │   Either     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         └──────────────────┼──────────────────┘                  │
└────────────────────────────┼────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                        DATA LAYER                                │
│  ┌────────────────┐              ┌────────────────┐             │
│  │ Remote API     │              │ Local Cache    │             │
│  │ (JMAP Server)  │◄────────────►│ (Hive)         │             │
│  │                │   Sync        │                │             │
│  │ • fetch()      │              │ • get()        │             │
│  │ • create()     │              │ • save()       │             │
│  │ • update()     │              │ • delete()     │             │
│  │ • delete()     │              │ • clear()      │             │
│  └────────────────┘              └────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Diagram 2: Nested View Hierarchy (Composer Example)

```
┌──────────────────────────────────────────────────────────────────┐
│                      ComposerScreen                               │
│                   (StatelessWidget)                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  GetX Binding: ComposerBinding                             │  │
│  │  • ComposerStateRepository (feature-scoped)                │  │
│  │  • ComposerController                                      │  │
│  │  • RecipientController                                     │  │
│  │  • AttachmentController                                    │  │
│  │  • EditorController                                        │  │
│  │  • DraftController                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                     AppBar                                  │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │  │
│  │  │ Send Button  │  │ Save Draft   │  │ Close        │     │  │
│  │  │              │  │              │  │              │     │  │
│  │  │ Uses:        │  │ Uses:        │  │ Uses:        │     │  │
│  │  │ Composer     │  │ Draft        │  │ Composer     │     │  │
│  │  │ Controller   │  │ Controller   │  │ Controller   │     │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                RecipientField Widget                        │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<RecipientController>                      │  │  │
│  │  │                                                        │  │  │
│  │  │  TextField(                                            │  │  │
│  │  │    onChanged: controller.onRecipientChanged,          │  │  │
│  │  │  )                                                     │  │  │
│  │  │                                                        │  │  │
│  │  │  Obx(() => controller.isSearching                     │  │  │
│  │  │      ? AutocompleteList()                             │  │  │
│  │  │      : SizedBox.shrink()                              │  │  │
│  │  │  )                                                     │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                              │  │
│  │  Controller: RecipientController                            │  │
│  │  State: ComposerStateRepository.recipients                 │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                 SubjectField Widget                         │  │
│  │  TextField(                                                 │  │
│  │    controller: Get.find<ComposerController>().subject,     │  │
│  │  )                                                          │  │
│  │                                                              │  │
│  │  Controller: ComposerController (shared)                    │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                  EditorArea Widget                          │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<EditorController>                         │  │  │
│  │  │                                                        │  │  │
│  │  │  RichTextEditor(                                       │  │  │
│  │  │    onChanged: controller.onContentChanged,            │  │  │
│  │  │    initialContent: controller.content.value,          │  │  │
│  │  │  )                                                     │  │  │
│  │  │                                                        │  │  │
│  │  │  FormattingToolbar(                                    │  │  │
│  │  │    onBold: controller.toggleBold,                     │  │  │
│  │  │    onItalic: controller.toggleItalic,                 │  │  │
│  │  │  )                                                     │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                              │  │
│  │  Controller: EditorController                               │  │
│  │  State: ComposerStateRepository.editorContent              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │               AttachmentPanel Widget                        │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<AttachmentController>                     │  │  │
│  │  │                                                        │  │  │
│  │  │  Obx(() => ListView.builder(                          │  │  │
│  │  │    itemCount: controller.attachments.length,          │  │  │
│  │  │    itemBuilder: (_, i) => AttachmentTile(             │  │  │
│  │  │      attachment: controller.attachments[i],           │  │  │
│  │  │      onRemove: controller.removeAttachment,           │  │  │
│  │  │    )                                                   │  │  │
│  │  │  ))                                                    │  │  │
│  │  │                                                        │  │  │
│  │  │  AddAttachmentButton(                                  │  │  │
│  │  │    onTap: controller.pickFile,                        │  │  │
│  │  │  )                                                     │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                              │  │
│  │  Controller: AttachmentController                           │  │
│  │  State: ComposerStateRepository.attachments                │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Diagram 3: Controller Communication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                   USER INTERACTION FLOW                          │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ↓
                  User taps "Add Recipient"
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│                    RecipientController                           │
│                                                                   │
│  void addRecipient(EmailAddress addr) {                         │
│    _composerState.recipients.add(addr); ←── Updates repository  │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│               ComposerStateRepository (Singleton)                │
│                                                                   │
│  final recipients = <EmailAddress>[].obs;                       │
│  final attachments = <Attachment>[].obs;                        │
│  final editorContent = ''.obs;                                  │
│                                                                   │
│  // Broadcast streams                                            │
│  Stream<List<EmailAddress>> get recipientsStream                │
│  Stream<List<Attachment>> get attachmentsStream                 │
│  Stream<String> get contentStream                               │
└─────────────────────────────────────────────────────────────────┘
                             │
                ┌────────────┼────────────┐
                ↓            ↓            ↓
        ┌───────────┐ ┌──────────┐ ┌──────────────┐
        │ Composer  │ │  Draft   │ │ Recipient    │
        │Controller │ │Controller│ │ Controller   │
        │           │ │          │ │              │
        │ Listens   │ │ Listens  │ │ Updates UI   │
        │ to all    │ │ for      │ │ when list    │
        │ changes   │ │ auto-save│ │ changes      │
        └───────────┘ └──────────┘ └──────────────┘
                │            │            │
                ↓            ↓            ↓
        ┌───────────────────────────────────┐
        │         UI Rebuilds               │
        │  • Send button enabled?           │
        │  • Draft auto-saved               │
        │  • Recipient chips updated        │
        └───────────────────────────────────┘
```

---

## Diagram 4: Concrete Example - MailboxController Split

### BEFORE (1561 lines, monolithic)

```
┌──────────────────────────────────────────────────────────────────┐
│              MailboxController (1561 lines)                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  RESPONSIBILITIES (7+ concerns):                            │  │
│  │  1. Mailbox tree building                                   │  │
│  │  2. Folder operations (create, rename, delete, move)        │  │
│  │  3. Subscription management                                 │  │
│  │  4. WebSocket state sync                                    │  │
│  │  5. UI action handling                                      │  │
│  │  6. Tree expansion state                                    │  │
│  │  7. Dashboard controller access                             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  PROBLEMS:                                                         │
│  • Get.find<MailboxDashBoardController>() (tight coupling)        │
│  • 30+ use case dependencies                                      │
│  • Hard to test                                                   │
│  • SRP violation                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### AFTER (Split into 3 controllers + 1 repository)

```
┌─────────────────────────────────────────────────────────────────┐
│                  MailboxStateRepository                          │
│                    (Singleton, permanent)                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  State:                                                     │  │
│  │  • selectedMailbox: Rxn<Mailbox>                           │  │
│  │  • mailboxTree: MailboxTree                                │  │
│  │  • expandedFolders: List<MailboxId>                        │  │
│  │  • filter: MailboxFilter                                   │  │
│  │                                                             │  │
│  │  Streams:                                                   │  │
│  │  • selectedMailboxStream                                   │  │
│  │  • treeChangedStream                                       │  │
│  │  • filterChangedStream                                     │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ↓                  ↓                  ↓
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ MailboxTree    │  │ MailboxActions │  │ MailboxSync    │
│ Controller     │  │ Controller     │  │ Controller     │
│ (180 lines)    │  │ (150 lines)    │  │ (120 lines)    │
│                │  │                │  │                │
│ • Build tree   │  │ • Create       │  │ • WebSocket    │
│ • Expand/      │  │ • Rename       │  │   listener     │
│   Collapse     │  │ • Delete       │  │ • State sync   │
│ • Navigation   │  │ • Move         │  │ • Cache        │
│ • Filtering    │  │ • Subscribe    │  │   update       │
└────────────────┘  └────────────────┘  └────────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ↓
                   Shared Repository
                   No direct calls
```

### MailboxScreen Widget Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    MailboxScreen                                 │
│                  (StatelessWidget)                               │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  GetX Binding: MailboxBinding                             │  │
│  │  • MailboxStateRepository (singleton, app-level)          │  │
│  │  • MailboxTreeController                                  │  │
│  │  • MailboxActionsController                               │  │
│  │  • MailboxSyncController                                  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              MailboxTreeWidget                             │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<MailboxTreeController>                   │  │  │
│  │  │                                                       │  │  │
│  │  │  Obx(() => TreeView(                                 │  │  │
│  │  │    nodes: controller.treeNodes,                      │  │  │
│  │  │    onNodeTap: controller.onMailboxSelected,          │  │  │
│  │  │    onExpand: controller.toggleExpansion,             │  │  │
│  │  │  ))                                                   │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                             │  │
│  │  Each MailboxNode contains:                                │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  MailboxTile Widget                                  │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │ Icon + Name + Unread Count                     │  │  │  │
│  │  │  │                                                 │  │  │  │
│  │  │  │ ContextMenu:                                    │  │  │  │
│  │  │  │   Uses MailboxActionsController                │  │  │  │
│  │  │  │   • Rename                                      │  │  │  │
│  │  │  │   • Delete                                      │  │  │  │
│  │  │  │   • Move                                        │  │  │  │
│  │  │  │   • Subscribe/Unsubscribe                       │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │            MailboxFilterBar Widget                         │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<MailboxTreeController>                   │  │  │
│  │  │                                                       │  │  │
│  │  │  SegmentedButton(                                    │  │  │
│  │  │    selected: controller.filter,                      │  │  │
│  │  │    onChanged: controller.setFilter,                  │  │  │
│  │  │    options: [All, Personal, Teams, Favorites]        │  │  │
│  │  │  )                                                    │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              SyncIndicator Widget                          │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  GetBuilder<MailboxSyncController>                   │  │  │
│  │  │                                                       │  │  │
│  │  │  Obx(() => controller.isSyncing                      │  │  │
│  │  │      ? LoadingIndicator()                            │  │  │
│  │  │      : LastSyncTime(controller.lastSync)             │  │  │
│  │  │  )                                                    │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Diagram 5: State Flow (User Selects Mailbox)

```
┌────────────────────────────────────────────────────────────────┐
│ STEP 1: User taps "Inbox" in mailbox tree                      │
└────────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌────────────────────────────────────────────────────────────────┐
│ MailboxTreeWidget                                               │
│   onNodeTap(mailbox) called                                    │
└────────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌────────────────────────────────────────────────────────────────┐
│ STEP 2: MailboxTreeController.onMailboxSelected(mailbox)      │
│                                                                 │
│  void onMailboxSelected(Mailbox mailbox) {                    │
│    _mailboxState.selectMailbox(mailbox); ← Updates repository │
│  }                                                              │
└────────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌────────────────────────────────────────────────────────────────┐
│ STEP 3: MailboxStateRepository                                │
│                                                                 │
│  void selectMailbox(Mailbox mailbox) {                        │
│    selectedMailbox.value = mailbox;                           │
│    _selectedMailboxController.add(mailbox); ← Emit stream     │
│  }                                                              │
└────────────────────────────────────────────────────────────────┘
                            │
                            ↓ (Stream broadcasts to all listeners)
                ┌───────────┴───────────┐
                │                       │
                ↓                       ↓
┌──────────────────────┐    ┌──────────────────────┐
│ STEP 4a: Email       │    │ STEP 4b: Email       │
│ ListController       │    │ DetailController     │
│ (different screen)   │    │ (different screen)   │
│                      │    │                      │
│ @override            │    │ @override            │
│ void onInit() {      │    │ void onInit() {      │
│   _sub = _mailbox    │    │   _sub = _mailbox    │
│     State.selected   │    │     State.selected   │
│     MailboxStream    │    │     MailboxStream    │
│     .listen((mbox) { │    │     .listen((mbox) { │
│       _loadEmails(); │    │       _clear();      │
│     });              │    │     });              │
│ }                    │    │ }                    │
└──────────────────────┘    └──────────────────────┘
                │                       │
                ↓                       ↓
┌────────────────────────────────────────────────────────────────┐
│ STEP 5: UI Rebuilds (Reactive)                                │
│                                                                 │
│  • MailboxTree highlights "Inbox"                             │
│  • EmailList loads emails for Inbox                           │
│  • EmailDetail clears previous email                          │
│  • All happen automatically via streams                       │
└────────────────────────────────────────────────────────────────┘
```

---

## Diagram 6: GetX Binding Scopes

```
┌─────────────────────────────────────────────────────────────────┐
│                      APP LIFETIME                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  AppBinding (initialized in main.dart)                    │  │
│  │  permanent: true                                           │  │
│  │                                                            │  │
│  │  ┌──────────────────────────────────────────────────────┐│  │
│  │  │ Singleton Repositories (live entire app)             ││  │
│  │  │                                                       ││  │
│  │  │ • MailboxStateRepository                             ││  │
│  │  │ • EmailStateRepository                               ││  │
│  │  │ • NetworkService                                     ││  │
│  │  │ • AuthService                                        ││  │
│  │  │ • CachingManager                                     ││  │
│  │  └──────────────────────────────────────────────────────┘│  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ↓                    ↓                    ↓
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ ROUTE SCOPE  │    │ ROUTE SCOPE  │    │ ROUTE SCOPE  │
│              │    │              │    │              │
│ MailboxBind  │    │ EmailListBind│    │ ComposerBind │
│              │    │              │    │              │
│ Controllers: │    │ Controllers: │    │ Controllers: │
│ • MailboxTree│    │ • EmailList  │    │ • Composer   │
│ • MailboxAct │    │ • EmailSrch  │    │ • Recipient  │
│ • MailboxSync│    │ • EmailSel   │    │ • Attachment │
│              │    │              │    │ • Editor     │
│ ┌──────────┐ │    │ ┌──────────┐ │    │              │
│ │ Disposed │ │    │ │ Disposed │ │    │ Feature Repo:│
│ │ when     │ │    │ │ when     │ │    │ • Composer   │
│ │ route    │ │    │ │ route    │ │    │   State      │
│ │ closed   │ │    │ │ closed   │ │    │              │
│ └──────────┘ │    │ └──────────┘ │    │ ┌──────────┐ │
│              │    │              │    │ │ Disposed │ │
└──────────────┘    └──────────────┘    │ │ when     │ │
                                        │ │ route    │ │
                                        │ │ closed   │ │
                                        │ └──────────┘ │
                                        └──────────────┘
```

---

## Diagram 7: Memory Management (Lifecycle)

```
App Start
    │
    ├─ AppBinding.dependencies() called
    │      │
    │      └─→ Singleton repositories created (permanent: true)
    │          • MailboxStateRepository
    │          • EmailStateRepository
    │          (Live until app closed)
    │
    ├─ User navigates to /mailbox
    │      │
    │      └─→ MailboxBinding.dependencies() called
    │             │
    │             └─→ Controllers created (Get.lazyPut)
    │                 • MailboxTreeController
    │                 • MailboxActionsController
    │                 • MailboxSyncController
    │                 │
    │                 └─→ onInit() called
    │                     • Subscribe to repository streams
    │                     • Initialize UI state
    │
    ├─ User navigates to /email-list
    │      │
    │      ├─→ MailboxBinding.onClose() called
    │      │      │
    │      │      └─→ Controllers disposed
    │      │          • onClose() called on each controller
    │      │          • StreamSubscriptions cancelled
    │      │          • ScrollControllers disposed
    │      │          • Memory freed
    │      │
    │      └─→ EmailListBinding.dependencies() called
    │             │
    │             └─→ New controllers created
    │                 • EmailListController
    │                 (Repositories still alive)
    │
    └─ App Close
           │
           └─→ Singleton repositories disposed
               • MailboxStateRepository.dispose()
               • EmailStateRepository.dispose()
               • StreamControllers closed
```

---

## Summary: Key Verification Points

### ✅ Architecture Layers
- 4 clear layers: Presentation → Application → Domain → Data
- Each layer has defined responsibilities
- Dependencies flow downward only

### ✅ Controller Separation
- Each controller <200 lines, single responsibility
- Multiple controllers can coexist in one screen
- Each controller accessed via Get.find<ControllerType>()

### ✅ Communication Pattern
- Controllers NEVER call each other directly
- All communication via shared repository
- Repository emits streams, controllers listen

### ✅ State Management
- App-level state: Singleton repositories (permanent: true)
- Feature-level state: Feature repositories (scoped to binding)
- UI state: Controller Rx variables (scoped to controller)

### ✅ Lifecycle Management
- AppBinding: Permanent, app lifetime
- Route bindings: Scoped, auto-disposed
- Controllers: onInit() subscribe, onClose() cleanup

### ✅ View Nesting
- Parent view can contain multiple child widgets
- Each child widget can use different controller
- All controllers registered in same binding
- Child widgets get controllers via Get.find()

---

**Ready for implementation?** This architecture ensures:
- Zero circular dependencies
- Clear separation of concerns
- Testable components
- Scalable to 100+ controllers
- Memory-safe (auto cleanup)
