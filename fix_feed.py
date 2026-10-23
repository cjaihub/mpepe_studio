import re

with open('lib/feed/main_feed_screen.dart', 'r') as f:
    text = f.read()

# find _onPageChanged
start = text.find('void _onPageChanged(int index) {')
end = text.find('}', text.find('if (index < _feed.length) {')) + 3 # roughly

new_func = """void _onPageChanged(int index) {
    final recommendationService = ref.read(recommendationServiceProvider);
    
    if (_feed.isNotEmpty && _currentIndex < _feed.length) {
      final prevVideo = _feed[_currentIndex];
    }

    setState(() {
      _currentIndex = index;
    });

    ref.read(videoPlaybackManagerProvider).initializeAndPreload(_feed, index);
    
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'currentUser';
    if (index < _feed.length) {
      ref.read(interactionRepositoryProvider).recordView(uid, _feed[index].id);
      recommendationService.trackEvent(uid, _feed[index].id, ContentInteractionType.impression, {});
    }
  }"""

# Actually, I'll just use simple string replacement since I have the line numbers
lines = text.split('\n')
lines[169:192] = new_func.split('\n')

with open('lib/feed/main_feed_screen.dart', 'w') as f:
    f.write('\n'.join(lines))
