import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/router.dart';
import 'wellbeing_service.dart';

final appHeartbeatProvider = Provider<AppHeartbeatService>((ref) {
  final service = AppHeartbeatService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

class ScreenTimeLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLocked(bool locked) {
    state = locked;
  }
}

final screenTimeLockProvider = NotifierProvider<ScreenTimeLockNotifier, bool>(ScreenTimeLockNotifier.new);

/// Tracks active foreground time and syncs to Firestore.
/// Enforces digital wellbeing limits and triggers breaks.
class AppHeartbeatService extends WidgetsBindingObserver {
  final Ref _ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  Timer? _heartbeatTimer;
  int _currentSessionMinutes = 0;

  AppHeartbeatService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _stopHeartbeat();
    }
  }

  void _startHeartbeat() {
    if (_heartbeatTimer != null) return;
    _currentSessionMinutes = 0;
    
    // Heartbeat ticks every 1 minute of active foreground time
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _onHeartbeatTick();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _onHeartbeatTick() async {
    _currentSessionMinutes++;
    
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    
    // 1. Increment daily usage in Firestore
    final dateStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('engagement')
        .doc('daily_$dateStr');
        
    try {
      await docRef.set({
        'date': dateStr,
        'screenTimeMinutes': FieldValue.increment(1),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. Enforce limits based on preferences
      _checkWellbeingLimits(uid, docRef);
    } catch (e) {
      debugPrint('Failed to sync heartbeat: $e');
    }
  }

  Future<void> _checkWellbeingLimits(String uid, DocumentReference dailyDocRef) async {
    try {
      final prefsAsync = _ref.read(wellbeingPreferencesProvider);
      final prefs = prefsAsync.value;
      if (prefs == null) return;

      // Check daily limit
      if (prefs.screenTimeRemindersEnabled) {
        final dailyDoc = await dailyDocRef.get();
        if (dailyDoc.exists) {
          final data = dailyDoc.data() as Map<String, dynamic>;
          final int todayMinutes = data['screenTimeMinutes'] ?? 0;
          
          if (todayMinutes >= prefs.screenTimeLimitMinutes) {
            // Lock the screen directly by navigating
            _ref.read(screenTimeLockProvider.notifier).setLocked(true);
            final router = _ref.read(routerProvider);
            if (router.routerDelegate.currentConfiguration.uri.path != '/wellbeing/lock') {
              router.go('/wellbeing/lock');
            }
          }
        }
      }

      // Check continuous break limit
      if (prefs.breakRemindersEnabled && prefs.breakReminderIntervalMinutes > 0) {
        if (_currentSessionMinutes > 0 && _currentSessionMinutes % prefs.breakReminderIntervalMinutes == 0) {
          // Time for a break! We could trigger a local notification or snackbar
          debugPrint('Digital Wellbeing: Time for a break! You have been scrolling for $_currentSessionMinutes minutes.');
          // In a real app, integrate with a local push notification package or a global overlay
        }
      }
    } catch (e) {
      debugPrint('Error checking wellbeing limits: $e');
    }
  }
}
