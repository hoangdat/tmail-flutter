import 'dart:convert';

import 'package:core/domain/exceptions/app_base_exception.dart';
import 'package:core/utils/app_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:model/oidc/token_oidc.dart';
import 'package:tmail_ui_user/features/caching/clients/token_oidc_cache_client.dart';
import 'package:tmail_ui_user/features/login/data/extensions/token_oidc_cache_extension.dart';
import 'package:tmail_ui_user/features/login/data/local/token_oidc_cache_manager.dart';
import 'package:tmail_ui_user/features/login/domain/exceptions/authentication_exception.dart';

/// OIDC-token store backed by [FlutterSecureStorage] (iOS Keychain /
/// Android EncryptedSharedPreferences) instead of Hive.
///
/// Hive's append-only log can leave a half-written (block-misaligned) frame
/// when the OS kills the app mid-flush, which later fails AES-CBC decryption
/// and forces a logout. Secure-storage writes are atomic OS operations, so that
/// partial-write corruption class cannot occur.
///
/// Extends [TokenOidcCacheManager] and overrides every public storage method so
/// it is a drop-in replacement: existing callers keep their `TokenOidcCacheManager`
/// type and resolve this implementation via DI. The legacy Hive client is kept
/// only for the one-time [migrateHiveTokenToSecureStorage] migration.
class TokenOidcSecureStorageManager extends TokenOidcCacheManager {
  static const String _keyPrefix = 'token_oidc_';

  final FlutterSecureStorage _secureStorage;
  final TokenOidcCacheClient _legacyHiveClient;

  TokenOidcSecureStorageManager(
    this._secureStorage,
    TokenOidcCacheClient legacyHiveClient,
  )   : _legacyHiveClient = legacyHiveClient,
        super(legacyHiveClient);

  String _storageKey(String key) => '$_keyPrefix$key';

  @override
  Future<TokenOIDC> getTokenOidc(String tokenIdHash) async {
    try {
      final raw = await _secureStorage.read(key: _storageKey(tokenIdHash));
      if (raw == null || raw.isEmpty) {
        // Not in secure storage yet. After an app update the token may still
        // live only in the legacy Hive box if this read races ahead of the
        // one-time migration — recover it on demand so the user is not signed
        // out. Returns null when Hive has nothing (or is corrupted).
        final recovered = await _recoverFromLegacyHive(tokenIdHash);
        if (recovered != null) {
          return recovered;
        }
        throw NotFoundStoredTokenException();
      }
      return TokenOIDC.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on AppBaseException {
      rethrow;
    } catch (e, stackTrace) {
      // Secure-storage read failed (e.g. Android Keystore key loss after an OS
      // upgrade, or a value we can no longer decode). Drop the unreadable entry
      // so the next read starts clean and triggers normal re-authentication
      // instead of looping.
      logError(
        'TokenOidcSecureStorageManager::getTokenOidc(): '
        'token_unreadable=true | error_type=${e.runtimeType} | clearing entry',
        exception: e,
        stackTrace: stackTrace,
      );
      await _safelyDelete(_storageKey(tokenIdHash));
      throw NotFoundStoredTokenException();
    }
  }

  @override
  Future<void> persistOneTokenOidc(TokenOIDC tokenOIDC) =>
      _writeToken(tokenOIDC.tokenIdHash, tokenOIDC);

  @override
  Future<void> persistOneTokenOidcAt(String key, TokenOIDC tokenOIDC) =>
      _writeToken(key, tokenOIDC);

  Future<void> _writeToken(String key, TokenOIDC tokenOIDC) async {
    await _secureStorage.write(
      key: _storageKey(key),
      value: jsonEncode(tokenOIDC.toJson()),
    );
    // Keep exactly one current token, matching the legacy single-token cache.
    await _pruneOtherTokens(keepStorageKey: _storageKey(key));
  }

  Future<void> _pruneOtherTokens({required String keepStorageKey}) async {
    try {
      final all = await _secureStorage.readAll();
      final staleKeys = all.keys.where(
        (k) => k.startsWith(_keyPrefix) && k != keepStorageKey,
      );
      for (final key in staleKeys) {
        await _secureStorage.delete(key: key);
      }
    } catch (e) {
      logWarning('TokenOidcSecureStorageManager::_pruneOtherTokens(): $e');
    }
  }

  @override
  Future<void> clear() async {
    final all = await _secureStorage.readAll();
    final tokenKeys = all.keys.where((k) => k.startsWith(_keyPrefix));
    for (final key in tokenKeys) {
      await _secureStorage.delete(key: key);
    }
  }

  /// On-demand recovery of a single token from the legacy Hive box, promoting it
  /// into secure storage so subsequent reads are served from there. Best-effort:
  /// a corrupted or empty Hive box yields null (the caller then re-authenticates).
  Future<TokenOIDC?> _recoverFromLegacyHive(String key) async {
    try {
      final legacy = await _legacyHiveClient.getItem(key);
      if (legacy == null) return null;
      final token = legacy.toTokenOidc();
      await _writeToken(key, token);
      log('TokenOidcSecureStorageManager::_recoverFromLegacyHive(): '
          'promoted legacy Hive token → secure storage');
      return token;
    } catch (e) {
      logWarning('TokenOidcSecureStorageManager::_recoverFromLegacyHive(): $e');
      return null;
    }
  }

  /// One-time migration of any token already stored in the legacy Hive box into
  /// secure storage, so existing logged-in users are not signed out by the
  /// storage switch. Best-effort: a corrupted or empty Hive box is swallowed —
  /// such a user re-authenticates once and never hits the corruption again.
  Future<void> migrateHiveTokenToSecureStorage() async {
    try {
      final existing = await _secureStorage.readAll();
      final alreadyMigrated =
          existing.keys.any((k) => k.startsWith(_keyPrefix));
      if (alreadyMigrated) {
        log('TokenOidcSecureStorageManager::migrateHiveTokenToSecureStorage(): '
            'secure storage already has a token, skipping');
        return;
      }

      final legacyItems = await _legacyHiveClient.getMapItems();
      if (legacyItems.isEmpty) return;

      for (final entry in legacyItems.entries) {
        await _secureStorage.write(
          key: _storageKey(entry.key),
          value: jsonEncode(entry.value.toTokenOidc().toJson()),
        );
      }
      log('TokenOidcSecureStorageManager::migrateHiveTokenToSecureStorage(): '
          '✅ migrated ${legacyItems.length} token(s) Hive → secure storage');
      await _legacyHiveClient.clearAllData();
    } catch (e) {
      logWarning(
        'TokenOidcSecureStorageManager::migrateHiveTokenToSecureStorage(): '
        '❌ migration skipped (non-fatal) | error_type=${e.runtimeType} | $e',
      );
    }
  }

  /// Token is no longer kept in Hive, so the Hive→IsolatedHive migration is moot.
  @override
  Future<void> migrateHiveToIsolatedHive() async {}

  Future<void> _safelyDelete(String storageKey) async {
    try {
      await _secureStorage.delete(key: storageKey);
    } catch (e) {
      logWarning('TokenOidcSecureStorageManager::_safelyDelete(): $e');
    }
  }
}
