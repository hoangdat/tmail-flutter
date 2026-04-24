import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../models/test_tags.dart';
import '../../scenarios/send_email_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see success toast when send email successfully',
    shard: TestShard.noProvision,
    userSlot: 0,
    scenarioBuilder: ($, robots, credentials) => SendEmailScenario($, robots, credentials: credentials),
    tags: [TestTags.android, TestTags.ios, TestTags.web],
  );
}