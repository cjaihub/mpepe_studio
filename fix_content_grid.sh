sed -i '' -e 's/  @override\n    final contentAsync = ref.watch(_userContentProvider(authorId));/  @override\n  Widget build(BuildContext context, WidgetRef ref) {\n    final contentAsync = ref.watch(_userContentProvider(authorId));/g' lib/social_hub/profile/public_profile_screen.dart

sed -i '' -e "s/analyticsAsync.valueOrNull/analyticsAsync.value/g" lib/social_hub/profile/public_profile_screen.dart

sed -i '' -e "s/AggregateField.sum('reactionCount')/sum('reactionCount')/g" lib/social_hub/profile/analytics_provider.dart

