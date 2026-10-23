import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final oneovaSmartPhoneEngineProvider = Provider<OneovaSmartPhoneEngine>((ref) {
  return OneovaSmartPhoneEngine();
});

/// Comprehensive country metadata for worldwide smart phone parsing & formatting
class CountryPhoneMeta {
  final String isoCode;
  final String countryName;
  final String dialCode;
  final String flagEmoji;
  final String exampleLocal;
  final String formatHint;
  final int minDigits;
  final int maxDigits;
  final bool hasLeadingZeroInDailyUse;

  const CountryPhoneMeta({
    required this.isoCode,
    required this.countryName,
    required this.dialCode,
    required this.flagEmoji,
    required this.exampleLocal,
    required this.formatHint,
    required this.minDigits,
    required this.maxDigits,
    this.hasLeadingZeroInDailyUse = true,
  });

  /// Digits of dial code without the '+' prefix
  String get dialDigits => dialCode.replaceAll('+', '');
}

/// The result of parsing and normalizing an entered phone string
class ParsedPhoneResult {
  final String rawInput;
  final String cleanedDigits;
  final String nationalNumber;
  final String e164;
  final String formattedDisplay;
  final CountryPhoneMeta country;
  final bool isValid;
  final bool isComplete;
  final String? validationMessage;
  final bool wasCountryAutoSwitched;

  const ParsedPhoneResult({
    required this.rawInput,
    required this.cleanedDigits,
    required this.nationalNumber,
    required this.e164,
    required this.formattedDisplay,
    required this.country,
    required this.isValid,
    required this.isComplete,
    this.validationMessage,
    this.wasCountryAutoSwitched = false,
  });
}

/// Information about the last phone number and account used on this device
class LastUsedAccountInfo {
  final String phoneE164;
  final String countryIso;
  final String? displayName;
  final String? username;
  final DateTime? lastUsedAt;

  const LastUsedAccountInfo({
    required this.phoneE164,
    required this.countryIso,
    this.displayName,
    this.username,
    this.lastUsedAt,
  });
}

/// Production-ready Worldwide Smart Phone Engine for Oneova.
///
/// Features:
/// 1. Silent country detection (Cache -> Device Locale -> Background Geo-IP -> Fallback).
/// 2. Comprehensive country directory with flag emojis, dial codes, and daily use hints.
/// 3. Resilient normalization (handles leading 0s, dial codes typed in field, pasted full international +E.164, and 00 prefixes).
/// 4. Auto-sniffing: automatically switches country if user pastes or types another country's code.
/// 5. Remembers last used phone and account details on this device for instant 1-tap re-login.
class OneovaSmartPhoneEngine {
  static const String _prefKeyLastPhone = 'oneova_last_used_phone';
  static const String _prefKeyLastCountryIso = 'oneova_last_country_iso';
  static const String _prefKeyLastDisplayName = 'oneova_last_display_name';
  static const String _prefKeyLastUsername = 'oneova_last_username';
  static const String _prefKeyLastTimestamp = 'oneova_last_used_timestamp';

  /// Supported country directory covering major creator markets worldwide
  static final List<CountryPhoneMeta> allCountries = [
    const CountryPhoneMeta(
      isoCode: 'KE',
      countryName: 'Kenya',
      dialCode: '+254',
      flagEmoji: '🇰🇪',
      exampleLocal: '0712 345 678',
      formatHint: '0700... / 700... (KE)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'US',
      countryName: 'United States',
      dialCode: '+1',
      flagEmoji: '🇺🇸',
      exampleLocal: '(555) 234-5678',
      formatHint: '(555) 000-0000 (US)',
      minDigits: 10,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: false,
    ),
    const CountryPhoneMeta(
      isoCode: 'GB',
      countryName: 'United Kingdom',
      dialCode: '+44',
      flagEmoji: '🇬🇧',
      exampleLocal: '07911 123456',
      formatHint: '07000 000000 (UK)',
      minDigits: 10,
      maxDigits: 11,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'NG',
      countryName: 'Nigeria',
      dialCode: '+234',
      flagEmoji: '🇳🇬',
      exampleLocal: '0803 123 4567',
      formatHint: '0800... / 800... (NG)',
      minDigits: 10,
      maxDigits: 11,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'TZ',
      countryName: 'Tanzania',
      dialCode: '+255',
      flagEmoji: '🇹🇿',
      exampleLocal: '0754 123 456',
      formatHint: '0700... / 700... (TZ)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'UG',
      countryName: 'Uganda',
      dialCode: '+256',
      flagEmoji: '🇺🇬',
      exampleLocal: '0772 123 456',
      formatHint: '0700... / 700... (UG)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'RW',
      countryName: 'Rwanda',
      dialCode: '+250',
      flagEmoji: '🇷🇼',
      exampleLocal: '0788 123 456',
      formatHint: '0700... / 700... (RW)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'ZA',
      countryName: 'South Africa',
      dialCode: '+27',
      flagEmoji: '🇿🇦',
      exampleLocal: '082 123 4567',
      formatHint: '080... / 80... (ZA)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'GH',
      countryName: 'Ghana',
      dialCode: '+233',
      flagEmoji: '🇬🇭',
      exampleLocal: '024 123 4567',
      formatHint: '020... / 20... (GH)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'IN',
      countryName: 'India',
      dialCode: '+91',
      flagEmoji: '🇮🇳',
      exampleLocal: '98765 43210',
      formatHint: '98000 00000 (IN)',
      minDigits: 10,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: false,
    ),
    const CountryPhoneMeta(
      isoCode: 'AE',
      countryName: 'United Arab Emirates',
      dialCode: '+971',
      flagEmoji: '🇦🇪',
      exampleLocal: '050 123 4567',
      formatHint: '050... / 50... (AE)',
      minDigits: 9,
      maxDigits: 9,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'CA',
      countryName: 'Canada',
      dialCode: '+1',
      flagEmoji: '🇨🇦',
      exampleLocal: '(416) 234-5678',
      formatHint: '(416) 000-0000 (CA)',
      minDigits: 10,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: false,
    ),
    const CountryPhoneMeta(
      isoCode: 'AU',
      countryName: 'Australia',
      dialCode: '+61',
      flagEmoji: '🇦🇺',
      exampleLocal: '0412 345 678',
      formatHint: '0400... / 400... (AU)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'DE',
      countryName: 'Germany',
      dialCode: '+49',
      flagEmoji: '🇩🇪',
      exampleLocal: '0151 23456789',
      formatHint: '0150... / 150... (DE)',
      minDigits: 10,
      maxDigits: 11,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'FR',
      countryName: 'France',
      dialCode: '+33',
      flagEmoji: '🇫🇷',
      exampleLocal: '06 12 34 56 78',
      formatHint: '06... / 6... (FR)',
      minDigits: 9,
      maxDigits: 10,
      hasLeadingZeroInDailyUse: true,
    ),
    const CountryPhoneMeta(
      isoCode: 'BR',
      countryName: 'Brazil',
      dialCode: '+55',
      flagEmoji: '🇧🇷',
      exampleLocal: '(11) 98765-4321',
      formatHint: '(11) 90000-0000 (BR)',
      minDigits: 10,
      maxDigits: 11,
      hasLeadingZeroInDailyUse: false,
    ),
  ];

  static CountryPhoneMeta get defaultCountry => allCountries.first;

  /// Find country metadata by ISO code (e.g., 'KE')
  CountryPhoneMeta findByIso(String isoCode) {
    final upper = isoCode.trim().toUpperCase();
    return allCountries.firstWhere(
      (c) => c.isoCode == upper,
      orElse: () => defaultCountry,
    );
  }

  /// Find country metadata by dial code (e.g., '+254' or '254')
  CountryPhoneMeta? findByDialCode(String dialCode) {
    final clean = dialCode.replaceAll('+', '').trim();
    final matches = allCountries.where((c) => c.dialDigits == clean).toList();
    return matches.isNotEmpty ? matches.first : null;
  }

  // ── 1. Silent Location & Country Detection ──────────────────────────────────

  /// Silently detects the user's country with zero friction:
  /// 1. Stored user preference in SharedPreferences.
  /// 2. Device system locale.
  /// 3. Silent Geo-IP background check (non-blocking fallback).
  /// 4. Default fallback: Kenya ('KE').
  Future<CountryPhoneMeta> detectCountrySilently() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIso = prefs.getString(_prefKeyLastCountryIso);
      if (cachedIso != null && cachedIso.isNotEmpty) {
        final cached = findByIso(cachedIso);
        if (cached.isoCode == cachedIso.toUpperCase()) {
          return cached;
        }
      }

      // Check device platform locale
      final deviceCountry = PlatformDispatcher.instance.locale.countryCode;
      if (deviceCountry != null && deviceCountry.isNotEmpty) {
        final match = allCountries.where((c) => c.isoCode == deviceCountry.toUpperCase()).toList();
        if (matchesCountry(match)) {
          final found = match.first;
          await prefs.setString(_prefKeyLastCountryIso, found.isoCode);
          return found;
        }
      }

      // Silent Geo-IP check with short timeout
      final geoCountry = await _fetchCountryFromGeoIp().timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => null,
      );
      if (geoCountry != null) {
        final found = findByIso(geoCountry);
        await prefs.setString(_prefKeyLastCountryIso, found.isoCode);
        return found;
      }
    } catch (_) {
      // Graceful silent fallback
    }

    return defaultCountry;
  }

  bool matchesCountry(List<CountryPhoneMeta> list) => list.isNotEmpty;

  /// Silent Geo-IP query to resolve visitor country code without location permissions prompt
  Future<String?> _fetchCountryFromGeoIp() async {
    try {
      final uri = Uri.parse('https://ipapi.co/json/');
      final res = await http.get(uri).timeout(const Duration(milliseconds: 2000));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map && data['country_code'] != null) {
          return data['country_code'].toString().toUpperCase();
        }
      }
    } catch (_) {
      // Ignore network errors in silent detection
    }
    return null;
  }

  // ── 2. Smart Phone Normalization & Auto-Sniffing ──────────────────────────

  /// Parses any format a user types or pastes (daily format, national with 0,
  /// international +254..., 00 prefix, or duplicate dial code), and normalizes
  /// it into a clean E.164 string with formatted display.
  ParsedPhoneResult parseAndNormalize({
    required String input,
    CountryPhoneMeta? fallbackCountry,
  }) {
    CountryPhoneMeta targetCountry = fallbackCountry ?? defaultCountry;
    bool wasSwitched = false;
    String trimmed = input.trim();

    if (trimmed.isEmpty) {
      return ParsedPhoneResult(
        rawInput: input,
        cleanedDigits: '',
        nationalNumber: '',
        e164: '',
        formattedDisplay: '',
        country: targetCountry,
        isValid: false,
        isComplete: false,
        validationMessage: null,
      );
    }

    // 1. Detect if the user pasted/typed a full international number with '+'
    if (trimmed.startsWith('+')) {
      final digitsOnly = trimmed.replaceAll(RegExp(r'[^\d]'), '');
      for (final c in allCountries) {
        if (digitsOnly.startsWith(c.dialDigits)) {
          targetCountry = c;
          wasSwitched = true;
          trimmed = digitsOnly.substring(c.dialDigits.length);
          break;
        }
      }
    }
    // 2. Detect international number with '00'
    else if (trimmed.startsWith('00')) {
      final digitsOnly = trimmed.substring(2).replaceAll(RegExp(r'[^\d]'), '');
      for (final c in allCountries) {
        if (digitsOnly.startsWith(c.dialDigits)) {
          targetCountry = c;
          wasSwitched = true;
          trimmed = digitsOnly.substring(c.dialDigits.length);
          break;
        }
      }
    }
    // 3. Detect duplicate dial code without '+' (e.g. user selected +254 and typed '254712...')
    else {
      final cleanDigits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanDigits.startsWith(targetCountry.dialDigits) &&
          cleanDigits.length >= targetCountry.dialDigits.length + targetCountry.minDigits - 1) {
        trimmed = cleanDigits.substring(targetCountry.dialDigits.length);
      }
    }

    // Clean all non-digit characters from the national part
    String nationalDigits = trimmed.replaceAll(RegExp(r'[^\d]'), '');

    // 4. Handle daily local formats with leading zero (e.g. '0712345678')
    String e164Digits = nationalDigits;
    if (e164Digits.startsWith('0')) {
      e164Digits = e164Digits.substring(1);
    }

    final e164String = e164Digits.isNotEmpty ? '${targetCountry.dialCode}$e164Digits' : '';
    final formattedDisplay = _formatFriendly(nationalDigits, targetCountry);

    // Determine completion and validity
    final isComplete = (e164Digits.length >= targetCountry.minDigits - 1) &&
        (e164Digits.length <= targetCountry.maxDigits);
    final isValid = isComplete;

    String? error;
    if (nationalDigits.length > targetCountry.maxDigits + 1) {
      error = 'Number is too long for ${targetCountry.countryName}';
    }

    return ParsedPhoneResult(
      rawInput: input,
      cleanedDigits: nationalDigits,
      nationalNumber: nationalDigits,
      e164: e164String,
      formattedDisplay: formattedDisplay,
      country: targetCountry,
      isValid: isValid,
      isComplete: isComplete,
      validationMessage: error,
      wasCountryAutoSwitched: wasSwitched,
    );
  }

  /// Formats national digits for clear, high-contrast, premium spacing
  String _formatFriendly(String digits, CountryPhoneMeta country) {
    if (digits.isEmpty) return '';

    // Grouping for 9-10 digit numbers (e.g. Kenya, UK, Nigeria, Tanzania): 0712 345 678
    if (digits.length <= 4) {
      return digits;
    } else if (digits.length <= 7) {
      return '${digits.substring(0, 4)} ${digits.substring(4)}';
    } else if (digits.length <= 10) {
      return '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    } else {
      return '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7, 10)} ${digits.substring(10)}';
    }
  }

  // ── 3. Device Memory & Last Used Account Engine ──────────────────────────

  /// Persists the verified/used phone and country on this device for instant recognition
  Future<void> saveLastUsedAccount({
    required String phoneE164,
    required String countryIso,
    String? displayName,
    String? username,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastPhone, phoneE164.trim());
      await prefs.setString(_prefKeyLastCountryIso, countryIso.trim().toUpperCase());
      if (displayName != null && displayName.isNotEmpty) {
        await prefs.setString(_prefKeyLastDisplayName, displayName.trim());
      }
      if (username != null && username.isNotEmpty) {
        await prefs.setString(_prefKeyLastUsername, username.trim().replaceAll('@', ''));
      }
      await prefs.setInt(_prefKeyLastTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[OneovaSmartPhoneEngine] Failed to save last used account: $e');
    }
  }

  /// Retrieves the last used phone number and account info from this device
  Future<LastUsedAccountInfo?> getLastUsedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(_prefKeyLastPhone);
      final countryIso = prefs.getString(_prefKeyLastCountryIso) ?? 'KE';
      if (phone != null && phone.isNotEmpty) {
        final displayName = prefs.getString(_prefKeyLastDisplayName);
        final username = prefs.getString(_prefKeyLastUsername);
        final ts = prefs.getInt(_prefKeyLastTimestamp);

        return LastUsedAccountInfo(
          phoneE164: phone,
          countryIso: countryIso,
          displayName: displayName,
          username: username,
          lastUsedAt: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
        );
      }
    } catch (e) {
      debugPrint('[OneovaSmartPhoneEngine] Failed to load last used account: $e');
    }
    return null;
  }

  /// Clears stored device phone memory
  Future<void> clearLastUsedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyLastPhone);
      await prefs.remove(_prefKeyLastDisplayName);
      await prefs.remove(_prefKeyLastUsername);
      await prefs.remove(_prefKeyLastTimestamp);
    } catch (_) {}
  }
}
