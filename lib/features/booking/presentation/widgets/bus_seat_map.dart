import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../domain/seat_models.dart';

/// Phone (upright) seat geometry — mirrors the web `seatMap.css` base tokens so
/// a full 45-seat layout fits the seat modal on a phone without scrolling.
const double _seatW = 52;
const double _seatH = 48;
const double _aisleW = _seatW * 1.05;
const double _seatGap = 5;
const double _rowGap = 5;
const double _shellPad = 6;

/// Camera tilt of the seat stack (web `--tilt: 5deg`) and the matching
/// perspective projection. Web uses `perspective: 1200px`, which divides by
/// `1 - z/1200`; Flutter's homogeneous divide needs the `(3, 2)` entry set to
/// `-1/1200` so rows recede upward (verified against the CSS).
const double _tilt = 5 * math.pi / 180;
const double _perspective = -1 / 1200;

/// Layered gradients per state. Colours are functional seat-state only, ported
/// from the web `Seat.tsx` `SKIN` map.
class _SeatSkin {
  final Gradient? back;
  final Gradient? cushion;
  final Gradient? head;
  final Color border;
  final Color text;
  final bool striped;

  const _SeatSkin({
    required this.border,
    required this.text,
    this.back,
    this.cushion,
    this.head,
    this.striped = false,
  });
}

LinearGradient _grad(int top, int bottom) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(top), Color(bottom)],
    );

final _seatSkinAvailable = _SeatSkin(
  back: _grad(0xFFFFFFFF, 0xFFEAF1FF),
  cushion: _grad(0xFFF8FBFF, 0xFFDBE7FB),
  head: _grad(0xFFFFFFFF, 0xFFEEF4FF),
  border: const Color(0xFFC3D4F2),
  text: const Color(0xFF1E3A8A),
);

final _seatSkinSelected = _SeatSkin(
  back: _grad(0xFF2563EB, 0xFF1D4ED8),
  cushion: _grad(0xFF1D4ED8, 0xFF1E40AF),
  head: _grad(0xFF3B82F6, 0xFF2563EB),
  border: const Color(0xFF1E40AF),
  text: const Color(0xFFFFFFFF),
);

final _seatSkinTaken = _SeatSkin(
  back: _grad(0xFFB25151, 0xFF9B3D3D),
  cushion: _grad(0xFFA04444, 0xFF8A3434),
  head: _grad(0xFFB85C5C, 0xFFA34A4A),
  border: const Color(0xFF7F3B3B),
  text: const Color(0xEBFFFFFF),
);

const _seatSkinBlocked = _SeatSkin(
  border: Color(0xFF94A3B8),
  text: Color(0xFFFFFFFF),
  striped: true,
);

_SeatSkin _skinFor(VisualSeatState state) {
  switch (state) {
    case VisualSeatState.available:
      return _seatSkinAvailable;
    case VisualSeatState.selected:
      return _seatSkinSelected;
    case VisualSeatState.taken:
      return _seatSkinTaken;
    case VisualSeatState.blocked:
      return _seatSkinBlocked;
  }
}

/// Data-driven, camera-tilted bus seat map. The layout comes entirely from the
/// API. Rows are laid out upright with the driver pinned at the bottom and the
/// front row nearest it, so the map reads like looking at the bus from the
/// front — matching the web build below the `sm` breakpoint.
class BusSeatMap extends StatefulWidget {
  final List<SeatRow> rows;
  final Set<String> selectedSet;
  final ValueChanged<String>? onToggleSeat;
  final String? agencyName;
  final String? logo;

  const BusSeatMap({
    super.key,
    required this.rows,
    this.selectedSet = const {},
    this.onToggleSeat,
    this.agencyName,
    this.logo,
  });

  @override
  State<BusSeatMap> createState() => _BusSeatMapState();
}

class _BusSeatMapState extends State<BusSeatMap> {
  final ScrollController _viewport = ScrollController();

  @override
  void initState() {
    super.initState();
    // The upright layout stacks the front row — and the driver — at the bottom,
    // so open the scroll area on the front seats rather than the back.
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFront());
  }

  @override
  void didUpdateWidget(covariant BusSeatMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows.length != widget.rows.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToFront());
    }
  }

  void _jumpToFront() {
    if (!mounted || !_viewport.hasClients) return;
    _viewport.jumpTo(_viewport.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasDriverCell =
        widget.rows.any((r) => r.cells.any((c) => c.type == SeatCellType.driver));
    // Front row (y = 1) nearest the driver. Reverse so the back rows sit at the
    // top and the front rows + driver sit at the bottom (upright layout).
    final ordered = [...widget.rows]..sort((a, b) => a.y.compareTo(b.y));

    final children = <Widget>[];
    for (final row in ordered.reversed) {
      if (row.cells.any((c) => c.type == SeatCellType.driver)) {
        children
            .add(_DriverCabin(logo: widget.logo, agencyName: widget.agencyName));
        continue;
      }
      children.add(_buildRow(row));
    }
    if (!hasDriverCell) {
      children
          .add(_DriverCabin(logo: widget.logo, agencyName: widget.agencyName));
    }

    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          children[i],
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The white shell is full-bleed and stays upright: in the web build the
        // `perspective` sits on the viewport and the `rotateX` only on the seat
        // stack, so the bus body is never tilted. Reserve the shell padding so
        // the panel never overflows its slot.
        final maxHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - _shellPad * 2).clamp(0.0, double.infinity)
            : 620.0;
        return SizedBox(
          width: constraints.maxWidth,
          child: _BusShell(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                controller: _viewport,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Center(
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, _perspective)
                      ..rotateX(_tilt),
                    child: inner,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(SeatRow row) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < row.cells.length; i++) ...[
          if (i > 0) const SizedBox(width: _seatGap),
          _buildCell(row.cells[i]),
        ],
      ],
    );
  }

  Widget _buildCell(SeatCell cell) {
    switch (cell.type) {
      case SeatCellType.seat:
        final label = cell.label ?? '';
        final selected = label.isNotEmpty && widget.selectedSet.contains(label);
        return _SeatTile(
          cell: cell,
          state: visualStateOf(cell, selected),
          onTap: (label.isEmpty || widget.onToggleSeat == null)
              ? null
              : () => widget.onToggleSeat!(label),
        );
      case SeatCellType.aisle:
        return const _Aisle();
      default:
        return const SizedBox(width: _seatW, height: _seatH);
    }
  }
}

class _Aisle extends StatelessWidget {
  const _Aisle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _aisleW,
      constraints: const BoxConstraints(minHeight: _seatH),
      margin: const EdgeInsets.symmetric(horizontal: _seatGap),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
      child: const CustomPaint(
        painter: _BandsPainter(
          alongX: true,
          colorA: Color(0xFFDBEAFE),
          colorB: Color(0xFFEFF6FF),
          widthA: 3,
          widthB: 3,
        ),
      ),
    );
  }
}

/// The physical bus: rounded body plus the fixed fixtures (luggage rails, entry
/// door, step and handrail) drawn behind the seat rows.
class _BusShell extends StatelessWidget {
  final Widget child;

  const _BusShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: CustomPaint(
        painter: _BusShellPainter(),
        child: Padding(
          padding: const EdgeInsets.all(_shellPad),
          child: child,
        ),
      ),
    );
  }
}

/// Draws the fixed bus fixtures using the same fractional geometry as the web
/// `seatMap.css` upright layout.
class _BusShellPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // Body.
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Luggage rails down each side.
    final railTop = h * 0.08;
    final railHeight = (h * 0.84 - railTop).clamp(0.0, h).toDouble();
    final railPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x8C94A3B8), Color(0x3394A3B8)],
      ).createShader(Rect.fromLTWH(0, railTop, 0, railHeight));
    for (final left in [18.0, w - 24]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, railTop, 6, railHeight),
          const Radius.circular(3),
        ),
        railPaint,
      );
    }

    // Entry door (right side, just behind the driver).
    final doorBottom = h * 0.87;
    final doorRect = Rect.fromLTRB(w - 20, doorBottom - 74, w, doorBottom);
    final doorRRect = RRect.fromRectAndCorners(
      doorRect,
      topLeft: const Radius.circular(10),
      bottomLeft: const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(doorRRect);
    _paintBands(
      canvas,
      doorRect,
      alongX: false,
      colorA: const Color(0xFFD7DEE9),
      colorB: const Color(0xFFEEF2F8),
      widthA: 5,
      widthB: 5,
    );
    // `border-left: 2px solid #c3ccd9` — only the inner (left) edge is ruled.
    canvas.drawRect(
      Rect.fromLTWH(doorRect.left, doorRect.top, 2, doorRect.height),
      Paint()..color = const Color(0xFFC3CCD9),
    );
    // `box-shadow: inset 2px 0 4px rgba(15,23,42,0.12)`.
    canvas.drawRect(
      Rect.fromLTWH(doorRect.left, doorRect.top, 6, doorRect.height),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x1F0F172A), Color(0x000F172A)],
        ).createShader(Rect.fromLTWH(doorRect.left, doorRect.top, 6, doorRect.height)),
    );
    canvas.restore();

    // Door step.
    final stepRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w - 34, doorBottom + 2, 30, 10),
      const Radius.circular(3),
    );
    canvas.drawRRect(stepRRect, Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawRRect(
      stepRRect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB9C3D2),
    );

    // Handrail (sits just above the door: `bottom: 14%`).
    final handrailRect = Rect.fromLTWH(w - 26, h * 0.86 - 62, 4, 62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(handrailRect, const Radius.circular(2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF94A3B8), Color(0xFFCBD5E1)],
        ).createShader(handrailRect),
    );
  }

  @override
  bool shouldRepaint(covariant _BusShellPainter oldDelegate) => false;
}

/// Driver cabin: the driver's seat with its steering wheel, plus the agency
/// logo (or a "Driver" label) underneath. Right-aligned, matching the web.
class _DriverCabin extends StatelessWidget {
  final String? logo;
  final String? agencyName;

  const _DriverCabin({this.logo, this.agencyName});

  static const double _seatWide = _seatW + 12; // calc(seat-w + 12px)
  static const double _wheelSize = _seatW * 0.95;
  static const double _wheelOverlap = _seatH * 0.25;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Driver's seat with the steering wheel tucked under its front edge so
          // the two read as one unit (web `.bus-driver__unit`).
          SizedBox(
            width: _seatWide,
            height: _seatH + _wheelSize - _wheelOverlap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: _seatH - _wheelOverlap,
                  left: (_seatWide - _wheelSize) / 2,
                  child: Transform.rotate(
                    // The source art reads upside-down in the top-down map.
                    angle: math.pi,
                    child: Image.asset(
                      'assets/images/steering_wheel.png',
                      width: _wheelSize,
                      height: _wheelSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Positioned(top: 0, left: 0, child: _seat()),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (logo != null && logo!.isNotEmpty)
            _AgencyLogo(url: logo!)
          else
            _driverLabel(),
        ],
      ),
    );
  }

  Widget _seat() {
    return Container(
      width: _seatWide,
      height: _seatH,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEEF2F8), Color(0xFFD3DBE7)],
        ),
        border: Border.all(color: const Color(0xFFC3CCD9)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0F172A),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 6,
            right: 6,
            top: 5,
            height: _seatH * 0.46,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFDFE6F0), Color(0xFFC3CCD9)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 6,
            height: _seatH * 0.38,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF0F4FA), Color(0xFFD7DEE9)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverLabel() => Text(
        'Driver',
        style: AppTypography.labelSmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: const Color(0xFF64748B),
        ),
      );
}

class _AgencyLogo extends StatelessWidget {
  final String url;

  const _AgencyLogo({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      height: 22,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Text(
        'Driver',
        style: AppTypography.labelSmall.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: const Color(0xFF64748B),
        ),
      ),
    );
  }
}

/// A single seat: layered backrest / headrest / cushion / armrests / buckle with
/// the seat number and a state mark (check / X / lock). Ported from `Seat.tsx`.
class _SeatTile extends StatelessWidget {
  final SeatCell cell;
  final VisualSeatState state;
  final VoidCallback? onTap;

  const _SeatTile({
    required this.cell,
    required this.state,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = _skinFor(state);
    final label = cell.label ?? '';
    final selected = state == VisualSeatState.selected;
    final detailHidden = state == VisualSeatState.taken ||
        state == VisualSeatState.blocked;

    final seat = SizedBox(
      width: _seatW,
      height: _seatH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Body: an unfilled, bordered, shadowed rounded rect. Only the
          // backrest / headrest / cushion carry colour, so the white shell shows
          // through the seat's edges (web `.bus-seat__body` has no background).
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: skin.border),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x400F172A),
                    blurRadius: 8,
                    offset: Offset(0, 6),
                  ),
                  if (selected) ...[
                    // Brand-blue halo on the selected seat.
                    const BoxShadow(color: Color(0x591D4ED8), spreadRadius: 2),
                    const BoxShadow(
                      color: Color(0x731D4ED8),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // Backrest
                    Positioned(
                      left: 6,
                      right: 6,
                      top: 5,
                      height: _seatH * 0.46,
                      child: _panel(
                        skin: skin,
                        gradient: skin.back,
                        radius: 8,
                        child: detailHidden
                            ? null
                            : Stack(
                                children: [
                                  Positioned.fill(
                                    left: 6,
                                    right: 6,
                                    child: _Seams(color: skin.text),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    // Headrest
                    Positioned(
                      top: 1,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: SizedBox(
                          width: _seatW * 0.46,
                          height: 9,
                          child: _panel(
                            skin: skin,
                            gradient: skin.head,
                            radius: 6,
                          ),
                        ),
                      ),
                    ),
                    // Cushion
                    Positioned(
                      left: 7,
                      right: 7,
                      bottom: 6,
                      height: _seatH * 0.38,
                      child: _panel(
                        skin: skin,
                        gradient: skin.cushion,
                        radius: 8,
                      ),
                    ),
                    // Armrests
                    Positioned(
                      left: 1,
                      top: _seatH * 0.3,
                      width: 5,
                      height: _seatH * 0.4,
                      child: _arm(),
                    ),
                    Positioned(
                      right: 1,
                      top: _seatH * 0.3,
                      width: 5,
                      height: _seatH * 0.4,
                      child: _arm(),
                    ),
                    // Seat-belt buckle
                    if (!detailHidden)
                      Positioned(
                        bottom: 8,
                        right: 9,
                        child: Container(
                          width: 6,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xBFDC2626),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Seat number
          Positioned(
            left: 0,
            right: 0,
            top: _seatH * 0.3,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                fontSize: 11.44,
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: 0.11,
                color: skin.text,
                shadows: const [
                  Shadow(
                    color: Color(0x99FFFFFF),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          // State mark
          if (selected)
            _mark(
              icon: Icons.check,
              color: Colors.white,
              background: const Color(0x38FFFFFF),
            ),
          if (state == VisualSeatState.taken)
            _mark(icon: Icons.close, color: const Color(0xE6FFFFFF)),
          if (state == VisualSeatState.blocked)
            _mark(icon: Icons.lock, color: Colors.white),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Matches CSS `translateY(-2px) scale(1.03)` about the seat centre.
      child: Transform.translate(
        offset: Offset(0, selected ? -2 : 0),
        child: Transform.scale(
          scale: selected ? 1.03 : 1.0,
          child: seat,
        ),
      ),
    );
  }

  /// A single seat panel (backrest / headrest / cushion): the state gradient, or
  /// the diagonal hatch when blocked, clipped to [radius].
  Widget _panel({
    required _SeatSkin skin,
    Gradient? gradient,
    required double radius,
    Widget? child,
  }) {
    final Widget fill = skin.striped
        ? const CustomPaint(
            painter: _DiagonalStripesPainter(
              colorA: Color(0xFF94A3B8),
              colorB: Color(0xFFCBD5E1),
              stripeWidth: 4,
              period: 8,
            ),
          )
        : DecoratedBox(decoration: BoxDecoration(gradient: gradient));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(child: fill),
          ?child,
        ],
      ),
    );
  }

  Widget _arm() => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x8C1D4ED8),
          borderRadius: BorderRadius.circular(3),
        ),
      );

  Widget _mark({
    required IconData icon,
    required Color color,
    Color? background,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 3,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}

/// Two dashed seam lines across the backrest, matching the web seat's stitching.
class _Seams extends StatelessWidget {
  final Color color;

  const _Seams({required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SeamsPainter(color));
  }
}

class _SeamsPainter extends CustomPainter {
  final Color color;

  const _SeamsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (final t in [0.4, 0.66]) {
      final y = size.height * t;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 3, size.width), y),
          paint,
        );
        x += 6;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeamsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Legend for the seat states. Colour is never the only signal — selected
/// carries a check, taken an X and blocked a lock — so the map stays readable
/// for colour-blind users. Ported from the web `Legend.tsx`.
class SeatLegend extends StatelessWidget {
  final String availableLabel;
  final String selectedLabel;
  final String takenLabel;
  final String blockedLabel;

  const SeatLegend({
    super.key,
    required this.availableLabel,
    required this.selectedLabel,
    required this.takenLabel,
    required this.blockedLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _item(
          availableLabel,
          _Swatch(
            gradient: _grad(0xFFFFFFFF, 0xFFEEF1F6),
            border: const Color(0xFFCFD6E2),
          ),
        ),
        _item(
          selectedLabel,
          _Swatch(
            gradient: _grad(0xFF2563EB, 0xFF1D4ED8),
            border: const Color(0xFF1E40AF),
            icon: Icons.check,
          ),
        ),
        _item(
          takenLabel,
          _Swatch(
            gradient: _grad(0xFFB25151, 0xFF9B3D3D),
            border: const Color(0xFF7F3B3B),
            icon: Icons.close,
          ),
        ),
        _item(
          blockedLabel,
          const _Swatch(
            border: Color(0xFF94A3B8),
            hatch: true,
            icon: Icons.lock,
          ),
        ),
      ],
    );
  }

  Widget _item(String label, Widget swatch) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Gradient? gradient;
  final Color border;
  final IconData? icon;
  final bool hatch;

  const _Swatch({
    this.gradient,
    required this.border,
    this.icon,
    this.hatch = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: border),
        color: hatch ? Colors.white : null,
        gradient: hatch ? null : gradient,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hatch)
            const Positioned.fill(
              child: CustomPaint(
                painter: _DiagonalStripesPainter(
                  colorA: Color(0xFF94A3B8),
                  colorB: Color(0xFFCBD5E1),
                  stripeWidth: 3,
                  period: 6,
                ),
              ),
            ),
          if (icon != null) Icon(icon, size: 10, color: Colors.white),
        ],
      ),
    );
  }
}

class _DiagonalStripesPainter extends CustomPainter {
  final Color colorA;
  final Color colorB;
  final double stripeWidth;
  final double period;

  const _DiagonalStripesPainter({
    required this.colorA,
    required this.colorB,
    this.stripeWidth = 4,
    this.period = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colorB);
    final paint = Paint()
      ..color = colorA
      ..strokeWidth = stripeWidth
      ..strokeCap = StrokeCap.butt;
    // 45° lines: horizontal centre-to-centre step for a perpendicular period p
    // is p·√2.
    final step = period * math.sqrt2;
    for (double x = -size.height - step; x < size.width + step; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiagonalStripesPainter oldDelegate) =>
      oldDelegate.colorA != colorA ||
      oldDelegate.colorB != colorB ||
      oldDelegate.stripeWidth != stripeWidth ||
      oldDelegate.period != period;
}

/// Alternating bands (used for the aisle and the ribbed door). `alongX` bands run
/// vertically; otherwise they run horizontally.
class _BandsPainter extends CustomPainter {
  final bool alongX;
  final Color colorA;
  final Color colorB;
  final double widthA;
  final double widthB;

  const _BandsPainter({
    required this.alongX,
    required this.colorA,
    required this.colorB,
    required this.widthA,
    required this.widthB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBands(
      canvas,
      Offset.zero & size,
      alongX: alongX,
      colorA: colorA,
      colorB: colorB,
      widthA: widthA,
      widthB: widthB,
    );
  }

  @override
  bool shouldRepaint(covariant _BandsPainter oldDelegate) =>
      oldDelegate.alongX != alongX ||
      oldDelegate.colorA != colorA ||
      oldDelegate.colorB != colorB ||
      oldDelegate.widthA != widthA ||
      oldDelegate.widthB != widthB;
}

void _paintBands(
  Canvas canvas,
  Rect rect, {
  required bool alongX,
  required Color colorA,
  required Color colorB,
  required double widthA,
  required double widthB,
}) {
  canvas.drawRect(rect, Paint()..color = colorB);
  final paintA = Paint()..color = colorA;
  final period = widthA + widthB;
  if (period <= 0) return;
  if (alongX) {
    for (double x = rect.left; x < rect.right; x += period) {
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          rect.top,
          math.min(widthA, rect.right - x),
          rect.height,
        ),
        paintA,
      );
    }
  } else {
    for (double y = rect.top; y < rect.bottom; y += period) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          y,
          rect.width,
          math.min(widthA, rect.bottom - y),
        ),
        paintA,
      );
    }
  }
}
