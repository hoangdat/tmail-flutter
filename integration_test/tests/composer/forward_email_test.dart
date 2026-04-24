import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../scenarios/forward_email_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see HTML content contain enough: Subject, From, To, Cc, Bcc, Reply to',
    shard: TestShard.preloadedEmails,
    userSlot: 0,
    scenarioBuilder: ($, robots, credentials) => ForwardEmailScenario($, robots, credentials: credentials),
  );
}