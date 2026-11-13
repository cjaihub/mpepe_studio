import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favourite and recently used filters, kept on this phone.
class FilterPrefs extends ChangeNotifier {
  FilterPrefs._();
  static final FilterPrefs instance = FilterPrefs._();

  static const _favKey = 'oneova_filter_favourites';
  static const _recentKey = 'oneova_filter_recent';
  static const _maxRecent = 30;

  List<String> _favs = const [];
  List<String> _recent = const [];
  bool _loaded = false;

  List<String> get favourites => _favs;
  List<String> get recent => _recent;
  bool isFavourite(String id) => _favs.contains(id);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _favs = p.getStringList(_favKey) ?? const [];
      _recent = p.getStringList(_recentKey) ?? const [];
      notifyListeners();
    } catch (e) {
      debugPrint('[FilterPrefs] load failed: $e');
    }
  }

  Future<void> toggleFavourite(String id) async {
    _favs = isFavourite(id) ? [..._favs.where((f) => f != id)] : [id, ..._favs];
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setStringList(_favKey, _favs);
    } catch (_) {}
  }

  Future<void> markUsed(String id) async {
    if (id == 'none') return;
    _recent = [id, ..._recent.where((f) => f != id)].take(_maxRecent).toList();
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setStringList(_recentKey, _recent);
    } catch (_) {}
  }
}
