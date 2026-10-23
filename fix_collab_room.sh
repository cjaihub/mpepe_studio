sed -i '' -e 's/!project.memberIds.contains/project.memberIds?.contains(senderId) != true/g' lib/backend/projects/services/collaborative_room_service.dart
sed -i '' -e '/Future<void> sendRoomMessage(dynamic project/,+4d' lib/backend/projects/services/collaborative_room_service.dart
echo "}" >> lib/backend/projects/services/collaborative_room_service.dart
