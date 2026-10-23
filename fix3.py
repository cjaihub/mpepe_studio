with open('lib/feed/widgets/comment_bottom_sheet.dart', 'r') as f:
    text = f.read()

text = text.replace(
    'final commentsAsync = ref.watch(commentsStreamProvider(widget.return ClipRRect(',
    'final commentsAsync = ref.watch(commentsStreamProvider(widget.content.id));\n    return ClipRRect('
)

with open('lib/feed/widgets/comment_bottom_sheet.dart', 'w') as f:
    f.write(text)
