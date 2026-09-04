import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_en.dart';
import 'app_fr.dart';
import 'app_rw.dart';
import 'app_sw.dart';

/// Only locales supported by Material/Cupertino go here.
/// Our custom [AppLocalizationsDelegate] handles all app strings.
const supportedLocales = [
  Locale('en'),
  Locale('rw'),
  Locale('sw'),
  Locale('fr'),
];

class AppLocalizations {
  final Locale locale;
  late final Map<String, String> _strings;

  AppLocalizations(this.locale) {
    _strings = switch (locale.languageCode) {
      'rw' => AppRw.strings,
      'sw' => AppSw.strings,
      'fr' => AppFr.strings,
      _ => AppEn.strings,
    };
  }

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  String translate(String key) => _strings[key] ?? key;

  String get languageCode => locale.languageCode;
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

/// Wraps [GlobalMaterialLocalizations] to accept any locale,
/// falling back to English for Material widget strings.
class _AdaptiveMaterialLocalizations extends LocalizationsDelegate<MaterialLocalizations> {
  const _AdaptiveMaterialLocalizations();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    return GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) => false;
}

/// Wraps [GlobalCupertinoLocalizations] to accept any locale,
/// falling back to English for Cupertino widget strings.
class _AdaptiveCupertinoLocalizations extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AdaptiveCupertinoLocalizations();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) async {
    return GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}

/// Localization delegates that work with all app locales.
const appLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizationsDelegate(),
  _AdaptiveMaterialLocalizations(),
  GlobalWidgetsLocalizations.delegate,
  _AdaptiveCupertinoLocalizations(),
];

class LanguagePreference {
  static const _key = 'vdk_language';

  static Future<Locale> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key) ?? 'en';
    return Locale(code);
  }

  static Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}

final appLocaleProvider = StateProvider<Locale>((ref) {
  return const Locale('en');
});

Future<void> initializeLocale(WidgetRef ref) async {
  final locale = await LanguagePreference.getLocale();
  ref.read(appLocaleProvider.notifier).state = locale;
}
