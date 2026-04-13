# Phase 1: AppEventBus + Email Read Events

## Overview
- **Priority:** P0 — everything else depends on this
- **Status:** Todo
- **Effort:** ~30 min

## What to Create

### 1. `AppEventBus` GetxService

**File:** `lib/features/base/event_bus/app_event_bus.dart`

```dart
import 'dart:async';
import 'package:get/get.dart';

class AppEventBus extends GetxService {
  final _controller = StreamController<Object>.broadcast();

  Stream<T> on<T>() => _controller.stream.whereType<T>();

  void fire(Object event) => _controller.add(event);

  @override
  void onClose() {
    _controller.close();
    super.onClose();
  }
}
```

### 2. Email Read Events

**File:** `lib/features/email/presentation/event/email_read_event.dart`

```dart
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:model/email/read_actions.dart';

class EmailReadSuccessEvent {
  final EmailId emailId;
  final ReadActions readActions;
  const EmailReadSuccessEvent(this.emailId, this.readActions);
}

class EmailReadMultipleSuccessEvent {
  final List<EmailId> emailIds;
  final ReadActions readActions;
  const EmailReadMultipleSuccessEvent(this.emailIds, this.readActions);
}

class EmailReadFailureEvent {
  final Object failure;
  const EmailReadFailureEvent(this.failure);
}
```

## Register AppEventBus in Bindings

Find the main binding that registers GetxServices (likely near `SessionStateProvider` and `EmailListStateProvider`).

```dart
// Wherever SessionStateProvider is registered, add:
Get.lazyPut(() => AppEventBus(), fenix: true);
```

**Search for binding location:**
```bash
grep -r "SessionStateProvider" lib/ --include="*.dart" -l
```

## Files to Create
- `lib/features/base/event_bus/app_event_bus.dart`
- `lib/features/email/presentation/event/email_read_event.dart`

## Files to Modify
- Bindings file that registers `SessionStateProvider`

## Success Criteria
- `AppEventBus` is registered and findable via `Get.find<AppEventBus>()`
- `AppEventBus.on<EmailReadSuccessEvent>()` returns a typed stream
- `AppEventBus.fire(EmailReadSuccessEvent(...))` emits on that stream

## Notes
- `broadcast()` stream — multiple listeners without subscription management
- No subscription stored — callers manage their own `StreamSubscription`
- Event classes are plain Dart (no GetX dependency)
