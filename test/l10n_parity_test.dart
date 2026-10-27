import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/l10n/app_en.dart';
import 'package:katisha/l10n/app_fr.dart';
import 'package:katisha/l10n/app_localizations.dart';
import 'package:katisha/l10n/app_rw.dart';
import 'package:katisha/l10n/app_sw.dart';

/// Guards the translations across every shipped locale.
///
/// A missing key does not fail the build — `translate` silently falls back to
/// the key itself — so a drifted locale would only surface as raw English (or a
/// raw snake_case key) in the UI. Two things have actually caused that here:
/// adding a key to some locales but not others, and adding a key that already
/// exists, which is a compile error only because the maps are const.
void main() {
  final maps = <String, Map<String, String>>{
    'en': AppEn.strings,
    'rw': AppRw.strings,
    'fr': AppFr.strings,
    'sw': AppSw.strings,
  };

  final english = maps['en']!.keys.toSet();

  test('every locale defines exactly the English key set', () {
    for (final entry in maps.entries) {
      expect(
        entry.value.keys.toSet().difference(english),
        isEmpty,
        reason: '${entry.key} has keys absent from en',
      );
      expect(
        english.difference(entry.value.keys.toSet()),
        isEmpty,
        reason: '${entry.key} is missing keys present in en',
      );
    }
  });

  test('no locale defines a duplicate key', () {
    // A const map literal rejects duplicates at compile time, so reaching this
    // assertion means the maps are no longer const. Keep the guard anyway.
    for (final entry in maps.entries) {
      expect(entry.value.length, entry.value.keys.toSet().length,
          reason: '${entry.key} has duplicate keys');
    }
  });

  test('no value is blank', () {
    for (final entry in maps.entries) {
      entry.value.forEach((key, value) {
        expect(value.trim(), isNotEmpty, reason: '${entry.key}/$key is blank');
      });
    }
  });

  test('translate falls back to the key for unknown lookups', () {
    final l10n = AppLocalizations(const Locale('en'));
    expect(l10n.translate('definitely_not_a_real_key'),
        'definitely_not_a_real_key');
  });

  group('calendar copy', () {
    test('both full and abbreviated month keys coexist', () {
      const months = [
        'jan', 'feb', 'mar', 'apr', 'may', 'jun',
        'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
      ];
      for (final entry in maps.entries) {
        for (final m in months) {
          expect(entry.value, contains('month_$m'),
              reason: '${entry.key} is missing month_$m');
          expect(entry.value, contains('month_${m}_abbr'),
              reason: '${entry.key} is missing month_${m}_abbr');
        }
      }
    });

    test('abbreviated months stay short enough for the trend axis', () {
      for (final entry in maps.entries) {
        for (final m in ['jan', 'may', 'sep', 'dec']) {
          expect(entry.value['month_${m}_abbr']!.length, lessThanOrEqualTo(5),
              reason: '${entry.key}/month_${m}_abbr is too wide');
        }
      }
    });
  });
}
