import 'package:tmail_ui_user/features/base/upgradeable/upgrade_database_steps.dart';
import 'package:tmail_ui_user/features/caching/caching_manager.dart';

/// Moves the stored OIDC token out of the encrypted Hive box and into secure
/// storage (iOS Keychain / Android EncryptedSharedPreferences), so existing
/// logged-in users keep their session after the storage switch.
class UpgradeHiveDatabaseStepsV23 extends UpgradeDatabaseSteps {
  final CachingManager _cachingManager;

  UpgradeHiveDatabaseStepsV23(this._cachingManager);

  @override
  Future<void> onUpgrade(int oldVersion, int newVersion) async {
    if (_shouldUpgrade(oldVersion, newVersion)) {
      await _cachingManager.migrateTokenOidcToSecureStorage();
    }
  }

  bool _shouldUpgrade(int oldVersion, int newVersion) =>
      oldVersion > 0 && oldVersion < newVersion && newVersion == 23;
}
