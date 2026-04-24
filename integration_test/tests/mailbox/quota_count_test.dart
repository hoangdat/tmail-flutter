import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../scenarios/mailbox/quota_count_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see quota increase when send email successfully',
    shard: TestShard.infra,
    userSlot: 0,
    scenarioBuilder: ($, robots, credentials) => QuotaCountScenario($, robots, credentials: credentials),
  );
}