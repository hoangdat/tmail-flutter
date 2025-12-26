# Memory Management

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Stream Cleanup Rules

### Rule 1: Always Close StreamControllers

✅ **CORRECT**:
```dart
class MailboxStateRepository {
  final _selectedMailbox = StreamController<Mailbox?>.broadcast();

  void dispose() {
    _selectedMailbox.close(); // ESSENTIAL!
  }
}
```

❌ **INCORRECT**:
```dart
class MailboxStateRepository {
  final _selectedMailbox = StreamController<Mailbox?>.broadcast();

  void dispose() {
    // Missing close() = memory leak!
  }
}
```

### Rule 2: Cancel Subscriptions in Controller Cleanup

✅ **CORRECT**:
```dart
class EmailListController extends GetxController {
  late StreamSubscription _subscription;

  @override
  void onInit() {
    _subscription = repository.stream.listen(...);
  }

  @override
  void onClose() {
    _subscription.cancel(); // ESSENTIAL!
    super.onClose();
  }
}
```

❌ **INCORRECT**:
```dart
class EmailListController extends GetxController {
  @override
  void onInit() {
    repository.stream.listen(...); // No reference = can't cancel!
  }

  @override
  void onClose() {
    // Missing cancel() = memory leak!
    super.onClose();
  }
}
```

### Rule 3: Prefer StreamBuilder for Automatic Cleanup

✅ **BEST** (Automatic subscription management):
```dart
Widget buildUI() {
  return StreamBuilder<Mailbox?>(
    stream: mailboxRepository.selectedMailboxStream,
    builder: (context, snapshot) {
      // StreamBuilder auto-unsubscribes when widget disposed
      if (snapshot.hasData) {
        return buildMailboxUI(snapshot.data!);
      }
      return LoadingIndicator();
    },
  );
}
```

⚠️ **ACCEPTABLE** (Manual subscription, must cancel):
```dart
class EmailListController extends GetxController {
  late StreamSubscription _sub;

  @override
  void onInit() {
    _sub = repository.stream.listen((data) {
      // Update state...
    });
  }

  @override
  void onClose() {
    _sub.cancel(); // MUST cancel manually
    super.onClose();
  }
}
```

### Rule 4: Dispose Repositories on App Shutdown

✅ **CORRECT**:
```dart
void main() {
  setupDI();
  runApp(MyApp());

  // Cleanup on app dispose
  WidgetsBinding.instance.addObserver(
    LifecycleEventHandler(
      detachedCallBack: () {
        getIt<MailboxStateRepository>().dispose();
        getIt<UserStateRepository>().dispose();
        getIt<EmailStateRepository>().dispose();
      },
    ),
  );
}
```

---

## Memory Leak Patterns to Avoid

### Anti-Pattern 1: Forgotten Subscription Cancel

❌ **MEMORY LEAK**:
```dart
class Controller extends GetxController {
  @override
  void onInit() {
    // Subscription created but never cancelled
    repository.stream.listen((data) {
      print(data);
    });
  }

  // Missing onClose() with cancel()
}
```

**Impact**: Subscription persists after controller destroyed, holds reference to controller → memory leak

**Fix**:
```dart
class Controller extends GetxController {
  late StreamSubscription _sub;

  @override
  void onInit() {
    _sub = repository.stream.listen((data) {
      print(data);
    });
  }

  @override
  void onClose() {
    _sub.cancel(); // Fixed!
    super.onClose();
  }
}
```

### Anti-Pattern 2: StreamController Not Closed

❌ **MEMORY LEAK**:
```dart
class Repository {
  final _controller = StreamController<Data>.broadcast();

  // Missing dispose() method
}
```

**Impact**: StreamController stays open indefinitely, listeners persist → memory leak

**Fix**:
```dart
class Repository {
  final _controller = StreamController<Data>.broadcast();

  void dispose() {
    _controller.close(); // Fixed!
  }
}

// Ensure dispose called on app shutdown
getIt.registerSingleton<Repository>(
  Repository(),
  dispose: (repo) => repo.dispose(), // GetIt calls dispose
);
```

### Anti-Pattern 3: Multiple Subscriptions Without References

❌ **MEMORY LEAK**:
```dart
class Controller extends GetxController {
  @override
  void onInit() {
    repository.stream1.listen(...); // No reference!
    repository.stream2.listen(...); // No reference!
    repository.stream3.listen(...); // No reference!
  }

  // Can't cancel what we can't reference
}
```

**Fix**:
```dart
class Controller extends GetxController {
  late StreamSubscription _sub1;
  late StreamSubscription _sub2;
  late StreamSubscription _sub3;

  @override
  void onInit() {
    _sub1 = repository.stream1.listen(...);
    _sub2 = repository.stream2.listen(...);
    _sub3 = repository.stream3.listen(...);
  }

  @override
  void onClose() {
    _sub1.cancel();
    _sub2.cancel();
    _sub3.cancel();
    super.onClose();
  }
}
```

**Better Fix** (CompositeSubscription pattern):
```dart
class Controller extends GetxController {
  final _subscriptions = CompositeSubscription();

  @override
  void onInit() {
    _subscriptions.add(repository.stream1.listen(...));
    _subscriptions.add(repository.stream2.listen(...));
    _subscriptions.add(repository.stream3.listen(...));
  }

  @override
  void onClose() {
    _subscriptions.dispose(); // Cancels all!
    super.onClose();
  }
}
```

---

## Best Practices

### Use BehaviorSubject for State Repositories

✅ **RECOMMENDED** (RxDart BehaviorSubject):
```dart
class MailboxStateRepository {
  final _selectedMailbox = BehaviorSubject<Mailbox?>();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailbox.stream;

  // Benefit: Can get latest value without listening
  Mailbox? get selectedMailbox => _selectedMailbox.valueOrNull;

  void selectMailbox(Mailbox? mailbox) => _selectedMailbox.add(mailbox);

  void dispose() => _selectedMailbox.close();
}
```

**Benefits**:
- New subscribers immediately get latest value
- Can access current value synchronously
- Replays last value to late subscribers

### Use StreamController.broadcast() for Multiple Listeners

✅ **CORRECT** (Broadcast for pub-sub):
```dart
final _events = StreamController<EmailEvent>.broadcast();
```

⚠️ **WRONG** (Single-subscription for multiple listeners):
```dart
final _events = StreamController<EmailEvent>(); // Throws if >1 listener!
```

### Lifecycle Hooks Checklist

For every repository:
- [ ] `dispose()` method closes all StreamControllers
- [ ] Registered with GetIt disposal callback
- [ ] Called on app shutdown

For every controller:
- [ ] `onInit()` creates subscriptions with references
- [ ] `onClose()` cancels all subscriptions
- [ ] Calls `super.onClose()`

For every widget:
- [ ] Use `StreamBuilder` or `ValueListenableBuilder` (auto-cleanup)
- [ ] If manual subscription, cancel in `dispose()`

---

## Leak Detection Tools

### Dev Tools Memory Profiler

1. Run app in debug mode
2. Open Flutter DevTools
3. Go to Memory tab
4. Capture snapshot before navigation
5. Navigate through screens
6. Capture snapshot after navigation
7. Compare snapshots (look for retained StreamSubscriptions)

### Manual Leak Tests

```dart
testWidgets('No subscription leaks after controller disposal', (tester) async {
  final repository = MailboxStateRepository();

  // Create controller
  final controller = EmailListController(repository);

  // Subscribe
  expect(repository._controller.hasListener, isTrue);

  // Dispose controller
  controller.onClose();

  // Verify subscription cancelled
  expect(repository._controller.hasListener, isFalse);
});
```

---

## Disposal Checklist

### Repository Disposal

```dart
class MailboxStateRepository {
  final _selectedMailbox = BehaviorSubject<Mailbox?>();
  final _mailboxList = BehaviorSubject<List<Mailbox>>();

  void dispose() {
    _selectedMailbox.close();
    _mailboxList.close();
    // Close ALL StreamControllers
  }
}
```

### Controller Disposal

```dart
class EmailListController extends GetxController {
  late StreamSubscription _mailboxSub;
  late StreamSubscription _emailSub;
  late StreamSubscription _searchSub;

  @override
  void onClose() {
    _mailboxSub.cancel();
    _emailSub.cancel();
    _searchSub.cancel();
    // Cancel ALL subscriptions
    super.onClose();
  }
}
```

### App Shutdown

```dart
void main() {
  setupDI();
  runApp(MyApp());

  WidgetsBinding.instance.addObserver(
    LifecycleEventHandler(
      detachedCallBack: () {
        // Dispose all singletons
        getIt<MailboxStateRepository>().dispose();
        getIt<UserStateRepository>().dispose();
        getIt<EmailStateRepository>().dispose();
        getIt<SearchStateRepository>().dispose();
      },
    ),
  );
}
```
