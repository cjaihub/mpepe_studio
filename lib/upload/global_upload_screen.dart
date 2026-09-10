import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select File Source', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: AppColors.mpepeGold),
              title: const Text('Local Device', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, 'local'),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.blueAccent),
              title: const Text('Google Cloud Storage', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Coming Soon', style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () => Navigator.pop(ctx, 'gcs'),
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.greenAccent),
              title: const Text('Server Link', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Coming Soon', style: TextStyle(color: Colors.white54, fontSize: 10)),
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

      if (result != null && result.isNotEmpty) {
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
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to start $pendingCount pending upload(s)?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mpepeMaroon,
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
                      const VerticalDivider(width: 1, color: Colors.white12),
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
                backgroundColor: AppColors.mpepeMaroon,
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
                  style: AppTheme.h1Style.copyWith(fontSize: 24),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              MpepeButton(
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
          indicatorColor: AppColors.mpepeMaroon,
          labelColor: AppColors.mpepeMaroon,
          unselectedLabelColor: Colors.white54,
          indicatorWeight: 3,
          dividerColor: Colors.white12,
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
            child: Text('Select Destinations', style: AppTheme.h2Style.copyWith(fontSize: 18)),
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
                    const Icon(Icons.link_off, color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    const Text('No accounts connected yet.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    const Text('Link your YouTube, TikTok, or Meta accounts to start publishing.', style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 16),
                    MpepeButton(
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
                    activeColor: AppColors.mpepeMaroon,
                    title: Text(dest.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(dest.platform.name.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    secondary: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPlatformIcon(dest.platform),
                        IconButton(
                          icon: const Icon(Icons.settings, size: 18, color: Colors.white54),
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
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${dest.name} Settings', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform: ${dest.platform.name.toUpperCase()}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            const Text('These settings are linked to your management center.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            // Placeholder for actual settings fields
            TextFormField(
              initialValue: 'Public',
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Default Privacy',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.mpepeMaroon),
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
              const Icon(Icons.account_circle, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('Please log in to manage your uploads', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
          return const Center(child: CircularProgressIndicator(color: AppColors.mpepeGold));
        }

        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(FriendlyErrorParser.parse(snapshot.error), style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
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
                  const Icon(Icons.history, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text('No upload history', style: AppTheme.h2Style),
                  const SizedBox(height: 8),
                  const Text('Select destinations and click below to browse files', style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 24),
                  MpepeButton(
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

            return MpepeCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_done, color: AppColors.mpepeGold),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('Status: \${status.toUpperCase()}', style: TextStyle(color: status == 'completed' ? Colors.green : (status == 'failed' ? Colors.red : Colors.white54), fontSize: 12)),
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
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(AppColors.mpepeGold),
                            ),
                          ],
                          if (publishedLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: publishedLinks.entries.map((e) {
                                return Chip(
                                  backgroundColor: Colors.white12,
                                  label: Text('\${e.key}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  avatar: const Icon(Icons.link, size: 12, color: Colors.white),
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
      return const Center(child: Text('Please log in', style: TextStyle(color: Colors.white)));
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
          return const Center(child: CircularProgressIndicator(color: AppColors.mpepeGold));
        }

        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(FriendlyErrorParser.parse(snapshot.error), style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
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
                const Icon(Icons.history, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                Text(emptyTitle, style: AppTheme.h2Style),
                const SizedBox(height: 8),
                Text(emptySubtitle, style: const TextStyle(color: Colors.white54)),
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

            return MpepeCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.cloud_done, color: AppColors.mpepeGold),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text('Status: ${status.toUpperCase()}', style: TextStyle(color: status == 'completed' ? Colors.green : (status == 'failed' ? Colors.red : Colors.white54), fontSize: 12)),
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
                              backgroundColor: Colors.white12,
                              valueColor: const AlwaysStoppedAnimation(AppColors.mpepeGold),
                            ),
                          ],
                          if (publishedLinks.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: publishedLinks.entries.map((e) {
                                return Chip(
                                  backgroundColor: Colors.white12,
                                  label: Text('${e.key}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                                  avatar: const Icon(Icons.link, size: 12, color: Colors.white),
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
                MpepeButton(
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
              return MpepeCard(
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
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.video_file, color: Colors.white54),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(task.file.path.split('/').last, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                const SizedBox(height: 4),
                                Text('${task.selectedDestinations.length} destinations selected', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: task.progress,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.mpepeGold),
                                ),
                                const SizedBox(height: 4),
                                Text(task.status.name.toUpperCase(), style: TextStyle(color: task.status == UploadStatus.failed ? Colors.red : AppColors.mpepeGold, fontSize: 10, fontWeight: FontWeight.bold)),
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
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () {
                                engine.removeTask(task.id);
                              },
                            )
                        ],
                      ),
                      if (task.status == UploadStatus.pending) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: task.title,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Video Title',
                            labelStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.mpepeGold)),
                          ),
                          onChanged: (val) => engine.updateTaskMetadata(task.id, title: val),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: task.description,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            labelStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.mpepeGold)),
                          ),
                          onChanged: (val) => engine.updateTaskMetadata(task.id, description: val),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: task.tags?.join(', '),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Tags (comma separated)',
                            labelStyle: TextStyle(color: Colors.white54),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.mpepeGold)),
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
                              child: MpepeButton(
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
                              child: MpepeButton(
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
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 8),
                          const Text('YouTube Settings', style: TextStyle(color: AppColors.mpepeGold, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: task.ytMetadata.privacyStatus,
                            dropdownColor: AppColors.cardDark,
                            decoration: const InputDecoration(
                              labelText: 'Privacy Status',
                              labelStyle: TextStyle(color: Colors.white54),
                              border: OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.mpepeGold)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'public', child: Text('Public', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: 'unlisted', child: Text('Unlisted', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: 'private', child: Text('Private', style: TextStyle(color: Colors.white))),
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
                            dropdownColor: AppColors.cardDark,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              labelStyle: TextStyle(color: Colors.white54),
                              border: OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.mpepeGold)),
                            ),
                            items: const [
                              DropdownMenuItem(value: '1', child: Text('Film & Animation', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '2', child: Text('Autos & Vehicles', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '10', child: Text('Music', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '15', child: Text('Pets & Animals', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '17', child: Text('Sports', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '20', child: Text('Gaming', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '22', child: Text('People & Blogs', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '23', child: Text('Comedy', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '24', child: Text('Entertainment', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '25', child: Text('News & Politics', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '26', child: Text('Howto & Style', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '27', child: Text('Education', style: TextStyle(color: Colors.white))),
                              DropdownMenuItem(value: '28', child: Text('Science & Technology', style: TextStyle(color: Colors.white))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(categoryId: val));
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            title: const Text('Made for Kids', style: TextStyle(color: Colors.white)),
                            subtitle: const Text('Required by COPPA', style: TextStyle(color: Colors.white54, fontSize: 12)),
                            value: task.ytMetadata.madeForKids,
                            activeThumbColor: AppColors.mpepeGold,
                            onChanged: (val) {
                              engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(madeForKids: val));
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Allow Embedding', style: TextStyle(color: Colors.white)),
                            value: task.ytMetadata.embeddable,
                            activeThumbColor: AppColors.mpepeGold,
                            onChanged: (val) {
                              engine.updateTaskMetadata(task.id, ytMetadata: task.ytMetadata.copyWith(embeddable: val));
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Show Likes/Dislikes', style: TextStyle(color: Colors.white)),
                            value: task.ytMetadata.publicStatsViewable,
                            activeThumbColor: AppColors.mpepeGold,
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
