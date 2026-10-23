with open('pubspec.yaml', 'r') as f:
    content = f.read()

content = content.replace("  gif_view: ^0.3.8\n", "  gif_view: ^1.0.3\n")

with open('pubspec.yaml', 'w') as f:
    f.write(content)
