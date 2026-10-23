import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../backend/user_service.dart';
import '../../backend/messaging_repository.dart';
import '../../shared/theme/app_theme.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  List<AppUser> _searchResults = [];
  final Set<AppUser> _selectedUsers = {};
  bool _isLoading = false;

  void _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('fullName', isGreaterThanOrEqualTo: query)
          .where('fullName', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.data(), doc.id))
          .where((u) => u.id != currentUserId)
          .toList();

      if (mounted) {
        setState(() {
          _searchResults = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleUserSelection(AppUser user) {
    setState(() {
      if (_selectedUsers.contains(user)) {
        _selectedUsers.remove(user);
      } else {
        _selectedUsers.add(user);
      }
    });
  }

  void _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a group name.')));
      return;
    }
    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one user.')));
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
    );

    try {
      final participantIds = [currentUserId, ..._selectedUsers.map((u) => u.id)];
      // Note: the backend needs to support a group name flag or metadata. 
      // For now, we will create a standard chat with multiple participants.
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.createChat(participantIds);
      
      if (mounted) {
        Navigator.pop(context); // close loading
        Navigator.pop(context); // close modal
        context.push('/hub/messages/$chatId');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating group: $e')));
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Create a Group',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: AppColors.brandBlue, size: 28),
                  onPressed: _createGroup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Group Name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.darkSurface,
                  child: Icon(Icons.groups_rounded, color: Colors.white54, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: 'Group Name',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Add Users',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),

          // Selected Users Horizontal List
          if (_selectedUsers.isNotEmpty)
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedUsers.length,
                itemBuilder: (context, index) {
                  final user = _selectedUsers.elementAt(index);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.brandBlue,
                          child: Text(
                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => _toggleUserSelection(user),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ).animate().scale(duration: 200.ms);
                },
              ),
            ),
          
          const SizedBox(height: 16),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: TextField(
              controller: _searchController,
              onChanged: _searchUsers,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search for people...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: AppColors.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),

          // Search Results
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
                  : _searchResults.isEmpty && _searchController.text.isNotEmpty
                      ? const Center(child: Text("No users found", style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 16, bottom: 32),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final user = _searchResults[index];
                            final isSelected = _selectedUsers.contains(user);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: isSelected ? AppColors.brandBlue : const Color(0xFF262626),
                                child: Text(
                                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                user.fullName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              trailing: GestureDetector(
                                onTap: () => _toggleUserSelection(user),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.brandBlue : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected ? AppColors.brandBlue : Colors.white54,
                                      width: 2,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.check,
                                    size: 16,
                                    color: isSelected ? Colors.white : Colors.transparent,
                                  ),
                                ),
                              ),
                              onTap: () => _toggleUserSelection(user),
                            ).animate().fadeIn(delay: Duration(milliseconds: 30 * index)).slideY(begin: 0.1, end: 0);
                          },
                        ),
            ),
          ),
          
          // Create Button at bottom
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: _createGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('CREATE A GROUP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
