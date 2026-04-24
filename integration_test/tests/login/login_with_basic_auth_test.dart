import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../models/test_tags.dart';
import '../../scenarios/login_with_basic_auth_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see thread view when login with basic auth successfully',
    shard: TestShard.noProvision,
    userSlot: 1,
    scenarioBuilder: ($, robots, credentials) =>
        LoginWithBasicAuthScenario($, robots, credentials: credentials),
    tags: [TestTags.android, TestTags.ios, TestTags.web],
  );
}