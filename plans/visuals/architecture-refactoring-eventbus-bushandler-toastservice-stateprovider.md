# Diagram: Controller Architecture Refactoring

## The Problem — God Controller (Before)

```ascii
┌─────────────────────────────────────────────────────────────────┐
│                  MailboxDashBoardController                      │
│                      (3,508 lines)                               │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ consumeState │  │ consumeState │  │    consumeState       │  │
│  │ markAsRead   │  │ markAsStar   │  │    moveEmail ...      │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                       │              │
│         ▼                 ▼                       ▼              │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              handleSuccessViewState()                       │ │
│  │   if MarkAsReadSuccess → updateFlag()                      │ │
│  │   if MarkAsStarSuccess → updateFlag()   ← EDIT PER ACTION │ │
│  │   if MoveEmailSuccess  → updateList()                      │ │
│  │   if ArchiveSuccess    → ...                               │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
  ↓ every new feature = edit this file
```

## The Solution — Decoupled Architecture (After)

```ascii
  User Action (tap / swipe)
         │
         ▼
  ┌─────────────────┐
  │   Controller    │  thin: submit action + onSuccess for screen-specific only
  │  (trigger only) │
  └────────┬────────┘
           │ submit(XEmailAction, onSuccess: navigate/scroll)
           ▼
  ┌──────────────────────┐
  │   EmailActionQueue   │  executes stream, always fires to bus
  │   (GetxService)      │
  └──────────┬───────────┘
             │ fire(XSuccess / XFailure)
             ▼
  ┌────────────────────┐
  │    AppEventBus     │  broadcast, app-lifecycle scope
  └──────┬─────────────┘
         │
    ┌────┴─────────────────────────┐
    │                              │
    ▼                              ▼
  ┌──────────────────┐    ┌──────────────────────┐
  │   XBusHandler    │    │   YBusHandler         │
  │  (GetxService)   │    │  (GetxService)         │
  └──────┬───────────┘    └──────────────────────┘
         │
    ┌────┴──────────────┐
    │                   │
    ▼                   ▼
  ┌────────────────┐  ┌──────────────┐
  │ StateProvider  │  │ ToastService │
  │  (pure store)  │  │ (GetxService)│
  └───────┬────────┘  └──────────────┘
          │ Rx mutation
          ▼
  ┌──────────────────┐
  │   Obx(Widget)    │  re-renders automatically
  └──────────────────┘
```

## Mermaid: Full Data Flow

```mermaid
flowchart TD
    UserAction["👆 User Action\n(tap / swipe)"]
    Controller["Controller\n(thin trigger)"]
    Queue["EmailActionQueue\nGetxService — app lifecycle"]
    Bus["AppEventBus\nbroadcast stream"]
    Handler["XBusHandler\nGetxService per event type"]
    Provider["EmailListStateProvider\npure observable store"]
    Toast["ToastService\nGetxService"]
    Widget["Obx Widget\nauto re-renders"]
    OnSuccess["onSuccess callback\nscreen-specific only"]

    UserAction --> Controller
    Controller -->|"submit(XEmailAction)"| Queue
    Queue -->|"fire(XSuccess)"| Bus
    Bus -->|"on&lt;XSuccess&gt;"| Handler
    Handler -->|"updateEmailFlag()"| Provider
    Handler -->|"showToast / showWithAction"| Toast
    Provider -->|"Rx mutation"| Widget
    Queue -.->|"if token not cancelled"| OnSuccess
    OnSuccess -.->|"navigate / scroll / close dialog"| Controller

    style Queue fill:#4A90D9,color:#fff
    style Bus fill:#E8A838,color:#fff
    style Handler fill:#5BA85A,color:#fff
    style Provider fill:#9B59B6,color:#fff
    style Toast fill:#E74C3C,color:#fff
    style OnSuccess stroke-dasharray: 5 5
```

## Mermaid: Adding a New Feature (OCP Compliance)

```mermaid
flowchart LR
    subgraph NEW["✅ New Files Only"]
        A["MarkAsStarEmailAction\nextends EmailAction"]
        B["MarkAsStarBusHandler\nextends GetxService"]
    end

    subgraph EDIT["✏️ 1-line Additions"]
        C["busHandlerFactories\n+1 entry in registry"]
        D["Controller\n+1 trigger method"]
    end

    subgraph UNTOUCHED["🔒 Zero Edits"]
        E["EmailActionQueue"]
        F["AppEventBus"]
        G["EmailListStateProvider"]
        H["Existing BusHandlers"]
        I["ToastService"]
    end

    A --> C
    B --> C
    C --> E
    B --> G
    B --> I

    style NEW fill:#27AE60,color:#fff
    style EDIT fill:#F39C12,color:#fff
    style UNTOUCHED fill:#7F8C8D,color:#fff
```

## Mermaid: Responsibility Boundaries

```mermaid
flowchart TD
    subgraph BUS["BusHandler owns"]
        B1["Domain state mutations\nupdateEmailFlag / updateList"]
        B2["Shared toast\nsame reaction on any screen"]
        B3["Undo → re-fires to Queue\nno controller involved"]
    end

    subgraph CB["onSuccess callback owns"]
        C1["Navigation\nclose detail / open folder"]
        C2["Scroll to position"]
        C3["Close dialog"]
    end

    subgraph NEVER["Never in Controller"]
        N1["if success is X → updateState()"]
        N2["handleSuccessViewState\nif/else chains"]
    end

    style BUS fill:#27AE60,color:#fff
    style CB fill:#2980B9,color:#fff
    style NEVER fill:#E74C3C,color:#fff
```

## Mermaid: File Structure

```mermaid
flowchart LR
    subgraph BASE["lib/features/base/"]
        subgraph EB["event_bus/"]
            R["bus_handler_registry.dart\n🗂 central registry"]
            BUS["app_event_bus.dart"]
            H1["mark_as_read_bus_handler.dart"]
            H2["get_all_email_bus_handler.dart"]
            H3["mark_as_star_bus_handler.dart\n(next)"]
        end
        subgraph SVC["service/"]
            TS["toast_service.dart\n🔔 shared UI reactions"]
        end
        subgraph ST["state/"]
            SP["email_list_state_provider.dart\n📦 pure data store"]
        end
    end

    subgraph ACTION["lib/features/email/presentation/action/"]
        AQ["email_action_queue.dart\n⚙️ executor"]
        AA["email_action.dart\nabstract base"]
        A1["mark_as_read_email_action.dart"]
        A2["mark_as_read_multiple_email_action.dart"]
        A3["mark_as_star_email_action.dart\n(next)"]
    end

    R --> H1
    R --> H2
    H1 --> SP
    H1 --> TS
    AQ --> BUS
    BUS --> H1
    BUS --> H2

    style R fill:#F39C12,color:#fff
    style TS fill:#E74C3C,color:#fff
    style SP fill:#9B59B6,color:#fff
    style AQ fill:#4A90D9,color:#fff
```
