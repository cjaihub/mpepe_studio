import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:qr/qr.dart';

import '../agent_workspace/ova_agent_mac_executor.dart';
import '../agent_workspace/ova_agent_models.dart';
import '../agent_workspace/ova_agent_sync_controller.dart';
import '../agent_workspace/widgets/oneova_workstation_auth_dialog.dart';
import '../agent_workspace/widgets/ova_claude_agent_workspace.dart';
import '../auth/security/login_security.dart';
import '../auth/services/oneova_biometrics_service.dart';
import '../auth/services/oneova_smart_phone_engine.dart';
import '../auth/widgets/oneova_auth_backdrop.dart';
import '../backend/native_plugin_server.dart';
import '../backend/secure_pairing/crypto_utils.dart';
import '../backend/secure_pairing/secure_pairing_service.dart';
import '../backend/telemetry/desktop_telemetry_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/theme/theme_provider.dart';
import 'desktop_firebase_rest_client.dart';
import 'desktop_webrtc_responder.dart';
import 'macos_mouse_ffi.dart';

enum _DesktopAuthTab {
  signIn,
  qrSession,
  codeSession,
}

class DesktopAgentScreen extends ConsumerStatefulWidget {
  const DesktopAgentScreen({super.key});

  @override
  ConsumerState<DesktopAgentScreen> createState() => _DesktopAgentScreenState();
}

class _DesktopAgentScreenState extends ConsumerState<DesktopAgentScreen> {
  final DesktopFirebaseRestClient _cloud = DesktopFirebaseRestClient.instance;
  final OneovaSmartPhoneEngine _phoneEngine = OneovaSmartPhoneEngine();
  final String _computerName = Platform.localHostname;
  final List<String> _recentCommands = [];

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _DesktopAuthTab _activeTab = _DesktopAuthTab.qrSession;
  bool _usePhoneSignIn = true;
  bool _passwordVisible = false;

  CountryPhoneMeta _selectedCountryMeta = OneovaSmartPhoneEngine.defaultCountry;
  String _selectedCountryIso = 'KE';
  String _formatHint = 'e.g. 0712 345 678';

  Timer? _lookupDebounce;
  bool _isCheckingAccount = false;
  Map<String, dynamic>? _identifiedUser;

  bool _biometricsAvailable = false;
  String _biometricLabel = 'Touch ID';
  String? _bioQuickAccountLabel;

  String? _pairedOwnerUid;
  String? _pairedAccountDisplay;
  bool _authInitializing = true;
  bool _signingIn = false;
  bool _publishingSession = false;
  String? _authError;
  String? _authInfo;
  String _activeWindow = 'Desktop';
  bool _showSystemsPane = false;

  StreamSubscription<List<DesktopRestDoc>>? _pairingSubscription;
  StreamSubscription<List<DesktopRestDoc>>? _commandSubscription;
  StreamSubscription<List<DesktopRestDoc>>? _viewerSubscription;
  final Set<String> _handledResponseIds = {};
  final Set<String> _handledCommandIds = {};
  Timer? _heartbeatTimer;
  Timer? _liveFrameTimer;
  bool _hasActiveMobileViewer = false;
  bool _capturingLiveFrame = false;
  List<String> _cachedOpenApps = const ['Finder', 'Safari', 'Terminal'];
  DateTime _lastOpenAppsFetch = DateTime.fromMillisecondsSinceEpoch(0);
  DesktopTelemetryService? _telemetry;
  late final DesktopWebRTCResponder _webrtcResponder;

  String? get _effectiveOwnerUid {
    if (_cloud.isAccountUser && _cloud.currentUid != null) {
      return _cloud.currentUid;
    }
    return _pairedOwnerUid;
  }

  String? get _agentAuthUid => _cloud.currentUid;

  String get _completePhoneE164 {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return '';
    return _phoneEngine
        .parseAndNormalize(input: raw, fallbackCountry: _selectedCountryMeta)
        .e164;
  }

  bool get _capsLockOn => HardwareKeyboard.instance.lockModesEnabled
      .contains(KeyboardLockMode.capsLock);

  String _deviceIdFor(String ownerUid) {
    final cleanHost = _computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'desktop_${ownerUid}_$cleanHost';
  }

  @override
  void initState() {
    super.initState();
    OvaAgentMacExecutor.instance
      ..onSendHotkey = MacOSMouseController.sendHotkey
      ..onTypeText = MacOSMouseController.typeString
      ..onGetActiveWindow = MacOSMouseController.getActiveAppName
      ..onAuditLog = _recordCommandLog;
    _webrtcResponder = DesktopWebRTCResponder(
      cloudClient: _cloud,
      onAiCommand: _handleAiTaskExecution,
      onControlEvent: _recordCommandLog,
    );
    _phoneController.addListener(_scheduleAccountLookup);
    _emailController.addListener(_scheduleAccountLookup);
    _initDesktopAgent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _telemetry = ref.read(desktopTelemetryProvider);
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pairingSubscription?.cancel();
    _commandSubscription?.cancel();
    _viewerSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _liveFrameTimer?.cancel();
    _telemetry?.stop();
    _webrtcResponder.dispose();
    super.dispose();
  }

  void _recordCommandLog(String entry) {
    if (!mounted) return;
    setState(() {
      _recentCommands.insert(0, entry);
      if (_recentCommands.length > 6) {
        _recentCommands.removeLast();
      }
    });
  }

  Future<void> _initDesktopAgent() async {
    setState(() {
      _authInitializing = true;
      _authError = null;
      _authInfo = null;
    });

    try {
      await NativePluginServer().start();
    } catch (e) {
      debugPrint('[DesktopAgent] NativePluginServer notice: $e');
    }

    unawaited(_initPhoneCountryAndBiometrics());

    try {
      await _cloud.ensureAuthenticated();
    } catch (e) {
      debugPrint('[DesktopAgent] Bootstrap notice: $e');
      if (mounted) {
        setState(() {
          _authInitializing = false;
          _activeTab = _DesktopAuthTab.signIn;
          _authError = 'Sign in with your Oneova account to authorize this workstation.';
        });
      }
      return;
    }

    final pairingService = ref.read(securePairingProvider.notifier);
    final persistedUid = await pairingService.loadPersistedPairing();
    final rememberedLabel = await _cloud.getBiometricQuickAccountLabel();

    if (mounted) {
      setState(() {
        if (persistedUid != null) {
          _pairedOwnerUid = persistedUid;
        }
        _pairedAccountDisplay = rememberedLabel;
        _authInitializing = false;
      });
    }

    if (_effectiveOwnerUid != null) {
      await _activatePairedServices();
    } else {
      await _startSecurePairing();
    }
  }

  Future<void> _initPhoneCountryAndBiometrics() async {
    try {
      final detected = await _phoneEngine.detectCountrySilently();
      if (mounted) {
        setState(() {
          _selectedCountryMeta = detected;
          _selectedCountryIso = detected.isoCode;
          _formatHint = detected.formatHint;
        });
      }
    } catch (_) {}

    try {
      final bioService = ref.read(oneovaBiometricsServiceProvider);
      final avail = await bioService.isBiometricsAvailable();
      final label = await bioService.getBiometricTypeLabel();
      final quickLabel = await _cloud.getBiometricQuickAccountLabel();
      if (mounted) {
        setState(() {
          _biometricsAvailable = avail;
          _biometricLabel = label;
          _bioQuickAccountLabel = quickLabel;
        });
      }
    } catch (_) {}
  }

  void _scheduleAccountLookup() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 420), _runAccountLookup);
  }

  Future<void> _runAccountLookup() async {
    if (_usePhoneSignIn) {
      final e164 = _completePhoneE164;
      if (e164.replaceAll(RegExp(r'\D'), '').length < 8) {
        if (mounted && _identifiedUser != null) {
          setState(() => _identifiedUser = null);
        }
        return;
      }
      if (mounted) setState(() => _isCheckingAccount = true);
      final found = await _cloud.lookupAccount(phone: e164);
      if (mounted) {
        setState(() {
          _isCheckingAccount = false;
          _identifiedUser = found;
        });
      }
    } else {
      final email = _emailController.text.trim();
      if (!email.contains('@') || !email.contains('.')) {
        if (mounted && _identifiedUser != null) {
          setState(() => _identifiedUser = null);
        }
        return;
      }
      if (mounted) setState(() => _isCheckingAccount = true);
      final found = await _cloud.lookupAccount(email: email);
      if (mounted) {
        setState(() {
          _isCheckingAccount = false;
          _identifiedUser = found;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Authentication Flows (Phone + Password, Email + Password, Google, Touch ID)
  // ---------------------------------------------------------------------------

  Future<void> _signInWithCredentials() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _authError = 'Enter your Oneova password.');
      return;
    }

    String targetEmail;
    String rememberLabel;

    if (_usePhoneSignIn) {
      final e164 = _completePhoneE164;
      if (e164.replaceAll(RegExp(r'\D'), '').length < 7) {
        setState(() => _authError = 'Enter your mobile number first.');
        return;
      }
      targetEmail = LoginSecurity.authEmailForPhone(e164);
      final handle = _identifiedUser?['username'] as String?;
      rememberLabel = handle != null && handle.isNotEmpty ? '@$handle • $e164' : e164;
    } else {
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        setState(() => _authError = 'Enter a valid email address.');
        return;
      }
      targetEmail = email;
      final handle = _identifiedUser?['username'] as String?;
      rememberLabel = handle != null && handle.isNotEmpty ? '@$handle • $email' : email;
    }

    setState(() {
      _signingIn = true;
      _authError = null;
      _authInfo = null;
    });

    try {
      final uid = await _cloud.signInWithEmailAndPassword(
        email: targetEmail,
        password: password,
      );
      await _cloud.setRememberedAccountLabel(rememberLabel);
      _passwordController.clear();

      if (!mounted) return;
      setState(() {
        _pairedOwnerUid = uid;
        _pairedAccountDisplay = rememberLabel;
        _bioQuickAccountLabel = rememberLabel;
        _signingIn = false;
      });
      await _pairingSubscription?.cancel();
      _pairingSubscription = null;
      await _activatePairedServices();
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _authError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _authError = e.toString();
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _signingIn = true;
      _authError = null;
      _authInfo = null;
    });

    try {
      final uid = await _cloud.signInWithGoogle();
      final label = await _cloud.getBiometricQuickAccountLabel();
      if (!mounted) return;
      setState(() {
        _pairedOwnerUid = uid;
        _pairedAccountDisplay = label;
        _bioQuickAccountLabel = label;
        _signingIn = false;
      });
      await _pairingSubscription?.cancel();
      _pairingSubscription = null;
      await _activatePairedServices();
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          if (e.code != 'canceled') {
            _authError = e.message;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _authError = e.toString();
        });
      }
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() {
      _authError = null;
      _authInfo = null;
    });

    try {
      final bio = ref.read(oneovaBiometricsServiceProvider);
      final ok = await bio.authenticate(
        reason: 'Sign in to Oneova Computer Agent',
      );
      if (!ok) return;

      setState(() => _signingIn = true);
      final uid = await _cloud.signInWithRememberedBiometricToken();
      final label = await _cloud.getBiometricQuickAccountLabel();
      if (!mounted) return;
      setState(() {
        _pairedOwnerUid = uid;
        _pairedAccountDisplay = label;
        _signingIn = false;
      });
      await _pairingSubscription?.cancel();
      _pairingSubscription = null;
      await _activatePairedServices();
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _authError = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _authError = e.toString();
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _usePhoneSignIn = false;
        _authError = 'Enter your Oneova email address above, then click Reset Password.';
      });
      return;
    }

    setState(() {
      _authError = null;
      _authInfo = null;
    });

    try {
      await _cloud.sendPasswordResetEmail(email);
      if (mounted) {
        setState(() {
          _authInfo = 'Password reset link sent to $email.';
        });
      }
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() => _authError = e.message);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // QR Session & 6-Digit Session Code Pairing
  // ---------------------------------------------------------------------------

  Future<void> _startSecurePairing() async {
    await _pairingSubscription?.cancel();
    _pairingSubscription = null;
    _handledResponseIds.clear();

    if (mounted) {
      setState(() {
        _publishingSession = true;
        _authError = null;
      });
    }

    try {
      await _cloud.ensureAuthenticated();
    } catch (e) {
      if (mounted) {
        setState(() {
          _publishingSession = false;
          _authError = 'Unable to initialize pairing channel: $e';
        });
      }
      return;
    }

    final pairingService = ref.read(securePairingProvider.notifier);
    final pin = pairingService.generatePairingPin();
    final salt = ref.read(securePairingProvider).salt;
    final agentUid = _agentAuthUid;

    debugPrint('[DesktopAgent] Session PIN & QR ready: $pin (agent_uid=$agentUid)');

    try {
      await _cloud.setDocument('desktop_pairing/$pin', {
        'computer_name': _computerName,
        'salt': salt,
        'agent_uid': ?agentUid,
        'os': Platform.operatingSystem,
        'status': 'waiting',
        'created_at': DateTime.now().toUtc(),
      });
    } catch (e) {
      debugPrint('[DesktopAgent] Failed to publish pairing PIN: $e');
      if (mounted) {
        setState(() {
          _publishingSession = false;
          _authError = 'Pairing channel error: $e';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _publishingSession = false);
    }

    _pairingSubscription = _cloud
        .watchCollection(
          'desktop_pairing/$pin/responses',
          interval: const Duration(milliseconds: 1000),
          idleInterval: const Duration(seconds: 3),
        )
        .listen(
      (docs) async {
        for (final doc in docs) {
          if (!_handledResponseIds.add(doc.id)) continue;
          final encryptedUid = doc.data['encrypted_uid'] as String?;
          if (encryptedUid == null || encryptedUid.isEmpty) continue;

          final key = CryptoUtils.deriveKeyFromPin(pin, salt);
          final decryptedUid = CryptoUtils.decryptPayload(encryptedUid, key);
          // The reply is stored under the replying account's id (Firestore
          // rules), so a reply can only pair the account that sent it.
          if (decryptedUid != null && decryptedUid.isNotEmpty && decryptedUid == doc.id) {
            pairingService.setDerivedKey(key);
            await pairingService.persistPairing(decryptedUid, key);
            await _pairingSubscription?.cancel();
            _pairingSubscription = null;

            unawaited(_cloud.deleteDocument('desktop_pairing/$pin').catchError((_) {}));

            if (mounted) {
              setState(() {
                _pairedOwnerUid = decryptedUid;
              });
            }
            await _activatePairedServices();
            return;
          }
        }
      },
      onError: (Object err) {
        debugPrint('[DesktopAgent] Pairing watch notice: $err');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Paired Workstation Services (Registration, Commands, Telemetry, WebRTC)
  // ---------------------------------------------------------------------------

  Future<void> _activatePairedServices() async {
    final ownerUid = _effectiveOwnerUid;
    if (ownerUid == null) return;
    final deviceId = _deviceIdFor(ownerUid);

    try {
      await _registerComputer(ownerUid, deviceId);
    } on DesktopCloudException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'not-found') {
        debugPrint(
          '[DesktopAgent] Stale pairing ($e); starting fresh QR / Code session.',
        );
        await ref.read(securePairingProvider.notifier).clearPairing();
        if (_cloud.isAccountUser) {
          await _cloud.signOutAccount();
          await _cloud.ensureAuthenticated();
        }
        if (mounted) {
          setState(() => _pairedOwnerUid = null);
        }
        await _startSecurePairing();
        return;
      }
      rethrow;
    }

    _listenForCommands(deviceId);
    _listenForMobileViewers(deviceId);
    ref.read(desktopTelemetryProvider).start(deviceId);
    ref.read(ovaAgentSyncProvider.notifier).bindDesktopWorkstation(
          deviceId: deviceId,
          computerName: _computerName,
          activeWindow: _activeWindow,
          ownerUid: ownerUid,
        );
    await _webrtcResponder.start(deviceId);
    // Publish an initial live preview frame so ConnectScreen & Remote Control have instant display
    unawaited(_publishLiveScreenFrame(deviceId, force: true));

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      final activeApp = await MacOSMouseController.getActiveAppName();
      if (activeApp != null && mounted && activeApp != _activeWindow) {
        setState(() => _activeWindow = activeApp);
        ref.read(ovaAgentSyncProvider.notifier).updateDesktopActiveWindow(activeApp);
      }
      final currentOwner = _effectiveOwnerUid;
      if (currentOwner != null) {
        final currentDeviceId = _deviceIdFor(currentOwner);
        try {
          await _cloud.updateDocument(
            'registered_computers/$currentDeviceId',
            {
              'desktop_connected': true,
              'status': 'online',
              'active_window': activeApp ?? _activeWindow,
              'last_seen': DateTime.now().toUtc(),
            },
          );
        } catch (_) {}
      }
    });
  }

  void _listenForMobileViewers(String deviceId) {
    _viewerSubscription?.cancel();
    _viewerSubscription = _cloud
        .watchCollection(
          'registered_computers/$deviceId/viewer_sessions',
          interval: const Duration(milliseconds: 1500),
          idleInterval: const Duration(seconds: 5),
        )
        .listen(
      (docs) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        bool active = false;
        for (final doc in docs) {
          final untilMs = (doc.data['active_until_ms'] as num?)?.toInt() ?? 0;
          if (untilMs > nowMs) {
            active = true;
            break;
          }
        }
        _hasActiveMobileViewer = active;
        _syncLiveFramePublisher(deviceId);
      },
      onError: (Object e) {
        debugPrint('[DesktopAgent] Viewer sessions notice: $e');
      },
    );
  }

  void _syncLiveFramePublisher(String deviceId) {
    if (_hasActiveMobileViewer) {
      if (_liveFrameTimer == null || !_liveFrameTimer!.isActive) {
        unawaited(_publishLiveScreenFrame(deviceId, force: true));
        _liveFrameTimer = Timer.periodic(
          const Duration(milliseconds: 950),
          (_) => unawaited(_publishLiveScreenFrame(deviceId)),
        );
      }
    } else {
      _liveFrameTimer?.cancel();
      _liveFrameTimer = null;
    }
  }

  Future<List<String>> _getOpenGuiApps() async {
    if (!Platform.isMacOS) return _cachedOpenApps;
    if (DateTime.now().difference(_lastOpenAppsFetch).inSeconds < 8) {
      return _cachedOpenApps;
    }
    try {
      final res = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get name of every application process whose background only is false',
      ]);
      if (res.exitCode == 0) {
        final apps = res.stdout
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .take(12)
            .toList();
        if (apps.isNotEmpty) {
          _cachedOpenApps = apps;
          _lastOpenAppsFetch = DateTime.now();
        }
      }
    } catch (_) {}
    return _cachedOpenApps;
  }

  Future<void> _publishLiveScreenFrame(
    String deviceId, {
    bool force = false,
  }) async {
    if (!Platform.isMacOS) return;
    if (!force && !_hasActiveMobileViewer) return;
    if (_capturingLiveFrame) return;

    _capturingLiveFrame = true;
    final tmpPath =
        '${Directory.systemTemp.path}/oneova_live_${deviceId.hashCode.abs()}.jpg';
    try {
      final capRes = await Process.run(
        '/usr/sbin/screencapture',
        ['-x', '-C', '-t', 'jpg', tmpPath],
      );
      final file = File(tmpPath);
      if (capRes.exitCode != 0 || !await file.exists()) {
        return;
      }

      await Process.run(
        '/usr/bin/sips',
        ['-Z', '1024', '-s', 'formatOptions', '56', tmpPath],
      );

      final bytes = await file.readAsBytes();
      unawaited(file.delete().catchError((_) => file));
      if (bytes.isEmpty || bytes.length > 720000) return;

      final bounds = MacOSMouseController.getMainDisplayBounds();
      final cursor = MacOSMouseController.getCursorPosition();
      final apps = await _getOpenGuiApps();
      final cursorNx = bounds.width > 0
          ? (cursor.x / bounds.width).clamp(0.0, 1.0)
          : 0.5;
      final cursorNy = bounds.height > 0
          ? (cursor.y / bounds.height).clamp(0.0, 1.0)
          : 0.5;

      await _cloud.setDocument(
        'registered_computers/$deviceId/live_stream/current',
        {
          'frame_b64': base64Encode(bytes),
          'width': bounds.width,
          'height': bounds.height,
          'cursor_nx': cursorNx,
          'cursor_ny': cursorNy,
          'active_window': _activeWindow,
          'computer_name': _computerName,
          'open_apps': apps,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        merge: true,
      );
    } catch (e) {
      debugPrint('[DesktopAgent] Live frame publish notice: $e');
    } finally {
      _capturingLiveFrame = false;
    }
  }

  Future<void> _registerComputer(String ownerUid, String deviceId) async {
    final activeApp = await MacOSMouseController.getActiveAppName();
    if (activeApp != null && mounted) {
      setState(() => _activeWindow = activeApp);
    }

    final statusFields = <String, dynamic>{
      'computer_name': _computerName,
      'os': Platform.operatingSystem,
      'desktop_connected': true,
      'status': 'online',
      'is_locked': false,
      'is_sleeping': false,
      'requires_passkey': false,
      'active_window': activeApp ?? _activeWindow,
      'system_info': {
        'hostname': _computerName,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
      },
      'software': {
        'webrtc_stream': 'online',
        'input_bridge': 'online',
        'plugin_ws': 'ws://127.0.0.1:8080',
      },
      'last_seen': DateTime.now().toUtc(),
    };

    if (_cloud.isAccountUser && _cloud.currentUid == ownerUid) {
      await _cloud.setDocument(
        'registered_computers/$deviceId',
        {
          'owner_uid': ownerUid,
          ...statusFields,
        },
        merge: true,
      );
    } else {
      await _cloud.updateDocument(
        'registered_computers/$deviceId',
        statusFields,
      );
    }
  }

  void _listenForCommands(String deviceId) {
    _commandSubscription?.cancel();
    _handledCommandIds.clear();
    _commandSubscription = _cloud
        .watchCollection(
          'registered_computers/$deviceId/commands',
          interval: const Duration(milliseconds: 950),
          idleInterval: const Duration(seconds: 3),
        )
        .listen(
      (docs) {
        for (final doc in docs) {
          final status = (doc.data['status'] ?? '').toString();
          if (status != 'pending') continue;
          if (!_handledCommandIds.add(doc.id)) continue;
          unawaited(_executeCommand(deviceId, doc.id, doc.data));
        }
      },
      onError: (Object e) {
        debugPrint('[DesktopAgent] Commands stream notice: $e');
      },
    );
  }

  Future<void> _executeCommand(
    String deviceId,
    String docId,
    Map<String, dynamic> data,
  ) async {
    final softwareId = (data['software_id'] ?? 'system').toString();
    final command = (data['command'] ?? 'unknown').toString();

    final encryptedPayload = data['payload_encrypted'] as String?;
    String? decryptedPayloadJson;

    if (encryptedPayload != null && encryptedPayload.isNotEmpty) {
      final key = ref.read(securePairingProvider).activeKey;
      if (key != null) {
        decryptedPayloadJson = CryptoUtils.decryptPayload(encryptedPayload, key);
      }
    }

    _recordCommandLog(
      '${encryptedPayload != null && encryptedPayload.isNotEmpty ? "E2EE • " : ""}$softwareId: $command',
    );

    if (encryptedPayload != null &&
        encryptedPayload.isNotEmpty &&
        decryptedPayloadJson == null) {
      await _cloud.updateDocument(
        'registered_computers/$deviceId/commands/$docId',
        {
          'status': 'error',
          'result_message': 'Failed to decrypt payload (E2EE key mismatch)',
        },
      );
      return;
    }

    Map<String, dynamic> payloadMap = {};
    if (decryptedPayloadJson != null) {
      try {
        payloadMap = jsonDecode(decryptedPayloadJson) as Map<String, dynamic>;
      } catch (_) {}
    } else if (data['payload'] is Map) {
      payloadMap = Map<String, dynamic>.from(data['payload'] as Map);
    }

    NativePluginServer().broadcastCommand(command, payloadMap);
    final agentNotifier = ref.read(ovaAgentSyncProvider.notifier);

    if (command == 'wake_and_unlock' || command == 'unlock_workstation') {
      final passkey =
          (payloadMap['password'] ?? payloadMap['passkey'] ?? data['passkey'] ?? '')
              .toString();
      final cleanPass = passkey == 'biometric_passkey_verified' ? '' : passkey;
      await MacOSMouseController.wakeAndUnlock(cleanPass);
      agentNotifier.recordLiveActionEvent(
        category: 'system',
        summary: 'Wake & unlock workstation',
        originOverride: 'mobile',
      );
    } else if (command == 'sleep_workstation') {
      await Process.run('pmset', ['displaysleepnow']);
      agentNotifier.recordLiveActionEvent(
        category: 'system',
        summary: 'Sleep workstation display',
        originOverride: 'mobile',
      );
    } else if (command == 'key_tap') {
      final key = (payloadMap['key'] ?? data['key'] ?? '').toString();
      await MacOSMouseController.tapKey(key);
      agentNotifier.recordLiveActionEvent(
        category: 'keyboard',
        summary: 'Key tap: $key',
        originOverride: 'mobile',
      );
    } else if (command == 'key_combination') {
      final combo = (payloadMap['combo'] ?? data['combo'] ?? '').toString();
      await MacOSMouseController.sendHotkey(combo);
      agentNotifier.recordLiveActionEvent(
        category: 'keyboard',
        summary: 'Shortcut: $combo',
        originOverride: 'mobile',
      );
    } else if (command == 'paste_text' || command == 'type_text') {
      final text = (payloadMap['text'] ?? data['text'] ?? '').toString();
      final pressEnter = payloadMap['pressEnter'] == true || data['pressEnter'] == true;
      await MacOSMouseController.pasteTextInstant(text, pressEnter: pressEnter);
      final isWispr = softwareId == 'wispr_flow' || payloadMap['source'] == 'wispr_mobile';
      agentNotifier.recordLiveActionEvent(
        category: isWispr ? 'wispr' : 'keyboard',
        summary:
            '${isWispr ? "Wispr Flow" : "Typed"} (${text.length} chars) → $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_left_down') {
      MacOSMouseController.leftClickDown();
    } else if (command == 'mouse_left_up') {
      MacOSMouseController.leftClickUp();
    } else if (command == 'mouse_left_click') {
      MacOSMouseController.click();
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Left click on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_right_click') {
      MacOSMouseController.rightClick();
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Right click on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_double_click') {
      MacOSMouseController.doubleClick();
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Double click on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_scroll') {
      final dy = ((payloadMap['dy'] ?? data['dy']) as num?)?.toDouble() ?? 0.0;
      MacOSMouseController.scroll(dy);
    } else if (command == 'mouse_move') {
      final dx = ((payloadMap['dx'] ?? data['dx']) as num?)?.toDouble() ?? 0.0;
      final dy = ((payloadMap['dy'] ?? data['dy']) as num?)?.toDouble() ?? 0.0;
      MacOSMouseController.moveBy(dx, dy);
    } else if (command == 'mouse_move_to') {
      final x = ((payloadMap['x'] ?? data['x']) as num?)?.toDouble() ?? 0.0;
      final y = ((payloadMap['y'] ?? data['y']) as num?)?.toDouble() ?? 0.0;
      MacOSMouseController.moveTo(x, y);
    } else if (command == 'mouse_move_normalized') {
      final nx = (((payloadMap['nx'] ?? data['nx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final ny = (((payloadMap['ny'] ?? data['ny']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final bounds = MacOSMouseController.getMainDisplayBounds();
      MacOSMouseController.moveTo(nx * bounds.width, ny * bounds.height);
    } else if (command == 'mouse_click_normalized') {
      final nx = (((payloadMap['nx'] ?? data['nx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final ny = (((payloadMap['ny'] ?? data['ny']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final bounds = MacOSMouseController.getMainDisplayBounds();
      MacOSMouseController.clickAt(nx * bounds.width, ny * bounds.height);
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Tap (${(nx * 100).round()}%, ${(ny * 100).round()}%) on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_right_click_normalized') {
      final nx = (((payloadMap['nx'] ?? data['nx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final ny = (((payloadMap['ny'] ?? data['ny']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final bounds = MacOSMouseController.getMainDisplayBounds();
      MacOSMouseController.clickAt(
        nx * bounds.width,
        ny * bounds.height,
        right: true,
      );
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Right click (${(nx * 100).round()}%, ${(ny * 100).round()}%) on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_double_click_normalized') {
      final nx = (((payloadMap['nx'] ?? data['nx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final ny = (((payloadMap['ny'] ?? data['ny']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final bounds = MacOSMouseController.getMainDisplayBounds();
      MacOSMouseController.clickAt(
        nx * bounds.width,
        ny * bounds.height,
        doubleClick: true,
      );
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Double click (${(nx * 100).round()}%, ${(ny * 100).round()}%) on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'mouse_drag_normalized') {
      final fromNx = (((payloadMap['fromNx'] ?? data['fromNx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final fromNy = (((payloadMap['fromNy'] ?? data['fromNy']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final toNx = (((payloadMap['toNx'] ?? data['toNx']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final toNy = (((payloadMap['toNy'] ?? data['toNy']) as num?)?.toDouble() ?? 0.5)
          .clamp(0.0, 1.0);
      final bounds = MacOSMouseController.getMainDisplayBounds();
      MacOSMouseController.moveTo(fromNx * bounds.width, fromNy * bounds.height);
      await MacOSMouseController.dragTo(toNx * bounds.width, toNy * bounds.height);
      agentNotifier.recordLiveActionEvent(
        category: 'mouse',
        summary: 'Dragged on $_activeWindow',
        originOverride: 'mobile',
      );
    } else if (command == 'capture_live_frame') {
      await _publishLiveScreenFrame(deviceId, force: true);
    } else if (command == 'switch_app') {
      final appName = (payloadMap['appName'] ?? data['appName'] ?? '').toString().trim();
      if (appName.isNotEmpty) {
        await Process.run('open', ['-a', appName]);
        final nowActive = await MacOSMouseController.getActiveAppName();
        if (nowActive != null && mounted) {
          setState(() => _activeWindow = nowActive);
        }
        agentNotifier.recordLiveActionEvent(
          category: 'system',
          summary: 'Switched to $appName',
          originOverride: 'mobile',
        );
      }
    } else if (command == 'sync_clipboard') {
      final text = (payloadMap['text'] ?? data['text'] ?? '').toString();
      if (text.isNotEmpty) {
        await MacOSMouseController.writeClipboard(text);
        agentNotifier.recordLiveActionEvent(
          category: 'system',
          summary: 'Synced mobile clipboard (${text.length} chars) to Mac',
          originOverride: 'mobile',
        );
      } else {
        final macClip = await MacOSMouseController.readClipboard();
        await _cloud.updateDocument(
          'registered_computers/$deviceId/commands/$docId',
          {
            'status': 'completed',
            'clipboard_text': macClip,
            'result_message': 'Read Mac clipboard (${macClip.length} chars)',
          },
        );
        return;
      }
    } else if (command == 'system_control') {
      await OvaAgentMacExecutor.instance.execute(
        OvaAgentToolCall(
          id: docId,
          name: 'system_control',
          title: 'Remote System Control',
          args: payloadMap,
        ),
      );
      agentNotifier.recordLiveActionEvent(
        category: 'system',
        summary: 'System control: ${payloadMap['action'] ?? command}',
        originOverride: 'mobile',
      );
    } else if (command == 'open_mac_app') {
      await OvaAgentMacExecutor.instance.execute(
        OvaAgentToolCall(
          id: docId,
          name: 'open_mac_app',
          title: 'Open Mac App',
          args: payloadMap,
        ),
      );
      agentNotifier.recordLiveActionEvent(
        category: 'system',
        summary: 'Opened app: ${payloadMap['appName'] ?? "Finder"}',
        originOverride: 'mobile',
      );
    } else if (command == 'play_pause') {
      await MacOSMouseController.tapKey('space');
    } else if (command == 'sync_project') {
      await MacOSMouseController.sendHotkey('cmd+s');
    } else if (command == 'render_and_send') {
      await MacOSMouseController.sendHotkey('cmd+e');
    } else if (command == 'execute_ai_task') {
      final prompt = (payloadMap['prompt'] ?? data['prompt'] ?? '').toString();
      await _handleAiTaskExecution(prompt);
    }

    await _cloud.updateDocument(
      'registered_computers/$deviceId/commands/$docId',
      {
        'status': 'completed',
        'result_message': 'Executed on $_computerName via Oneova Computer Agent',
      },
    );

    if (_hasActiveMobileViewer) {
      Future<void>.delayed(
        const Duration(milliseconds: 160),
        () => unawaited(_publishLiveScreenFrame(deviceId, force: true)),
      );
    }
  }

  Future<void> _handleAiTaskExecution(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return;
    NativePluginServer().broadcastCommand('execute_ai_task', {'prompt': trimmed});
    ref.read(ovaAgentSyncProvider.notifier).recordLiveActionEvent(
          category: 'agent',
          summary: 'Remote AI instruction: "$trimmed"',
          originOverride: 'mobile',
        );
    unawaited(ref.read(ovaAgentSyncProvider.notifier).sendPrompt(trimmed));
  }

  Future<void> _confirmAndDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogCtx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: dialogCtx.border, width: 1.0),
        ),
        title: Text(
          'Disconnect Workstation?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dialogCtx.textPrimary,
          ),
        ),
        content: Text(
          'This stops live WebRTC screen streaming, hardware telemetry, and ends the active workstation session.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: dialogCtx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: dialogCtx.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Disconnect',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final ownerUid = _effectiveOwnerUid;
    if (ownerUid != null) {
      try {
        await _cloud.updateDocument(
          'registered_computers/${_deviceIdFor(ownerUid)}',
          {
            'desktop_connected': false,
            'status': 'offline',
            'last_seen': DateTime.now().toUtc(),
          },
        );
      } catch (_) {}
    }

    _heartbeatTimer?.cancel();
    await _commandSubscription?.cancel();
    _telemetry?.stop();
    ref.read(ovaAgentSyncProvider.notifier).unbindDesktopWorkstation();
    await _webrtcResponder.stop();
    await ref.read(securePairingProvider.notifier).clearPairing();
    await _cloud.signOutAccount();

    if (mounted) {
      setState(() {
        _pairedOwnerUid = null;
        _recentCommands.clear();
      });
    }
    await _initDesktopAgent();
  }

  // ---------------------------------------------------------------------------
  // UI Construction
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final ownerUid = _effectiveOwnerUid;
    final themeMode = ref.watch(themeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPopRoute = ModalRoute.of(context)?.canPop ?? false;
    final showStudioWorkspace =
        !_authInitializing && ownerUid != null && !_showSystemsPane;

    return Scaffold(
      backgroundColor: context.bg,
      extendBodyBehindAppBar: !showStudioWorkspace,
      appBar: showStudioWorkspace
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: AppBar(
                backgroundColor: context.bg.withValues(alpha: 0.72),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: canPopRoute
                    ? IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: context.textPrimary, size: 20),
                        onPressed: () {
                          if (context.canPop()) context.pop();
                        },
                      )
                    : Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Center(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Icon(Icons.hub_rounded,
                                color: AppColors.brandWhite, size: 16),
                          ),
                        ),
                      ),
                title: Text(
                  'Oneova Computer Agent • $_computerName',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                centerTitle: false,
                actions: [
                  IconButton(
                    tooltip: isDark
                        ? 'Switch to Light Mode'
                        : 'Switch to Dark Mode',
                    icon: Icon(
                      isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: context.textSecondary,
                      size: 19,
                    ),
                    onPressed: () {
                      ref.read(themeProvider.notifier).setThemeMode(
                            themeMode == ThemeMode.light
                                ? ThemeMode.dark
                                : ThemeMode.light,
                          );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
      body: showStudioWorkspace
          ? SafeArea(
              child: OvaAgentWorkspace(
                showSessionSidebar: true,
                onDisconnect: _confirmAndDisconnect,
                onToggleBridges: () => setState(() => _showSystemsPane = true),
                onOpenAuth: () => OneovaWorkstationAuthDialog.show(
                  context,
                  onSignedOut: _confirmAndDisconnect,
                  onSignedIn: () => setState(() {}),
                ),
              ),
            )
          : OneovaAuthBackdrop(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 468),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ownerUid == null) ...[
                            _buildMobileBrandHeader(context),
                            const SizedBox(height: 16),
                          ],
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: context.surface.withValues(alpha: isDark ? 0.94 : 0.97),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: context.border, width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.brandBlue.withValues(alpha: isDark ? 0.14 : 0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: _authInitializing
                                ? _buildInitializingView(context)
                                : ownerUid == null
                                    ? _buildAuthAndSessionCard(context)
                                    : _buildConnectedAgentView(context, ownerUid),
                          ),
                          if (ownerUid == null) ...[
                            const SizedBox(height: 14),
                            const OneovaAuthPromises(),
                            const SizedBox(height: 10),
                            _buildSecurityFooter(context),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildMobileBrandHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          padding: const EdgeInsets.all(2.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: const LinearGradient(
              colors: [AppColors.brandBlue, AppColors.brandPink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md - 2),
            child: Image.asset(
              'assets/images/oneova_logo.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.brandBlue,
                child: const Icon(Icons.hub_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const OneovaAuthTagline(compact: true),
      ],
    );
  }

  Widget _buildSecurityFooter(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.brandBlue),
              const SizedBox(width: 5),
              Text(
                '256-Bit E2EE • Zero-Trust Workstation Link',
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInitializingView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.brandBlue),
          ),
          const SizedBox(height: 14),
          Text(
            'Starting Oneova Computer Components...',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthAndSessionCard(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Connect Workstation',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 16.5,
                letterSpacing: -0.3,
                color: context.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                'LIVE SYNC',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Scan QR, enter a 6-digit session code, or sign in with your Oneova account.',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: context.textSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),

        // 3-Mode Session Switcher: QR Session | Session Code | Sign In
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              _buildModeTab(
                context,
                tab: _DesktopAuthTab.qrSession,
                icon: Icons.qr_code_2_rounded,
                label: 'QR Session',
              ),
              _buildModeTab(
                context,
                tab: _DesktopAuthTab.codeSession,
                icon: Icons.pin_rounded,
                label: 'Code Session',
              ),
              _buildModeTab(
                context,
                tab: _DesktopAuthTab.signIn,
                icon: Icons.person_rounded,
                label: 'Sign In',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_authError != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _authError!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.brandPink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_authInfo != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 15, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _authInfo!,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        switch (_activeTab) {
          _DesktopAuthTab.qrSession => _buildQrSessionTab(context),
          _DesktopAuthTab.codeSession => _buildCodeSessionTab(context),
          _DesktopAuthTab.signIn => _buildMobileParitySignInTab(context),
        },
      ],
    );
  }

  Widget _buildModeTab(
    BuildContext context, {
    required _DesktopAuthTab tab,
    required IconData icon,
    required String label,
  }) {
    final selected = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _activeTab = tab;
            _authError = null;
            _authInfo = null;
          });
          if (tab != _DesktopAuthTab.signIn && _pairingSubscription == null) {
            _startSecurePairing();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : context.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? Colors.white : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: QR Session
  // ---------------------------------------------------------------------------

  Widget _buildQrSessionTab(BuildContext context) {
    final pairingState = ref.watch(securePairingProvider);
    final pin = pairingState.activePin;
    final qrPayload = pin != null
        ? 'ONEOVA-PAIR:${jsonEncode({"pin": pin, "host": _computerName})}'
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.35),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: qrPayload == null || _publishingSession
              ? const SizedBox(
                  width: 186,
                  height: 186,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.brandBlue,
                    ),
                  ),
                )
              : SizedBox(
                  width: 186,
                  height: 186,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(186, 186),
                        painter: _DesktopSessionQrPainter(
                          data: qrPayload,
                          fgColor: const Color(0xFF0F172A),
                          accentColor: AppColors.brandBlue,
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.brandBlue, width: 1.5),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.hub_rounded,
                            size: 20,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ).animate().fadeIn(duration: 220.ms).scale(begin: const Offset(0.97, 0.97)),
        const SizedBox(height: 14),
        Text(
          'Scan with Oneova Mobile',
          style: GoogleFonts.inter(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Open Oneova on your phone → Workstation Connect → Scan Workstation QR Code',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: context.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _buildHandshakeStatusPill(context, 'Waiting for QR scan handshake...'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.border, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: Icon(Icons.refresh_rounded, size: 15, color: context.textPrimary),
                  label: Text(
                    'Refresh QR',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  onPressed: _publishingSession ? null : _startSecurePairing,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: const Icon(Icons.pin_rounded, size: 15, color: AppColors.brandBlue),
                  label: Text(
                    'Use 6-Digit Code',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  onPressed: () => setState(() => _activeTab = _DesktopAuthTab.codeSession),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 6-Digit Code Session
  // ---------------------------------------------------------------------------

  Widget _buildCodeSessionTab(BuildContext context) {
    final pairingState = ref.watch(securePairingProvider);
    final pin = pairingState.activePin ?? '------';
    final chars = pin.padRight(6, '-').split('').take(6).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.32),
              width: 1.0,
            ),
          ),
          child: const Icon(
            Icons.phonelink_lock_rounded,
            size: 26,
            color: AppColors.brandBlue,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '6-Digit E2EE Session Code',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter this code in Oneova Mobile → Workstation Connect → Pair via 6-Digit Session Code.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: context.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),

        // 6 Individual Digit Boxes (matching MainLoginScreen OTP style)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (idx) {
            return Container(
              width: 46,
              height: 54,
              margin: EdgeInsets.only(right: idx == 5 ? 0 : 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.55),
                  width: 1.0,
                ),
              ),
              child: _publishingSession
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandBlue,
                      ),
                    )
                  : Text(
                      chars[idx],
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandBlue,
                      ),
                    ),
            );
          }),
        ),
        const SizedBox(height: 14),
        _buildHandshakeStatusPill(context, 'Waiting for mobile code handshake...'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.border, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: Icon(Icons.copy_rounded, size: 15, color: context.textPrimary),
                  label: Text(
                    'Copy Code',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  onPressed: pin == '------'
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: pin));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('6-digit session code copied'),
                              backgroundColor: AppColors.brandBlue,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 15, color: AppColors.brandBlue),
                  label: Text(
                    'New Code',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  onPressed: _publishingSession ? null : _startSecurePairing,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHandshakeStatusPill(BuildContext context, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: context.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Mobile-Parity Account Sign In (Phone / Email / Google / Touch ID)
  // ---------------------------------------------------------------------------

  Widget _buildMobileParitySignInTab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1-Tap Biometric Quick Card (matches MainLoginScreen._buildBiometricQuickCard)
        if (_biometricsAvailable && _bioQuickAccountLabel != null) ...[
          Material(
            color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: _signingIn ? null : _unlockWithBiometrics,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Continue with $_biometricLabel',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            _bioQuickAccountLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.brandBlue),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Phone Number vs Email Pill Toggle
        Row(
          children: [
            _buildIdentityToggleChip(
              context,
              selected: _usePhoneSignIn,
              icon: Icons.phone_iphone_rounded,
              label: 'Mobile Number',
              onTap: () {
                setState(() {
                  _usePhoneSignIn = true;
                  _identifiedUser = null;
                  _authError = null;
                });
                _scheduleAccountLookup();
              },
            ),
            const SizedBox(width: 8),
            _buildIdentityToggleChip(
              context,
              selected: !_usePhoneSignIn,
              icon: Icons.alternate_email_rounded,
              label: 'Email Address',
              onTap: () {
                setState(() {
                  _usePhoneSignIn = false;
                  _identifiedUser = null;
                  _authError = null;
                });
                _scheduleAccountLookup();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_usePhoneSignIn) ...[
          IntlPhoneField(
            key: ValueKey('desktop_phone_$_selectedCountryIso'),
            controller: _phoneController,
            initialCountryCode: _selectedCountryIso,
            disableLengthCheck: true,
            keyboardType: TextInputType.phone,
            cursorColor: AppColors.brandBlue,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
            ],
            decoration: InputDecoration(
              hintText: _formatHint,
              hintStyle: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              filled: true,
              fillColor: context.surfaceMid,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
              ),
              counterText: '',
            ),
            dropdownIcon: Icon(Icons.arrow_drop_down_rounded, color: context.textSecondary),
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
            onCountryChanged: (country) {
              final meta = _phoneEngine.findByIso(country.code);
              setState(() {
                _selectedCountryIso = country.code;
                _selectedCountryMeta = meta;
                _formatHint = meta.formatHint;
              });
              _scheduleAccountLookup();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedCountryMeta.flagEmoji} ${_selectedCountryMeta.formatHint}',
                  style: GoogleFonts.inter(
                    color: context.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isCheckingAccount)
                  Row(
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandBlue),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Looking…',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ] else ...[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: context.surfaceMid,
              hintText: 'creator@oneova.app',
              hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
              prefixIcon: Icon(Icons.mail_outline_rounded, size: 17, color: context.textSecondary),
              suffixIcon: _isCheckingAccount
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandBlue),
                      ),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: BorderSide(color: context.border, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
              ),
            ),
          ),
        ],

        // Real-Time Identified Account Preview Card (matches MainLoginScreen)
        if (_identifiedUser != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    ((_identifiedUser!['displayName'] ?? _identifiedUser!['username'] ?? 'O')
                            .toString()
                            .trim()
                            .characters
                            .firstOrNull ??
                        'O')
                        .toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              (_identifiedUser!['displayName'] ?? 'Oneova Creator').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue),
                        ],
                      ),
                      if (_identifiedUser!['username'] != null)
                        Text(
                          '@${_identifiedUser!['username']}',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: context.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Account found',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 180.ms),
        ],

        const SizedBox(height: 10),

        // Password Field with Show/Hide Toggle
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
          onSubmitted: (_) => _signInWithCredentials(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.surfaceMid,
            hintText: 'Oneova Password',
            hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 17, color: context.textSecondary),
            suffixIcon: IconButton(
              splashRadius: 16,
              icon: Icon(
                _passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 17,
                color: context.textSecondary,
              ),
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border, width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_capsLockOn)
                Text(
                  'Caps Lock is ON',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPink,
                  ),
                )
              else
                const SizedBox.shrink(),
              if (!_usePhoneSignIn)
                InkWell(
                  onTap: _signingIn ? null : _handleForgotPassword,
                  child: Text(
                    'Reset password',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Primary Sign In CTA (40px executive button)
        SizedBox(
          height: 40,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: _signingIn ? null : _signInWithCredentials,
            icon: _signingIn
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_user_rounded, size: 16),
            label: Text(
              _identifiedUser != null
                  ? 'Continue as ${(_identifiedUser!['displayName'] ?? 'Creator').toString().split(' ').first} →'
                  : 'Sign In & Link Computer',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Divider(color: context.border, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'OR',
                style: GoogleFonts.inter(
                  color: context.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(child: Divider(color: context.border, thickness: 1)),
          ],
        ),
        const SizedBox(height: 12),

        // Continue with Google Button (matches MainLoginScreen)
        SizedBox(
          height: 40,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: context.surfaceMid,
              side: BorderSide(color: context.border, width: 1.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: _signingIn ? null : _signInWithGoogle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/google_logo.svg',
                  width: 16,
                  height: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Continue with Google',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityToggleChip(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandBlue.withValues(alpha: 0.12)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.brandBlue : context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.brandBlue : context.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? AppColors.brandBlue : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Connected Workstation Dashboard
  // ---------------------------------------------------------------------------

  Widget _buildConnectedAgentView(BuildContext context, String ownerUid) {
    final deviceId = _deviceIdFor(ownerUid);
    final ownerLabel = _pairedAccountDisplay ??
        '${ownerUid.substring(0, math.min(10, ownerUid.length))}…';

    return ValueListenableBuilder<DesktopResponderSnapshot>(
      valueListenable: _webrtcResponder.state,
      builder: (context, rtcSnap, _) {
        final streamActive = rtcSnap.status == DesktopResponderStatus.streaming;
        final responderReady = rtcSnap.status != DesktopResponderStatus.stopped &&
            rtcSnap.status != DesktopResponderStatus.error;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.brandBlue.withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: const Icon(
                    Icons.desktop_mac_rounded,
                    size: 24,
                    color: AppColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _computerName,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$ownerLabel • Active: $_activeWindow',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: AppColors.brandBlue.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    'ONLINE',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: context.border, height: 1),
            const SizedBox(height: 14),
            _buildComponentRow(
              context,
              icon: Icons.cast_connected_rounded,
              title: 'WebRTC Display Stream',
              subtitle: rtcSnap.statusDetail ?? 'Standby for phone viewer',
              isActive: responderReady,
              badgeText:
                  streamActive ? 'STREAMING' : (responderReady ? 'READY' : 'ERROR'),
            ),
            const SizedBox(height: 10),
            _buildComponentRow(
              context,
              icon: Icons.mouse_rounded,
              title: 'CoreGraphics Input Bridge',
              subtitle: rtcSnap.dataChannelOpen
                  ? 'Low-latency DataChannel connected'
                  : 'Cloud + DataChannel mouse & hotkeys armed',
              isActive: true,
              badgeText: rtcSnap.dataChannelOpen ? 'LIVE P2P' : 'ARMED',
            ),
            const SizedBox(height: 10),
            _buildComponentRow(
              context,
              icon: Icons.speed_rounded,
              title: 'Telemetry Engine (E2EE)',
              subtitle: 'CPU, RAM, disk & network every 3s ($deviceId)',
              isActive: true,
              badgeText: 'SYNCING',
            ),
            const SizedBox(height: 10),
            _buildComponentRow(
              context,
              icon: Icons.extension_rounded,
              title: 'Studio Plugin WebSocket',
              subtitle: 'Listening on ws://127.0.0.1:8080',
              isActive: true,
              badgeText: 'PORT 8080',
            ),
            if (_recentCommands.isNotEmpty) ...[
              const SizedBox(height: 16),
              Divider(color: context.border, height: 1),
              const SizedBox(height: 10),
              Text(
                'RECENT REMOTE EVENTS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ..._recentCommands.map(
                (cmd) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, size: 14, color: AppColors.brandPink),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cmd,
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      label: Text(
                        'Ova Assistant',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => _showOvaAgentModal(context),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.border, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: Icon(Icons.link_off_rounded, size: 17, color: context.textSecondary),
                    label: Text(
                      'Disconnect',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    onPressed: _confirmAndDisconnect,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildComponentRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required String badgeText,
  }) {
    final accent = isActive ? AppColors.brandBlue : AppColors.brandPink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.0),
            ),
            child: Text(
              badgeText,
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOvaAgentModal(BuildContext context) {
    if (_effectiveOwnerUid != null) {
      setState(() => _showSystemsPane = false);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.82,
          decoration: BoxDecoration(
            color: sheetCtx.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: sheetCtx.border, width: 1.0),
          ),
          child: const ClipRRect(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            child: OvaAgentWorkspace(compactSheet: true),
          ),
        );
      },
    );
  }
}

class _DesktopSessionQrPainter extends CustomPainter {
  final String data;
  final Color fgColor;
  final Color accentColor;

  const _DesktopSessionQrPainter({
    required this.data,
    required this.fgColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final qrImage = QrImage(qr);
    final count = qrImage.moduleCount;
    final moduleSize = size.width / count;

    final paintFg = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    final paintAccent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        if (qrImage.isDark(y, x)) {
          final isCorner = (x < 7 && y < 7) ||
              (x < 7 && y >= count - 7) ||
              (x >= count - 7 && y < 7);
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize * 0.92,
            moduleSize * 0.92,
          );
          final rrect = RRect.fromRectAndRadius(
            rect,
            Radius.circular(moduleSize * 0.24),
          );
          canvas.drawRRect(rrect, isCorner ? paintAccent : paintFg);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopSessionQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.fgColor != fgColor ||
        oldDelegate.accentColor != accentColor;
  }
}
