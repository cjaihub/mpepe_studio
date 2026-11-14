import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';

/// Every country (ISO 3166-1), so a business anywhere can register.
const kIdCountries = <String, String>{
  'AF': 'Afghanistan', 'AL': 'Albania', 'DZ': 'Algeria', 'AD': 'Andorra', 'AO': 'Angola', 'AG': 'Antigua and Barbuda',
  'AR': 'Argentina', 'AM': 'Armenia', 'AU': 'Australia', 'AT': 'Austria', 'AZ': 'Azerbaijan', 'BS': 'Bahamas', 'BH': 'Bahrain',
  'BD': 'Bangladesh', 'BB': 'Barbados', 'BY': 'Belarus', 'BE': 'Belgium', 'BZ': 'Belize', 'BJ': 'Benin', 'BT': 'Bhutan',
  'BO': 'Bolivia', 'BA': 'Bosnia and Herzegovina', 'BW': 'Botswana', 'BR': 'Brazil', 'BN': 'Brunei', 'BG': 'Bulgaria',
  'BF': 'Burkina Faso', 'BI': 'Burundi', 'CV': 'Cabo Verde', 'KH': 'Cambodia', 'CM': 'Cameroon', 'CA': 'Canada',
  'CF': 'Central African Republic', 'TD': 'Chad', 'CL': 'Chile', 'CN': 'China', 'CO': 'Colombia', 'KM': 'Comoros',
  'CG': 'Congo', 'CD': 'Congo (DRC)', 'CR': 'Costa Rica', 'CI': 'Côte d’Ivoire', 'HR': 'Croatia', 'CU': 'Cuba', 'CY': 'Cyprus',
  'CZ': 'Czechia', 'DK': 'Denmark', 'DJ': 'Djibouti', 'DM': 'Dominica', 'DO': 'Dominican Republic', 'EC': 'Ecuador',
  'EG': 'Egypt', 'SV': 'El Salvador', 'GQ': 'Equatorial Guinea', 'ER': 'Eritrea', 'EE': 'Estonia', 'SZ': 'Eswatini',
  'ET': 'Ethiopia', 'FJ': 'Fiji', 'FI': 'Finland', 'FR': 'France', 'GA': 'Gabon', 'GM': 'Gambia', 'GE': 'Georgia',
  'DE': 'Germany', 'GH': 'Ghana', 'GR': 'Greece', 'GD': 'Grenada', 'GT': 'Guatemala', 'GN': 'Guinea', 'GW': 'Guinea-Bissau',
  'GY': 'Guyana', 'HT': 'Haiti', 'HN': 'Honduras', 'HK': 'Hong Kong', 'HU': 'Hungary', 'IS': 'Iceland', 'IN': 'India',
  'ID': 'Indonesia', 'IR': 'Iran', 'IQ': 'Iraq', 'IE': 'Ireland', 'IL': 'Israel', 'IT': 'Italy', 'JM': 'Jamaica', 'JP': 'Japan',
  'JO': 'Jordan', 'KZ': 'Kazakhstan', 'KE': 'Kenya', 'KI': 'Kiribati', 'XK': 'Kosovo', 'KW': 'Kuwait', 'KG': 'Kyrgyzstan',
  'LA': 'Laos', 'LV': 'Latvia', 'LB': 'Lebanon', 'LS': 'Lesotho', 'LR': 'Liberia', 'LY': 'Libya', 'LI': 'Liechtenstein',
  'LT': 'Lithuania', 'LU': 'Luxembourg', 'MO': 'Macao', 'MG': 'Madagascar', 'MW': 'Malawi', 'MY': 'Malaysia', 'MV': 'Maldives',
  'ML': 'Mali', 'MT': 'Malta', 'MH': 'Marshall Islands', 'MR': 'Mauritania', 'MU': 'Mauritius', 'MX': 'Mexico',
  'FM': 'Micronesia', 'MD': 'Moldova', 'MC': 'Monaco', 'MN': 'Mongolia', 'ME': 'Montenegro', 'MA': 'Morocco',
  'MZ': 'Mozambique', 'MM': 'Myanmar', 'NA': 'Namibia', 'NR': 'Nauru', 'NP': 'Nepal', 'NL': 'Netherlands', 'NZ': 'New Zealand',
  'NI': 'Nicaragua', 'NE': 'Niger', 'NG': 'Nigeria', 'KP': 'North Korea', 'MK': 'North Macedonia', 'NO': 'Norway', 'OM': 'Oman',
  'PK': 'Pakistan', 'PW': 'Palau', 'PS': 'Palestine', 'PA': 'Panama', 'PG': 'Papua New Guinea', 'PY': 'Paraguay', 'PE': 'Peru',
  'PH': 'Philippines', 'PL': 'Poland', 'PT': 'Portugal', 'PR': 'Puerto Rico', 'QA': 'Qatar', 'RO': 'Romania', 'RU': 'Russia',
  'RW': 'Rwanda', 'KN': 'Saint Kitts and Nevis', 'LC': 'Saint Lucia', 'VC': 'Saint Vincent and the Grenadines', 'WS': 'Samoa',
  'SM': 'San Marino', 'ST': 'São Tomé and Príncipe', 'SA': 'Saudi Arabia', 'SN': 'Senegal', 'RS': 'Serbia', 'SC': 'Seychelles',
  'SL': 'Sierra Leone', 'SG': 'Singapore', 'SK': 'Slovakia', 'SI': 'Slovenia', 'SB': 'Solomon Islands', 'SO': 'Somalia',
  'ZA': 'South Africa', 'KR': 'South Korea', 'SS': 'South Sudan', 'ES': 'Spain', 'LK': 'Sri Lanka', 'SD': 'Sudan',
  'SR': 'Suriname', 'SE': 'Sweden', 'CH': 'Switzerland', 'SY': 'Syria', 'TW': 'Taiwan', 'TJ': 'Tajikistan', 'TZ': 'Tanzania',
  'TH': 'Thailand', 'TL': 'Timor-Leste', 'TG': 'Togo', 'TO': 'Tonga', 'TT': 'Trinidad and Tobago', 'TN': 'Tunisia',
  'TR': 'Türkiye', 'TM': 'Turkmenistan', 'TV': 'Tuvalu', 'UG': 'Uganda', 'UA': 'Ukraine', 'AE': 'United Arab Emirates',
  'GB': 'United Kingdom', 'US': 'United States', 'UY': 'Uruguay', 'UZ': 'Uzbekistan', 'VU': 'Vanuatu', 'VA': 'Vatican City',
  'VE': 'Venezuela', 'VN': 'Vietnam', 'YE': 'Yemen', 'ZM': 'Zambia', 'ZW': 'Zimbabwe',
};

const _dialToCountry = <String, String>{
  '+254': 'KE', '+255': 'TZ', '+256': 'UG', '+250': 'RW', '+251': 'ET', '+257': 'BI', '+211': 'SS', '+252': 'SO',
  '+253': 'DJ', '+234': 'NG', '+233': 'GH', '+27': 'ZA', '+20': 'EG', '+212': 'MA', '+221': 'SN', '+225': 'CI', '+237': 'CM',
  '+243': 'CD', '+260': 'ZM', '+263': 'ZW', '+265': 'MW', '+258': 'MZ', '+44': 'GB', '+91': 'IN', '+971': 'AE', '+966': 'SA',
};

/// Best guess of where the person is: verified ID country, then phone number,
/// then profile location text, then the phone's region, then Kenya.
String guessHomeCountry({String? verifiedCountry, String? profileLocation}) {
  final v = verifiedCountry?.toUpperCase();
  if (v != null && kIdCountries.containsKey(v)) return v;
  final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
  for (final len in [4, 3]) {
    if (phone.length > len) {
      final hit = _dialToCountry[phone.substring(0, len)];
      if (hit != null) return hit;
    }
  }
  final loc = (profileLocation ?? '').toLowerCase();
  if (loc.isNotEmpty) {
    for (final e in kIdCountries.entries) {
      if (loc.contains(e.value.toLowerCase())) return e.key;
    }
  }
  final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase();
  return kIdCountries.containsKey(region) ? region! : 'KE';
}

/// Tappable field that opens a searchable list of every country.
class IdCountryField extends StatelessWidget {
  const IdCountryField({super.key, required this.value, required this.onChanged, this.label = 'Country of registration'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: context.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
          builder: (_) => _CountrySheet(selected: value),
        );
        if (picked != null) {
          HapticFeedback.selectionClick();
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more_rounded)),
        child: Text(kIdCountries[value] ?? value, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.selected});
  final String selected;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final all = kIdCountries.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final list = q.isEmpty ? all : all.where((e) => e.value.toLowerCase().contains(q) || e.key.toLowerCase() == q).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search countries',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: context.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('No country matches “$_q”', style: TextStyle(color: context.textSecondary)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final on = e.key == widget.selected;
                      return ListTile(
                        title: Text(e.value, style: TextStyle(color: context.textPrimary, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
                        trailing: on ? const Icon(Icons.check_rounded, color: AppColors.brandBlue) : null,
                        onTap: () => Navigator.pop(context, e.key),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Choice pill where the selected one is clearly the strongest:
/// brand fill + white text + check; unselected ones are quiet outlines.
class IdChoicePill extends StatelessWidget {
  const IdChoicePill({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[const Icon(Icons.check_rounded, size: 16, color: Colors.white), const SizedBox(width: 6)],
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : context.textSecondary,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}
