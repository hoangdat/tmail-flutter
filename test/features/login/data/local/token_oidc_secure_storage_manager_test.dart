import 'package:flutter_test/flutter_test.dart';
import 'package:model/oidc/token_id.dart';
import 'package:model/oidc/token_oidc.dart';
import 'package:tmail_ui_user/features/login/data/extensions/token_oidc_extension.dart';
import 'package:tmail_ui_user/features/login/data/local/token_oidc_secure_storage_manager.dart';
import 'package:tmail_ui_user/features/login/domain/exceptions/authentication_exception.dart';

import 'in_memory_secure_storage.dart';
import 'memory_token_oidc_cache_client.dart';

void main() {
  final validToken = TokenOIDC(
    'access-token-abc',
    TokenId('token-id-123'),
    'refresh-token-xyz',
    expiredTime: DateTime(2099),
  );

  late InMemorySecureStorage secureStorage;
  late MemoryTokenOidcCacheClient legacyHiveClient;
  late TokenOidcSecureStorageManager manager;

  setUp(() {
    secureStorage = InMemorySecureStorage();
    legacyHiveClient = MemoryTokenOidcCacheClient();
    manager = TokenOidcSecureStorageManager(secureStorage, legacyHiveClient);
  });

  group('getTokenOidc', () {
    test('WHEN secure storage is empty\n'
        'THEN throws NotFoundStoredTokenException', () async {
      await expectLater(
        manager.getTokenOidc('any-hash'),
        throwsA(isA<NotFoundStoredTokenException>()),
      );
    });

    test('WHEN a token was persisted\n'
        'THEN returns the same TokenOIDC', () async {
      await manager.persistOneTokenOidc(validToken);

      final result = await manager.getTokenOidc(validToken.tokenIdHash);

      expect(result.token, validToken.token);
      expect(result.tokenId.uuid, validToken.tokenId.uuid);
      expect(result.refreshToken, validToken.refreshToken);
      expect(result.expiredTime, validToken.expiredTime);
    });

    test('WHEN a different key is requested\n'
        'THEN throws NotFoundStoredTokenException', () async {
      await manager.persistOneTokenOidc(validToken);

      await expectLater(
        manager.getTokenOidc('other-hash'),
        throwsA(isA<NotFoundStoredTokenException>()),
      );
    });

    test('WHEN secure-storage read throws (e.g. Android Keystore loss)\n'
        'THEN clears the entry and throws NotFoundStoredTokenException', () async {
      await manager.persistOneTokenOidc(validToken);
      secureStorage.throwOnRead = true;

      await expectLater(
        manager.getTokenOidc(validToken.tokenIdHash),
        throwsA(isA<NotFoundStoredTokenException>()),
      );

      secureStorage.throwOnRead = false;
      expect(secureStorage.store.keys.any((k) => k.startsWith('token_oidc_')),
          isFalse,
          reason: 'unreadable entry must be cleared so the next read is clean');
    });
  });

  group('getTokenOidc — legacy Hive fallback (no logout on update)', () {
    test('WHEN secure storage is empty but the legacy Hive box has the token\n'
        'THEN it is recovered, returned, and promoted to secure storage',
        () async {
      await legacyHiveClient.insertItem(
        validToken.tokenIdHash,
        validToken.toTokenOidcCache(),
      );

      final result = await manager.getTokenOidc(validToken.tokenIdHash);
      expect(result.token, validToken.token,
          reason: 'token must be recovered from Hive instead of logging out');

      // Subsequent read served from secure storage even after Hive is wiped.
      await legacyHiveClient.clearAllData();
      final secondRead = await manager.getTokenOidc(validToken.tokenIdHash);
      expect(secondRead.token, validToken.token);
      expect(
        secureStorage.store.keys
            .where((k) => k.startsWith('token_oidc_'))
            .length,
        1,
        reason: 'recovered token must be promoted into secure storage',
      );
    });

    test('WHEN both secure storage and the legacy Hive box are empty\n'
        'THEN throws NotFoundStoredTokenException', () async {
      await expectLater(
        manager.getTokenOidc('missing-hash'),
        throwsA(isA<NotFoundStoredTokenException>()),
      );
    });
  });

  group('persist — single-token semantics', () {
    test('WHEN a new token is persisted\n'
        'THEN the previous token entry is pruned', () async {
      final oldToken = TokenOIDC(
        'old-access',
        TokenId('old-id'),
        'old-refresh',
        expiredTime: DateTime(2099),
      );
      final newToken = TokenOIDC(
        'new-access',
        TokenId('new-id'),
        'new-refresh',
        expiredTime: DateTime(2099),
      );

      await manager.persistOneTokenOidc(oldToken);
      await manager.persistOneTokenOidc(newToken);

      final tokenKeys = secureStorage.store.keys
          .where((k) => k.startsWith('token_oidc_'))
          .toList();
      expect(tokenKeys.length, 1, reason: 'only the latest token is kept');

      final result = await manager.getTokenOidc(newToken.tokenIdHash);
      expect(result.token, newToken.token);

      await expectLater(
        manager.getTokenOidc(oldToken.tokenIdHash),
        throwsA(isA<NotFoundStoredTokenException>()),
      );
    });

    test('WHEN persistOneTokenOidcAt is used with an explicit key\n'
        'THEN getTokenOidc resolves it by that key', () async {
      await manager.persistOneTokenOidcAt('explicit-key', validToken);

      final result = await manager.getTokenOidc('explicit-key');
      expect(result.token, validToken.token);
    });
  });

  group('clear', () {
    test('WHEN clear is called\n'
        'THEN all token entries are removed but other keys remain', () async {
      await manager.persistOneTokenOidc(validToken);
      secureStorage.store['unrelated_key'] = 'keep-me';

      await manager.clear();

      expect(secureStorage.store.keys.any((k) => k.startsWith('token_oidc_')),
          isFalse);
      expect(secureStorage.store['unrelated_key'], 'keep-me',
          reason: 'clear must only touch token_oidc_* keys');
    });
  });

  group('migrateHiveTokenToSecureStorage', () {
    test('WHEN a token exists in the legacy Hive box and secure storage is empty\n'
        'THEN it is copied to secure storage and the Hive box is cleared',
        () async {
      await legacyHiveClient.insertItem(
        validToken.tokenIdHash,
        validToken.toTokenOidcCache(),
      );

      await manager.migrateHiveTokenToSecureStorage();

      final result = await manager.getTokenOidc(validToken.tokenIdHash);
      expect(result.token, validToken.token);

      final remaining = await legacyHiveClient.getAll();
      expect(remaining, isEmpty,
          reason: 'legacy Hive box must be cleared after migration');
    });

    test('WHEN secure storage already holds a token\n'
        'THEN migration is skipped and the existing token is untouched',
        () async {
      await manager.persistOneTokenOidc(validToken);
      final otherToken = TokenOIDC(
        'legacy-access',
        TokenId('legacy-id'),
        'legacy-refresh',
        expiredTime: DateTime(2099),
      );
      await legacyHiveClient.insertItem('legacy-id', otherToken.toTokenOidcCache());

      await manager.migrateHiveTokenToSecureStorage();

      // Existing secure-storage token is untouched...
      final result = await manager.getTokenOidc(validToken.tokenIdHash);
      expect(result.token, validToken.token);
      // ...and migration was skipped, so the legacy Hive box was NOT cleared.
      final legacyRemaining = await legacyHiveClient.getAll();
      expect(legacyRemaining, isNotEmpty,
          reason: 'migration must skip (not clear Hive) when a token already exists');
    });

    test('WHEN the legacy Hive read throws (corrupted box)\n'
        'THEN migration is swallowed and completes without throwing', () async {
      legacyHiveClient.throwOnGetMapItems = true;

      await expectLater(
        manager.migrateHiveTokenToSecureStorage(),
        completes,
      );
    });
  });
}
