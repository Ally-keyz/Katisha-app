import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../data/promoter_repository.dart';

final promoterRepositoryProvider = Provider<PromoterRepository>((ref) {
  return PromoterRepository(ref.watch(apiClientProvider));
});

/// Bumped after a payout or a settings change so screens refetch.
///
/// Balances, the commission ledger and the payout history all move together, so
/// one shared counter is simpler than invalidating individual caches.
final promoterDataVersionProvider = StateProvider<int>((ref) => 0);
