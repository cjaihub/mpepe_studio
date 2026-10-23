with open('lib/create/gif_creator_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("final url = await storageService.uploadBytes(\n        gifBytes,\n      );", "final url = await storageService.uploadBytes(\n        gifBytes, path\n      );")

with open('lib/create/gif_creator_screen.dart', 'w') as f:
    f.write(content)
