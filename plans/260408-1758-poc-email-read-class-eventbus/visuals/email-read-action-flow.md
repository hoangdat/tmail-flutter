```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                     EMAIL READ ACTION FLOW — NEW ARCHITECTURE                   ║
╚══════════════════════════════════════════════════════════════════════════════════╝

  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                           NEW PATH  (PoC)                                   │
  └─────────────────────────────────────────────────────────────────────────────┘

  User taps "Mark as Read"
         │
         ▼
  ┌─────────────────────────┐
  │    ThreadController     │  holds: _emailFlagHandler (plain class field)
  │  (extends BaseController│
  │   with EmailAction...)  │
  └────────────┬────────────┘
               │  _emailFlagHandler.markAsRead(email, ...)
               ▼
  ┌─────────────────────────┐   Get.find<EmailServiceRegistry>()
  │  EmailFlagActionHandler │   Get.find<SessionStateProvider>()
  │  (plain class, no mixin)│   Get.find<AppEventBus>()
  └────────────┬────────────┘
               │  _registry.flag.markAsRead(session, accountId, ...)
               ▼
  ┌─────────────────────────┐
  │    EmailFlagService     │  (unchanged domain layer)
  │    returns Stream<      │
  │    Either<F,S>>         │
  └────────────┬────────────┘
               │  .listen() directly — NO consumeState
               │
         ┌─────┴──────┐
         │            │
   on failure    on success (MarkAsEmailReadSuccess)
         │            │
         ▼            ▼
  ┌──────────┐  ┌────────────────────────────┐
  │EventBus  │  │       AppEventBus          │
  │.fire(    │  │  .fire(EmailReadSuccess    │
  │ ReadFail)│  │       Event(id, actions))  │
  └──────────┘  └──────────────┬─────────────┘
                               │  broadcast stream
                     ┌─────────┴──────────┐
                     │                    │
                     ▼                    ▼
          ┌──────────────────┐   ┌─────────────────────┐
          │EmailListState    │   │ (future subscribers) │
          │Provider          │   │ ThreadDetailCtrl     │
          │ onInit() listens │   │ SearchEmailCtrl      │
          │ to bus events    │   │ etc.                 │
          └────────┬─────────┘   └─────────────────────┘
                   │  updateEmailFlagByEmailIds(...)
                   ▼
          ┌──────────────────┐
          │  emailsCurrent   │  .obs list refreshes
          │  Mailbox.refresh │  → Obx() widgets rebuild
          └──────────────────┘


  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                          OLD PATH  (untouched, still works)                 │
  └─────────────────────────────────────────────────────────────────────────────┘

  Other controllers still using:
  markAsEmailRead(email, ReadActions.markAsRead, MarkReadAction.tap)
         │
         ▼
  ┌─────────────────────────┐
  │  EmailActionController  │  mixin on BaseController
  │  (mixin, unchanged)     │
  └────────────┬────────────┘
               │  consumeState(_emailRegistry.flag.markAsRead(...))
               ▼
  ┌─────────────────────────┐
  │    BaseController       │
  │    viewState.value =    │  shared Rx state
  │    handleSuccess...()   │
  └────────────┬────────────┘
               │  onSuccess callback
               ▼
  ┌─────────────────────────┐
  │  _emailListProvider     │  called directly (not via event bus)
  │  .updateEmailFlagBy...  │
  └─────────────────────────┘


  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                         KEY DIFFERENCES                                     │
  └─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────┬─────────────────────────┬────────────────────────────────┐
  │                  │  OLD PATH               │  NEW PATH                      │
  ├──────────────────┼─────────────────────────┼────────────────────────────────┤
  │ Abstraction      │ Mixin (on BaseCtrl)     │ Plain class (no constraint)    │
  │ consumeState     │ Yes — shared viewState  │ No — direct .listen()          │
  │ Result routing   │ handleSuccessViewState()│ AppEventBus.fire(event)        │
  │ List update      │ Direct callback         │ Provider subscribes to event   │
  │ BaseController   │ Required (constraint)   │ Not needed                     │
  │ Testability      │ Needs full controller   │ Instantiate class + mock bus   │
  │ New subscribers  │ Must touch handler code │ Just subscribe to bus          │
  └──────────────────┴─────────────────────────┴────────────────────────────────┘


  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                         COMPONENT OWNERSHIP                                 │
  └─────────────────────────────────────────────────────────────────────────────┘

  lib/
  ├── features/base/
  │   ├── event_bus/
  │   │   └── app_event_bus.dart          ← broadcast stream GetxService
  │   └── state/
  │       └── email_list_state_provider   ← subscribes to events in onInit
  │
  ├── features/email/presentation/
  │   ├── event/
  │   │   └── email_read_event.dart       ← plain Dart event classes
  │   ├── handler/
  │   │   └── email_flag_action_handler   ← plain class, fires events
  │   └── service/
  │       └── email_flag_service          ← unchanged, returns Stream
  │
  └── features/thread/presentation/
      └── thread_controller.dart          ← holds handler as field, calls it
```
