/// World and local languages people can pick for translations (reels, and
/// anywhere else Oneova translates). Codes are ISO 639-1 where one exists,
/// else ISO 639-2/3. Names are the English name and the language's own name.
class WorldLanguage {
  final String code;
  final String name;
  final String native;
  const WorldLanguage(this.code, this.name, this.native);

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || native.toLowerCase().contains(q) || code.toLowerCase() == q;
  }
}

class WorldLanguages {
  WorldLanguages._();

  static WorldLanguage? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final c = code.toLowerCase();
    for (final l in all) {
      if (l.code.toLowerCase() == c) return l;
    }
    final base = c.split(RegExp('[-_]')).first;
    for (final l in all) {
      if (l.code == base) return l;
    }
    return null;
  }

  /// English name for a code, or null when it isn't in the list.
  static String? nameOf(String? code) => byCode(code)?.name;

  static List<WorldLanguage> search(String query) => all.where((l) => l.matches(query)).toList();

  static const List<WorldLanguage> all = [
    // Africa
    WorldLanguage('sw', 'Swahili', 'Kiswahili'),
    WorldLanguage('yo', 'Yoruba', 'Yorùbá'),
    WorldLanguage('ha', 'Hausa', 'Hausa'),
    WorldLanguage('ig', 'Igbo', 'Asụsụ Igbo'),
    WorldLanguage('zu', 'Zulu', 'isiZulu'),
    WorldLanguage('xh', 'Xhosa', 'isiXhosa'),
    WorldLanguage('am', 'Amharic', 'አማርኛ'),
    WorldLanguage('so', 'Somali', 'Soomaali'),
    WorldLanguage('om', 'Oromo', 'Afaan Oromoo'),
    WorldLanguage('ti', 'Tigrinya', 'ትግርኛ'),
    WorldLanguage('af', 'Afrikaans', 'Afrikaans'),
    WorldLanguage('rw', 'Kinyarwanda', 'Ikinyarwanda'),
    WorldLanguage('rn', 'Kirundi', 'Ikirundi'),
    WorldLanguage('lg', 'Luganda', 'Oluganda'),
    WorldLanguage('ki', 'Kikuyu', 'Gĩkũyũ'),
    WorldLanguage('luo', 'Luo (Dholuo)', 'Dholuo'),
    WorldLanguage('kam', 'Kamba', 'Kikamba'),
    WorldLanguage('ak', 'Akan (Twi)', 'Akan'),
    WorldLanguage('ee', 'Ewe', 'Eʋegbe'),
    WorldLanguage('gaa', 'Ga', 'Gã'),
    WorldLanguage('wo', 'Wolof', 'Wolof'),
    WorldLanguage('ff', 'Fula (Fulfulde)', 'Fulfulde'),
    WorldLanguage('bm', 'Bambara', 'Bamanankan'),
    WorldLanguage('ln', 'Lingala', 'Lingála'),
    WorldLanguage('kg', 'Kongo', 'Kikongo'),
    WorldLanguage('lua', 'Tshiluba', 'Tshiluba'),
    WorldLanguage('sn', 'Shona', 'chiShona'),
    WorldLanguage('nd', 'Northern Ndebele', 'isiNdebele'),
    WorldLanguage('ny', 'Chichewa (Nyanja)', 'Chichewa'),
    WorldLanguage('bem', 'Bemba', 'Ichibemba'),
    WorldLanguage('st', 'Sesotho', 'Sesotho'),
    WorldLanguage('tn', 'Setswana', 'Setswana'),
    WorldLanguage('ts', 'Tsonga', 'Xitsonga'),
    WorldLanguage('ve', 'Venda', 'Tshivenḓa'),
    WorldLanguage('ss', 'Swati', 'siSwati'),
    WorldLanguage('mg', 'Malagasy', 'Malagasy'),
    WorldLanguage('ber', 'Berber (Tamazight)', 'Tamaziɣt'),
    WorldLanguage('efi', 'Efik', 'Efik'),
    WorldLanguage('tiv', 'Tiv', 'Tiv'),
    WorldLanguage('kr', 'Kanuri', 'Kanuri'),
    WorldLanguage('nso', 'Northern Sotho (Sepedi)', 'Sepedi'),
    WorldLanguage('kab', 'Kabyle', 'Taqbaylit'),
    WorldLanguage('mos', 'Mossi (Mooré)', 'Mooré'),
    WorldLanguage('sg', 'Sango', 'Sängö'),
    // Middle East and Central Asia
    WorldLanguage('ar', 'Arabic', 'العربية'),
    WorldLanguage('fa', 'Persian (Farsi)', 'فارسی'),
    WorldLanguage('he', 'Hebrew', 'עברית'),
    WorldLanguage('tr', 'Turkish', 'Türkçe'),
    WorldLanguage('ku', 'Kurdish', 'Kurdî'),
    WorldLanguage('ps', 'Pashto', 'پښتو'),
    WorldLanguage('az', 'Azerbaijani', 'Azərbaycanca'),
    WorldLanguage('kk', 'Kazakh', 'Қазақ тілі'),
    WorldLanguage('uz', 'Uzbek', 'Oʻzbekcha'),
    WorldLanguage('ky', 'Kyrgyz', 'Кыргызча'),
    WorldLanguage('tg', 'Tajik', 'Тоҷикӣ'),
    WorldLanguage('tk', 'Turkmen', 'Türkmençe'),
    WorldLanguage('hy', 'Armenian', 'Հայերեն'),
    WorldLanguage('ka', 'Georgian', 'ქართული'),
    // South Asia
    WorldLanguage('hi', 'Hindi', 'हिन्दी'),
    WorldLanguage('ur', 'Urdu', 'اردو'),
    WorldLanguage('bn', 'Bengali', 'বাংলা'),
    WorldLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
    WorldLanguage('gu', 'Gujarati', 'ગુજરાતી'),
    WorldLanguage('mr', 'Marathi', 'मराठी'),
    WorldLanguage('ta', 'Tamil', 'தமிழ்'),
    WorldLanguage('te', 'Telugu', 'తెలుగు'),
    WorldLanguage('kn', 'Kannada', 'ಕನ್ನಡ'),
    WorldLanguage('ml', 'Malayalam', 'മലയാളം'),
    WorldLanguage('or', 'Odia', 'ଓଡ଼ିଆ'),
    WorldLanguage('as', 'Assamese', 'অসমীয়া'),
    WorldLanguage('ne', 'Nepali', 'नेपाली'),
    WorldLanguage('si', 'Sinhala', 'සිංහල'),
    WorldLanguage('sd', 'Sindhi', 'سنڌي'),
    // East and Southeast Asia, Pacific
    WorldLanguage('zh', 'Chinese (Simplified)', '简体中文'),
    WorldLanguage('zh-Hant', 'Chinese (Traditional)', '繁體中文'),
    WorldLanguage('yue', 'Cantonese', '粵語'),
    WorldLanguage('ja', 'Japanese', '日本語'),
    WorldLanguage('ko', 'Korean', '한국어'),
    WorldLanguage('mn', 'Mongolian', 'Монгол'),
    WorldLanguage('vi', 'Vietnamese', 'Tiếng Việt'),
    WorldLanguage('th', 'Thai', 'ไทย'),
    WorldLanguage('lo', 'Lao', 'ລາວ'),
    WorldLanguage('km', 'Khmer', 'ខ្មែរ'),
    WorldLanguage('my', 'Burmese', 'မြန်မာ'),
    WorldLanguage('id', 'Indonesian', 'Bahasa Indonesia'),
    WorldLanguage('ms', 'Malay', 'Bahasa Melayu'),
    WorldLanguage('jv', 'Javanese', 'Basa Jawa'),
    WorldLanguage('su', 'Sundanese', 'Basa Sunda'),
    WorldLanguage('fil', 'Filipino (Tagalog)', 'Filipino'),
    WorldLanguage('ceb', 'Cebuano', 'Cebuano'),
    WorldLanguage('mi', 'Māori', 'Te Reo Māori'),
    WorldLanguage('sm', 'Samoan', 'Gagana Sāmoa'),
    WorldLanguage('to', 'Tongan', 'Lea Faka-Tonga'),
    WorldLanguage('fj', 'Fijian', 'Vosa Vakaviti'),
    WorldLanguage('haw', 'Hawaiian', 'ʻŌlelo Hawaiʻi'),
    WorldLanguage('tpi', 'Tok Pisin', 'Tok Pisin'),
    // Europe
    WorldLanguage('en', 'English', 'English'),
    WorldLanguage('fr', 'French', 'Français'),
    WorldLanguage('pt', 'Portuguese', 'Português'),
    WorldLanguage('pt-BR', 'Portuguese (Brazil)', 'Português (Brasil)'),
    WorldLanguage('es', 'Spanish', 'Español'),
    WorldLanguage('de', 'German', 'Deutsch'),
    WorldLanguage('it', 'Italian', 'Italiano'),
    WorldLanguage('nl', 'Dutch', 'Nederlands'),
    WorldLanguage('ru', 'Russian', 'Русский'),
    WorldLanguage('uk', 'Ukrainian', 'Українська'),
    WorldLanguage('pl', 'Polish', 'Polski'),
    WorldLanguage('cs', 'Czech', 'Čeština'),
    WorldLanguage('sk', 'Slovak', 'Slovenčina'),
    WorldLanguage('hu', 'Hungarian', 'Magyar'),
    WorldLanguage('ro', 'Romanian', 'Română'),
    WorldLanguage('bg', 'Bulgarian', 'Български'),
    WorldLanguage('el', 'Greek', 'Ελληνικά'),
    WorldLanguage('sr', 'Serbian', 'Српски'),
    WorldLanguage('hr', 'Croatian', 'Hrvatski'),
    WorldLanguage('bs', 'Bosnian', 'Bosanski'),
    WorldLanguage('sl', 'Slovenian', 'Slovenščina'),
    WorldLanguage('mk', 'Macedonian', 'Македонски'),
    WorldLanguage('sq', 'Albanian', 'Shqip'),
    WorldLanguage('be', 'Belarusian', 'Беларуская'),
    WorldLanguage('lt', 'Lithuanian', 'Lietuvių'),
    WorldLanguage('lv', 'Latvian', 'Latviešu'),
    WorldLanguage('et', 'Estonian', 'Eesti'),
    WorldLanguage('fi', 'Finnish', 'Suomi'),
    WorldLanguage('sv', 'Swedish', 'Svenska'),
    WorldLanguage('no', 'Norwegian', 'Norsk'),
    WorldLanguage('da', 'Danish', 'Dansk'),
    WorldLanguage('is', 'Icelandic', 'Íslenska'),
    WorldLanguage('ga', 'Irish', 'Gaeilge'),
    WorldLanguage('cy', 'Welsh', 'Cymraeg'),
    WorldLanguage('gd', 'Scottish Gaelic', 'Gàidhlig'),
    WorldLanguage('eu', 'Basque', 'Euskara'),
    WorldLanguage('ca', 'Catalan', 'Català'),
    WorldLanguage('gl', 'Galician', 'Galego'),
    WorldLanguage('mt', 'Maltese', 'Malti'),
    WorldLanguage('lb', 'Luxembourgish', 'Lëtzebuergesch'),
    // Americas and Caribbean
    WorldLanguage('ht', 'Haitian Creole', 'Kreyòl ayisyen'),
    WorldLanguage('jam', 'Jamaican Patois', 'Patwa'),
    WorldLanguage('qu', 'Quechua', 'Runa Simi'),
    WorldLanguage('gn', 'Guarani', 'Avañeʼẽ'),
    WorldLanguage('ay', 'Aymara', 'Aymar aru'),
    WorldLanguage('nah', 'Nahuatl', 'Nāhuatl'),
    WorldLanguage('yua', 'Yucatec Maya', 'Maaya tʼaan'),
    WorldLanguage('chr', 'Cherokee', 'ᏣᎳᎩ'),
    WorldLanguage('nv', 'Navajo', 'Diné bizaad'),
    // Other widely used
    WorldLanguage('eo', 'Esperanto', 'Esperanto'),
    WorldLanguage('la', 'Latin', 'Latina'),
    WorldLanguage('yi', 'Yiddish', 'ייִדיש'),
  ];
}
