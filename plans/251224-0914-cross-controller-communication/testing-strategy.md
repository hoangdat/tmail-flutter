# Testing Strategy

**Parent**: [Cross-Controller Communication Strategy](./plan.md)

---

## Repository Testing

### State Repository Tests

```dart
test('MailboxStateRepository emits selected mailbox', () {
  final repository = MailboxStateRepository();
  final testMailbox = Mailbox(id: '123', name: 'Inbox');

  // Expect stream emission
  expectLater(
    repository.selectedMailboxStream,
    emits(testMailbox),
  );

  // Trigger change
  repository.selectMailbox(testMailbox);
});

test('MailboxStateRepository supports multiple subscribers', () {
  final repository = MailboxStateRepository();
  final testMailbox = Mailbox(id: '123', name: 'Inbox');

  // Multiple listeners
  final listener1 = <Mailbox?>[];
  final listener2 = <Mailbox?>[];

  repository.selectedMailboxStream.listen(listener1.add);
  repository.selectedMailboxStream.listen(listener2.add);

  repository.selectMailbox(testMailbox);

  expect(listener1, [testMailbox]);
  expect(listener2, [testMailbox]);
});

test('MailboxStateRepository closes stream on dispose', () {
  final repository = MailboxStateRepository();

  repository.dispose();

  expect(
    () => repository.selectMailbox(testMailbox),
    throwsStateError, // Stream closed
  );
});
```

### Event Repository Tests

```dart
test('EmailRepository emits EmailSentEvent when email sent', () {
  final repository = EmailRepository();
  final testEmail = Email(id: '123');

  expectLater(
    repository.events,
    emits(isA<EmailSentEvent>()),
  );

  repository.sendEmail(testEmail);
});

test('EmailRepository emits DraftSavedEvent when draft saved', () {
  final repository = EmailRepository();

  expectLater(
    repository.events,
    emits(isA<DraftSavedEvent>()),
  );

  repository.saveDraft(EmailId('456'));
});
```

---

## Controller Testing (With Mock Repository)

### Testing with Mock Streams

```dart
test('EmailListController loads emails when mailbox selected', () {
  // Mock repository
  final mockMailboxState = MockMailboxStateRepository();
  final mailboxStream = StreamController<Mailbox?>.broadcast();

  when(mockMailboxState.selectedMailboxStream)
    .thenAnswer((_) => mailboxStream.stream);

  // Create controller with mock
  final controller = EmailListController(mockMailboxState);

  // Emit mailbox
  final testMailbox = Mailbox(id: '123', name: 'Inbox');
  mailboxStream.add(testMailbox);

  // Verify controller reacted
  expect(controller.currentMailbox, testMailbox);
  verify(controller.loadEmails(testMailbox)).called(1);
});

test('EmailListController cancels subscription on close', () {
  final mockMailboxState = MockMailboxStateRepository();
  final mailboxStream = StreamController<Mailbox?>.broadcast();

  when(mockMailboxState.selectedMailboxStream)
    .thenAnswer((_) => mailboxStream.stream);

  final controller = EmailListController(mockMailboxState);

  // Close controller
  controller.onClose();

  // Verify no memory leak (subscription cancelled)
  expect(controller.subscription.isPaused, isTrue);
});
```

### Testing Event Reactions

```dart
test('EmailListController refreshes when email sent', () {
  final mockEmailRepo = MockEmailRepository();
  final eventStream = StreamController<EmailEvent>.broadcast();

  when(mockEmailRepo.events).thenAnswer((_) => eventStream.stream);

  final controller = EmailListController(mockEmailRepo);

  // Emit event
  eventStream.add(EmailSentEvent(testEmail));

  // Verify refresh called
  verify(controller.refreshEmailList()).called(1);
});

test('EmailListController ignores non-EmailSentEvent', () {
  final mockEmailRepo = MockEmailRepository();
  final eventStream = StreamController<EmailEvent>.broadcast();

  when(mockEmailRepo.events).thenAnswer((_) => eventStream.stream);

  final controller = EmailListController(mockEmailRepo);

  // Emit different event
  eventStream.add(DraftSavedEvent(EmailId('123')));

  // Verify refresh NOT called
  verifyNever(controller.refreshEmailList());
});
```

---

## Integration Testing (Cross-Controller)

### Testing Controller Communication via Repository

```dart
testWidgets('Selecting mailbox updates email list', (tester) async {
  // Setup real repository (not mock)
  final mailboxState = MailboxStateRepository();
  final emailRepo = EmailRepository();

  // Setup DI (or provide directly)
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider.value(value: mailboxState),
          Provider.value(value: emailRepo),
        ],
        child: HomeScreen(),
      ),
    ),
  );

  // Navigate to mailbox list
  await tester.tap(find.text('Mailboxes'));
  await tester.pumpAndSettle();

  // Tap mailbox
  await tester.tap(find.text('Inbox'));
  await tester.pumpAndSettle();

  // Verify email list updated
  expect(find.byType(EmailListView), findsOneWidget);
  expect(find.text('Loading emails for Inbox'), findsOneWidget);
});

testWidgets('Sending email refreshes email list', (tester) async {
  // Setup repositories
  final emailRepo = EmailRepository();

  await tester.pumpWidget(
    MaterialApp(
      home: Provider.value(
        value: emailRepo,
        child: HomeScreen(),
      ),
    ),
  );

  // Open composer
  await tester.tap(find.byIcon(Icons.compose));
  await tester.pumpAndSettle();

  // Send email
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();

  // Verify email list refreshed
  expect(find.text('Email sent'), findsOneWidget);
  expect(find.byType(EmailListView), findsOneWidget);
});
```

---

## Test Improvement Metrics

### Before DI (GetX Service Locator)

```dart
test('EmailController loads emails', () {
  // Setup: 20+ Get.put() mocks
  Get.put<MailboxStateRepository>(mockMailboxState);
  Get.put<EmailRepository>(mockEmailRepo);
  Get.put<AuthService>(mockAuthService);
  Get.put<NetworkService>(mockNetworkService);
  // ... 16 more Get.put() calls

  final controller = EmailController(); // Hidden dependencies

  // Test logic...
});
```

**Problems**:
- 20+ mocks needed
- Hidden dependencies (not in constructor)
- Must mock entire GetX registry
- Test setup time: ~50 lines

### After DI (GetIt Constructor Injection)

```dart
test('EmailController loads emails', () {
  // Setup: 3 constructor mocks
  final controller = EmailController(
    mockMailboxState,  // Explicit!
    mockEmailRepo,     // Explicit!
    mockAuthService,   // Explicit!
  );

  // Test logic...
});
```

**Benefits**:
- 3 mocks (only what controller needs)
- Explicit dependencies (clear in constructor)
- No registry mocking
- Test setup time: ~10 lines (80% reduction)

---

## Memory Leak Testing

### Stream Disposal Tests

```dart
test('Repository closes streams on dispose', () async {
  final repository = MailboxStateRepository();

  // Subscribe to stream
  final subscription = repository.selectedMailboxStream.listen((_) {});

  // Dispose repository
  repository.dispose();

  // Wait for async disposal
  await Future.delayed(Duration.zero);

  // Verify stream closed
  expect(subscription.isPaused, isTrue);
});

test('Controller cancels subscriptions on close', () {
  final mockRepo = MockMailboxStateRepository();
  final streamController = StreamController<Mailbox?>.broadcast();

  when(mockRepo.selectedMailboxStream)
    .thenAnswer((_) => streamController.stream);

  final controller = EmailListController(mockRepo);

  // Get subscription
  final sub = controller.subscription;

  // Close controller
  controller.onClose();

  // Verify subscription cancelled
  expect(sub.isPaused, isTrue);
});
```

### Leak Detection (Integration)

```dart
testWidgets('No memory leaks when navigating screens', (tester) async {
  // Track active subscriptions
  final activeSubscriptions = <StreamSubscription>[];

  // Navigate through screens multiple times
  for (int i = 0; i < 10; i++) {
    await tester.tap(find.text('Email List'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
  }

  // Verify no subscription leaks
  expect(activeSubscriptions.length, 0);
});
```

---

## Test Coverage Goals

### Phase 3 (Architecture)

- Repository stream tests: 100%
- Controller subscription tests: 80%
- Integration tests: 5+ cross-controller scenarios
- Overall coverage: 70%

### Phase 4 (DI Migration)

- DI container tests: 100%
- Controller constructor injection tests: 90%
- Integration tests: 10+ scenarios
- Overall coverage: 75%

---

## CI/CD Test Gates

### Required Checks

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Code coverage ≥70% (Phase 3) or ≥75% (Phase 4)
- [ ] Zero memory leaks (leak detection tests)
- [ ] Zero Get.find() in new code (lint check)
- [ ] All streams properly closed (disposal tests)

### Test Execution Order

1. Unit tests (repositories, controllers) - Fast
2. Integration tests (cross-controller) - Medium
3. Widget tests (UI) - Slow
4. Memory leak tests - Slow

**Optimization**: Run in parallel, fail fast on unit test failures
