import 'package:full_cover/src/util/map_bounded.dart';
import 'package:test/test.dart';

void main() {
  test('preserves input order regardless of completion order', () async {
    final delays = [30, 10, 20, 0];
    final result = await mapBounded(delays, 4, (ms) async {
      await Future.delayed(Duration(milliseconds: ms));
      return ms;
    });
    expect(result, delays);
  });

  test('never runs more than maxConcurrent tasks at once', () async {
    var current = 0;
    var maxObserved = 0;
    await mapBounded(List.generate(10, (i) => i), 3, (i) async {
      current++;
      maxObserved = maxObserved < current ? current : maxObserved;
      await Future.delayed(const Duration(milliseconds: 5));
      current--;
      return i;
    });
    expect(maxObserved, lessThanOrEqualTo(3));
  });

  test('handles an empty list', () async {
    final result = await mapBounded<int, int>([], 4, (i) async => i);
    expect(result, isEmpty);
  });

  test(
    'caps concurrency at the item count when maxConcurrent is larger',
    () async {
      final result = await mapBounded([1, 2], 10, (i) async => i * 2);
      expect(result, [2, 4]);
    },
  );
}
