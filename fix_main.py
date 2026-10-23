import os

path = 'lib/main.dart'
with open(path, 'r') as f:
    content = f.read()

content = content.replace("  WidgetsBinding.instance;\n  WidgetsFlutterBinding.ensureInitialized();", "  WidgetsFlutterBinding.ensureInitialized();")

with open(path, 'w') as f:
    f.write(content)
print("Fixed main.dart binding crash")
