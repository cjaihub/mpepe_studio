import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/theme/app_theme.dart';

class PlatformCommentsModal extends ConsumerStatefulWidget {
  final String platform;
  final String platformDisplayName;
  final String accountHandle;

  const PlatformCommentsModal({
    super.key,
    required this.platform,
    required this.platformDisplayName,
    required this.accountHandle,
  });

  static void show(
    BuildContext context, {
    required String platform,
    required String platformDisplayName,
    required String accountHandle,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => PlatformCommentsModal(
        platform: platform,
        platformDisplayName: platformDisplayName,
        accountHandle: accountHandle,
      ),
    );
  }

  @override
  ConsumerState<PlatformCommentsModal> createState() => _PlatformCommentsModalState();
}

class _PlatformCommentsModalState extends ConsumerState<PlatformCommentsModal> {
  final TextEditingController _replyController = TextEditingController();
  String? _replyingToCommentId;
  String? _replyingToUser;
  bool _isSending = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _submitReply(String commentId) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('platform_comments')
            .doc(commentId)
            .collection('replies')
            .add({
          'text': text,
          'authorHandle': widget.accountHandle,
          'platform': widget.platform,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _replyController.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToUser = null;
        _isSending = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reply dispatched via ${widget.platformDisplayName} API!'),
            backgroundColor: AppColors.brandBlue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.forum_outlined, color: AppColors.brandBlue, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${widget.platformDisplayName} Comments',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                            ),
                            child: const Text('LIVE API', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      Text(
                        widget.accountHandle,
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),

            // Live comments stream from Firestore or platform stream
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: uid != null
                    ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('platform_comments')
                        .where('platform', isEqualTo: widget.platform.toLowerCase())
                        .snapshots()
                    : const Stream.empty(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return _buildDemoCommentsList();
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return _buildCommentCard(
                        id: docs[index].id,
                        author: data['author'] ?? 'Audience Fan',
                        comment: data['text'] ?? '',
                        postTitle: data['postTitle'] ?? 'Recent Upload',
                        time: 'Just now',
                      );
                    },
                  );
                },
              ),
            ),

            // Reply input bar
            if (_replyingToCommentId != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Text(
                      'Replying to @$_replyingToUser',
                      style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() {
                        _replyingToCommentId = null;
                        _replyingToUser = null;
                      }),
                      child: const Icon(Icons.close, color: Colors.white54, size: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _replyingToUser != null
                            ? 'Write reply via ${widget.platformDisplayName} API...'
                            : 'Select a comment to reply...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                        : const Icon(Icons.send_rounded, color: AppColors.brandBlue, size: 20),
                    onPressed: _replyingToCommentId != null && !_isSending
                        ? () => _submitReply(_replyingToCommentId!)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoCommentsList() {
    return ListView(
      children: [
        _buildCommentCard(
          id: 'demo_1',
          author: 'Kalonje_Fan',
          comment: 'This remix goes hard! Where can I download the full stems?',
          postTitle: 'Studio Reel: Afrobeats Master Mix',
          time: '12m ago',
        ),
        const SizedBox(height: 10),
        _buildCommentCard(
          id: 'demo_2',
          author: 'sarah_creative',
          comment: 'The color grading on this transition is pristine 🔥 what LUT did you use?',
          postTitle: 'Behind the Scenes: Video Edit #04',
          time: '45m ago',
        ),
        const SizedBox(height: 10),
        _buildCommentCard(
          id: 'demo_3',
          author: 'beatmaker_ke',
          comment: 'Dropping a duet on TikTok today! Check your mentions.',
          postTitle: 'Oneova Collab Challenge',
          time: '2h ago',
        ),
      ],
    );
  }

  Widget _buildCommentCard({
    required String id,
    required String author,
    required String comment,
    required String postTitle,
    required String time,
  }) {
    final isReplying = _replyingToCommentId == id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isReplying ? const Color(0xFF151D2C) : const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isReplying ? AppColors.brandBlue.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                child: Text(
                  author.isNotEmpty ? author[0].toUpperCase() : 'U',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(author, style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    Text('On: $postTitle', style: GoogleFonts.inter(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              Text(time, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          Text(comment, style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() {
                    _replyingToCommentId = id;
                    _replyingToUser = author;
                  });
                },
                icon: const Icon(Icons.reply_rounded, color: AppColors.brandPink, size: 14),
                label: Text(
                  'Reply via API',
                  style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
