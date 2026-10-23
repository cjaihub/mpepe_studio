import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/utils/friendly_error_parser.dart';
import 'models/connected_destination.dart';
import 'models/omnichannel_upload_task.dart';
import 'services/omnichannel_upload_engine.dart';
import 'screens/preview_matrix_screen.dart';
import 'screens/ab_testing_dashboard.dart';
import '../hub/voice_assistant_overlay.dart';

class GlobalUploadScreen extends ConsumerStatefulWidget {
  const GlobalUploadScreen({super.key});

  @override
  ConsumerState<GlobalUploadScreen> createState() => _GlobalUploadScreenState();
}

class _GlobalUploadScreenState extends ConsumerState<GlobalUploadScreen> with SingleTickerProviderStateMixin {
  List<ConnectedDestination> _availableDestinations = [];
  final Set<ConnectedDestination> _selectedDestinations = {};
  bool _isLoadingDestinations = true;
  bool _isSidebarOpen = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadDestinations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDestinations() async {
    final engine = ref.read(omnichannelUploadEngineProvider.notifier);
    final dests = await engine.fetchAllDestinations();
    setState(() {
      _availableDestinations = dests;
      _isLoadingDestinations = false;
    });
  }

  Future<void> _pickFiles() async {
    if (_selectedDestinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one destination first.')),
      );
      return;
    }

    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select File Source', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: AppColors.brandBlue),
              title: Text('Local Device', style: TextStyle(color: context.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'local'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blueAccent),
              title: Text('Google Cloud Storage', style: TextStyle(color: context.textPrimary)),
              subtitle: Text('Coming Soon', style: TextStyle(color: context.textMuted, fontSize: 10)),
              onTap: () => Navigator.pop(ctx, 'gcs'),
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.greenAccent),
              title: Text('Server Link', style: TextStyle(color: context.textPrimary)),
              subtitle: Text('Coming Soon', style: TextStyle(color: context.textMuted, fontSize: 10)),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );

    if (source == 'local') {
      final result = await FilePicker.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );

      if (result.isNotEmpty) {
        final engine = ref.read(omnichannelUploadEngineProvider.notifier);
        final files = <File>[];
        for (final file in result) {
          if (file.path != null) {
            files.add(File(file.path!));
          }
        }
        if (files.isNotEmpty) {
          engine.addTasks(files, _selectedDestinations.toList());
        }
      }
    } else if (source == 'gcs' || source == 'url') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Source "$source" is not fully implemented yet.')),
      );
    }
  }

  void _confirmAndStartUploads(BuildContext context, int pendingCount) {
    if (pendingCount == 0) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm Upload', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to start $pendingCount pending upload(s)?', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(omnichannelUploadEngineProvider.notifier).startUploads();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Uploads started successfully.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(omnichannelUploadEngineProvider);

    return Scaffold(
      backgroundColor: context.bg,
      body: StudioBackground(
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: _isSidebarOpen ? 280 : 0,
                      child: ClipRect(
                        child: _isSidebarOpen ? _buildDestinationPicker() : const SizedBox.shrink(),
                      ),
                    ),
                    if (_isSidebarOpen)
                      VerticalDivider(width: 1, color: context.border),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildInProgressTab(tasks),
                          _buildScheduledTab(),
                          _buildPublishedTab(),
                          _buildHistoryTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: MediaQuery.of(context).viewInsets.bottom > 0 || FirebaseAuth.instance.currentUser == null ? null : ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'voice_ai',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const VoiceAssistantOverlay(),
                  );
                },
                backgroundColor: AppColors.brandBlue,
                icon: const Icon(Icons.psychology, color: Colors.white, size: 20),
                label: const Text('AI Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              if (_tabController.index == 0) ...[
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'upload_btn',
                  onPressed: tasks.isNotEmpty ? () {
                    final pendingCount = tasks.where((t) => t.status == UploadStatus.pending).length;
                    if (pendingCount > 0) {
                      _confirmAndStartUploads(context, pendingCount);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No pending uploads to start.')),
                      );
                    }
                  } : null,
                  backgroundColor: tasks.isNotEmpty ? Theme.of(context).colorScheme.primary : Colors.grey.shade800,
                  icon: const Icon(Icons.cloud_upload, size: 20),
                  label: const Text('Start Uploads', style: TextStyle(fontSize: 13)),
                ),
              ]
            ],
          );
        }
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_isSidebarOpen ? Icons.menu_open : Icons.menu),
                onPressed: () {
                  setState(() {
                    _isSidebarOpen = !_isSidebarOpen;
                  });
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Omnichannel Upload',
                  style: AppTheme.h1Style.copyWith(fontSize: 24, color: context.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OneovaButton(
                text: 'New Upload',
                onPressed: _pickFiles,
                isPrimary: true,
              )
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.brandBlue,
          labelColor: AppColors.brandBlue,
          unselectedLabelColor: context.textMuted,
          indicatorWeight: 3,
          dividerColor: context.border,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'In Progress'),
            Tab(text: 'Scheduled'),
            Tab(text: 'Published'),
            Tab(text: 'History'),
          ],
        ),
      ],
    );
  }

  Widget _buildDestinationPicker() {
    return SizedBox(
      width: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Select Destinations', style: AppTheme.h2Style.copyWith(fontSize: 18, color: context.textPrimary)),
          ),
          if (_isLoadingDestinations)
            const Center(child: CircularProgressIndicator())
          else if (_availableDestinations.isEmpty)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.link_off, color: context.textMuted, size: 48),
                    const SizedBox(height: 16),
                    Text('No accounts connected yet.', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Link your YouTube, TikTok, or Meta accounts to start publishing.', style: TextStyle(color: context.textMuted)),
                    const SizedBox(height: 16),
                    OneovaButton(
                      text: 'Go to Settings',
                      onPressed: () => context.push('/settings'),
                      isPrimary: false,
                    )
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _availableDestinations.length,
                itemBuilder: (context, index) {
                  final dest = _availableDestinations[index];
                  final isSelected = _selectedDestinations.contains(dest);
                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: AppColors.brandBlue,
                    title: Text(dest.name, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                    subtitle: Text(dest.platform.name.toUpperCase(), style: TextStyle(color: context.textMuted, fontSize: 10)),
                    secondary: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPlatformIcon(dest.platform),
                        IconButton(
                          icon: Icon(Icons.settings, size: 18, color: context.textMuted),
                          onPressed: () => _openDestinationSettings(dest),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedDestinations.add(dest);
                        } else {
                          _selectedDestinations.remove(dest);
                        }
                      });
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlatformIcon(PlatformType type) {
    switch (type) {
      case PlatformType.youtube: return const Icon(Icons.play_circle_fill, color: Colors.red);
      case PlatformType.tiktok: return const Icon(Icons.music_note, color: Colors.cyanAccent);
      case PlatformType.facebook: return const Icon(Icons.facebook, color: Colors.blue);
      case PlatformType.instagram: return const Icon(Icons.camera_alt, color: Colors.purpleAccent);
    }
  }

  void _openDestinationSettings(ConnectedDestination dest) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${dest.name} Settings', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform: ${dest.platform.name.toUpperCase()}', style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: 16),
            Text('These settings are linked to your management center.', style: TextStyle(color: context.textMuted, fontSize: 12)),
            const SizedBox(height: 16),
            // Placeholder for actual settings fields
            TextFormField(
              initialValue: 'Public',
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: 'Default Privacy',
                labelStyle: TextStyle(color: context.textMuted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledTab() {
    return _buildFirestoreList('scheduled', 'No scheduled uploads', 'Your upcoming releases will appear here.');
  }

  Widget _buildPublishedTab() {
    return _buildFirestoreList('completed', 'No published uploads yet', 'Your successfully published content will appear here.');
  }

  Widget _buildHistoryTab() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_circle, size: 64, color: context.textMuted),
              const SizedBox(height: 16),
              Text('Please log in to manage your uploads', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('uploadTasks')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
        }

        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(FriendlyErrorParser.parse(snapshot.error), style: TextStyle(color: context.textSecondary, fontSize: 16), textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        
        if (docs.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: context.textMuted),
                  const SizedBox(height: 16),
                  Text('No upload history', style: AppTheme.h2Style.copyWith(color: context.textPrimary)),
                  const SizedBox(height: 8),
                  Text('Select destinations and click below to browse files', style: TextStyle(color: context.textMuted)),
                  const SizedBox(height: 24),
                  OneovaButton(
                    text: 'Browse Files',
                    onPressed: _pickFiles,
                    isPrimary: true,
                  )
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
            final title = metadata['title'] ?? 'Untitled Video';
            final status = data['status'] as String? ?? 'unknown';
            final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
            final publishedLinks = data['publishedLinks'] as Map<String, dynamic>? ?? {};

            return OneovaCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_done, color: AppColors.brandBlue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                          const SizedBox(height: 4),
                          Text('Status: \${status.toUpperCase()}', style: TextStyle(color: status == 'completed' ? Colors.green : (status == 'failed' ? Colors.red : context.textMuted), fontSize: 12)),
                          if (status == 'failed' && data['errorMessage'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              FriendlyErrorParser.parse(data['errorMessage']), 
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12)
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (status == 'uploading') ...[
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: context.border,
                              valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
                            ),
                          ],
                          if (publishedLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: publishedLinks.entries.map((e) {
                                return Chip(
                                  backgroundColor: context.surfaceMid,
                                  label: Text('\${e.key}', style: TextStyle(fontSize: 10, color: context.textPrimary)),
                                  avatar: Icon(Icons.link, size: 12, color: context.textPrimary),
                                );
                              }).toList(),
                            )
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFirestoreList(String filterStatus, String emptyTitle, String emptySubtitle) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Center(child: Text('Please log in', style: TextStyle(color: context.textPrimary)));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('uploadTasks')
          .where('status', isEqualTo: filterStatus)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
        }

        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(FriendlyErrorParser.parse(snapshot.error), style: TextStyle(color: context.textSecondary, fontSize: 16), textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 64, color: context.textMuted),
                const SizedBox(height: 16),
                Text(emptyTitle, style: AppTheme.h2Style.copyWith(color: context.textPrimary)),
                const SizedBox(height: 8),
                Text(emptySubtitle, style: TextStyle(color: context.textMuted)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final metadata = data['metadata'] as Map<String, dynamic>? ?? {};
            final title = metadata['title'] ?? 'Untitled Video';
            final status = data['status'] as String? ?? 'unknown';
            final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
            final publishedLinks = data['publishedLinks'] as Map<String, dynamic>? ?? {};

            return OneovaCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_done, color: AppColors.brandBlue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                          const SizedBox(height: 4),
                          Text('Status: ${status.toUpperCase()}', style: TextStyle(color: status == 'completed' ? Colors.green : (status == 'failed' ? Colors.red : context.textMuted), fontSize: 12)),
                          if (status == 'failed' && data['errorMessage'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              FriendlyErrorParser.parse(data['errorMessage']), 
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12)
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (status == 'uploading') ...[
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: context.border,
                              valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
                            ),
                          ],
                          if (publishedLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: publishedLinks.entries.map((e) {
                                return Chip(
                                  backgroundColor: context.surfaceMid,
                                  label: Text(e.key, style: TextStyle(fontSize: 10, color: context.textPrimary)),
                                  avatar: Icon(Icons.link, size: 12, color: context.textPrimary),
                                );
                              }).toList(),
                            )
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInProgressTab(List<OmnichannelUploadTask> tasks) {
    final pendingCount = tasks.where((t) => t.status == UploadStatus.pending).length;
    final engine = ref.read(omnichannelUploadEngineProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pendingCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$pendingCount Pending Uploads', style: AppTheme.h3Style),
                OneovaButton(
                  text: 'Start Uploads',
                  onPressed: () {
                    _confirmAndStartUploads(context, pendingCount);
                  },
                  isPrimary: true,
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return OneovaCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.video_file_rounded, color: context.textMuted),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.file.path.split('/').last, style: TextStyle(fontWeight: FontWeight.bold, color: context.textPrimary)),
                                const SizedBox(height: 4),
                                Text('${task.selectedDestinations.length} destinations selected', style: TextStyle(color: context.textMuted, fontSize: 12)),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: task.progress,
                                  backgroundColor: context.border,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.brandBlue),
                                ),
                                const SizedBox(height: 4),
                                Text(task.status.name.toUpperCase(), style: TextStyle(color: task.status == UploadStatus.failed ? Colors.red : AppColors.brandBlue, fontSize: 10, fontWeight: FontWeight.bold)),
                                if (task.status == UploadStatus.failed && task.errorMessage != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    FriendlyErrorParser.parse(task.errorMessage), 
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 11)
                                  ),
                                ]
                              ],
                            ),
                          ),
                          if (task.status == UploadStatus.pending)
                            IconButton(
                              icon: Icon(Icons.close, color: context.textMuted),
                              onPressed: () {
                                engine.removeTask(task.id);
                              },
                            )
                        ],
                      ),
                      if (task.status == UploadStatus.pending) ...[
                        const SizedBox(height: 16),
                        Divider(color: context.border),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: task.title,
                          style: TextStyle(color: context.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Video Title',
                            labelStyle: TextStyle(color: context.textMuted),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                          ),
                          onChanged: (val) => engine.updateTaskMetadata(task.id, title: val),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: task.description,
                          maxLines: 3,
                          style: TextStyle(color: context.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Description',
                            labelStyle: TextStyle(color: context.textMuted),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                          ),
                          onChanged: (val) => engine.updateTaskMetadata(task.id, description: val),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: task.tags.join(', '),
                          style: TextStyle(color: context.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Tags (comma separated)',
                            labelStyle: TextStyle(color: context.textMuted),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                          ),
                          onChanged: (val) {
                            final tags = val.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            engine.updateTaskMetadata(task.id, tags: tags);
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OneovaButton(
                                text: 'Preview Matrix',
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => PreviewMatrixScreen(task: task),
                                  ));
                                },
                                isPrimary: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OneovaButton(
                                text: 'AI Viral Guide',
                                onPressed: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => AbTestingDashboard(task: task),
                                  ));
                                },
                                isPrimary: true,
                              ),
                            ),
                          ],
                        ),
                        if (task.selectedDestinations.any((d) => d.platform == PlatformType.youtube)) ...[
                          const SizedBox(height: 16),
                          Divider(color: context.border),
                          const SizedBox(height: 8),
                          const Text('YouTube Settings', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: task.ytMetadata.privacyStatus,
                            dropdownColor: context.surface,
                            decoration: InputDecoration(
                              labelText: 'Privacy Status',
                              labelStyle: TextStyle(color: context.textMuted),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                            ),
                            items: [
                              DropdownMenuItem(value: 'public', child: Text('Public', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: 'unlisted', child: Text('Unlisted', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: 'private', child: Text('Private', style: TextStyle(color: context.textPrimary))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(privacyStatus: val));
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: task.ytMetadata.categoryId,
                            dropdownColor: context.surface,
                            decoration: InputDecoration(
                              labelText: 'Category',
                              labelStyle: TextStyle(color: context.textMuted),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: context.border)),
                              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.brandBlue)),
                            ),
                            items: [
                              DropdownMenuItem(value: '1', child: Text('Film & Animation', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '2', child: Text('Autos & Vehicles', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '10', child: Text('Music', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '15', child: Text('Pets & Animals', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '17', child: Text('Sports', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '20', child: Text('Gaming', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '22', child: Text('People & Blogs', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '23', child: Text('Comedy', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '24', child: Text('Entertainment', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '25', child: Text('News & Politics', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '26', child: Text('Howto & Style', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '27', child: Text('Education', style: TextStyle(color: context.textPrimary))),
                              DropdownMenuItem(value: '28', child: Text('Science & Technology', style: TextStyle(color: context.textPrimary))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(categoryId: val));
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: Text('Made for Kids', style: TextStyle(color: context.textPrimary)),
                            subtitle: Text('Required by COPPA', style: TextStyle(color: context.textMuted, fontSize: 12)),
                            value: task.ytMetadata.madeForKids,
                            activeThumbColor: AppColors.brandBlue,
                            onChanged: (val) {
                              engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(madeForKids: val));
                            },
                          ),
                          SwitchListTile(
                            title: Text('Allow Embedding', style: TextStyle(color: context.textPrimary)),
                            value: task.ytMetadata.embeddable,
                            activeThumbColor: AppColors.brandBlue,
                            onChanged: (val) {
                              engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(embeddable: val));
                            },
                          ),
                          SwitchListTile(
                            title: Text('Show Likes/Dislikes', style: TextStyle(color: context.textPrimary)),
                            value: task.ytMetadata.publicStatsViewable,
                            activeThumbColor: AppColors.brandBlue,
                            onChanged: (val) {
                              engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(publicStatsViewable: val));
                            },
                          ),
                        ]
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
