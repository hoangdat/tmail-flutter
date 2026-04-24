import 'package:core/utils/config/env_loader.dart';
import 'package:core/utils/platform_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:tmail_ui_user/main/main_entry.dart';

import '../models/test_shard.dart';
import '../models/test_tags.dart';
import '../models/user_credentials.dart';
import 'base_scenario.dart';
import '../factories/robot_factory.dart';
import '../factories/robot_factory_provider.dart';

class TestBase {
  static final TestBase _instance = TestBase._internal();
  factory TestBase() => _instance;

  TestBase._internal();

  // SHARD dart-define is baked in at compile time — reliable on-device filtering.
  // patrol test --tags is not reliable for bundled APKs (all test files compile together).
  static const _runningShard = String.fromEnvironment('SHARD');

  void runPatrolTest({
    required String description,
    required BaseScenario Function(
      PatrolIntegrationTester $,
      RobotFactory robots,
      UserCredentials? credentials,
    ) scenarioBuilder,
    TestShard? shard,
    int userSlot = 0,
    List<TestTags> tags = const [TestTags.android, TestTags.ios],
  }) {
    // Skip tests that belong to a different shard than the one currently running.
    if (_runningShard.isNotEmpty && shard != null && shard.name != _runningShard) {
      test(description, () {}, skip: 'Skipped: shard=${shard.name}, running=$_runningShard');
      return;
    }

    patrolSetUp(_setup);

    patrolTearDown(_tearDown);

    final shardTag = shard?.tagName;
    final allTags = [
      ...tags.map((t) => t.name),
      if (shardTag != null) shardTag,
    ];

    patrolTest(
      description,
      config: const PatrolTesterConfig(
        settlePolicy: SettlePolicy.trySettle,
        visibleTimeout: Duration(seconds: 30),
        printLogs: true,
      ),
      tags: allTags,
      platformAutomatorConfig: PlatformAutomatorConfig.fromOptions(
        findTimeout: const Duration(seconds: 10),
      ),
      framePolicy: LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive,
      ($) async {
        await setupTest();
        final credentials = shard != null ? _resolveCredentials(shard, userSlot) : null;
        await scenarioBuilder($, createRobotFactory($), credentials).execute();
      },
    );
  }

  UserCredentials _resolveCredentials(TestShard shard, int userSlot) {
    const domain = String.fromEnvironment('DOMAIN', defaultValue: 'example.com');
    const hostUrl = String.fromEnvironment('BASIC_AUTH_URL');
    final slot = userSlot.toString().padLeft(3, '0');
    final username = '${shard.userPrefix}_$slot';
    return UserCredentials(
      email: '$username@$domain',
      username: username,
      password: username,
      hostUrl: hostUrl,
    );
  }

  Future<void> setupTest() async {
    await EnvLoader.loadEnvFile();
    await runTmail();

    final originalOnError = FlutterError.onError!;
    FlutterError.onError = (FlutterErrorDetails details) {
      originalOnError(details);
    };
  }

  Future<void> _setup() async {
    PlatformInfo.isIntegrationTesting = true;
  }

  Future<void> _tearDown() async {
    PlatformInfo.isIntegrationTesting = false;
  }
}