import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/katisha_modal.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/seat_repository.dart';
import '../../domain/seat_models.dart';
import 'bus_seat_map.dart';

/// What the seat modal hands back to the wizard when the rider confirms.
class SeatSelectionResult {
  /// Seats held (empty when the map is unavailable and only a count was chosen).
  final List<String> seatNumbers;

  /// Number of seats (equals `seatNumbers.length` when the map is active).
  final int count;

  /// Client id that owns the holds, submitted so the booking can claim them.
  final String clientId;

  /// True when the live map produced the selection (vs the fallback stepper).
  final bool active;

  const SeatSelectionResult({
    required this.seatNumbers,
    required this.count,
    required this.clientId,
    required this.active,
  });
}

/// Interactive seat picker shown inside a [KatishaModal]. Resolves the departure
/// to a trip, loads the live layout, lets the rider pick seats (polling the
/// server every 15s) and places a hold on confirm. Ported from the web
/// `SeatSelectionStep` + `useTripSeats`.
class SeatSelectionSheet extends ConsumerStatefulWidget {
  final String agencyId;
  final String routeId;
  final String travelDate;
  final String travelTime;
  final num price;
  final String currency;
  final List<String> initialSeatNumbers;
  final int initialCount;

  const SeatSelectionSheet({
    super.key,
    required this.agencyId,
    required this.routeId,
    required this.travelDate,
    required this.travelTime,
    required this.price,
    required this.currency,
    this.initialSeatNumbers = const [],
    this.initialCount = 1,
  });

  @override
  ConsumerState<SeatSelectionSheet> createState() => _SeatSelectionSheetState();
}

class _SeatSelectionSheetState extends ConsumerState<SeatSelectionSheet> {
  static const _pollMs = 15000;

  String _clientId = '';
  String? _tripId;
  TripSeatMap? _data;
  bool _loading = true;
  bool _refreshing = false;
  bool _reserving = false;
  bool _failed = false;
  String? _notice;
  List<String> _selected = [];
  late int _fallbackCount = widget.initialCount < 1 ? 1 : widget.initialCount;
  Timer? _poll;
  bool _prefilled = false;

  bool get _active =>
      _tripId != null && !_failed && (_data?.rows.isNotEmpty ?? false);

  int get _maxSeats => _data?.maxPerBooking ?? 5;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initialSeatNumbers);
    _prefilled = _selected.isNotEmpty;
    _poll = Timer.periodic(const Duration(milliseconds: _pollMs), (_) => _pollSeats());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _clientId = await seatClientId();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final repo = ref.read(seatRepositoryProvider);
    final resolved = await repo.resolveTrip(
      agencyId: widget.agencyId,
      routeId: widget.routeId,
      travelDate: widget.travelDate,
      travelTime: widget.travelTime,
      price: widget.price,
    );
    if (!mounted) return;
    resolved.fold(
      (failure) => setState(() {
        _failed = true;
        _loading = false;
        _notice = failure.message;
      }),
      (trip) {
        if (trip.tripId.isEmpty) {
          setState(() {
            _failed = true;
            _loading = false;
          });
          return;
        }
        _tripId = trip.tripId;
        _fetch(initial: true);
      },
    );
  }

  Future<void> _fetch({bool initial = false}) async {
    final tripId = _tripId;
    if (tripId == null) return;
    final repo = ref.read(seatRepositoryProvider);
    final res = await repo.getTripSeats(tripId, clientId: _clientId);
    if (!mounted) return;
    res.fold(
      (failure) => setState(() {
        if (initial) {
          _failed = true;
          _loading = false;
          _notice = failure.message;
        }
      }),
      (map) {
        setState(() {
          _data = map;
          _loading = false;
          _failed = map.rows.isEmpty;
        });
        _applyPrefill();
        _reconcile();
      },
    );
  }

  Future<void> _pollSeats() async {
    if (!_active || _refreshing || _reserving) return;
    _refreshing = true;
    final repo = ref.read(seatRepositoryProvider);
    final res = await repo.getTripSeats(_tripId!, clientId: _clientId);
    _refreshing = false;
    if (!mounted) return;
    res.fold((_) {}, (map) {
      setState(() => _data = map);
      _reconcile();
    });
  }

  /// Applies any seats carried in from a previous open once the layout loads.
  void _applyPrefill() {
    if (_prefilled || _data == null) return;
    _prefilled = true;
    final wanted = widget.initialSeatNumbers.where((s) => s.isNotEmpty).toList();
    if (wanted.isEmpty) return;
    final taken = <String>{};
    for (final row in _data!.rows) {
      for (final cell in row.cells) {
        if (cell.isSeat && cell.isOccupied && cell.label != null) {
          taken.add(cell.label!);
        }
      }
    }
    final keep = wanted
        .where((s) => !taken.contains(s))
        .take(_maxSeats)
        .toList(growable: false);
    if (keep.isNotEmpty) setState(() => _selected = List.of(keep));
  }

  /// Drops any selected seat that a live update has invalidated, with a notice.
  void _reconcile() {
    if (_selected.isEmpty || _data == null) return;
    final gone = _selected.where((label) {
      final cell = _findCell(label);
      return cell == null || !cell.isInteractive;
    }).toList();
    if (gone.isEmpty) return;
    setState(() {
      _selected = _selected.where((l) => !gone.contains(l)).toList();
      _notice = gone.length == 1
          ? AppLocalizations.of(context).translate('seat_was_taken').replaceAll('%s', gone.first)
          : AppLocalizations.of(context)
              .translate('seats_were_taken')
              .replaceAll('%s', gone.join(', '));
    });
  }

  SeatCell? _findCell(String label) {
    final data = _data;
    if (data == null) return null;
    for (final row in data.rows) {
      for (final cell in row.cells) {
        if (cell.label == label) return cell;
      }
    }
    return null;
  }

  void _toggleSeat(String label) {
    if (_selected.contains(label)) {
      setState(() => _selected = _selected.where((l) => l != label).toList());
      return;
    }
    final cell = _findCell(label);
    if (cell == null || !cell.isInteractive) return;
    if (_selected.length >= _maxSeats) {
      setState(() => _notice = AppLocalizations.of(context)
          .translate('up_to_seats_per_booking')
          .replaceAll('%d', '$_maxSeats'));
      return;
    }
    setState(() {
      _selected = [..._selected, label];
      if (_notice != null &&
          _notice!.startsWith(
              AppLocalizations.of(context).translate('up_to_seats_per_booking').split('%d').first)) {
        _notice = null;
      }
    });
  }

  Future<void> _confirm() async {
    if (!_active) {
      Navigator.of(context).pop(SeatSelectionResult(
        seatNumbers: const [],
        count: _fallbackCount,
        clientId: _clientId,
        active: false,
      ));
      return;
    }
    if (_selected.isEmpty) return;
    setState(() => _reserving = true);
    final repo = ref.read(seatRepositoryProvider);
    final res = await repo.reserveTripSeats(
      tripId: _tripId!,
      seatNumbers: _selected,
      clientId: _clientId,
    );
    if (!mounted) return;
    res.fold(
      (failure) {
        setState(() => _reserving = false);
        if (failure is SeatConflictFailure) {
          final taken = failure.alreadyTaken;
          final l10n = AppLocalizations.of(context);
          setState(() {
            _selected = _selected.where((l) => !taken.contains(l)).toList();
            _notice = taken.length <= 1
                ? l10n
                    .translate('seat_was_taken')
                    .replaceAll('%s', taken.isEmpty ? '' : taken.first)
                : l10n
                    .translate('seats_were_taken')
                    .replaceAll('%s', taken.join(', '));
          });
          _fetch();
        } else {
          setState(() => _notice = failure.message);
        }
      },
      (seats) {
        Navigator.of(context).pop(SeatSelectionResult(
          seatNumbers: seats,
          count: seats.length,
          clientId: _clientId,
          active: true,
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedSet = _selected.toSet();
    return KatishaModal(
      title: l10n.translate('select_your_seats'),
      subtitle: l10n.translate('pick_seats_on_map'),
      closeLabel: l10n.translate('close'),
      bodyScrollable: false,
      footer: _buildFooter(l10n),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Web hides the legend below the `sm` breakpoint (`hidden sm:flex`).
          if (_active && MediaQuery.sizeOf(context).width >= 640)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
              child: SeatLegend(
                availableLabel: l10n.translate('seat_available'),
                selectedLabel: l10n.translate('seat_selected'),
                takenLabel: l10n.translate('seat_taken'),
                blockedLabel: l10n.translate('seat_blocked'),
              ),
            ),
          Expanded(child: _buildBody(l10n, selectedSet)),
          if (_notice != null && _notice!.isNotEmpty)
            _buildNotice(_notice!),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, Set<String> selectedSet) {
    if (_loading && _tripId == null) {
      return const _SeatMapSkeleton();
    }
    if (!_active) {
      return _buildFallbackStepper(l10n);
    }
    return Stack(
      children: [
        BusSeatMap(
          rows: _data!.rows,
          selectedSet: selectedSet,
          onToggleSeat: _toggleSeat,
          agencyName: _data!.trip.agencyName,
          logo: _data!.trip.agencyLogo,
        ),
        if (_refreshing)
          Positioned(
            top: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNotice(String message) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                fontSize: 13,
                color: AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackStepper(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.translate('seat_map_unavailable'),
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 13,
                      color: AppColors.textSub,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepperButton(
                icon: Icons.remove,
                onPressed: _fallbackCount > 1
                    ? () => setState(() => _fallbackCount--)
                    : null,
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$_fallbackCount',
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              _stepperButton(
                icon: Icons.add,
                onPressed: _fallbackCount < 10
                    ? () => setState(() => _fallbackCount++)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({required IconData icon, VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onPressed != null ? AppColors.white : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: onPressed != null
                ? AppColors.border
                : AppColors.border.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onPressed != null ? AppColors.textSub : AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    final price = widget.price;
    final total = price * _selected.length;
    final canConfirm = !_reserving && (!_active || _selected.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _active
                      ? (_selected.isEmpty
                          ? l10n.translate('no_seats_selected_yet')
                          : l10n
                              .translate('seats_selected_count')
                              .replaceAll('%d', '${_selected.length}'))
                      : l10n
                          .translate('seats_selected_count')
                          .replaceAll('%d', '$_fallbackCount'),
                  style: AppTypography.bodySmall.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub,
                  ),
                ),
              ),
              if (_active && _selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _selected = []),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.primary,
                  ),
                  child: Text(
                    l10n.translate('clear'),
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          if (_active && _selected.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in _selected)
                  _seatChip(label, () => _toggleSeat(label)),
              ],
            ),
          ] else if (_active && _data != null) ...[
            const SizedBox(height: 2),
            Text(
              '${_data!.summary.available} of ${_data!.summary.total} seats available — tap a seat to choose.',
              style: AppTypography.bodySmall.copyWith(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.translate('total').toUpperCase(),
                    style: AppTypography.labelSmall.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.66,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    '${widget.currency} ${_formatAmount(total)}',
                    style: AppTypography.titleLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: canConfirm ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.primaryLight,
                      disabledForegroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                    child: _reserving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            l10n.translate('confirm_seats'),
                            style: AppTypography.buttonMedium,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seatChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 12, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  String _formatAmount(num value) {
    final s = value.round().abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return value < 0 ? '-$buf' : buf.toString();
  }
}

/// Grey placeholder rows shown while the trip resolves.
class _SeatMapSkeleton extends StatelessWidget {
  const _SeatMapSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            2,
            (i) => Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
