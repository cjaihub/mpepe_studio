with open('lib/feed/widgets/comment_bottom_sheet.dart', 'r') as f:
    text = f.read()

import re
text = re.sub(
    r'showModalBottomSheet\([\s\S]*?builder: \(context\) => Padding\(',
    '''showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(''',
    text
)
with open('lib/feed/widgets/comment_bottom_sheet.dart', 'w') as f:
    f.write(text)
