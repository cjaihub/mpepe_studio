import re
path = 'lib/shared/router.dart'
with open(path, 'r') as f:
    content = f.read()

content = re.sub(r'\s*GoRoute\(\s*path: \'/social_hub/unified_inbox\',.*?builder: \(context, state\) => const UnifiedInboxScreen\(\),\s*\),?', '', content, flags=re.DOTALL)

with open(path, 'w') as f:
    f.write(content)
