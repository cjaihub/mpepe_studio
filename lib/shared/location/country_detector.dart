import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../identity/widgets/id_country_picker.dart';

/// Where a detected country came from, in the order we trust it.
enum CountrySource { location, network, sim, phone, region, none }

class CountryDetection {
  final String? code;
  final CountrySource source;

  /// Every signal we saw (location, network, sim, phone, region → ISO code).
  /// Sent with KYC so reviewers can see when the ID country differs.
  final Map<String, String> signals;
  const CountryDetection(this.code, this.source, this.signals);

  String get sourceLabel => switch (source) {
        CountrySource.location => 'from your location',
        CountrySource.network => 'from your mobile network',
        CountrySource.sim => 'from your SIM card',
        CountrySource.phone => 'from your phone number',
        CountrySource.region => 'from your phone’s region',
        CountrySource.none => '',
      };
}

/// Finds the person's country on the phone itself: GPS (only with permission)
/// through the phone's own geocoder, then mobile network, SIM, phone number and
/// region. Nothing goes to a third-party service.
class CountryDetector {
  CountryDetector._();

  static const _ch = MethodChannel('com.oneova.app/country_signals');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String? _iso(Object? v) {
    final s = (v is String ? v : '').toUpperCase();
    return kIdCountries.containsKey(s) ? s : null;
  }

  /// [askLocation] shows the location permission prompt if it hasn't been
  /// answered; otherwise location is used only if already allowed.
  static Future<CountryDetection> detect({bool askLocation = false}) async {
    final signals = <String, String>{};

    final loc = await _fromLocation(askLocation);
    if (loc != null) signals['location'] = loc;

    if (_android) {
      try {
        final t = await _ch.invokeMapMethod<String, Object?>('telephony');
        final net = _iso(t?['network']);
        final sim = _iso(t?['sim']);
        if (net != null) signals['network'] = net;
        if (sim != null) signals['sim'] = sim;
      } catch (e) {
        debugPrint('[CountryDetector] telephony: $e');
      }
    }

    final phone = countryFromPhone(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    final region = _iso(WidgetsBinding.instance.platformDispatcher.locale.countryCode);
    if (phone != null) signals['phone'] = phone;
    if (region != null) signals['region'] = region;

    for (final (key, source) in const [
      ('location', CountrySource.location),
      ('network', CountrySource.network),
      ('sim', CountrySource.sim),
      ('phone', CountrySource.phone),
      ('region', CountrySource.region),
    ]) {
      final c = signals[key];
      if (c != null) return CountryDetection(c, source, signals);
    }
    return CountryDetection(null, CountrySource.none, signals);
  }

  static Future<String?> _fromLocation(bool ask) async {
    if (!_android) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return null;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          );
      return _iso(await _ch.invokeMethod<String>('countryAt', {'lat': pos.latitude, 'lng': pos.longitude}));
    } catch (e) {
      debugPrint('[CountryDetector] location: $e');
      return null;
    }
  }
}
