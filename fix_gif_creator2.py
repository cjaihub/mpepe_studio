with open('lib/create/gif_creator_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("onProgress: (p0) {},", "")

content = content.replace("Share.shareUri(Uri.parse(_gifUrl!), text: 'Check out my GIF from MPEPE Studio 🎬');", "Share.share(_gifUrl!, subject: 'Check out my GIF from MPEPE Studio 🎬');")

with open('lib/create/gif_creator_screen.dart', 'w') as f:
    f.write(content)
