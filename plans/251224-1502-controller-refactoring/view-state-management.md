# View State Management

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Keeping View State in Memory

### State Types

#### 1. UI State (Ephemeral - Controller-scoped)
Lives in controller, dies when controller disposed.

```dart
class EmailListController {
  // UI-only state (not shared, not persisted)
  final isLoading = false.obs;
  final scrollOffset = 0.0.obs;
  final selectedItems = <Email>[].obs;
  final showFab = true.obs;

  // Lifecycle: onInit → onClose (screen lifetime)
}
```

**Examples**: Loading flags, scroll position, expanded panels, selection mode

#### 2. Application State (Persistent - Repository-scoped)
Lives in state repository, survives controller disposal.

```dart
class MailboxStateRepository {
  // Shared state (survives navigation)
  final selectedMailbox = Rxn<Mailbox>();
  final expandedFolders = <MailboxId>[].obs;
  final lastSyncTime = Rxn<DateTime>();

  // Lifecycle: App lifetime (singleton)
}
```

**Examples**: Selected mailbox, filter settings, search query, user preferences

#### 3. Domain State (Cached - Data Repository)
Lives in data repository, persisted to disk.

```dart
class EmailRepository {
  final _cache = <MailboxId, List<Email>>{};

  Stream<List<Email>> getEmails(MailboxId id) async* {
    // Emit cached (in-memory)
    if (_cache.containsKey(id)) {
      yield _cache[id]!;
    }

    // Fetch fresh (API)
    final emails = await _remoteDataSource.fetch(id);
    _cache[id] = emails; // Update cache
    yield emails;
  }
}
```

**Examples**: Email lists, mailbox trees, account data

---

## Memory Management Strategies

### Strategy 1: LRU Cache for Lists

```dart
class EmailCache {
  static const maxCacheSize = 10; // 10 mailboxes cached
  final _cache = LinkedHashMap<MailboxId, List<Email>>();

  void cache(MailboxId id, List<Email> emails) {
    if (_cache.length >= maxCacheSize) {
      _cache.remove(_cache.keys.first); // Remove oldest
    }
    _cache[id] = emails;
  }

  List<Email>? get(MailboxId id) => _cache[id];
}
```

### Strategy 2: Weak References for Large Objects

```dart
class AttachmentCache {
  final _cache = <AttachmentId, WeakReference<Uint8List>>{};

  Uint8List? get(AttachmentId id) {
    return _cache[id]?.target; // Null if GC'd
  }

  void set(AttachmentId id, Uint8List data) {
    _cache[id] = WeakReference(data);
  }
}
```

### Strategy 3: Pagination State

```dart
class EmailListController {
  static const pageSize = 50;
  final _currentPage = 0.obs;
  final _hasMore = true.obs;

  Future<void> loadMore() async {
    if (!_hasMore.value) return;

    final emails = await _useCase.execute(
      offset: _currentPage.value * pageSize,
      limit: pageSize,
    );

    if (emails.length < pageSize) {
      _hasMore.value = false;
    }

    _currentPage.value++;
  }
}
```

---

## State Synchronization

### Problem: Multiple Controllers, One Source of Truth

```
MailboxListController displays mailbox tree
EmailListController displays emails for selected mailbox
EmailDetailController displays single email

All need to react when mailbox selected
```

### Solution: Stream-Based Sync

```dart
// Repository (single source of truth)
class MailboxStateRepository {
  Mailbox? _selected;
  final _controller = StreamController<Mailbox?>.broadcast();

  Mailbox? get selected => _selected;
  Stream<Mailbox?> get selectedStream => _controller.stream;

  void select(Mailbox? m) {
    _selected = m;
    _controller.add(m); // Notify all listeners
  }
}

// Controllers subscribe
class MailboxListController {
  late StreamSubscription _sub;

  @override
  void onInit() {
    _sub = _mailboxState.selectedStream.listen((mailbox) {
      _highlightSelected(mailbox);
    });
  }

  @override
  void onClose() {
    _sub.cancel(); // Critical: prevent memory leak
  }
}

class EmailListController {
  late StreamSubscription _sub;

  @override
  void onInit() {
    _sub = _mailboxState.selectedStream.listen((mailbox) {
      if (mailbox != null) _loadEmails(mailbox);
    });
  }

  @override
  void onClose() {
    _sub.cancel();
  }
}
```

---

## View State Patterns

### Pattern 1: Either<Failure, Success> for Async Operations

```dart
class EmailListController {
  final viewState = Rx<Either<Failure, Success>>(Right(UIState.idle));

  Future<void> loadEmails() async {
    viewState.value = Right(LoadingState());

    final result = await _useCase.execute();

    result.fold(
      (failure) => viewState.value = Left(failure),
      (success) => viewState.value = Right(success),
    );
  }
}

// UI reacts
Obx(() {
  return viewState.value.fold(
    (failure) => ErrorWidget(failure),
    (success) {
      if (success is LoadingState) return LoadingWidget();
      if (success is LoadedState) return EmailList(success.emails);
      return SizedBox.shrink();
    },
  );
});
```

### Pattern 2: Loading/Error/Success States

```dart
class EmailListController {
  final isLoading = false.obs;
  final error = Rxn<String>();
  final emails = <Email>[].obs;

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;

    try {
      final result = await _useCase.execute();
      emails.value = result;
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }
}
```

### Pattern 3: Nullable State

```dart
class EmailDetailController {
  final email = Rxn<Email>(); // Reactive nullable

  void loadEmail(EmailId id) async {
    email.value = null; // Clear previous
    email.value = await _useCase.execute(id);
  }
}

// UI reacts
Obx(() {
  final e = email.value;
  if (e == null) return LoadingWidget();
  return EmailDetailWidget(e);
});
```

---

## Preventing Memory Leaks

### Common Leak Sources

1. **Unclosed StreamControllers**
2. **Uncancelled StreamSubscriptions**
3. **Undisposed ScrollControllers**
4. **Lingering timers**
5. **WebSocket connections**

### Prevention Checklist

```dart
class EmailListController extends GetxController {
  // Resources to dispose
  final _scrollController = ScrollController();
  StreamSubscription? _emailsSub;
  StreamSubscription? _mailboxSub;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    _emailsSub = _emailState.stream.listen(...);
    _mailboxSub = _mailboxState.stream.listen(...);
    _refreshTimer = Timer.periodic(...);
  }

  @override
  void onClose() {
    // Critical: dispose in reverse order of creation
    _refreshTimer?.cancel();
    _mailboxSub?.cancel();
    _emailsSub?.cancel();
    _scrollController.dispose();
    super.onClose();
  }
}
```

### Linter Rules

```yaml
# analysis_options.yaml
linter:
  rules:
    - cancel_subscriptions
    - close_sinks
    - avoid_web_libraries_in_flutter
```

---

## State Persistence (Optional)

### Save State on App Backgrounded

```dart
class EmailStateRepository {
  final _prefs = Get.find<SharedPreferences>();

  void saveState() {
    _prefs.setString('last_mailbox', selectedMailbox?.id.value);
    _prefs.setStringList('filter', filter.toJson());
  }

  void restoreState() {
    final mailboxId = _prefs.getString('last_mailbox');
    if (mailboxId != null) {
      selectedMailbox = Mailbox(id: MailboxId(Id(mailboxId)));
    }
  }
}

// App lifecycle
class App extends StatefulWidget {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      getIt<EmailStateRepository>().saveState();
    } else if (state == AppLifecycleState.resumed) {
      getIt<EmailStateRepository>().restoreState();
    }
  }
}
```

---

## Summary

| State Type | Lifecycle | Storage | Example |
|------------|-----------|---------|---------|
| UI State | Controller | In-memory (Rx) | isLoading, scrollOffset |
| App State | Repository | In-memory (Rx/Stream) | selectedMailbox, filter |
| Domain State | Repository | Cache + DB | Email lists, mailbox tree |
| Persisted State | Repository | SharedPreferences/Hive | User preferences |

**Key Rules**:
1. UI state → Controller (dies with screen)
2. Shared state → Repository (survives navigation)
3. Domain data → Data repository (cached + persisted)
4. Always dispose subscriptions/controllers in onClose()
5. Use streams for cross-controller sync
