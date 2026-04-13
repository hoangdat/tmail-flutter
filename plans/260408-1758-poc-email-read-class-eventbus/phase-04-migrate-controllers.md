# Phase 4: Migrate Controllers to EmailActionQueue

## Overview
- **Priority:** P3 — depends on Phases 1–3
- **Status:** Todo
- **Replaces:** old phase-04 (migrate to EmailFlagActionHandler)

## Context

Replace `EmailFlagActionHandler` usage in all 3 controllers with `EmailActionQueue.submit()`.
Each controller creates a `CancellationToken`, cancels in `onClose`.

## Target Controllers

### 1. ThreadController

```dart
class ThreadController extends BaseController with EmailActionController {
  late final EmailActionQueue _actionQueue;
  final _cancelToken = CancellationToken();

  @override
  void onInit() {
    super.onInit();
    _actionQueue = Get.find<EmailActionQueue>();
  }

  void markEmailAsRead(PresentationEmail email) {
    _actionQueue.submit(MarkAsReadEmailAction(
      email.id!, ReadActions.markAsRead, MarkReadAction.tap,
      email.mailboxContain?.mailboxId, _emailFlagService,
    ));
  }

  void markAsReadMultiple(List<PresentationEmail> emails, ReadActions readActions) {
    final needMark = emails.where((e) => readActions == ReadActions.markAsUnread ? e.hasRead : !e.hasRead).toList();
    if (needMark.isEmpty) return;
    _actionQueue.submit(MarkAsReadMultipleEmailAction(
      needMark.listEmailIds, readActions, needMark.emailIdsByMailboxId, _emailFlagService,
    ));
  }

  @override
  void onClose() {
    _cancelToken.cancel();
    super.onClose();
  }
}
```

### 2. SearchEmailController

Same pattern as ThreadController — replace handler calls with `_actionQueue.submit(...)`.

### 3. SingleEmailController

```dart
// Auto mark-as-read on email open — fire-and-forget (no token)
_actionQueue.submit(MarkAsReadEmailAction(...));

// If screen-specific reaction needed — with token
_actionQueue.submit(MarkAsReadEmailAction(...),
  token: _cancelToken,
  onSuccess: (s) {
    if (s is MarkAsEmailReadSuccess) {
      _threadDetailController?.markCollapsedEmailReadSuccess(s);
    }
  },
);
```

## Cleanup

- Delete `lib/features/email/presentation/handler/email_flag_action_handler.dart`
- Remove handler field + dispose from all 3 controllers

## Files to Modify
- `lib/features/thread/presentation/thread_controller.dart`
- `lib/features/search/email/presentation/search_email_controller.dart`
- `lib/features/email/presentation/controller/single_email_controller.dart`

## Files to Delete
- `lib/features/email/presentation/handler/email_flag_action_handler.dart`

## Success Criteria
- All 3 controllers use `_actionQueue.submit()` instead of handler
- `CancellationToken` cancelled in each controller's `onClose`
- Auto mark-as-read (SingleEmailController) works without token — survives navigation
- User-tapped actions work with token + optional callbacks
- `EmailFlagActionHandler` deleted, no references remain
