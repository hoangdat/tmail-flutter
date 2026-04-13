# Dependency Graph: markAsEmailRead Migration

## Before: Hub-and-Spoke (All through Dashboard)

```mermaid
graph TD
    TC1[ThreadController] --> DASH[MailboxDashBoardController<br/>3,498 lines]
    SEC1[SearchEmailController] --> DASH
    SIEC1[SingleEmailController] --> DASH
    DASH --> MARI[MarkAsEmailReadInteractor]
    DASH --> MAMRI[MarkAsMultipleEmailReadInteractor]
    DASH --> HSV[handleSuccessViewState<br/>30+ type checks]
    DASH --> UEF[updateEmailFlagByEmailIds]

    style DASH fill:#ffcdd2
    style HSV fill:#ffcdd2
```

## After: Provider + Service + Callback

```mermaid
graph TD
    TC[ThreadController] --> |via mixin| EAC[EmailActionController<br/>mixin on BaseController]
    SEC[SearchEmailController] --> |via mixin| EAC
    SIEC[SingleEmailController] --> |own impl| SSP2[SessionStateProvider]
    SIEC --> |own impl| ELP2[EmailListStateProvider]
    SIEC --> |own impl| ESR2[EmailServiceRegistry]

    EAC --> SSP[SessionStateProvider<br/>18 lines]
    EAC --> ELP[EmailListStateProvider<br/>95 lines]
    EAC --> ESR[EmailServiceRegistry<br/>19 lines]

    ESR --> EFS[EmailFlagService<br/>57 lines]
    ESR2 --> EFS

    EFS --> MARI[MarkAsEmailReadInteractor]
    EFS --> MAMRI[MarkAsMultipleEmailReadInteractor]

    style SSP fill:#e1f5fe
    style ELP fill:#e1f5fe
    style SSP2 fill:#e1f5fe
    style ELP2 fill:#e1f5fe
    style ESR fill:#fff3e0
    style ESR2 fill:#fff3e0
    style EFS fill:#fff3e0
    style EAC fill:#e8f5e9
```

## Data Flow: Single markAsEmailRead Call

```mermaid
sequenceDiagram
    participant UI as ThreadView
    participant TC as ThreadController
    participant Mixin as EmailActionController
    participant SSP as SessionStateProvider
    participant ESR as EmailServiceRegistry
    participant EFS as EmailFlagService
    participant INT as MarkAsEmailReadInteractor
    participant ELP as EmailListStateProvider

    UI->>TC: markAsEmailRead(email, readAction)
    TC->>Mixin: (inherited from mixin)
    Mixin->>SSP: session.value / accountId.value
    SSP-->>Mixin: Session, AccountId
    Mixin->>ESR: flag.markAsRead(...)
    ESR->>EFS: markAsRead(...)
    EFS->>INT: execute(...)
    INT-->>Mixin: Stream yields Right(MarkAsEmailReadSuccess)
    Note over Mixin: consumeState routes to onSuccess callback
    Mixin->>ELP: updateEmailFlagByEmailIds([emailId])
    Note over ELP: Updates shared reactive list<br/>All Obx widgets rebuild
```

## Recipe: Apply to Any Action

```mermaid
flowchart LR
    S1["1. SERVICE<br/>Wrap interactor<br/>in service method"] --> S2["2. REGISTRY<br/>Add late final<br/>to registry"]
    S2 --> S3["3. MIXIN<br/>consumeState +<br/>onSuccess callback"]
    S3 --> S4["4. DASHBOARD<br/>Remove interactor call +<br/>handleSuccess branch"]

    style S1 fill:#fff3e0
    style S2 fill:#fff3e0
    style S3 fill:#e8f5e9
    style S4 fill:#ffebee
```

## Migration Roadmap

```mermaid
gantt
    title Action Migration from Dashboard
    dateFormat X
    axisFormat %s

    section EmailFlagService
    markAsEmailRead       :done, 0, 1
    markAsReadMultiple    :done, 0, 1
    markAsStarEmail       :active, 1, 2
    markAsStarMultiple    :2, 3

    section EmailMoveService
    moveToMailbox         :3, 4
    moveMultiple          :4, 5
    moveToTrash           :5, 6

    section EmailDeleteService
    deletePermanently     :6, 7
    deleteMultiple        :7, 8
    emptyTrash            :8, 9

    section ComposerSendService
    sendEmail             :9, 10
    saveDraft             :10, 11
```
