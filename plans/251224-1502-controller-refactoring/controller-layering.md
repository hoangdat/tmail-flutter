# Controller Layering Architecture

**Parent**: [Controller Refactoring Plan](./plan.md)

---

## Overview

Four-layer architecture with clear separation of concerns:
- **Presentation Layer** - UI Controllers (view logic only)
- **Application Layer** - State Repositories (state + streams)
- **Domain Layer** - Use Cases (business logic)
- **Data Layer** - Data Repositories (API + cache)

---

## Layer 1: Presentation Layer (UI Controllers)

### Responsibilities
- Handle UI events (tap, scroll, input)
- Subscribe to state streams
- Update view state (Rx observables)
- Coordinate multiple use cases
- NO business logic
- NO direct controller communication
- NO direct data access

### Characteristics
- **Size**: <200 lines (max 250 for complex UI)
- **Lifecycle**: Factory (new instance per route)
- **Dependencies**: State repositories, use cases (constructor-injected)
- **State**: View-only state (loading, error, selected items)

### Example Structure

```dart
class EmailListController extends BaseController {
  // Dependencies (constructor-injected)
  final EmailStateRepository _emailState;
  final MailboxStateRepository _mailboxState;
  final GetEmailsUseCase _getEmailsUseCase;
  final MarkEmailReadUseCase _markEmailReadUseCase;

  // View state (UI-only concerns)
  final isLoading = false.obs;
  final selectedEmails = <Email>[].obs;
  final scrollController = ScrollController();

  // Stream subscriptions
  late StreamSubscription _emailsSub;
  late StreamSubscription _mailboxSub;

  EmailListController(
    this._emailState,
    this._mailboxState,
    this._getEmailsUseCase,
    this._markEmailReadUseCase,
  );

  @override
  void onInit() {
    super.onInit();
    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    // React to mailbox changes
    _mailboxSub = _mailboxState.selectedMailboxStream.listen((mailbox) {
      if (mailbox != null) _loadEmails(mailbox);
    });

    // React to email state changes
    _emailsSub = _emailState.emailsStream.listen((emails) {
      update(); // Rebuild UI
    });
  }

  // UI event handlers
  Future<void> _loadEmails(Mailbox mailbox) async {
    isLoading.value = true;
    await _getEmailsUseCase.execute(mailbox.id);
    isLoading.value = false;
  }

  void onEmailTap(Email email) {
    _markEmailReadUseCase.execute(email.id);
  }

  void onEmailLongPress(Email email) {
    selectedEmails.add(email);
  }

  @override
  void onClose() {
    _emailsSub.cancel();
    _mailboxSub.cancel();
    scrollController.dispose();
    super.onClose();
  }
}
```

### Controller Types by Responsibility

#### 1. List Controllers
**Purpose**: Display paginated lists
**Examples**: EmailListController, MailboxListController
**Responsibilities**:
- Load initial data
- Pagination (load more)
- Pull-to-refresh
- Item selection
- Scroll position

#### 2. Form Controllers
**Purpose**: Handle form input/validation
**Examples**: ComposerController, SearchController
**Responsibilities**:
- Input validation
- Form state management
- Submit handling
- Error display

#### 3. Detail Controllers
**Purpose**: Display single item details
**Examples**: EmailDetailController, MailboxDetailController
**Responsibilities**:
- Load item details
- Handle item actions
- Navigate to edit/delete

#### 4. Navigation Controllers
**Purpose**: Coordinate screen navigation
**Examples**: DashboardController (refactored)
**Responsibilities**:
- Route management
- Screen transitions
- Deep linking

---

## Layer 2: Application Layer (State Repositories)

### Responsibilities
- Own canonical state (single source of truth)
- Expose streams for state changes
- Coordinate domain use cases
- NO UI knowledge
- NO direct data access (via repositories)

### Characteristics
- **Lifecycle**: Singleton (app lifetime)
- **Dependencies**: Domain use cases, data repositories
- **State**: Business state (selected items, filters, etc.)
- **Streams**: Broadcast streams for state propagation

### Repository Types

#### 1. State Repositories (UI State)
Own UI-related state shared across controllers

```dart
class MailboxStateRepository {
  // Private state
  Mailbox? _selectedMailbox;
  MailboxFilter _filter = MailboxFilter.all;

  // Broadcast streams
  final _selectedMailboxController = StreamController<Mailbox?>.broadcast();
  Stream<Mailbox?> get selectedMailboxStream => _selectedMailboxController.stream;

  final _filterController = StreamController<MailboxFilter>.broadcast();
  Stream<MailboxFilter> get filterStream => _filterController.stream;

  // Getters (current value)
  Mailbox? get selectedMailbox => _selectedMailbox;
  MailboxFilter get filter => _filter;

  // State mutations (emit to streams)
  void selectMailbox(Mailbox? mailbox) {
    _selectedMailbox = mailbox;
    _selectedMailboxController.add(mailbox);
  }

  void setFilter(MailboxFilter filter) {
    _filter = filter;
    _filterController.add(filter);
  }

  void dispose() {
    _selectedMailboxController.close();
    _filterController.close();
  }
}
```

**Examples**:
- `MailboxStateRepository` - Selected mailbox, filter, tree expansion
- `EmailStateRepository` - Email list, selection, sort order
- `SearchStateRepository` - Query, filters, results
- `ComposerStateRepository` - Draft state, recipient list

#### 2. Data Repositories (Business Data)
Fetch/cache/persist business data

```dart
class EmailRepository {
  final EmailDataSource _remoteDataSource;
  final EmailCache _localCache;

  EmailRepository(this._remoteDataSource, this._localCache);

  // Offline-first pattern
  Stream<List<Email>> getEmailsForMailbox(MailboxId id) async* {
    // Emit cached first
    yield await _localCache.getEmails(id);

    // Fetch from server
    final emails = await _remoteDataSource.fetchEmails(id);

    // Update cache
    await _localCache.saveEmails(emails);

    // Emit fresh data
    yield emails;
  }

  Future<void> markAsRead(EmailId id) async {
    await _remoteDataSource.markAsRead(id);
    await _localCache.updateEmailFlag(id, isRead: true);
  }
}
```

**Examples**:
- `MailboxRepository` - CRUD for mailboxes
- `EmailRepository` - CRUD for emails
- `AccountRepository` - Account management
- `AttachmentRepository` - Attachment handling

---

## Layer 3: Domain Layer (Use Cases)

### Responsibilities
- Implement business logic
- Coordinate repositories
- Validate business rules
- Return Either<Failure, Success>
- NO UI knowledge
- NO framework dependencies

### Characteristics
- **Size**: Single-purpose, focused
- **Lifecycle**: Singleton or factory
- **Dependencies**: Data repositories only
- **Return**: Either<Failure, Success> for error handling

### Use Case Pattern

```dart
class GetEmailsUseCase {
  final EmailRepository _emailRepository;
  final EmailStateRepository _emailState;

  GetEmailsUseCase(this._emailRepository, this._emailState);

  Future<Either<Failure, Success>> execute(MailboxId mailboxId) async {
    try {
      await for (final emails in _emailRepository.getEmailsForMailbox(mailboxId)) {
        _emailState.setEmails(emails); // Update state repository
      }
      return Right(GetEmailsSuccess(emails));
    } catch (e) {
      return Left(GetEmailsFailure(e));
    }
  }
}
```

### Use Case Examples

| Use Case | Repositories | Logic |
|----------|-------------|-------|
| `GetEmailsUseCase` | EmailRepository, EmailStateRepository | Fetch emails, update state |
| `MarkEmailReadUseCase` | EmailRepository, EmailStateRepository | Mark read, update cache |
| `SendEmailUseCase` | EmailRepository, DraftRepository | Validate, send, cleanup |
| `SelectMailboxUseCase` | MailboxStateRepository | Update selected mailbox |

---

## Layer 4: Data Layer (Data Sources)

### Responsibilities
- API communication (JMAP)
- Local caching (Hive)
- Data transformation (DTO ↔ Domain)
- NO business logic
- NO UI knowledge

### Data Source Types

#### Remote Data Source
```dart
class EmailRemoteDataSource {
  final JmapClient _jmapClient;

  Future<List<EmailDTO>> fetchEmails(MailboxId id) async {
    final response = await _jmapClient.getEmails(id);
    return response.list.map((e) => EmailDTO.fromJmap(e)).toList();
  }
}
```

#### Local Cache
```dart
class EmailLocalCache {
  final HiveInterface _hive;

  Future<List<Email>> getEmails(MailboxId id) async {
    final box = await _hive.openBox<EmailDTO>('emails');
    return box.values
        .where((e) => e.mailboxId == id)
        .map((dto) => dto.toDomain())
        .toList();
  }
}
```

---

## Communication Between Layers

### Allowed Dependencies

```
Presentation Layer
    ↓ (inject)
Application Layer (State Repositories)
    ↓ (inject)
Domain Layer (Use Cases)
    ↓ (inject)
Data Layer (Repositories)
```

### Prohibited Dependencies

❌ Presentation → Data (skip layers)
❌ Domain → Application (reverse dependency)
❌ Data → Domain (reverse dependency)
❌ Presentation → Presentation (controller ↔ controller)

### Communication Patterns

#### Pattern 1: User Action → State Update
```
User taps email
    ↓
EmailListController.onEmailTap(email)
    ↓
MarkEmailReadUseCase.execute(emailId)
    ↓
EmailRepository.markAsRead(emailId)
    ↓
EmailStateRepository.updateEmail(email.copyWith(isRead: true))
    ↓
EmailStateRepository.emailsStream emits updated list
    ↓
EmailListController rebuilds UI
```

#### Pattern 2: Cross-Controller Communication
```
MailboxListController.selectMailbox(mailbox)
    ↓
MailboxStateRepository.selectMailbox(mailbox)
    ↓
selectedMailboxStream emits mailbox
    ↓
EmailListController listening to stream
    ↓
EmailListController.loadEmails(mailbox)
```

---

## GetIt Dependency Injection Setup

```dart
final getIt = GetIt.instance;

void setupDI() {
  // Data Layer (Singletons)
  getIt.registerSingleton<EmailRemoteDataSource>(EmailRemoteDataSource());
  getIt.registerSingleton<EmailLocalCache>(EmailLocalCache());

  // Data Repositories (Singletons)
  getIt.registerSingleton<EmailRepository>(
    EmailRepository(getIt(), getIt()),
  );

  // Application Layer - State Repositories (Singletons)
  getIt.registerSingleton<EmailStateRepository>(EmailStateRepository());
  getIt.registerSingleton<MailboxStateRepository>(MailboxStateRepository());

  // Domain Layer - Use Cases (Singletons)
  getIt.registerSingleton<GetEmailsUseCase>(
    GetEmailsUseCase(getIt(), getIt()),
  );
  getIt.registerSingleton<MarkEmailReadUseCase>(
    MarkEmailReadUseCase(getIt(), getIt()),
  );

  // Presentation Layer - Controllers (Factories)
  getIt.registerFactory<EmailListController>(
    () => EmailListController(getIt(), getIt(), getIt(), getIt()),
  );
  getIt.registerFactory<MailboxListController>(
    () => MailboxListController(getIt(), getIt()),
  );
}
```

---

## Summary

| Layer | Responsibility | Size | Lifecycle | Dependencies |
|-------|---------------|------|-----------|--------------|
| Presentation | UI events, view state | <200 lines | Factory | State repos, use cases |
| Application | Shared state, streams | 100-200 lines | Singleton | Use cases, data repos |
| Domain | Business logic | 50-100 lines | Singleton | Data repos |
| Data | API, cache | 100-200 lines | Singleton | None |

**Key Benefit**: Clear separation → testable, maintainable, scalable
