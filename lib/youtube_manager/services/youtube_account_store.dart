import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────
//  Data Models
// ─────────────────────────────────────────────

class YtConnectedChannel {
  final String id;
  final String title;
  final String thumbnailUrl;
  final int subscriberCount;
  final int videoCount;
  final int viewCount;
  final bool isActive;

  const YtConnectedChannel({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.subscriberCount,
    this.videoCount = 0,
    this.viewCount = 0,
    this.isActive = false,
  });

  YtConnectedChannel copyWith({
    String? id,
    String? title,
    String? thumbnailUrl,
    int? subscriberCount,
    int? videoCount,
    int? viewCount,
    bool? isActive,
  }) {
    return YtConnectedChannel(
      id: id ?? this.id,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      videoCount: videoCount ?? this.videoCount,
      viewCount: viewCount ?? this.viewCount,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'subscriberCount': subscriberCount,
        'videoCount': videoCount,
        'viewCount': viewCount,
        'isActive': isActive,
      };

  factory YtConnectedChannel.fromMap(Map<String, dynamic> map) {
    return YtConnectedChannel(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown Channel',
      thumbnailUrl: map['thumbnailUrl'] as String? ?? '',
      subscriberCount: (map['subscriberCount'] as num?)?.toInt() ?? 0,
      videoCount: (map['videoCount'] as num?)?.toInt() ?? 0,
      viewCount: (map['viewCount'] as num?)?.toInt() ?? 0,
      isActive: map['isActive'] as bool? ?? false,
    );
  }
}

class YtLinkedAccount {
  final String googleId; // Unique ID to key Firestore doc
  final String accountName;
  final String email;
  final String profilePictureUrl;
  final List<YtConnectedChannel> channels;
  final DateTime connectedAt;
  final DateTime? lastRefreshed;

  const YtLinkedAccount({
    required this.googleId,
    required this.accountName,
    required this.email,
    required this.profilePictureUrl,
    required this.channels,
    required this.connectedAt,
    this.lastRefreshed,
  });

  YtLinkedAccount copyWith({
    List<YtConnectedChannel>? channels,
    DateTime? lastRefreshed,
  }) {
    return YtLinkedAccount(
      googleId: googleId,
      accountName: accountName,
      email: email,
      profilePictureUrl: profilePictureUrl,
      channels: channels ?? this.channels,
      connectedAt: connectedAt,
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    );
  }

  Map<String, dynamic> toMap() => {
        'googleId': googleId,
        'accountName': accountName,
        'email': email,
        'profilePictureUrl': profilePictureUrl,
        'channels': channels.map((c) => c.toMap()).toList(),
        'connectedAt': Timestamp.fromDate(connectedAt),
        'lastRefreshed':
            lastRefreshed != null ? Timestamp.fromDate(lastRefreshed!) : null,
      };

  factory YtLinkedAccount.fromMap(Map<String, dynamic> map) {
    final channelList = (map['channels'] as List<dynamic>? ?? [])
        .map((c) => YtConnectedChannel.fromMap(c as Map<String, dynamic>))
        .toList();

    return YtLinkedAccount(
      googleId: map['googleId'] as String? ?? '',
      accountName: map['accountName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      profilePictureUrl: map['profilePictureUrl'] as String? ?? '',
      channels: channelList,
      connectedAt: (map['connectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastRefreshed: (map['lastRefreshed'] as Timestamp?)?.toDate(),
    );
  }
}

class YtAccountsState {
  final List<YtLinkedAccount> accounts;
  final bool isLoading;
  final String? statusMessage;
  final String? error;

  const YtAccountsState({
    this.accounts = const [],
    this.isLoading = false,
    this.statusMessage,
    this.error,
  });

  YtAccountsState copyWith({
    List<YtLinkedAccount>? accounts,
    bool? isLoading,
    String? statusMessage,
    String? error,
  }) {
    return YtAccountsState(
      accounts: accounts ?? this.accounts,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage,
      error: error,
    );
  }

  /// The single active channel across all accounts
  YtConnectedChannel? get activeChannel {
    for (final account in accounts) {
      for (final channel in account.channels) {
        if (channel.isActive) return channel;
      }
    }
    // Fallback: first channel of first account
    if (accounts.isNotEmpty && accounts.first.channels.isNotEmpty) {
      return accounts.first.channels.first;
    }
    return null;
  }

  /// The account that owns the active channel
  YtLinkedAccount? get activeAccount {
    for (final account in accounts) {
      for (final channel in account.channels) {
        if (channel.isActive) return account;
      }
    }
    if (accounts.isNotEmpty) return accounts.first;
    return null;
  }
}

// ─────────────────────────────────────────────
//  Scopes
// ─────────────────────────────────────────────

const _ytScopes = [
  yt.YouTubeApi.youtubeReadonlyScope,
  yt.YouTubeApi.youtubeUploadScope,
  yt.YouTubeApi.youtubeForceSslScope,
];

// ─────────────────────────────────────────────
//  Account Store Notifier
// ─────────────────────────────────────────────

class YtAccountStore extends AsyncNotifier<YtAccountsState> {
  final _secureStorage = const FlutterSecureStorage();
  final _firestore = FirebaseFirestore.instance;
  final _firebaseAuth = FirebaseAuth.instance;

  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

  String get _uid => _firebaseAuth.currentUser?.uid ?? '';

  CollectionReference<Map<String, dynamic>> get _accountsCollection =>
      _firestore.collection('users').doc(_uid).collection('youtube_accounts');

  @override
  Future<YtAccountsState> build() async {
    if (_uid.isEmpty) return const YtAccountsState();
    return await _loadFromFirestore();
  }

  // ── Load all accounts from Firestore ──────────────────────────────────

  Future<YtAccountsState> _loadFromFirestore() async {
    try {
      final snapshot = await _accountsCollection.get();
      final accounts = snapshot.docs
          .map((doc) => YtLinkedAccount.fromMap(doc.data()))
          .toList();
      return YtAccountsState(accounts: accounts);
    } catch (e) {
      debugPrint('YtAccountStore: Failed to load from Firestore — $e');
      return YtAccountsState(error: e.toString());
    }
  }

  // ── Add a new Google Account ──────────────────────────────────────────

  Future<void> addAccount() async {
    if (_uid.isEmpty) return;

    state = AsyncData(state.value?.copyWith(
          isLoading: true,
          statusMessage: 'Opening Google Sign-In…',
        ) ??
        const YtAccountsState(isLoading: true));

    try {
      // Google Sign-In — triggers the account picker
      final googleAccount = await _googleSignIn.authenticate(
        scopeHint: _ytScopes,
      );

      final googleId = googleAccount.id;

      // Check if already added
      final currentAccounts = state.value?.accounts ?? [];
      if (currentAccounts.any((a) => a.googleId == googleId)) {
        state = AsyncData(state.requireValue.copyWith(
          isLoading: false,
          error: '${googleAccount.email} is already connected.',
        ));
        return;
      }

      state = AsyncData(state.requireValue.copyWith(
        statusMessage: 'Fetching your channels…',
      ));

      // Get auth client and fetch channels
      final authClient = await _getAuthClient(googleAccount);
      if (authClient == null) {
        state = AsyncData(state.requireValue.copyWith(
          isLoading: false,
          error: 'Failed to authenticate with YouTube.',
        ));
        return;
      }

      final channels = await _fetchChannels(authClient, googleId);

      // Build the account object
      final newAccount = YtLinkedAccount(
        googleId: googleId,
        accountName: googleAccount.displayName ?? 'Unknown',
        email: googleAccount.email,
        profilePictureUrl: googleAccount.photoUrl ?? '',
        channels: channels.asMap().entries.map((e) {
          // Mark first channel as active only if no other channels are active
          final isFirst = e.key == 0 && currentAccounts.isEmpty;
          return e.value.copyWith(isActive: isFirst);
        }).toList(),
        connectedAt: DateTime.now(),
        lastRefreshed: DateTime.now(),
      );

      // Persist to Firestore
      await _accountsCollection.doc(googleId).set(newAccount.toMap());

      // Store access token in secure storage (keyed by googleId)
      final authorization =
          await googleAccount.authorizationClient.authorizeScopes(_ytScopes).timeout(const Duration(seconds: 15));
      await _secureStorage.write(
        key: 'yt_token_$googleId',
        value: authorization.accessToken,
      );

      // Update in-memory state
      final updatedAccounts = [...currentAccounts, newAccount];
      state = AsyncData(YtAccountsState(accounts: updatedAccounts));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        state = AsyncData(
            state.value?.copyWith(isLoading: false) ??
                const YtAccountsState());
      } else {
        state = AsyncData(state.value?.copyWith(
              isLoading: false,
              error: 'Google Sign-In error: ${e.toString()}',
            ) ??
            const YtAccountsState());
      }
    } catch (e) {
      debugPrint('YtAccountStore.addAccount error: $e');
      state = AsyncData(state.value?.copyWith(
            isLoading: false,
            error: 'Failed to add account: ${e.toString()}',
          ) ??
          const YtAccountsState());
    }
  }

  // ── Remove an account ─────────────────────────────────────────────────

  Future<void> removeAccount(String googleId) async {
    try {
      await _accountsCollection.doc(googleId).delete();
      await _secureStorage.delete(key: 'yt_token_$googleId');

      final currentAccounts = state.value?.accounts ?? [];
      final updated = currentAccounts.where((a) => a.googleId != googleId).toList();

      // If we removed the account with the active channel, activate the first available
      final hasActive = updated.any((a) => a.channels.any((c) => c.isActive));
      if (!hasActive && updated.isNotEmpty && updated.first.channels.isNotEmpty) {
        await setActiveChannel(
          updated.first.googleId,
          updated.first.channels.first.id,
        );
        return;
      }

      state = AsyncData(YtAccountsState(accounts: updated));
    } catch (e) {
      debugPrint('YtAccountStore.removeAccount error: $e');
    }
  }

  // ── Set active channel ────────────────────────────────────────────────

  Future<void> setActiveChannel(
      String googleId, String channelId) async {
    final currentAccounts = state.value?.accounts ?? [];

    // Unmark all channels, then mark the chosen one
    final updated = currentAccounts.map((account) {
      final updatedChannels = account.channels.map((channel) {
        return channel.copyWith(
          isActive: account.googleId == googleId && channel.id == channelId,
        );
      }).toList();
      return account.copyWith(channels: updatedChannels);
    }).toList();

    state = AsyncData(YtAccountsState(accounts: updated));

    // Persist the change to Firestore
    try {
      for (final account in updated) {
        await _accountsCollection.doc(account.googleId).update({
          'channels': account.channels.map((c) => c.toMap()).toList(),
        });
      }
    } catch (e) {
      debugPrint('YtAccountStore.setActiveChannel persistence error: $e');
    }
  }

  // ── Refresh channels for an account ──────────────────────────────────

  Future<void> refreshAccount(String googleId) async {
    try {
      // Re-authenticate silently
      final attempt = _googleSignIn.attemptLightweightAuthentication();
      if (attempt == null) return;

      final googleAccount = await attempt;
      if (googleAccount == null || googleAccount.id != googleId) return;

      final authClient = await _getAuthClient(googleAccount);
      if (authClient == null) return;

      final channels = await _fetchChannels(authClient, googleId);

      final currentAccounts = state.value?.accounts ?? [];
      final oldAccount =
          currentAccounts.firstWhere((a) => a.googleId == googleId);

      // Preserve isActive flags
      final mergedChannels = channels.map((ch) {
        final old = oldAccount.channels.where((c) => c.id == ch.id).firstOrNull;
        return ch.copyWith(isActive: old?.isActive ?? false);
      }).toList();

      final updatedAccount = oldAccount.copyWith(
        channels: mergedChannels,
        lastRefreshed: DateTime.now(),
      );

      await _accountsCollection.doc(googleId).update({
        'channels': mergedChannels.map((c) => c.toMap()).toList(),
        'lastRefreshed': Timestamp.fromDate(DateTime.now()),
      });

      final updatedAccounts = currentAccounts
          .map((a) => a.googleId == googleId ? updatedAccount : a)
          .toList();

      state = AsyncData(YtAccountsState(accounts: updatedAccounts));
    } catch (e) {
      debugPrint('YtAccountStore.refreshAccount error: $e');
    }
  }

  // ── Get auth client for a Google account ──────────────────────────────

  Future<http.Client?> getAuthClientForAccount(String googleId) async {
    try {
      // Try to get from secure storage first
      final token = await _secureStorage.read(key: 'yt_token_$googleId');
      if (token != null) {
        return _BearerAuthClient({'Authorization': 'Bearer $token'});
      }
      return null;
    } catch (e) {
      debugPrint('YtAccountStore.getAuthClientForAccount error: $e');
      return null;
    }
  }

  Future<http.Client?> getActiveAuthClient() async {
    final activeAccount = state.value?.activeAccount;
    if (activeAccount == null) return null;
    return getAuthClientForAccount(activeAccount.googleId);
  }

  // ── Private helpers ────────────────────────────────────────────────────

  Future<http.Client?> _getAuthClient(
      GoogleSignInAccount googleAccount) async {
    try {
      final authorization =
          await googleAccount.authorizationClient.authorizeScopes(_ytScopes).timeout(const Duration(seconds: 15));
      return _BearerAuthClient(
          {'Authorization': 'Bearer ${authorization.accessToken}'});
    } catch (e) {
      debugPrint('YtAccountStore._getAuthClient error: $e');
      return null;
    }
  }

  Future<List<YtConnectedChannel>> _fetchChannels(
      http.Client client, String googleId) async {
    try {
      final ytApi = yt.YouTubeApi(client);
      final response = await ytApi.channels.list(
        ['snippet', 'statistics'],
        mine: true,
      ).timeout(const Duration(seconds: 20));

      return (response.items ?? []).map((ch) {
        return YtConnectedChannel(
          id: ch.id ?? '',
          title: ch.snippet?.title ?? 'Unknown Channel',
          thumbnailUrl:
              ch.snippet?.thumbnails?.medium?.url ??
              ch.snippet?.thumbnails?.default_?.url ??
              '',
          subscriberCount:
              int.tryParse(ch.statistics?.subscriberCount ?? '0') ?? 0,
          videoCount:
              int.tryParse(ch.statistics?.videoCount ?? '0') ?? 0,
          viewCount:
              int.tryParse(ch.statistics?.viewCount ?? '0') ?? 0,
          isActive: false,
        );
      }).toList();
    } catch (e) {
      debugPrint('YtAccountStore._fetchChannels error: $e');
      return [];
    }
  }

  Future<void> clearError() async {
    final current = state.value;
    if (current != null) {
      state = AsyncData(current.copyWith(error: null));
    }
  }
}

// ─────────────────────────────────────────────
//  Bearer HTTP Client
// ─────────────────────────────────────────────

class _BearerAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _inner = http.Client();

  _BearerAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────

final ytAccountStoreProvider =
    AsyncNotifierProvider<YtAccountStore, YtAccountsState>(
  YtAccountStore.new,
);

/// Convenience provider — the currently active channel (null if none)
final ytActiveChannelProvider = Provider<YtConnectedChannel?>((ref) {
  return ref
      .watch(ytAccountStoreProvider)
      .whenData((s) => s.activeChannel)
      .value;
});

/// Convenience provider — the account that owns the active channel
final ytActiveAccountProvider = Provider<YtLinkedAccount?>((ref) {
  return ref
      .watch(ytAccountStoreProvider)
      .whenData((s) => s.activeAccount)
      .value;
});

/// Stream of all linked accounts from Firestore (for real-time updates)
final ytAccountsStreamProvider =
    StreamProvider<List<YtLinkedAccount>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('youtube_accounts')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => YtLinkedAccount.fromMap(doc.data()))
          .toList());
});
