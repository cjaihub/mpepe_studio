import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math';

import '../../backend/messaging_repository.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';
import 'user_search_screen.dart';
import 'create_group_screen.dart';

class InAppMessagingScreen extends ConsumerStatefulWidget {
  const InAppMessagingScreen({super.key});

  @override
  ConsumerState<InAppMessagingScreen> createState() => _InAppMessagingScreenState();
}

class _InAppMessagingScreenState extends ConsumerState<InAppMessagingScreen> with SingleTickerProviderStateMixin {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  late TabController _tabController;
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openNewChatSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchScreen(),
    );
  }

  void _openCreateGroup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateGroupScreen(),
    );
  }

  Widget _buildOnlineUsersHorizontalList() {
    // For now, we simulate online friends with a static count to match the reference design.
    // In a real scenario, this would query a presence system.
    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 10,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final isOnline = Random().nextBool(); // Random online status for demo
          final avatarUrl = 'https://i.pravatar.cc/150?u=$index';
          
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.darkSurfaceHighlight,
                      backgroundImage: NetworkImage(avatarUrl),
                    ),
                    if (isOnline)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent[400],
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.darkBackground, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ).animate().scale(delay: Duration(milliseconds: index * 50)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: Text("Please sign in to view messages.", style: TextStyle(color: Colors.white))),
      );
    }

    final chatsAsync = ref.watch(userChatsProvider(currentUserId!));

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              )
            : Text('Messages', style: AppTheme.h1Style.copyWith(fontSize: 26, fontWeight: FontWeight.w900)),
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white, size: 28),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 28),
            onPressed: _openCreateGroup,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Online Users Horizontal List
          _buildOnlineUsersHorizontalList(),
          
          const SizedBox(height: 10),
          
          // Tab Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(25),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.mpepeMaroon,
                  borderRadius: BorderRadius.circular(25),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Friends'),
                  Tab(text: 'Groups'),
                  Tab(text: 'Events'),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Chat List inside TabBarView
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Friends Tab (1-on-1 chats)
                  _buildChatsList(chatsAsync),
                  
                  // Groups Tab (Mocked for now)
                  const Center(child: Text('Groups coming soon', style: TextStyle(color: Colors.white54))),
                  
                  // Events Tab (Mocked for now)
                  const Center(child: Text('Events coming soon', style: TextStyle(color: Colors.white54))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList(AsyncValue<List<ChatModel>> chatsAsync) {
    return chatsAsync.when(
      data: (chats) {
        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 16),
                const Text(
                  'No chats yet',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _openNewChatSearch,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Start a conversation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mpepeMaroon,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 80),
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final otherUserId = chat.participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => chat.participants.first,
            );

            final unreadCount = chat.unreadCounts[currentUserId!] ?? 0;
            // Determine if the last message was sent by the current user
            final lastMessageIsMe = false; // Mocked until we add sender ID to ChatModel's last message data
            
            final otherTypingUsers = chat.typingUsers.where((id) => id != currentUserId).toList();
            final isSomeoneTyping = otherTypingUsers.isNotEmpty;

            return FutureBuilder<AppUser?>(
              future: ref.read(userProvider.notifier).getUser(otherUserId),
              builder: (context, snapshot) {
                final otherUser = snapshot.data;
                final name = otherUser?.fullName ?? 'Unknown User';
                
                // Filtering logic
                if (_searchQuery.isNotEmpty && !name.toLowerCase().contains(_searchQuery)) {
                  return const SizedBox.shrink();
                }
                final avatarLetter = name.isNotEmpty ? name[0].toUpperCase() : '?';

                return InkWell(
                  onTap: () {
                    context.push('/hub/messages/${chat.id}');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.darkBackground,
                          child: Text(
                            avatarLetter,
                            style: const TextStyle(color: AppColors.mpepeMaroon, fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    timeago.format(chat.lastMessageTime?.toDate() ?? DateTime.now(), locale: 'en_short'),
                                    style: TextStyle(
                                      color: unreadCount > 0 ? AppColors.mpepeMaroon : Colors.white54,
                                      fontSize: 12,
                                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (lastMessageIsMe)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4.0),
                                      child: Icon(Icons.done_all, size: 16, color: Colors.blueAccent),
                                    ),
                                  Expanded(
                                    child: isSomeoneTyping 
                                    ? Row(
                                        children: [
                                          const Text('Typing', style: TextStyle(color: AppColors.mpepeMaroon, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 16,
                                            height: 10,
                                            child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.mpepeMaroon).animate().scale(duration: 300.ms),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        chat.lastMessage.isNotEmpty ? chat.lastMessage : 'Tap to chat',
                                        style: TextStyle(
                                          color: unreadCount > 0 ? Colors.white : Colors.white.withOpacity(0.6),
                                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ),
                                  if (unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: AppColors.mpepeMaroon,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        unreadCount > 9 ? '9+' : unreadCount.toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: Duration(milliseconds: 30 * index)).slideX(begin: 0.1, end: 0);
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.mpepeMaroon)),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
    );
  }
}
