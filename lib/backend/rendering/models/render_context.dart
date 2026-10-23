class RenderContext {
  final String cacheKey;
  final bool disableCache;
  final bool forceFullResolution;
  // This will hold project state versions, effect stack version etc
  final Map<String, dynamic> stateVersions;

  const RenderContext({
    required this.cacheKey,
    this.disableCache = false,
    this.forceFullResolution = false,
    this.stateVersions = const {},
  });
}
