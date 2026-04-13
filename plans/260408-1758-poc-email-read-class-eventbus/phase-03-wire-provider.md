# Phase 3: Wire EmailListStateProvider to EventBus

## Overview
- **Priority:** P2 — depends on Phase 1
- **Status:** Todo
- **Effort:** ~30 min

## Context

Currently `EmailListStateProvider.updateEmailFlagByEmailIds` is called **directly** by whoever handles mark-read success (mixin callback, single email controller, etc.).

New pattern: `EmailListStateProvider` **subscribes to events** — it reacts to `EmailReadSuccessEvent` without any caller knowing about it.

## What to Modify

### `lib/features/base/state/email_list_state_provider.dart`

Add `AppEventBus` dependency and subscribe in `onInit`:

```dart
import 'dart:async';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/base/event_bus/app_event_bus.dart';
import 'package:tmail_ui_user/features/email/presentation/event/email_read_event.dart';
// ... existing imports

class EmailListStateProvider extends GetxService {
  // ... existing fields unchanged

  StreamSubscription? _readSuccessSub;
  StreamSubscription? _readMultipleSuccessSub;

  @override
  void onInit() {
    super.onInit();
    final eventBus = Get.find<AppEventBus>();

    _readSuccessSub = eventBus.on<EmailReadSuccessEvent>().listen((event) {
      updateEmailFlagByEmailIds([event.emailId], readAction: event.readActions);
    });

    _readMultipleSuccessSub = eventBus.on<EmailReadMultipleSuccessEvent>().listen((event) {
      updateEmailFlagByEmailIds(event.emailIds, readAction: event.readActions);
    });
  }

  @override
  void onClose() {
    _readSuccessSub?.cancel();
    _readMultipleSuccessSub?.cancel();
    super.onClose();
  }

  // ... all existing methods unchanged
}
```

## Key Points

- `updateEmailFlagByEmailIds` method body is **not modified** — same logic, now triggered by event
- Old callers that still call `updateEmailFlagByEmailIds` directly continue to work (backward compat)
- `AppEventBus` must be registered **before** `EmailListStateProvider` in bindings

## Binding Order Check

Verify that `AppEventBus` is put before `EmailListStateProvider`:

```dart
// Correct order in binding:
Get.lazyPut(() => AppEventBus(), fenix: true);          // Phase 1
Get.lazyPut(() => SessionStateProvider(), fenix: true);
Get.lazyPut(() => EmailListStateProvider(), fenix: true); // depends on AppEventBus
```

With `lazyPut` + `fenix: true`, initialization is deferred — order matters at first `Get.find` call, not registration. `AppEventBus` must be registered before `EmailListStateProvider.onInit()` runs.

## Files to Modify
- `lib/features/base/state/email_list_state_provider.dart`

## Success Criteria
- Provider subscribes to `EmailReadSuccessEvent` on init
- Firing `EmailReadSuccessEvent` on the bus causes `emailsInCurrentMailbox` to refresh
- Subscriptions are cancelled on `onClose` — no leaks
- Existing direct callers of `updateEmailFlagByEmailIds` still compile and work
