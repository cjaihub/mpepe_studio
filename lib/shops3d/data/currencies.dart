import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../shared/theme/app_theme.dart';

/// World currencies for the shops.
///
/// The list of codes and their rates come live from `fx_rates/USD` (rewritten
/// every hour by the `fxRefresh` function), so a currency the rates source
/// adds shows up here without an app update. [currencyNames] only supplies
/// readable names.

/// Units of each currency per 1 US dollar, with when they were fetched.
@immutable
class FxRates {
  const FxRates(this.perUsd, this.fetchedAt);
  final Map<String, double> perUsd;
  final DateTime? fetchedAt;

  static const empty = FxRates({}, null);

  bool has(String code) => code.toUpperCase() == 'USD' || perUsd.containsKey(code.toUpperCase());

  /// Converts [amount] between two currencies, or null when a rate is missing.
  double? convert(num amount, String from, String to) {
    final f = from.toUpperCase(), t = to.toUpperCase();
    if (f == t) return amount.toDouble();
    final rf = f == 'USD' ? 1.0 : perUsd[f];
    final rt = t == 'USD' ? 1.0 : perUsd[t];
    if (rf == null || rt == null || rf <= 0) return null;
    return amount / rf * rt;
  }

  /// Every currency with a live rate, A–Z.
  List<String> get codes => ({'USD', ...perUsd.keys}.toList()..sort());
}

final fxRatesProvider = StreamProvider<FxRates>((ref) {
  return FirebaseFirestore.instance.doc('fx_rates/USD').snapshots().map((d) {
    final raw = d.data()?['rates'];
    if (raw is! Map) return FxRates.empty;
    final at = d.data()?['fetchedAt'];
    return FxRates(
      {
        for (final e in raw.entries)
          if (e.value is num && (e.value as num) > 0) '${e.key}'.toUpperCase(): (e.value as num).toDouble(),
      },
      at is Timestamp ? at.toDate() : null,
    );
  });
});

/// The currency of the phone's region (e.g. TZS in Tanzania), lower case.
String deviceCurrency() {
  try {
    final code = NumberFormat.simpleCurrency(locale: Platform.localeName).currencyName;
    if (code != null && code.length == 3) return code.toLowerCase();
  } catch (_) {/* unknown locale */}
  return 'usd';
}

/// The phone's region as an ISO country code ('' when unknown).
String deviceCountry() {
  final parts = Platform.localeName.split(RegExp('[_.-]'));
  return parts.length > 1 && parts[1].length == 2 ? parts[1].toUpperCase() : '';
}

String currencySymbol(String code) {
  try {
    return NumberFormat.simpleCurrency(name: code.toUpperCase()).currencySymbol;
  } catch (_) {
    return code.toUpperCase();
  }
}

/// "≈ KES 1,250" for a price in another currency, or null when it is the
/// same currency or no rate is known.
String? approxLocal(num amount, String currency, FxRates rates) {
  final mine = deviceCurrency();
  if (mine == currency.toLowerCase()) return null;
  final v = rates.convert(amount, currency, mine);
  if (v == null) return null;
  final digits = v >= 100 ? 0 : 2;
  return '≈ ${mine.toUpperCase()} ${NumberFormat.decimalPatternDigits(decimalDigits: digits).format(v)}';
}

String currencyName(String code) => currencyNames[code.toUpperCase()] ?? code.toUpperCase();

/// Searchable picker over every currency with a live rate. Returns the code
/// in lower case (the way products store it).
Future<String?> showCurrencyPicker(BuildContext context, WidgetRef ref, {required String selected}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _CurrencySheet(selected: selected.toUpperCase()),
  );
}

class _CurrencySheet extends ConsumerStatefulWidget {
  const _CurrencySheet({required this.selected});
  final String selected;

  @override
  ConsumerState<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends ConsumerState<_CurrencySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final rates = ref.watch(fxRatesProvider).value ?? FxRates.empty;
    // Before the first rates arrive the named list still lets the seller pick.
    final all = rates.perUsd.isEmpty ? (currencyNames.keys.toList()..sort()) : rates.codes;
    final mine = deviceCurrency().toUpperCase();
    final q = _q.trim().toLowerCase();
    final list = [
      for (final c in all)
        if (q.isEmpty || c.toLowerCase().contains(q) || currencyName(c).toLowerCase().contains(q)) c,
    ]..sort((a, b) {
        int rank(String c) => c == widget.selected ? 0 : (c == mine ? 1 : 2);
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.compareTo(b);
      });
    final at = rates.fetchedAt;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Currency', style: AppTypography.title3(context.textPrimary)),
            const SizedBox(height: 2),
            Text(
              at == null ? 'Loading live rates…' : '${all.length} currencies · rates updated ${DateFormat.MMMd().add_Hm().format(at)}',
              style: AppTypography.caption(context.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search currency or country money',
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('No currency matches “$_q”.', style: AppTypography.body(context.textSecondary)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final c = list[i];
                        final on = c == widget.selected;
                        final perMine = rates.convert(1, c, mine);
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onTap: () => Navigator.pop(context, c.toLowerCase()),
                          leading: Container(
                            width: 44,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? AppColors.brandBlue : context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(c, style: AppTypography.micro(on ? Colors.white : context.textPrimary)),
                          ),
                          title: Text(currencyName(c), style: AppTypography.callout(context.textPrimary)),
                          subtitle: c == mine
                              ? Text('Your region', style: AppTypography.caption(AppColors.brandBlue))
                              : (perMine == null
                                  ? null
                                  : Text(
                                      '1 $c ≈ ${NumberFormat.decimalPatternDigits(decimalDigits: perMine >= 100 ? 0 : (perMine >= 1 ? 2 : 4)).format(perMine)} $mine',
                                      style: AppTypography.caption(context.textSecondary),
                                    )),
                          trailing: on ? const Icon(Icons.check_rounded, size: 18, color: AppColors.brandBlue) : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Readable names (ISO 4217). Codes without a name here show as the code.
const currencyNames = <String, String>{
  'AED': 'UAE dirham', 'AFN': 'Afghan afghani', 'ALL': 'Albanian lek', 'AMD': 'Armenian dram', 'ANG': 'Netherlands Antillean guilder',
  'AOA': 'Angolan kwanza', 'ARS': 'Argentine peso', 'AUD': 'Australian dollar', 'AWG': 'Aruban florin', 'AZN': 'Azerbaijani manat',
  'BAM': 'Bosnia-Herzegovina mark', 'BBD': 'Barbadian dollar', 'BDT': 'Bangladeshi taka', 'BGN': 'Bulgarian lev', 'BHD': 'Bahraini dinar',
  'BIF': 'Burundian franc', 'BMD': 'Bermudian dollar', 'BND': 'Brunei dollar', 'BOB': 'Bolivian boliviano', 'BRL': 'Brazilian real',
  'BSD': 'Bahamian dollar', 'BTN': 'Bhutanese ngultrum', 'BWP': 'Botswana pula', 'BYN': 'Belarusian ruble', 'BZD': 'Belize dollar',
  'CAD': 'Canadian dollar', 'CDF': 'Congolese franc', 'CHF': 'Swiss franc', 'CLP': 'Chilean peso', 'CNY': 'Chinese yuan',
  'COP': 'Colombian peso', 'CRC': 'Costa Rican colón', 'CUP': 'Cuban peso', 'CVE': 'Cape Verdean escudo', 'CZK': 'Czech koruna',
  'DJF': 'Djiboutian franc', 'DKK': 'Danish krone', 'DOP': 'Dominican peso', 'DZD': 'Algerian dinar', 'EGP': 'Egyptian pound',
  'ERN': 'Eritrean nakfa', 'ETB': 'Ethiopian birr', 'EUR': 'Euro', 'FJD': 'Fijian dollar', 'FKP': 'Falkland Islands pound',
  'GBP': 'British pound', 'GEL': 'Georgian lari', 'GHS': 'Ghanaian cedi', 'GIP': 'Gibraltar pound', 'GMD': 'Gambian dalasi',
  'GNF': 'Guinean franc', 'GTQ': 'Guatemalan quetzal', 'GYD': 'Guyanese dollar', 'HKD': 'Hong Kong dollar', 'HNL': 'Honduran lempira',
  'HTG': 'Haitian gourde', 'HUF': 'Hungarian forint', 'IDR': 'Indonesian rupiah', 'ILS': 'Israeli shekel', 'INR': 'Indian rupee',
  'IQD': 'Iraqi dinar', 'IRR': 'Iranian rial', 'ISK': 'Icelandic króna', 'JMD': 'Jamaican dollar', 'JOD': 'Jordanian dinar',
  'JPY': 'Japanese yen', 'KES': 'Kenyan shilling', 'KGS': 'Kyrgyz som', 'KHR': 'Cambodian riel', 'KMF': 'Comorian franc',
  'KRW': 'South Korean won', 'KWD': 'Kuwaiti dinar', 'KYD': 'Cayman Islands dollar', 'KZT': 'Kazakhstani tenge', 'LAK': 'Lao kip',
  'LBP': 'Lebanese pound', 'LKR': 'Sri Lankan rupee', 'LRD': 'Liberian dollar', 'LSL': 'Lesotho loti', 'LYD': 'Libyan dinar',
  'MAD': 'Moroccan dirham', 'MDL': 'Moldovan leu', 'MGA': 'Malagasy ariary', 'MKD': 'Macedonian denar', 'MMK': 'Myanmar kyat',
  'MNT': 'Mongolian tögrög', 'MOP': 'Macanese pataca', 'MRU': 'Mauritanian ouguiya', 'MUR': 'Mauritian rupee', 'MVR': 'Maldivian rufiyaa',
  'MWK': 'Malawian kwacha', 'MXN': 'Mexican peso', 'MYR': 'Malaysian ringgit', 'MZN': 'Mozambican metical', 'NAD': 'Namibian dollar',
  'NGN': 'Nigerian naira', 'NIO': 'Nicaraguan córdoba', 'NOK': 'Norwegian krone', 'NPR': 'Nepalese rupee', 'NZD': 'New Zealand dollar',
  'OMR': 'Omani rial', 'PAB': 'Panamanian balboa', 'PEN': 'Peruvian sol', 'PGK': 'Papua New Guinean kina', 'PHP': 'Philippine peso',
  'PKR': 'Pakistani rupee', 'PLN': 'Polish złoty', 'PYG': 'Paraguayan guaraní', 'QAR': 'Qatari riyal', 'RON': 'Romanian leu',
  'RSD': 'Serbian dinar', 'RUB': 'Russian ruble', 'RWF': 'Rwandan franc', 'SAR': 'Saudi riyal', 'SBD': 'Solomon Islands dollar',
  'SCR': 'Seychellois rupee', 'SDG': 'Sudanese pound', 'SEK': 'Swedish krona', 'SGD': 'Singapore dollar', 'SHP': 'Saint Helena pound',
  'SLE': 'Sierra Leonean leone', 'SOS': 'Somali shilling', 'SRD': 'Surinamese dollar', 'SSP': 'South Sudanese pound', 'STN': 'São Tomé dobra',
  'SYP': 'Syrian pound', 'SZL': 'Eswatini lilangeni', 'THB': 'Thai baht', 'TJS': 'Tajikistani somoni', 'TMT': 'Turkmenistan manat',
  'TND': 'Tunisian dinar', 'TOP': 'Tongan paʻanga', 'TRY': 'Turkish lira', 'TTD': 'Trinidad and Tobago dollar', 'TWD': 'New Taiwan dollar',
  'TZS': 'Tanzanian shilling', 'UAH': 'Ukrainian hryvnia', 'UGX': 'Ugandan shilling', 'USD': 'US dollar', 'UYU': 'Uruguayan peso',
  'UZS': 'Uzbekistani som', 'VES': 'Venezuelan bolívar', 'VND': 'Vietnamese đồng', 'VUV': 'Vanuatu vatu', 'WST': 'Samoan tālā',
  'XAF': 'Central African CFA franc', 'XCD': 'East Caribbean dollar', 'XOF': 'West African CFA franc', 'XPF': 'CFP franc',
  'YER': 'Yemeni rial', 'ZAR': 'South African rand', 'ZMW': 'Zambian kwacha', 'ZWL': 'Zimbabwean dollar',
};
