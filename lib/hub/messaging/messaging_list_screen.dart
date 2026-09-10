import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/user_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class MessagingListScreen extends ConsumerWidget {
  const MessagingListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final chatsAsync = ref.watch(userChatsProvider(currentUserId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment, color: Colors.orange),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const NewChatDialog(),
              );
            },
          )
        ],
      ),
      body: chatsAsync.when(
        data: (chats) {
          if (chats.isEmpty) {
            return const Center(
              child: Text('No messages yet', style: TextStyle(color: Colors.white70)),
            ).animate().fade().scale();
          }
          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final unreadCount = chat.unreadCounts[currentUserId] ?? 0;
              final otherParticipants = chat.participants.where((p) => p != currentUserId).toList();
              final chatTitle = otherParticipants.isNotEmpty ? 'User ${otherParticipants.first.substring(0, 5)}' : 'Unknown';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: Colors.orange),
                ),
                title: Text(chatTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text(
                  chat.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: unreadCount > 0 ? Colors.white : Colors.white70),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (chat.lastMessageTime != null)
                      Text(
                        timeago.format(chat.lastMessageTime!.toDate(), locale: 'en_short'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    if (unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  context.push('/hub/messages/${chat.id}');
                },
              ).animate().fade(delay: (50 * index).ms).slideX();
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
        error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }
}


class NewChatDialog extends ConsumerStatefulWidget {
  const NewChatDialog({super.key});

  @override
  ConsumerState<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends ConsumerState<NewChatDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUserSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _createChat(List<String> participants) async {
    if (participants.length < 2) return;
    
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.createChat(participants);
      if (mounted) {
        Navigator.pop(context); // close dialog
        context.push('/hub/messages/$chatId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final usersAsync = ref.watch(userProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        decoration: BoxDecoration(
          color: Colors.grey[900]?.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.maps_ugc_rounded, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    const Text('New Chat', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search team members...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                ),
              ),

              // User List
              Expanded(
                child: usersAsync.when(
                  data: (users) {
                    final otherUsers = users.where((u) {
                      if (u.id == currentUserId) return false;
                      if (_searchQuery.isEmpty) return true;
                      return u.fullName.toLowerCase().contains(_searchQuery) || u.email.toLowerCase().contains(_searchQuery);
                    }).toList();
                    
                    if (otherUsers.isEmpty) {
                      return const Center(
                        child: Text('No members found.', style: TextStyle(color: Colors.white54)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: otherUsers.length,
                      itemBuilder: (context, index) {
                        final user = otherUsers[index];
                        final isSelected = _selectedUserIds.contains(user.id);
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.orange.withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Colors.orange.withValues(alpha: 0.5) : Colors.transparent,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: isSelected ? Colors.orange : Colors.grey[800],
                                  child: Text(
                                    user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?', 
                                    style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
                                      child: const Icon(Icons.check_circle, color: Colors.orange, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(user.fullName.isNotEmpty ? user.fullName : user.email, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(user.role, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            onTap: () {
                              if (_selectedUserIds.isEmpty) {
                                // Direct 1-on-1 chat if nothing selected yet
                                if (currentUserId != null) {
                                  _createChat([currentUserId, user.id]);
                                }
                              } else {
                                // Multi-select mode
                                _toggleUserSelection(user.id);
                              }
                            },
                            onLongPress: () {
                              _toggleUserSelection(user.id);
                            },
                            trailing: _selectedUserIds.isNotEmpty
                                ? Checkbox(
                                    value: isSelected,
                                    activeColor: Colors.orange,
                                    checkColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (_) => _toggleUserSelection(user.id),
                                  )
                                : null,
                          ),
                        ).animate().fade(duration: 200.ms, delay: (index * 20).ms).slideX(begin: 0.05, end: 0);
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: Colors.orange)),
                  error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
                ),
              ),

              // Bottom Actions
              if (_selectedUserIds.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                  ),
                  child: Row(
                    children: [
                      Text('${_selectedUserIds.length} selected', style: const TextStyle(color: Colors.white70)),
                      const Spacer(),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.group_add),
                          label: Text(_isLoading ? 'Creating...' : 'Create Group Chat', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _isLoading ? null : () {
                            if (currentUserId != null) {
                              final participants = [currentUserId, ..._selectedUserIds];
                              _createChat(participants);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ).animate().slideY(begin: 1.0, end: 0.0, curve: Curves.easeOutExpo),
            ],
          ),
        ),
      ),
    );
  }
}
