enum PrivacyMode {
  public,
  followers,
  connections,
  specificUsers,
  private,
  onlyMe
}

enum EncryptionMode {
  standard,
  e2ee
}

enum AiAccessMode {
  never,
  askEveryTime,
  allowed
}

enum RetentionPolicy {
  twentyFourHours,
  sevenDays,
  thirtyDays,
  forever
}

enum MediaPolicy {
  standard,
  preventDownloads,
  viewOnce
}
