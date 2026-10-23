import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/unified_inbox_provider.dart';

class SelectedInboxItemNotifier extends Notifier<UnifiedItem?> {
  @override
  UnifiedItem? build() => null;
  
  void select(UnifiedItem? item) {
    state = item;
  }
}

final selectedInboxItemProvider = NotifierProvider<SelectedInboxItemNotifier, UnifiedItem?>(() {
  return SelectedInboxItemNotifier();
});
