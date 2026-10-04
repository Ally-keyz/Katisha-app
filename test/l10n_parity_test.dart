import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/l10n/app_en.dart';
import 'package:katisha/l10n/app_fr.dart';
import 'package:katisha/l10n/app_localizations.dart';
import 'package:katisha/l10n/app_rw.dart';
import 'package:katisha/l10n/app_sw.dart';

/// Guards the promoter translations across every shipped locale.
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

  group('promoter copy', () {
    test('required keys exist in every locale', () {
      const required = [
        'nav_promoter',
        'nav_promoter_earnings',
        'nav_promoter_referrals',
        'nav_promoter_payouts',
        'sign_in',
        'back_to_booking',
        'promoter_settings_title',
        'promoter_tab_payout',
        'promoter_tab_security',
        'promoter_available_balance',
        'promoter_paid_out_total',
        'promoter_withdraw_now',
        'promoter_payout_phone',
        'promoter_no_commissions',
        'promoter_no_referrals',
        'promoter_no_payouts',
        'status_active',
        'status_pending',
        'status_paid',
        'status_failed',
        'status_reversed',
        'status_converted',
        'status_suspended',
      ];
      for (final entry in maps.entries) {
        for (final key in required) {
          expect(entry.value, contains(key),
              reason: '${entry.key} is missing $key');
        }
      }
    });

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

    test('placeholder counts match their printf verbs', () {
      // formatRwf/formatMoney insert values with String.replaceAll, so a
      // mismatched placeholder silently drops the number.
      void expectPlaceholders(String key, List<String> verbs) {
        for (final entry in maps.entries) {
          final value = entry.value[key];
          if (value == null) continue;
          for (final verb in verbs) {
            expect(value, contains(verb),
                reason: '${entry.key}/$key is missing $verb');
          }
        }
      }

      expectPlaceholders('promoter_paid_out_total', ['%s']);
      expectPlaceholders('promoter_commissions_n', ['%d']);
      expectPlaceholders('promoter_referrals_total_n', ['%d']);
      expectPlaceholders('promoter_signed_in_as', ['%s']);
    });
  });
}
