import re

with open('lib/hub/screens/photo_studio/photo_studio_screen.dart', 'r') as f:
    content = f.read()

content = content.replace(r'\$', '$')
content = content.replace('Icons.camera_lens', 'Icons.camera')
content = content.replace("List<Offset> _curvePoints = const [Offset(0, 0), Offset(0.25, 0.25), Offset(0.75, 0.75), Offset(1, 1)];\n  ", "")
content = content.replace("import 'package:mpepe_studio/hub/screens/photo_studio/curves_editor.dart';", "")

with open('lib/hub/screens/photo_studio/photo_studio_screen.dart', 'w') as f:
    f.write(content)
