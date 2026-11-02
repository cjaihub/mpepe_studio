import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

/// Structured result of an automatic location detection and reverse geocode.
class AutoLocationResult {
  final String formattedLocation; // e.g. "Nairobi, Kenya"
  final String? city;
  final String? state;
  final String? country;
  final String? countryCode; // e.g. "KE"
  final String? postalCode;
  final String? street;
  final String? phoneDialCode; // e.g. "+254"
  final String? currency; // e.g. "KES"
  final double latitude;
  final double longitude;

  const AutoLocationResult({
    required this.formattedLocation,
    this.city,
    this.state,
    this.country,
    this.countryCode,
    this.postalCode,
    this.street,
    this.phoneDialCode,
    this.currency,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
        'formattedLocation': formattedLocation,
        'city': city,
        'state': state,
        'country': country,
        'countryCode': countryCode,
        'postalCode': postalCode,
        'street': street,
        'phoneDialCode': phoneDialCode,
        'currency': currency,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// Service to detect GPS location and resolve rich regional and business metadata.
class OneovaLocationDetectorService {
  OneovaLocationDetectorService._();
  static final OneovaLocationDetectorService instance = OneovaLocationDetectorService._();

  static const String _ua = 'Oneova/1.0 (com.oneova.app)';

  /// Map of ISO 3166-1 alpha-2 country codes to international dial codes.
  static const Map<String, String> countryDialCodes = {
    'ng': '+234', // Nigeria
    'ke': '+254', // Kenya
    'za': '+27',  // South Africa
    'gh': '+233', // Ghana
    'tz': '+255', // Tanzania
    'ug': '+256', // Uganda
    'rw': '+250', // Rwanda
    'et': '+251', // Ethiopia
    'eg': '+20',  // Egypt
    'ma': '+212', // Morocco
    'sn': '+221', // Senegal
    'ci': '+225', // Ivory Coast
    'cm': '+237', // Cameroon
    'zm': '+260', // Zambia
    'zw': '+263', // Zimbabwe
    'gb': '+44',  // United Kingdom
    'us': '+1',   // United States
    'ca': '+1',   // Canada
    'ae': '+971', // United Arab Emirates
    'sa': '+966', // Saudi Arabia
    'in': '+91',  // India
    'de': '+49',  // Germany
    'fr': '+33',  // France
    'it': '+39',  // Italy
    'es': '+34',  // Spain
    'br': '+55',  // Brazil
    'au': '+61',  // Australia
    'jp': '+81',  // Japan
    'cn': '+86',  // China
  };

  /// Map of ISO country codes to local currency codes.
  static const Map<String, String> countryCurrencies = {
    'ng': 'NGN',
    'ke': 'KES',
    'za': 'ZAR',
    'gh': 'GHS',
    'tz': 'TZS',
    'ug': 'UGX',
    'rw': 'RWF',
    'et': 'ETB',
    'eg': 'EGP',
    'ma': 'MAD',
    'sn': 'XOF',
    'ci': 'XOF',
    'cm': 'XAF',
    'zm': 'ZMW',
    'zw': 'USD',
    'gb': 'GBP',
    'us': 'USD',
    'ca': 'CAD',
    'ae': 'AED',
    'sa': 'SAR',
    'in': 'INR',
    'de': 'EUR',
    'fr': 'EUR',
    'it': 'EUR',
    'es': 'EUR',
    'br': 'BRL',
    'au': 'AUD',
    'jp': 'JPY',
    'cn': 'CNY',
  };

  /// Resolves the phone dial code for an ISO country code.
  static String? dialCodeFor(String? countryCode) {
    if (countryCode == null) return null;
    return countryDialCodes[countryCode.toLowerCase().trim()];
  }

  /// Resolves the currency symbol or ISO code for an ISO country code.
  static String? currencyFor(String? countryCode) {
    if (countryCode == null) return null;
    return countryCurrencies[countryCode.toLowerCase().trim()];
  }

  /// Detects current device location and returns an [AutoLocationResult].
  /// Throws user-friendly [LocationException] if permissions or services are unavailable.
  Future<AutoLocationResult?> detect({BuildContext? context}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException('Location permission was denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException('Location permissions are permanently denied. Please enable them in app settings.');
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        position = last;
      } else {
        rethrow;
      }
    }

    return reverseGeocode(position.latitude, position.longitude);
  }

  /// Reverse geocodes [lat] and [lng] into an [AutoLocationResult] using Nominatim OpenStreetMap.
  Future<AutoLocationResult> reverseGeocode(double lat, double lng) async {
    try {
      final res = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'lat': '$lat',
          'lon': '$lng',
          'format': 'jsonv2',
          'zoom': '18',
          'addressdetails': '1',
        }),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};

        final city = (address['city'] ?? address['town'] ?? address['municipality'] ?? address['village'] ?? address['county'] ?? '') as String;
        final state = (address['state'] ?? address['region'] ?? '') as String;
        final country = (address['country'] ?? '') as String;
        final countryCode = (address['country_code'] ?? '') as String;
        final postalCode = (address['postcode'] ?? '') as String;
        final street = (address['road'] ?? address['suburb'] ?? '') as String;

        // Build a clean, readable location string: "City, Country" or "City, State, Country"
        String formatted;
        if (city.isNotEmpty && country.isNotEmpty) {
          formatted = '$city, $country';
        } else if (state.isNotEmpty && country.isNotEmpty) {
          formatted = '$state, $country';
        } else if (country.isNotEmpty) {
          formatted = country;
        } else {
          final displayName = (data['display_name'] as String?) ?? '';
          final parts = displayName.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(2).toList();
          formatted = parts.join(', ');
        }

        final upperCountryCode = countryCode.toUpperCase();
        final dialCode = dialCodeFor(countryCode);
        final currency = currencyFor(countryCode);

        return AutoLocationResult(
          formattedLocation: formatted.isNotEmpty ? formatted : 'Lat: ${lat.toStringAsFixed(2)}, Lng: ${lng.toStringAsFixed(2)}',
          city: city.isNotEmpty ? city : null,
          state: state.isNotEmpty ? state : null,
          country: country.isNotEmpty ? country : null,
          countryCode: upperCountryCode.isNotEmpty ? upperCountryCode : null,
          postalCode: postalCode.isNotEmpty ? postalCode : null,
          street: street.isNotEmpty ? street : null,
          phoneDialCode: dialCode,
          currency: currency,
          latitude: lat,
          longitude: lng,
        );
      }
    } catch (_) {
      // Fallback
    }

    return AutoLocationResult(
      formattedLocation: 'Lat: ${lat.toStringAsFixed(3)}, Lng: ${lng.toStringAsFixed(3)}',
      latitude: lat,
      longitude: lng,
    );
  }
}

/// A compact, high-density button that triggers auto-location detection.
/// Can be used as a suffix action in any [InputDecoration] or as a standalone chip.
class OneovaAutoLocationButton extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<AutoLocationResult>? onLocationDetected;
  final String tooltip;
  final bool asPill;
  final EdgeInsetsGeometry padding;

  const OneovaAutoLocationButton({
    super.key,
    this.controller,
    this.onLocationDetected,
    this.tooltip = 'Auto-detect current location',
    this.asPill = false,
    this.padding = const EdgeInsets.all(6),
  });

  @override
  State<OneovaAutoLocationButton> createState() => _OneovaAutoLocationButtonState();
}

class _OneovaAutoLocationButtonState extends State<OneovaAutoLocationButton> with SingleTickerProviderStateMixin {
  bool _isDetecting = false;
  late AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _handleDetect() async {
    if (_isDetecting) return;
    HapticFeedback.lightImpact();
    setState(() => _isDetecting = true);
    _spinController.repeat();

    try {
      final result = await OneovaLocationDetectorService.instance.detect(context: context);
      if (result != null && mounted) {
        if (widget.controller != null) {
          widget.controller!.text = result.formattedLocation;
          widget.controller!.selection = TextSelection.collapsed(offset: result.formattedLocation.length);
        }
        widget.onLocationDetected?.call(result);
        HapticFeedback.mediumImpact();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: AppColors.brandWhite),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Detected: ${result.formattedLocation}',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brandWhite),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.brandBlue,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is PermissionDeniedException ? (e.message ?? 'Location permission denied') : 'Could not detect location. Please check GPS settings.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandWhite),
          ),
          backgroundColor: AppColors.brandPink,
          action: SnackBarAction(
            label: 'Settings',
            textColor: AppColors.brandWhite,
            onPressed: Geolocator.openAppSettings,
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
        _spinController.stop();
        _spinController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asPill) {
      return InkWell(
        onTap: _isDetecting ? null : _handleDetect,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isDetecting)
                RotationTransition(
                  turns: _spinController,
                  child: const Icon(Icons.refresh_rounded, size: 14, color: AppColors.brandBlue),
                )
              else
                const Icon(Icons.my_location_rounded, size: 14, color: AppColors.brandBlue),
              const SizedBox(width: 5),
              Text(
                _isDetecting ? 'Detecting…' : 'Auto-detect Location',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: widget.tooltip,
      child: IconButton(
        icon: _isDetecting
            ? RotationTransition(
                turns: _spinController,
                child: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.brandBlue),
              )
            : const Icon(Icons.my_location_rounded, size: 18, color: AppColors.brandBlue),
        visualDensity: VisualDensity.compact,
        padding: widget.padding,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: _isDetecting ? null : _handleDetect,
      ),
    );
  }
}
