class AppLanguages {
  static const List<Map<String, String>> supported = [
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'uz', 'name': 'O‘zbek', 'flag': '🇺🇿'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'hi', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'ur', 'name': 'اردو', 'flag': '🇵🇰'},
    {'code': 'bn', 'name': 'বাংলা', 'flag': '🇧🇩'},
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'pl', 'name': 'Polski', 'flag': '🇵🇱'},
    {'code': 'nl', 'name': 'Nederlands', 'flag': '🇳🇱'},
    {'code': 'fa', 'name': 'فارسی', 'flag': '🇮🇷'},
    {'code': 'id', 'name': 'Bahasa Indonesia', 'flag': '🇮🇩'},
    {'code': 'vi', 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'code': 'th', 'name': 'ไทย', 'flag': '🇹🇭'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'tl', 'name': 'Tagalog', 'flag': '🇵🇭'},
    {'code': 'sw', 'name': 'Kiswahili', 'flag': '🇹🇿'},
    {'code': 'uk', 'name': 'Українська', 'flag': '🇺🇦'},
    {'code': 'ro', 'name': 'Română', 'flag': '🇷🇴'},
    {'code': 'cs', 'name': 'Čeština', 'flag': '🇨🇿'},
    {'code': 'hu', 'name': 'Magyar', 'flag': '🇭🇺'},
    {'code': 'sv', 'name': 'Svenska', 'flag': '🇸🇪'},
    {'code': 'da', 'name': 'Dansk', 'flag': '🇩🇰'},
    {'code': 'no', 'name': 'Norsk', 'flag': '🇳🇴'},
    {'code': 'el', 'name': 'Ελληνικά', 'flag': '🇬🇷'},
    {'code': 'he', 'name': 'עברית', 'flag': '🇮🇱'},
    {'code': 'pa', 'name': 'ਪੰਜਾਬੀ', 'flag': '🇮🇳'},
    {'code': 'ta', 'name': 'தமிழ்', 'flag': '🇮🇳'},
  ];

  static Map<String, String> getByCode(String code) {
    return supported.firstWhere(
      (element) => element['code'] == code,
      orElse: () => supported.first,
    );
  }
}
