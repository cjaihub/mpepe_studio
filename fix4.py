import re

with open('lib/feed/widgets/comment_bottom_sheet.dart', 'r') as f:
    text = f.read()

# I will replace the broken build method with the original but modified one.
start = text.find('Widget build(BuildContext context) {')
end = text.find('class _CommentTile extends ConsumerWidget {')

correct_build = """Widget build(BuildContext context) {
    final commentsAsync = ref.watch(commentsStreamProvider(widget.content.id));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.content.commentCount} Comments',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white70, size: 24),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        
        // Comment List
        Expanded(
          child: commentsAsync.when(
            data: (comments) {
              if (comments.isEmpty) {
                return const Center(
                  child: Text(
                    'Be the first to comment!',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 16, bottom: 24),
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  return _CommentTile(
                    comment: comments[index],
                    postAuthorId: widget.content.authorId,
                  );
                },
              );
            },
            loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
            error: (err, stack) => const Center(
              child: Text('Error loading comments', style: TextStyle(color: Colors.red)),
            ),
          ),
        ),
        
        // Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.transparent,
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Avatar
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.transparent,
                  child: Icon(Icons.person, color: Colors.white54, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _focusNode,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Add comment...',
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _postComment(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.smile, color: Colors.white54, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isPosting 
                    ? const SizedBox(width: 36, height: 36, child: Padding(padding: EdgeInsets.all(8), child: AnimatedLoadingIndicator(color: AppColors.brandBlue, strokeWidth: 2)))
                    : IconButton(
                        icon: const Icon(LucideIcons.send, color: AppColors.brandBlue),
                        onPressed: _postComment,
                      ),
              ],
            ),
          ),
        ),
      ],
    )))));
  }
}

"""

new_text = text[:start] + correct_build + text[end:]

with open('lib/feed/widgets/comment_bottom_sheet.dart', 'w') as f:
    f.write(new_text)

