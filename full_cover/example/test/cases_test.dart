import 'package:full_cover_example/src/cases.dart';
import 'package:test/test.dart';

class _StringMixinImpl with AStringMixin {}

void main() {
  group('AStringMixin', () {
    final impl = _StringMixinImpl();

    test('mix returns same characters', () {
      final result = impl.mix('hello');
      expect(result.length, 5);
      expect(result.split('').toSet(), {'h', 'e', 'l', 'o'});
    });

    test('mix handles empty string', () {
      expect(impl.mix(''), '');
    });
  });

  group('MixStringExt', () {
    test('mix returns same characters', () {
      const input = 'hello';
      final result = input.mix();
      expect(result.length, input.length);
      expect(result.split('').toSet(), input.split('').toSet());
    });

    test('mix handles empty string', () {
      expect(''.mix(), '');
    });
  });

  group('switchCase', () {
    test('matches double', () {
      expect(() => switchCase(3.14), prints('double\n'));
    });

    test('matches int', () {
      expect(() => switchCase(3), prints('int\n'));
    });
  });

  group('check', () {
    test('returns true for empty string', () {
      expect(check(''), isTrue);
    });

    test('returns false for non-empty string', () {
      expect(check('hi'), isFalse);
    });
  });

  group('ifElseBrackets', () {
    test('returns true for empty string', () {
      expect(ifElseBrackets(''), isTrue);
    });

    test('returns false for non-empty string', () {
      expect(ifElseBrackets('hi'), isFalse);
    });
  });

  group('ifElseFlat', () {
    test('returns true for empty string', () {
      expect(ifElseFlat(''), isTrue);
    });

    test('returns false for non-empty string', () {
      expect(ifElseFlat('hi'), isFalse);
    });
  });

  group('ifElseFallback', () {
    test('returns true for empty string', () {
      expect(ifElseFallback(''), isTrue);
    });

    test('returns false for non-empty string', () {
      expect(ifElseFallback('hi'), isFalse);
    });
  });

  group('square', () {
    test('squares its argument', () {
      expect(square(4), 16);
    });
  });

  group('classify', () {
    test('negative', () => expect(classify(-1), 'negative (-1)'));
    test('zero', () => expect(classify(0), 'zero (0)'));
    test('positive', () => expect(classify(5), 'positive (5)'));
  });

  group('labels', () {
    test('with extra', () => expect(labels(true), ['base', 'extra']));
    test('without extra', () => expect(labels(false), ['base', 'none']));
  });

  group('sumTo', () {
    test('sums 1..n', () => expect(sumTo(4), 10));
  });

  group('Counter', () {
    test('exposes its value and increments', () {
      final counter = Counter(1);
      expect(counter.value, 1);
      counter.increment();
      expect(counter.value, 2);
    });
  });
}
