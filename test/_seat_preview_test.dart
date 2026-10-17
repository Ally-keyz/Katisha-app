import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_fonts/src/google_fonts_base.dart' as gfb;
import 'package:katisha/features/booking/domain/seat_models.dart';
import 'package:katisha/features/booking/presentation/widgets/bus_seat_map.dart';

class _FakeAssetManifest implements AssetManifest {
  @override
  List<String> listAssets() => <String>[
        'assets/images/Inter-Light.ttf',
        'assets/images/Inter-Regular.ttf',
        'assets/images/Inter-Medium.ttf',
        'assets/images/Inter-SemiBold.ttf',
        'assets/images/Inter-Bold.ttf',
      ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

List<SeatRow> _rows() {
  final rows = <SeatRow>[];
  var n = 1;
  for (var r = 1; r <= 10; r++) {
    rows.add(SeatRow(y: r, cells: [
      SeatCell(type: 'seat', label: '${n++}'),
      SeatCell(
        type: 'seat',
        label: '${n++}',
        status: n == 7 ? 'booked_online' : null,
      ),
      SeatCell(type: 'aisle'),
      SeatCell(type: 'seat', label: '${n++}'),
      SeatCell(
        type: 'seat',
        label: '${n++}',
        status: n == 40 ? 'blocked' : null,
      ),
    ]));
  }
  rows.add(SeatRow(
    y: 11,
    cells: [for (var i = 0; i < 5; i++) SeatCell(type: 'seat', label: '${n++}')],
  ));
  return rows;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    gfb.assetManifest = _FakeAssetManifest();
  });

  testWidgets('seat map preview', (tester) async {
    tester.view.physicalSize = const Size(1170, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFEFF3F8),
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: RepaintBoundary(
              key: const Key('map'),
              child: BusSeatMap(
                rows: _rows(),
                selectedSet: const {'3', '20'},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('map')));
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    const bg = 0xEFF3F8;
    int px(int x, int y) {
      final o = (y * image.width + x) * 4;
      return (byteData.getUint8(o) << 16) |
          (byteData.getUint8(o + 1) << 8) |
          byteData.getUint8(o + 2);
    }

    bool nonBg(int x, int y) {
      final c = px(x, y);
      final dr = ((c >> 16) & 0xff) - ((bg >> 16) & 0xff);
      final dg = ((c >> 8) & 0xff) - ((bg >> 8) & 0xff);
      final db = (c & 0xff) - (bg & 0xff);
      return (dr.abs() + dg.abs() + db.abs()) > 24;
    }

    print('MAP SIZE: ${image.width} x ${image.height}');
    for (final frac in [0.03, 0.25, 0.5, 0.75, 0.97]) {
      final y = (image.height * frac).round().clamp(0, image.height - 1);
      var lo = -1, hi = -1;
      for (var x = 0; x < image.width; x++) {
        if (nonBg(x, y)) {
          if (lo < 0) lo = x;
          hi = x;
        }
      }
      print('y=$y (${(frac * 100).round()}%): x=[$lo..$hi] width=${hi - lo + 1}');
    }

    var blue = 0, red = 0, hatch = 0, white = 0, total = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final c = px(x, y);
        final r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff;
        total++;
        if (b > 150 && b > r + 40 && b > g + 20) blue++;
        if (r > 150 && r > g + 60 && r > b + 60) red++;
        if (r > 130 && r < 210 && g > 140 && g < 215 && b > 155 && b < 225 &&
            (r - g).abs() < 20) hatch++;
        if (r > 250 && g > 250 && b > 250) white++;
      }
    }
    print('blue=$blue red=$red grey=$hatch white=$white total=$total');

    await expectLater(
      find.byKey(const Key('map')),
      matchesGoldenFile('goldens/seat_map.png'),
    );
  });
}
