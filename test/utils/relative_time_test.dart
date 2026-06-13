import 'package:flutter_test/flutter_test.dart';
import 'package:rolekeeper/utils/relative_time.dart';

void main() {
  group('relativeTime', () {
    final now = DateTime.utc(2025, 11, 8, 12, 0, 0);

    group('"just now" boundary (< 1 minute)', () {
      test('0 seconds ago', () {
        expect(relativeTime(now, now: now), 'just now');
      });
      test('30 seconds ago', () {
        expect(
          relativeTime(now.subtract(const Duration(seconds: 30)), now: now),
          'just now',
        );
      });
      test('59 seconds ago', () {
        expect(
          relativeTime(now.subtract(const Duration(seconds: 59)), now: now),
          'just now',
        );
      });
    });

    group('"N minutes ago" boundary (1m – 59m)', () {
      test('exactly 1 minute', () {
        expect(
          relativeTime(now.subtract(const Duration(minutes: 1)), now: now),
          '1 minute ago',
        );
      });
      test('5 minutes', () {
        expect(
          relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          '5 minutes ago',
        );
      });
      test('59 minutes', () {
        expect(
          relativeTime(now.subtract(const Duration(minutes: 59)), now: now),
          '59 minutes ago',
        );
      });
    });

    group('"N hours ago" boundary (1h – 23h)', () {
      test('exactly 1 hour', () {
        expect(
          relativeTime(now.subtract(const Duration(hours: 1)), now: now),
          '1 hour ago',
        );
      });
      test('2 hours', () {
        expect(
          relativeTime(now.subtract(const Duration(hours: 2)), now: now),
          '2 hours ago',
        );
      });
      test('23 hours', () {
        expect(
          relativeTime(now.subtract(const Duration(hours: 23)), now: now),
          '23 hours ago',
        );
      });
    });

    group('"N days ago" boundary (1 day and beyond)', () {
      test('exactly 1 day', () {
        expect(
          relativeTime(now.subtract(const Duration(days: 1)), now: now),
          '1 day ago',
        );
      });
      test('3 days', () {
        expect(
          relativeTime(now.subtract(const Duration(days: 3)), now: now),
          '3 days ago',
        );
      });
      test('30 days', () {
        expect(
          relativeTime(now.subtract(const Duration(days: 30)), now: now),
          '30 days ago',
        );
      });
    });

    test('future timestamps clamp to "just now"', () {
      expect(
        relativeTime(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });
  });
}
