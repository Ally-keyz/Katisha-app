import 'package:flutter_test/flutter_test.dart';
import 'package:katisha/features/promoter/data/models/promoter_models.dart';
import 'package:katisha/shared/models/app_role.dart';
import 'package:katisha/shared/models/app_user.dart';

void main() {
  group('AppRole', () {
    test('fromString maps the backend role strings', () {
      expect(AppRole.fromString('user'), AppRole.user);
      expect(AppRole.fromString('regular_user'), AppRole.user);
      expect(AppRole.fromString('promoter'), AppRole.promoter);
      // Unknown roles must not become promoters.
      expect(AppRole.fromString('agency_admin'), AppRole.user);
    });

    test('hasRole checks roles[] then the legacy role field', () {
      expect(
        AppRole.hasRole(const {'roles': ['promoter']}, AppRole.promoter),
        isTrue,
      );
      expect(
        AppRole.hasRole(const {'roles': ['user']}, AppRole.promoter),
        isFalse,
      );
      // Pre-backfill accounts only carry the single `role` field.
      expect(
        AppRole.hasRole(const {'role': 'promoter'}, AppRole.promoter),
        isTrue,
      );
    });

    test('fromUserJson prefers promoter over the legacy role field', () {
      expect(
        AppRole.fromUserJson(const {'roles': ['user'], 'role': 'promoter'}),
        AppRole.promoter,
      );
      expect(
        AppRole.fromUserJson(const {'roles': ['agency_admin', 'promoter']}),
        AppRole.promoter,
      );
      expect(AppRole.fromUserJson(const {'role': 'user'}), AppRole.user);
      expect(AppRole.fromUserJson(const {}), AppRole.user);
    });
  });

  group('AppUser promoter flags', () {
    Map<String, dynamic> promoterJson(String status) => {
          'id': 'u1',
          'name': 'Test',
          'phone': '0788000007',
          'role': 'user',
          'roles': const ['user', 'promoter'],
          'promoterCode': 'KATI250',
          'promoterStatus': status,
        };

    test('an active promoter gets full access', () {
      final user = AppUser.fromJson(promoterJson('active'));
      expect(user.isPromoter, isTrue);
      expect(user.isPromoterActive, isTrue);
      expect(user.role, AppRole.promoter);
      expect(user.promoterCode, 'KATI250');
    });

    test('pending and suspended keep the role but not active access', () {
      final pending = AppUser.fromJson(promoterJson('pending'));
      expect(pending.isPromoter, isTrue);
      expect(pending.isPromoterActive, isFalse);
      expect(pending.promoterStatus, 'pending');

      final suspended = AppUser.fromJson(promoterJson('suspended'));
      expect(suspended.isPromoter, isTrue);
      expect(suspended.isPromoterActive, isFalse);
      expect(suspended.promoterStatus, 'suspended');
    });

    test('isPromoterActive tolerates casing and padding', () {
      expect(
        AppUser.fromJson(promoterJson(' Active ')).isPromoterActive,
        isTrue,
      );
      expect(
        AppUser.fromJson(promoterJson('ACTIVE')).isPromoterActive,
        isTrue,
      );
    });

    test('a plain user has no promoter flags', () {
      final user = AppUser.fromJson({
        'id': 'u2',
        'name': 'Plain',
        'phone': '0788000008',
        'roles': const ['user'],
      });
      expect(user.isPromoter, isFalse);
      expect(user.isPromoterActive, isFalse);
      expect(user.promoterCode, isNull);
    });

    test('a promoter code alone does not grant the role', () {
      // The role has to come from the account, not from a referral code that
      // happens to be attached to the profile.
      final user = AppUser.fromJson({
        'id': 'u3',
        'name': 'Coded',
        'phone': '0788000009',
        'roles': const ['user'],
        'promoterCode': 'KATI999',
        'promoterStatus': 'suspended',
      });
      expect(user.isPromoter, isFalse);
      expect(user.isPromoterActive, isFalse);
    });
  });

  group('PromoterStatus', () {
    test('parse handles the server values', () {
      expect(PromoterStatus.parse('active'), PromoterStatus.active);
      expect(PromoterStatus.parse('pending'), PromoterStatus.pending);
      expect(PromoterStatus.parse('suspended'), PromoterStatus.suspended);
    });

    test('parse is tolerant of casing and null', () {
      expect(PromoterStatus.parse('ACTIVE'), PromoterStatus.active);
      expect(PromoterStatus.parse('Active'), PromoterStatus.active);
      expect(PromoterStatus.parse(null), PromoterStatus.unknown);
      expect(PromoterStatus.parse('wat'), PromoterStatus.unknown);
    });
  });

  group('PromoterPagination', () {
    test('reads the server envelope', () {
      final page = PromoterPagination.fromJson(const {
        'page': 2,
        'limit': 20,
        'total': 45,
        'pages': 3,
      });
      expect(page.page, 2);
      expect(page.limit, 20);
      expect(page.total, 45);
      expect(page.pages, 3);
      expect(page.hasMore, isTrue);
    });

    test('hasMore is false on the last page', () {
      expect(
        PromoterPagination.fromJson(const {
          'page': 3,
          'limit': 20,
          'total': 45,
          'pages': 3,
        }).hasMore,
        isFalse,
      );
    });

    test('defaults to a single empty page for a sparse payload', () {
      final page = PromoterPagination.fromJson(const {});
      expect(page.page, 1);
      expect(page.total, 0);
      expect(page.pages, 0);
      expect(page.hasMore, isFalse);
    });
  });

  group('PromoterEarningsSummary', () {
    test('reads the server summary', () {
      final summary = PromoterEarningsSummary.fromJson(const {
        'availableBalance': 1500,
        'lifetimeEarned': 4200,
        'paidTotal': 1000,
        'reversedTotal': 0,
        'pendingCount': 1,
        'paidCount': 2,
        'reversedCount': 0,
        'commissionCount': 3,
        'currency': 'RWF',
      });
      expect(summary.availableBalance, 1500);
      expect(summary.lifetimeEarned, 4200);
      expect(summary.pendingCount, 1);
      expect(summary.commissionCount, 3);
      expect(summary.currency, 'RWF');
    });

    test('missing fields fall back to zero rather than throwing', () {
      final summary = PromoterEarningsSummary.fromJson(const {});
      expect(summary.availableBalance, 0);
      expect(summary.lifetimeEarned, 0);
      expect(summary.commissionCount, 0);
      expect(summary.currency, isNotEmpty);
    });
  });

  group('PromoterStats', () {
    test('parses nested sections and tolerates a sparse payload', () {
      final stats = PromoterStats.fromJson(const {
        'earnings': {'availableBalance': 500},
        'referrals': {'total': 4, 'converted': 2, 'conversionRate': 50},
        'thisMonth': {'total': 250, 'count': 2},
        'trend': [
          {'year': 2026, 'month': 3, 'total': 100},
          {'year': 2026, 'month': 4, 'total': 400},
        ],
        'recentCommissions': [
          {'id': 'c1', 'amount': 100, 'currency': 'RWF', 'status': 'earned'},
        ],
        'minPayout': 1,
        'canRequestPayout': true,
      });

      expect(stats.earnings.availableBalance, 500);
      expect(stats.referrals.total, 4);
      expect(stats.referrals.conversionRate, 50);
      expect(stats.thisMonth.count, 2);
      expect(stats.trend, hasLength(2));
      expect(stats.trend.last.month, 4);
      expect(stats.recentCommissions, hasLength(1));
      expect(stats.canRequestPayout, isTrue);

      // Sections the server omitted must not produce null dereferences.
      final empty = PromoterStats.fromJson(const {});
      expect(empty.trend, isEmpty);
      expect(empty.recentCommissions, isEmpty);
      expect(empty.earnings.availableBalance, 0);
    });
  });
}
