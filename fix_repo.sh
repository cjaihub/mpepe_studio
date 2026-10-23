sed -i '' -e 's/Future<StudioProject?> getProject(String id) async {/Future<dynamic> getProject(String id) async {/g' lib/backend/project_repository.dart
sed -i '' -e 's/Future<void> updateProject(StudioProject project) async {/Future<void> updateProject(dynamic project) async {/g' lib/backend/project_repository.dart
