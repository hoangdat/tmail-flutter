# Phase 2: EmailAction + EmailActionQueue + CancellationToken

## Overview
- **Priority:** P1 — depends on Phase 1
- **Status:** Todo
- **Replaces:** old phase-02 (EmailFlagActionHandler)

## Context

Instead of per-action-type handlers or background services, we use:
- `EmailAction` — typed, self-contained action (knows how to create its stream)
- `EmailActionQueue` — single GetxService, app lifecycle, executes any action
- `CancellationToken` — controller creates one, cancels in `onClose`; prevents callbacks but HTTP still completes

## Files to Create

### 1. `lib/features/email/presentation/action/cancellation_token.dart`

```dart
class CancellationToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}
```

### 2. `lib/features/email/presentation/action/email_action.dart`

```dart
import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/session/session.dart';

abstract class EmailAction {
  String get tag;
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId);
}
```

### 3. `lib/features/email/presentation/action/mark_as_read_action.dart`

```dart
class MarkAsReadEmailAction extends EmailAction {
  final EmailId emailId;
  final ReadActions readActions;
  final MarkReadAction markReadAction;
  final MailboxId? mailboxId;
  final EmailFlagService _flagService;

  MarkAsReadEmailAction(this.emailId, this.readActions, this.markReadAction, this.mailboxId, this._flagService);

  @override
  String get tag => 'MarkAsRead($emailId)';

  @override
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId) {
    return _flagService.markAsRead(session, accountId, emailId, readActions, markReadAction, mailboxId);
  }
}
```

### 4. `lib/features/email/presentation/action/mark_as_read_multiple_action.dart`

```dart
class MarkAsReadMultipleEmailAction extends EmailAction {
  final List<EmailId> emailIds;
  final ReadActions readActions;
  final Map<MailboxId, List<EmailId>> emailIdsByMailboxId;
  final EmailFlagService _flagService;

  @override
  String get tag => 'MarkAsReadMultiple(${emailIds.length})';

  @override
  Stream<Either<Failure, Success>> execute(Session session, AccountId accountId) {
    return _flagService.markAsReadMultiple(session, accountId, emailIds, readActions, emailIdsByMailboxId);
  }
}
```

### 5. `lib/features/email/presentation/action/email_action_queue.dart`

```dart
class EmailActionQueue extends GetxService {
  final AppEventBus _eventBus;
  final SessionStateProvider _sessionProvider;
  final _activeSubs = <String, StreamSubscription>{};

  EmailActionQueue(this._eventBus, this._sessionProvider);

  void submit(
    EmailAction action, {
    CancellationToken? token,
    ValueChanged<Success>? onSuccess,
    ValueChanged<Failure>? onFailure,
  }) {
    final session = _sessionProvider.session.value;
    final accountId = _sessionProvider.accountId.value;
    if (session == null || accountId == null) return;

    log('EmailActionQueue::submit ${action.tag}');

    late StreamSubscription sub;
    sub = action.execute(session, accountId).listen(
      (result) => result.fold(
        (failure) {
          _eventBus.fire(failure);
          if (token?.isCancelled != true) onFailure?.call(failure);
        },
        (success) {
          _eventBus.fire(success);
          if (token?.isCancelled != true) onSuccess?.call(success);
        },
      ),
      onDone: () => _activeSubs.remove(action.tag),
    );
    _activeSubs[action.tag] = sub;
  }

  @override
  void onClose() {
    for (final s in _activeSubs.values) s.cancel();
    _activeSubs.clear();
    super.onClose();
  }
}
```

## Registration (MailboxDashboardBindings)

```dart
Get.put(AppEventBus());
Get.put(EmailActionQueue(Get.find<AppEventBus>(), Get.find<SessionStateProvider>()));
Get.put(EmailListStateProvider());
```

## Design Decisions

| Decision | Reason |
|---|---|
| Single GetxService for all actions | No service proliferation, DRY |
| `CancellationToken` not `StreamSubscription.cancel()` | HTTP must complete, only callback is optional |
| `_activeSubs` as Map with tag key | Logging, future dedup/cancel-by-tag |
| `onDone` removes from map | Self-cleanup, no memory leak |
| Action holds service ref | Self-contained, testable |

## Success Criteria
- `EmailActionQueue` compiles as GetxService
- `MarkAsReadEmailAction` executes via queue, fires domain state on bus
- `CancellationToken.cancel()` prevents callbacks but bus still fires
- `EmailFlagActionHandler` can be deleted after migration
