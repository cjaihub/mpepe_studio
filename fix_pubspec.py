with open('pubspec.yaml', 'r') as f:
    content = f.read()

# Remove the incorrectly appended lines at the bottom
content = content.replace("""
  # GIF & Emoji support
  emoji_picker_flutter: ^4.3.0
  image: ^4.2.0
  gif_view: ^0.3.8
""", "")

# Add them properly in the dependencies section - right before the `path: any` line
content = content.replace("  path: any\n", """  path: any
  # GIF & Emoji support
  emoji_picker_flutter: ^4.3.0
  image: ^4.2.0
  gif_view: ^0.3.8
""")

with open('pubspec.yaml', 'w') as f:
    f.write(content)
