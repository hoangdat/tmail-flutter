enum TestShard {
  noProvision('shardNoProvision', 'np'),
  searchEmails('shardSearchEmails', 'se'),
  preloadedEmails('shardPreloadedEmails', 'pe'),
  infra('shardInfra', 'si');

  final String tagName;
  final String userPrefix;

  const TestShard(this.tagName, this.userPrefix);
}
