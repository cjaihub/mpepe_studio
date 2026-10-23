import re
with open("lib/social_hub/profile/public_profile_screen.dart", "r") as f:
    text = f.read()

# Fix _ContentGrid
text = re.sub(
    r"@override\n\s*final postsAsync = ref\.watch\(_userContentProvider\(authorId\)\);",
    r"@override\n  Widget build(BuildContext context, WidgetRef ref) {\n    final postsAsync = ref.watch(_userContentProvider(authorId));",
    text
)

# Fix _RepostGrid
text = re.sub(
    r"@override\n\s*Widget build\(BuildContext context, WidgetRef ref\) \{\n\s*final repostsAsync = ref\.watch\(_userRepostsProvider\(userId\)\);",
    r"@override\n  Widget build(BuildContext context, WidgetRef ref) {\n    final repostsAsync = ref.watch(_userRepostsProvider(userId));",
    text
)

text = re.sub(
    r"@override\n\s*final repostsAsync = ref\.watch\(_userRepostsProvider\(userId\)\);",
    r"@override\n  Widget build(BuildContext context, WidgetRef ref) {\n    final repostsAsync = ref.watch(_userRepostsProvider(userId));",
    text
)

# Fix _TabBarDelegate build
text = re.sub(
    r"@override\n\s*Widget build\(\n\s*return Container\(color: AppColors\.darkBackground, child: _tabBar\);\n\s*\}",
    r"@override\n  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {\n    return Container(color: AppColors.darkBackground, child: _tabBar);\n  }",
    text
)

with open("lib/social_hub/profile/public_profile_screen.dart", "w") as f:
    f.write(text)

with open("lib/social_hub/profile/social_profile_view.dart", "r") as f:
    text2 = f.read()

text2 = text2.replace("user.following", "(0)")
text2 = text2.replace("user.followers", "(0)")
text2 = text2.replace("user.likes", "(0)")
with open("lib/social_hub/profile/social_profile_view.dart", "w") as f:
    f.write(text2)

