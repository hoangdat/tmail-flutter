import '../../base/test_base.dart';
import '../../models/test_shard.dart';
import '../../scenarios/mailbox/team_mailbox_receive_email_scenario.dart';

void main() {
  TestBase().runPatrolTest(
    description: 'Should see email in team mailbox INBOX after sending to team mailbox address',
    shard: TestShard.infra,
    userSlot: 1,
    scenarioBuilder: ($, robots, credentials) =>
        TeamMailboxReceiveEmailScenario($, robots, credentials: credentials),
  );
} 