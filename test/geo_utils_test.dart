import 'package:flutter_test/flutter_test.dart';

import 'package:um_ar_admin/core/utils/geo_utils.dart';

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(haversineMeters(7.06492, 125.5984, 7.06492, 125.5984), 0);
    });

    test('one degree of longitude on the equator ≈ 111.195 km', () {
      expect(haversineMeters(0, 0, 0, 1), closeTo(111195.08, 0.5));
    });

    test('one degree of latitude ≈ 111.195 km', () {
      expect(haversineMeters(10, 20, 11, 20), closeTo(111195.08, 0.5));
    });

    test('is symmetric', () {
      final a = haversineMeters(7.0673, 125.5951, 7.0688, 125.5960);
      final b = haversineMeters(7.0688, 125.5960, 7.0673, 125.5951);
      expect(a, closeTo(b, 1e-9));
    });

    test('short campus distance (~0.0001° lat ≈ 11 m)', () {
      expect(haversineMeters(7.0673, 125.5951, 7.0674, 125.5951),
          closeTo(11.12, 0.01));
    });

    test('antipodal points ≈ half the circumference', () {
      expect(haversineMeters(0, 0, 0, 180), closeTo(20015114, 2));
    });
  });

  group('parseLatLngPair', () {
    test('parses "lat, lng"', () {
      final p = parseLatLngPair('7.06492, 125.59840');
      expect(p, isNotNull);
      expect(p!.lat, 7.06492);
      expect(p.lng, 125.5984);
    });

    test('accepts no space, spaces only, semicolon and parentheses', () {
      for (final s in [
        '7.06492,125.59840',
        '7.06492 125.59840',
        '7.06492;125.59840',
        '(7.06492, 125.59840)',
        '  7.06492 ,  125.59840  ',
      ]) {
        final p = parseLatLngPair(s);
        expect(p, isNotNull, reason: s);
        expect(p!.lat, 7.06492, reason: s);
        expect(p.lng, 125.5984, reason: s);
      }
    });

    test('accepts negative and integer values', () {
      final p = parseLatLngPair('-33, -70.5');
      expect(p!.lat, -33);
      expect(p.lng, -70.5);
    });

    test('rejects out-of-range values', () {
      expect(parseLatLngPair('91, 125'), isNull);
      expect(parseLatLngPair('7, 181'), isNull);
      expect(parseLatLngPair('-90.5, 0'), isNull);
    });

    test('rejects malformed input', () {
      for (final s in ['', '7.06492', 'abc, def', '7.0, 125.5, 3', '7..0, 125']) {
        expect(parseLatLngPair(s), isNull, reason: s);
      }
    });
  });

  group('validateLatLng', () {
    test('accepts the boundaries', () {
      expect(validateLatLng(90, 180), isNull);
      expect(validateLatLng(-90, -180), isNull);
    });

    test('rejects missing or out-of-range values', () {
      expect(validateLatLng(null, 0), isNotNull);
      expect(validateLatLng(0, null), isNotNull);
      expect(validateLatLng(90.1, 0), isNotNull);
      expect(validateLatLng(0, -180.1), isNotNull);
    });
  });

  group('geoMidpoint', () {
    test('midpoint on the equator', () {
      final m = geoMidpoint(0, 0, 0, 90);
      expect(m.lat, closeTo(0, 1e-9));
      expect(m.lng, closeTo(45, 1e-9));
    });

    test('midpoint along a meridian', () {
      final m = geoMidpoint(10, 20, 30, 20);
      expect(m.lat, closeTo(20, 1e-9));
      expect(m.lng, closeTo(20, 1e-9));
    });

    test('at campus scale it matches the plain average', () {
      final m = geoMidpoint(7.0638081, 125.5915322, 7.0705229, 125.5986040);
      expect(m.lat, closeTo((7.0638081 + 7.0705229) / 2, 1e-7));
      expect(m.lng, closeTo((125.5915322 + 125.5986040) / 2, 1e-7));
    });

    test('is equidistant from both ends', () {
      const a = (7.0673, 125.5951);
      const b = (7.0681, 125.5962);
      final m = geoMidpoint(a.$1, a.$2, b.$1, b.$2);
      expect(haversineMeters(a.$1, a.$2, m.lat, m.lng),
          closeTo(haversineMeters(m.lat, m.lng, b.$1, b.$2), 1e-6));
    });

    test('wraps across the antimeridian', () {
      final m = geoMidpoint(0, 179, 0, -179);
      expect(m.lng.abs(), closeTo(180, 1e-9));
    });
  });

  group('formatDistanceM', () {
    test('metres with one decimal', () {
      expect(formatDistanceM(12.44), '12.4 m');
      expect(formatDistanceM(12.46), '12.5 m');
      expect(formatDistanceM(0), '0.0 m');
      expect(formatDistanceM(999.9), '999.9 m');
    });

    test('kilometres from 1000 m', () {
      expect(formatDistanceM(1000), '1.00 km');
      expect(formatDistanceM(2345), '2.35 km');
    });
  });

  group('exceedsEdgeLimit', () {
    test('under, equal and over', () {
      expect(exceedsEdgeLimit(5.9, 6), isFalse);
      expect(exceedsEdgeLimit(6.0, 6), isFalse);
      expect(exceedsEdgeLimit(6.1, 6), isTrue);
    });

    test('uses the displayed 0.1 m precision', () {
      // Shown as "6.0 m" → not over a 6 m limit.
      expect(exceedsEdgeLimit(6.04, 6), isFalse);
      // Shown as "6.1 m" → over.
      expect(exceedsEdgeLimit(6.06, 6), isTrue);
    });
  });

  group('parseEdgeLimit', () {
    test('accepts 2 to 100', () {
      expect(parseEdgeLimit('2'), 2);
      expect(parseEdgeLimit(' 6 '), 6);
      expect(parseEdgeLimit('12.5'), 12.5);
      expect(parseEdgeLimit('100'), 100);
    });

    test('rejects out of range and non-numbers', () {
      for (final s in ['1.9', '100.1', '0', '-5', '', 'abc', 'NaN']) {
        expect(parseEdgeLimit(s), isNull, reason: s);
      }
    });
  });
}
