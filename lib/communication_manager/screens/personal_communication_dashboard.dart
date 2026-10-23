import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../models/contact_profile.dart';
import '../models/communication_preference.dart';
import '../services/contact_service.dart';
import '../services/communication_manager_service.dart';
import '../../backend/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';


/// The main Personal Communication Manager dashboard.
/// Combines Contacts, AI Personalization profile, and interaction history
/// in a unified tabbed interface.
class PersonalCommunicationDashboard extends ConsumerStatefulWidget {
  const PersonalCommunicationDashboard({super.key});

  @override
  ConsumerState<PersonalCommunicationDashboard> createState() =>
      _PersonalCommunicationDashboardState();
}

class _PersonalCommunicationDashboardState
    extends ConsumerState<PersonalCommunicationDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: _buildAppBar(context),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ContactsTab(),
          _AiProfileTab(),
          _HistoryTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.darkSurface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
        onPressed: () => context.pop(),
      ),
      title: Text(
        'Communication Manager',
        style: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.person_add, color: AppColors.textPrimary),
          tooltip: 'Add Contact',
          onPressed: () => _showAddContactDialog(context),
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.brandBlue,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: 'Contacts'),
          Tab(text: 'AI Profile'),
          Tab(text: 'History'),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddContactSheet(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// TAB 1 — CONTACTS
// ──────────────────────────────────────────────────────────────────

class _ContactsTab extends ConsumerStatefulWidget {
  const _ContactsTab();

  @override
  ConsumerState<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<_ContactsTab> {
  String _searchQuery = '';
  String _filterTag = '';

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactServiceProvider);
    final allContacts = contactsAsync.value ?? [];

    return Column(
      children: [
        _buildSearchAndFilter(allContacts),
        Expanded(
          child: contactsAsync.when(
            loading: () =>
                const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
            error: (e, _) => Center(
              child: Text('Error loading contacts',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            data: (contacts) {
              var filtered = contacts.where((c) {
                final matchesSearch = _searchQuery.isEmpty ||
                    c.user.fullName.toLowerCase().contains(_searchQuery) ||
                    c.user.email.toLowerCase().contains(_searchQuery);
                final matchesTag = _filterTag.isEmpty ||
                    c.relationalData.tags.any(
                        (t) => t.toLowerCase() == _filterTag.toLowerCase());
                return matchesSearch && matchesTag;
              }).toList();

              if (filtered.isEmpty) {
                return _buildEmptyContacts();
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (context, index) =>
                    _ContactListTile(contact: filtered[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilter(List<ContactProfile> contacts) {
    // Gather all unique tags from all contacts
    final allTags = <String>{};
    for (final c in contacts) {
      allTags.addAll(c.relationalData.tags);
    }

    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.darkBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: GoogleFonts.inter(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by name, email, or tag…',
                hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(
                    label: 'All',
                    isSelected: _filterTag.isEmpty,
                    onTap: () => setState(() => _filterTag = ''),
                  ),
                  ...allTags.map((tag) => _FilterChip(
                        label: tag,
                        isSelected: _filterTag == tag,
                        onTap: () =>
                            setState(() => _filterTag = _filterTag == tag ? '' : tag),
                      )),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildEmptyContacts() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people, size: 64, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: GoogleFonts.inter(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the + button to add people from Onerova.',
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue : AppColors.darkBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : AppColors.darkSurfaceHighlight,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ContactListTile extends StatelessWidget {
  final ContactProfile contact;

  const _ContactListTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    final user = contact.user;
    final rel = contact.relationalData;
    final initial =
        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => context.push('/communication/contact/${user.id}'),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
              child: Text(initial,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
            ),

            if (rel.isMuted)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.darkSurface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volume_off, size: 10, color: Colors.red),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                user.fullName,
                style: GoogleFonts.inter(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            _RelationshipBadge(status: rel.relationshipStatus),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user.department.isNotEmpty)
              Text(user.department,
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary, fontSize: 12)),
            if (rel.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: rel.tags
                    .take(3)
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(tag,
                              style: GoogleFonts.inter(
                                  color: AppColors.brandBlue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      ),
    );
  }
}

class _RelationshipBadge extends StatelessWidget {
  final RelationshipStatus status;

  const _RelationshipBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == RelationshipStatus.none) return const SizedBox.shrink();

    Color color;
    switch (status) {
      case RelationshipStatus.mutual:
        color = Colors.greenAccent;
        break;
      case RelationshipStatus.following:
        color = Colors.blueAccent;
        break;
      case RelationshipStatus.follower:
        color = Colors.purpleAccent;
        break;
      default:
        color = AppColors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: GoogleFonts.inter(
            color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// TAB 2 — AI PROFILE
// ──────────────────────────────────────────────────────────────────

class _AiProfileTab extends ConsumerStatefulWidget {
  const _AiProfileTab();

  @override
  ConsumerState<_AiProfileTab> createState() => _AiProfileTabState();
}

class _AiProfileTabState extends ConsumerState<_AiProfileTab> {
  PersonalizationSettings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings =
        await ref.read(communicationManagerProvider.notifier).getSettings();
    if (mounted) {
      setState(() {
      _settings = settings;
      _isLoading = false;
    });
    }
  }

  Future<void> _update(PersonalizationSettings s) async {
    setState(() => _settings = s);
    await ref.read(communicationManagerProvider.notifier).updateSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
    }

    final prefsAsync = ref.watch(communicationManagerProvider);
    final s = _settings!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Master toggle hero card
        _buildHeroCard(s),
        const SizedBox(height: 20),

        if (s.personalizationEnabled) ...[
          _buildSectionHeader('Learning Signals'),
          const SizedBox(height: 12),
          _buildToggleCard('Learn from messages', 'AI analyzes your outgoing messages',
              Icons.message, s.learnFromMessages,
              (v) => _update(s.copyWith(learnFromMessages: v))),
          _buildToggleCard('Learn from conversations',
              'AI learns from approved threads', Icons.forum,
              s.learnFromApprovedConversations,
              (v) => _update(s.copyWith(learnFromApprovedConversations: v))),
          _buildToggleCard('Learn from edits',
              'Improve drafts by analyzing your corrections', Icons.edit_note,
              s.learnFromEdits,
              (v) => _update(s.copyWith(learnFromEdits: v))),
          _buildToggleCard('Learn from reactions',
              'Detect tone preferences from emojis', Icons.favorite,
              s.learnFromReactions,
              (v) => _update(s.copyWith(learnFromReactions: v))),
          const SizedBox(height: 24),
          _buildSectionHeader('Learned Preferences'),
          const SizedBox(height: 12),
          prefsAsync.when(
            loading: () => const Center(
                child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
            error: (e, _) => Text('$e',
                style: const TextStyle(color: AppColors.textSecondary)),
            data: (prefs) {
              if (prefs.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.darkSurfaceHighlight),
                  ),
                  child: Text(
                    'No preferences learned yet. Enable the signals above and start messaging.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                );
              }
              return Column(
                children: prefs
                    .map((pref) => _PreferenceCard(
                          pref: pref,
                          onDelete: () => ref
                              .read(communicationManagerProvider.notifier)
                              .deletePreference(pref.id),
                        ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 32),
          _buildResetButton(),
        ],
      ],
    );
  }

  Widget _buildHeroCard(PersonalizationSettings s) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: s.personalizationEnabled
            ? const LinearGradient(
                colors: [AppColors.brandBlue, Color(0xFF6B0000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: s.personalizationEnabled ? null : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: s.personalizationEnabled
              ? Colors.transparent
              : AppColors.darkSurfaceHighlight,
          width: 1.5,
        ),
        boxShadow: s.personalizationEnabled
            ? [
                BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8))
              ]
            : [],
      ),
      child: Row(
        children: [
          Icon(
            s.personalizationEnabled
                ? Icons.psychology
                : Icons.psychology_outlined,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Personalization',
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  s.personalizationEnabled
                      ? 'Active — AI is learning your communication style'
                      : 'Disabled — AI learning and drafting is off',
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: s.personalizationEnabled,
            onChanged: (v) => _update(s.copyWith(personalizationEnabled: v)),
            activeThumbColor: Colors.white,
            activeTrackColor: Colors.white.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2),
    );
  }

  Widget _buildToggleCard(String title, String subtitle, IconData icon,
      bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? AppColors.brandBlue.withValues(alpha: 0.4)
              : AppColors.darkSurfaceHighlight,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? AppColors.brandBlue.withValues(alpha: 0.15)
                  : AppColors.darkSurfaceHighlight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: value ? AppColors.brandBlue : AppColors.textMuted,
                size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brandBlue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _confirmReset,
        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
        label: Text('Reset AI Profile',
            style: GoogleFonts.inter(
                color: Colors.redAccent, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset AI Profile?',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
            'This deletes all learned preferences and turns off AI access. This cannot be undone.',
            style: GoogleFonts.inter(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(communicationManagerProvider.notifier).resetProfile();
      await _load();
    }
  }
}

class _PreferenceCard extends StatelessWidget {
  final CommunicationPreference pref;
  final VoidCallback onDelete;

  const _PreferenceCard({required this.pref, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(pref.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(pref.category.name.toUpperCase(),
                        style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            letterSpacing: 1)),
                    const Spacer(),
                    _sourceBadge(pref.source),
                  ]),
                  const SizedBox(height: 8),
                  Text(pref.value,
                      style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceBadge(PreferenceSource source) {
    Color color;
    String label;
    switch (source) {
      case PreferenceSource.observed:
        color = Colors.blue;
        label = 'OBSERVED';
        break;
      case PreferenceSource.userConfirmed:
        color = Colors.green;
        label = 'CONFIRMED';
        break;
      case PreferenceSource.aiSuggested:
        color = Colors.orange;
        label = 'SUGGESTED';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              color: color, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }
}

// ──────────────────────────────────────────────────────────────────
// TAB 3 — INTERACTION HISTORY
// ──────────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactServiceProvider);

    return contactsAsync.when(
      loading: () =>
          const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      error: (e, _) => const Center(
          child: Text('Error', style: TextStyle(color: AppColors.textSecondary))),
      data: (contacts) {
        if (contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('No interactions yet',
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18)),
              ],
            ),
          );
        }

        // Sort contacts by most recent interaction
        final sorted = [...contacts]
          ..sort((a, b) => b.relationalData.lastInteraction
              .compareTo(a.relationalData.lastInteraction));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          itemBuilder: (ctx, i) {
            final c = sorted[i];
            final ago = _formatAgo(c.relationalData.lastInteraction);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
              ),
              child: ListTile(
                onTap: () =>
                    context.push('/communication/contact/${c.user.id}'),
                leading: CircleAvatar(
                  backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                  child: Text(
                    c.user.fullName.isNotEmpty
                        ? c.user.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(c.user.fullName,
                    style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                subtitle: Text('Last interaction $ago',
                    style:
                        GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: AppColors.textMuted),
              ),
            );
          },
        );
      },
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

// ──────────────────────────────────────────────────────────────────
// ADD CONTACT BOTTOM SHEET
// ──────────────────────────────────────────────────────────────────

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final TextEditingController _ctrl = TextEditingController();
  List<AppUser> _results = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _isSearching = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final lowerQuery = query.toLowerCase();
      final snap = await firestore
          .collection('users')
          .where('fullName', isGreaterThanOrEqualTo: lowerQuery)
          .where('fullName', isLessThanOrEqualTo: '$lowerQuery\uf8ff')
          .limit(10)
          .get();

      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final users = snap.docs
          .map((d) => AppUser.fromMap(d.data(), d.id))
          .where((u) => u.id != currentUid)
          .toList();

      if (mounted) setState(() => _results = users);
    } catch (e) {
      debugPrint('Search error: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addContact(AppUser user) async {
    await ref
        .read(contactServiceProvider.notifier)
        .setRelationshipStatus(user.id, RelationshipStatus.following);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.darkSurface,
          content: Text('${user.fullName} added to contacts',
              style: const TextStyle(color: Colors.white)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.darkSurfaceHighlight,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Add Contact',
                  style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20)),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.darkBackground,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.darkSurfaceHighlight, width: 1.5),
                ),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onSearch,
                  style: GoogleFonts.inter(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by name…',
                    hintStyle:
                        GoogleFonts.inter(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textSecondary, size: 20),
                    suffix: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: AnimatedLoadingIndicator(
                                strokeWidth: 2,
                                color: AppColors.brandBlue))
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _ctrl.text.length < 2
                            ? 'Type at least 2 characters to search'
                            : 'No users found',
                        style: GoogleFonts.inter(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final user = _results[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.brandBlue.withValues(alpha: 0.2),
                            backgroundImage: null,
                    child: Text(
                        user.fullName.isNotEmpty
                            ? user.fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),

                          ),
                          title: Text(user.fullName,
                              style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(user.department,
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondary, fontSize: 12)),
                          trailing: ElevatedButton(
                            onPressed: () => _addContact(user),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                            child: Text('Add',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
