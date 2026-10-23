with open('lib/feed/main_feed_screen.dart', 'r') as f:
    code = f.read()

# I need to fix the extra brace.
# Let's restore the original _loadFeed completely to be safe.
# Find the start of _loadFeed
start_idx = code.find('Future<void> _loadFeed() async {')
# Find the end of _loadFeed (where the original `if (mounted)` ends)
# Since I messed up the braces, it might be tricky.

# Let's just fix the patch.
bad_patch = """      if (mounted) {
        setState(() {
          _feed = recommendations;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading feed: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }"""

good_patch = """      setState(() {
        _feed = recommendations;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading feed: $e');
    }"""

if bad_patch in code:
    code = code.replace(bad_patch, good_patch)
    with open('lib/feed/main_feed_screen.dart', 'w') as f:
        f.write(code)
    print("Fixed brace issue")
else:
    print("Could not find bad patch")
