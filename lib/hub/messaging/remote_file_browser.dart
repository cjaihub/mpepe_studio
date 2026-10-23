import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../backend/remote_connect_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/secure_pairing/crypto_utils.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class RemoteFileBrowserBottomSheet extends ConsumerStatefulWidget {
  final String initialPath;
  const RemoteFileBrowserBottomSheet({super.key, this.initialPath = '~'});

  @override
  ConsumerState<RemoteFileBrowserBottomSheet> createState() => _RemoteFileBrowserBottomSheetState();
}

class _RemoteFileBrowserBottomSheetState extends ConsumerState<RemoteFileBrowserBottomSheet> {
  late String _currentPath;
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<DocumentSnapshot>? _commandSubscription;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory(_currentPath);
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items = [];
    });
    
    _commandSubscription?.cancel();

    final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;
    if (activeComputerId == null) {
      setState(() {
        _isLoading = false;
        _error = 'No active remote connection.';
      });
      return;
    }

    final commandId = await ref.read(remoteConnectProvider.notifier).sendCommand(
      'system',
      'list_directory',
      {'path': path},
    );

    if (commandId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to send command to remote computer.';
      });
      return;
    }

    // Set a timeout
    bool hasResponded = false;
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && !hasResponded) {
        setState(() {
          _isLoading = false;
          _error = 'Timeout waiting for remote computer.\nPlease ensure the Desktop Agent is running and supports file browsing.';
        });
        _commandSubscription?.cancel();
      }
    });

    _commandSubscription = ref.read(remoteConnectProvider.notifier).listenToCommand(commandId)?.listen((snapshot) {
      if (!snapshot.exists) return;
      
      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'] as String?;
      
      if (status == 'completed') {
        hasResponded = true;
        _commandSubscription?.cancel();
        
        try {
          List<dynamic> rawItems = [];
          
          if (data['payload_encrypted'] != null && data['payload_encrypted'].toString().isNotEmpty) {
             final key = ref.read(remoteConnectProvider).activeKeys[activeComputerId];
             if (key != null) {
               final decryptedJson = CryptoUtils.decryptPayload(data['payload_encrypted'], key);
               if (decryptedJson != null) {
                 final decoded = jsonDecode(decryptedJson) as Map<String, dynamic>;
                 rawItems = decoded['files'] as List<dynamic>? ?? [];
               }
             }
          } else if (data['payload'] != null) {
             rawItems = (data['payload'] as Map<String, dynamic>)['files'] as List<dynamic>? ?? [];
          }
          
          setState(() {
            _items = rawItems.map((e) => e as Map<String, dynamic>).toList();
            _items.sort((a, b) {
              // Folders first, then alphabetical
              bool isDirA = a['isDirectory'] ?? false;
              bool isDirB = b['isDirectory'] ?? false;
              if (isDirA && !isDirB) return -1;
              if (!isDirA && isDirB) return 1;
              String nameA = a['name'] ?? '';
              String nameB = b['name'] ?? '';
              return nameA.toLowerCase().compareTo(nameB.toLowerCase());
            });
            _currentPath = path;
            _isLoading = false;
          });
        } catch (e) {
          setState(() {
            _error = 'Error parsing directory listing: $e';
            _isLoading = false;
          });
        }
      } else if (status == 'error') {
        hasResponded = true;
        _commandSubscription?.cancel();
        setState(() {
          _error = data['error_message'] ?? 'Remote computer encountered an error.';
          _isLoading = false;
        });
      }
    });
  }

  void _navigateUp() {
    if (_currentPath == '~' || _currentPath == '/' || _currentPath == 'C:\\') return;
    
    String newPath;
    if (_currentPath.contains('/')) {
       final parts = _currentPath.split('/');
       parts.removeLast();
       newPath = parts.join('/');
       if (newPath.isEmpty) newPath = '/';
    } else if (_currentPath.contains('\\')) {
       final parts = _currentPath.split('\\');
       parts.removeLast();
       newPath = parts.join('\\');
       if (newPath.isEmpty) newPath = 'C:\\'; // Fallback
    } else {
       newPath = '~';
    }
    _loadDirectory(newPath);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (_currentPath != '~' && _currentPath != '/' && _currentPath != 'C:\\')
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    onPressed: _isLoading ? null : _navigateUp,
                  ),
                Expanded(
                  child: Text(
                    _currentPath,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(color: Colors.white12, height: 1),
          
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadDirectory(_currentPath),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'Folder is empty.',
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isDir = item['isDirectory'] as bool? ?? false;
        final name = item['name'] as String? ?? 'Unknown';
        final path = item['path'] as String? ?? '';
        final size = item['size'] as int?; 

        return ListTile(
          leading: Icon(
            isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            color: isDir ? AppColors.brandBlue : Colors.white70,
            size: 28,
          ),
          title: Text(
            name,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 15,
              fontWeight: isDir ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
          subtitle: !isDir && size != null
              ? Text(
                  '${(size / 1024).toStringAsFixed(1)} KB',
                  style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                )
              : null,
          onTap: () {
            if (isDir) {
              _loadDirectory(path);
            } else {
              Navigator.pop(context, path);
            }
          },
        );
      },
    );
  }
}
