import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../backend/social/models/social_profile.dart';
import '../../../shared/theme/app_theme.dart';
import '../services/post_search_service.dart';

class CollaboratorSheet extends StatefulWidget {
  final List<String> initialCollaborators;
  final List<String> initialTaggedUsers;
  final PostSearchService searchService;
  final Function(List<String> collaborators, List<String> taggedUsers) onSave;

  const CollaboratorSheet({
    super.key,
    required this.initialCollaborators,
    required this.initialTaggedUsers,
    required this.searchService,
    required this.onSave,
  });

  @override
  State<CollaboratorSheet> createState() => _CollaboratorSheetState();
}

class _CollaboratorSheetState extends State<CollaboratorSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  late List<String> _collaboratorIds;
  late List<String> _taggedUserIds;

  List<SocialProfile> _searchResults = [];
  bool _isSearching = false;

  final Map<String, SocialProfile> _loadedProfiles = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _collaboratorIds = List.from(widget.initialCollaborators);
    _taggedUserIds = List.from(widget.initialTaggedUsers);
    _loadInitialProfiles();
  }

  Future<void> _loadInitialProfiles() async {
    final allIds = {..._collaboratorIds, ..._taggedUserIds}.toList();
    if (allIds.isNotEmpty) {
      final profiles = await widget.searchService.fetchProfilesByIds(allIds);
      if (mounted) {
        setState(() {
          for (final p in profiles) {
            _loadedProfiles[p.userId] = p;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    if (val.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _isSearching = true);
      final results = await widget.searchService.searchUsers(val, limit: 12);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          for (final r in results) {
            _loadedProfiles[r.userId] = r;
          }
        });
      }
    });
  }

  void _toggleCollaborator(SocialProfile user) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_collaboratorIds.contains(user.userId)) {
        _collaboratorIds.remove(user.userId);
      } else {
        if (_collaboratorIds.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 5 co-authors per post allowed.')),
          );
          return;
        }
        _collaboratorIds.add(user.userId);
        _loadedProfiles[user.userId] = user;
      }
    });
  }

  void _toggleTaggedUser(SocialProfile user) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_taggedUserIds.contains(user.userId)) {
        _taggedUserIds.remove(user.userId);
      } else {
        if (_taggedUserIds.length >= 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 20 tagged people per post.')),
          );
          return;
        }
        _taggedUserIds.add(user.userId);
        _loadedProfiles[user.userId] = user;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header with Save Done button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'People & Collaborations',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onSave(_collaboratorIds, _taggedUserIds);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // TabBar
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.brandBlue,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textMuted,
            labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
            tabs: [
              Tab(
                text: 'Co-Authors (${_collaboratorIds.length})',
              ),
              Tab(
                text: 'Tag People (${_taggedUserIds.length})',
              ),
            ],
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search creators by username or name…',
                  hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCollaboratorsTab(),
                _buildTaggedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollaboratorsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Explanation Banner
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 0.8),
          ),
          child: Row(
            children: [
              const Icon(Icons.group_work_outlined, size: 18, color: AppColors.brandBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Co-authors receive an invitation notification. Upon accepting, this reel appears on both profiles and shares metrics.',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Selected Collaborators
        if (_collaboratorIds.isNotEmpty) ...[
          Text(
            'SELECTED CO-AUTHORS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _collaboratorIds.map((id) {
              final user = _loadedProfiles[id];
              return Chip(
                avatar: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.brandBlue,
                  backgroundImage: user != null && user.avatarUrl.isNotEmpty
                      ? NetworkImage(user.avatarUrl)
                      : null,
                  child: user == null || user.avatarUrl.isEmpty
                      ? const Text('?', style: TextStyle(fontSize: 8, color: Colors.white))
                      : null,
                ),
                label: Text(
                  user != null ? '@${user.username}' : id,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                backgroundColor: context.surface,
                side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  HapticFeedback.lightImpact();
                  setState(() => _collaboratorIds.remove(id));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],

        // Search Results / Suggested Creators
        _buildCreatorList(isCollabMode: true),
      ],
    );
  }

  Widget _buildTaggedTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Explanation Banner
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 0.8),
          ),
          child: Row(
            children: [
              const Icon(Icons.sell_outlined, size: 18, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tagged creators will receive a notification that you featured or mentioned them in this reel.',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Selected Tagged Users
        if (_taggedUserIds.isNotEmpty) ...[
          Text(
            'TAGGED USERS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _taggedUserIds.map((id) {
              final user = _loadedProfiles[id];
              return Chip(
                avatar: CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.brandPink,
                  backgroundImage: user != null && user.avatarUrl.isNotEmpty
                      ? NetworkImage(user.avatarUrl)
                      : null,
                  child: user == null || user.avatarUrl.isEmpty
                      ? const Text('?', style: TextStyle(fontSize: 8, color: Colors.white))
                      : null,
                ),
                label: Text(
                  user != null ? '@${user.username}' : id,
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                backgroundColor: context.surface,
                side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.5)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  HapticFeedback.lightImpact();
                  setState(() => _taggedUserIds.remove(id));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],

        // Search Results / Suggested Creators
        _buildCreatorList(isCollabMode: false),
      ],
    );
  }

  Widget _buildCreatorList({required bool isCollabMode}) {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
    }

    if (_searchController.text.trim().isNotEmpty && _searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No creators found matching "${_searchController.text.trim()}".',
            style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
          ),
        ),
      );
    }

    final list = _searchResults;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Type above to search real creators on Oneova.',
            style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
          ),
        ),
      );
    }

    return Column(
      children: list.map((user) {
        final isSelected = isCollabMode
            ? _collaboratorIds.contains(user.userId)
            : _taggedUserIds.contains(user.userId);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
            backgroundImage: user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
            child: user.avatarUrl.isEmpty
                ? Text(
                    user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  )
                : null,
          ),
          title: Row(
            children: [
              Text(
                user.displayName.isNotEmpty ? user.displayName : user.username,
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, size: 14, color: AppColors.brandBlue),
              ],
            ],
          ),
          subtitle: Text(
            '@${user.username}',
            style: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
          ),
          trailing: isSelected
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isCollabMode ? AppColors.brandBlue : AppColors.brandPink,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Added',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                )
              : OutlinedButton(
                  onPressed: () {
                    if (isCollabMode) {
                      _toggleCollaborator(user);
                    } else {
                      _toggleTaggedUser(user);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: context.textPrimary,
                    side: BorderSide(color: context.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text(
                    'Add',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
        );
      }).toList(),
    );
  }
}
