import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/settings_service.dart';

final settingsServiceProvider = Provider((ref) => SettingsService());

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Map<String, dynamic>>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends AsyncNotifier<Map<String, dynamic>> {
  String? _userId;

  @override
  FutureOr<Map<String, dynamic>> build() async {
    _userId = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != _userId) {
        _userId = user?.uid;
        _loadSettings();
      }
    });
    
    if (_userId == null) {
      return {};
    } else {
      final service = ref.read(settingsServiceProvider);
      return await service.getSettings(_userId!);
    }
  }

  Future<void> _loadSettings() async {
    if (_userId == null) {
      state = const AsyncValue.data({});
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(settingsServiceProvider);
      return await service.getSettings(_userId!);
    });
  }

  Future<void> updateCategory(String category, Map<String, dynamic> data) async {
    if (_userId == null) return;
    
    final currentData = state.value ?? {};
    final updatedData = Map<String, dynamic>.from(currentData);
    
    if (updatedData.containsKey(category)) {
      final categoryData = Map<String, dynamic>.from(updatedData[category] as Map<String, dynamic>);
      data.forEach((key, value) {
        categoryData[key] = value;
      });
      updatedData[category] = categoryData;
    } else {
      updatedData[category] = data;
    }
    
    state = AsyncValue.data(updatedData);
    
    try {
      final service = ref.read(settingsServiceProvider);
      await service.updateSettingsCategory(_userId!, category, data);
    } catch (e) {
      _loadSettings();
    }
  }

  Future<void> updateSetting(String category, String key, dynamic value) async {
    await updateCategory(category, {key: value});
  }
}
