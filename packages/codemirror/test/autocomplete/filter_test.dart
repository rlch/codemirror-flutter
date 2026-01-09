import 'package:codemirror/src/autocomplete/filter.dart';
import 'package:test/test.dart';

void main() {
  group('Penalty constants', () {
    test('has correct values', () {
      expect(Penalty.gap, -1100);
      expect(Penalty.notStart, -700);
      expect(Penalty.caseFold, -200);
      expect(Penalty.byWord, -100);
      expect(Penalty.notFull, -100);
    });
  });

  group('FuzzyMatcher', () {
    group('empty pattern', () {
      test('returns NotFull penalty with empty matched', () {
        final matcher = FuzzyMatcher('');
        final result = matcher.match('anything');

        expect(result, isNotNull);
        expect(result!.score, Penalty.notFull);
        expect(result.matched, isEmpty);
        expect(matcher.score, Penalty.notFull);
        expect(matcher.matched, isEmpty);
      });
    });

    group('single character match', () {
      test('at start of word', () {
        final matcher = FuzzyMatcher('a');
        final result = matcher.match('apple');

        expect(result, isNotNull);
        expect(result!.score, Penalty.notFull);
        expect(result.matched, [0, 1]);
      });

      test('with case fold', () {
        final matcher = FuzzyMatcher('A');
        final result = matcher.match('apple');

        expect(result, isNotNull);
        expect(result!.score, Penalty.notFull + Penalty.caseFold);
        expect(result.matched, [0, 1]);
      });

      test('full exact match single char', () {
        final matcher = FuzzyMatcher('a');
        final result = matcher.match('a');

        expect(result, isNotNull);
        expect(result!.score, 0);
        expect(result.matched, [0, 1]);
      });

      test('no match when character not found', () {
        final matcher = FuzzyMatcher('z');
        final result = matcher.match('apple');

        expect(result, isNull);
      });
    });

    group('exact prefix match', () {
      test('returns NotFull penalty when not full word', () {
        final matcher = FuzzyMatcher('get');
        final result = matcher.match('getUserProfile');

        expect(result, isNotNull);
        expect(result!.score, Penalty.notFull);
        expect(result.matched, [0, 3]);
      });

      test('full exact match returns score 0', () {
        final matcher = FuzzyMatcher('hello');
        final result = matcher.match('hello');

        expect(result, isNotNull);
        expect(result!.score, 0);
        expect(result.matched, [0, 5]);
      });
    });

    group('case-insensitive matching', () {
      test('matches lowercase pattern to uppercase word', () {
        final matcher = FuzzyMatcher('hello');
        final result = matcher.match('HELLO');

        expect(result, isNotNull);
        expect(result!.score, lessThan(0));
      });

      test('matches uppercase pattern to lowercase word', () {
        final matcher = FuzzyMatcher('HELLO');
        final result = matcher.match('hello');

        expect(result, isNotNull);
      });
    });

    group('camel case matching', () {
      test('matches initials of camel case', () {
        final matcher = FuzzyMatcher('gup');
        final result = matcher.match('getUserProfile');

        expect(result, isNotNull);
        expect(result!.matched.length, greaterThanOrEqualTo(2));
      });

      test('matches with case fold', () {
        final matcher = FuzzyMatcher('gp');
        final result = matcher.match('getUserProfile');

        expect(result, isNotNull);
      });

      test('matches adjacent camel case initials', () {
        final matcher = FuzzyMatcher('uc');
        final result = matcher.match('UserController');

        expect(result, isNotNull);
      });
    });

    group('snake case matching', () {
      test('matches initials of snake case', () {
        final matcher = FuzzyMatcher('gup');
        final result = matcher.match('get_user_profile');

        expect(result, isNotNull);
      });

      test('matches word boundaries after underscore', () {
        final matcher = FuzzyMatcher('up');
        final result = matcher.match('user_profile');

        expect(result, isNotNull);
      });
    });

    group('by-word matching scoring', () {
      test('applies byWord penalty', () {
        final matcher = FuzzyMatcher('gup');
        final result = matcher.match('getUserProfile');

        expect(result, isNotNull);
        expect(result!.score, lessThan(0));
      });

      test('byWord at start scores better than not at start', () {
        final matcherStart = FuzzyMatcher('gup');
        final resultStart = matcherStart.match('getUserProfile');

        final matcherNotStart = FuzzyMatcher('upr');
        final resultNotStart = matcherNotStart.match('getUserProfile');

        expect(resultStart, isNotNull);
        expect(resultNotStart, isNotNull);
        expect(resultStart!.score, greaterThan(resultNotStart!.score));
      });
    });

    group('gap penalty', () {
      test('applied when matching non-adjacent characters', () {
        final matcher = FuzzyMatcher('ace');
        final result = matcher.match('abcdef');

        expect(result, isNotNull);
        expect(result!.score, lessThan(Penalty.byWord));
      });

      test('adjacent chars score better than non-adjacent', () {
        final matcherAdjacent = FuzzyMatcher('abc');
        final resultAdjacent = matcherAdjacent.match('abcdef');

        final matcherGap = FuzzyMatcher('adf');
        final resultGap = matcherGap.match('abcdef');

        expect(resultAdjacent, isNotNull);
        expect(resultGap, isNotNull);
        expect(resultAdjacent!.score, greaterThan(resultGap!.score));
      });
    });

    group('notStart penalty', () {
      test('applied when match does not start at beginning', () {
        final matcher = FuzzyMatcher('user');
        final result = matcher.match('getUser');

        expect(result, isNotNull);
        expect(result!.score, lessThan(Penalty.notFull));
        expect(result.matched[0], 3);
      });

      test('no notStart penalty when match at position 0', () {
        final matcher = FuzzyMatcher('get');
        final result = matcher.match('getUser');

        expect(result, isNotNull);
        expect(result!.matched[0], 0);
      });
    });

    group('astral character handling', () {
      test('handles emoji in pattern', () {
        final matcher = FuzzyMatcher('🔥');
        expect(matcher.astral, true);
        expect(matcher.chars.length, 1);

        final result = matcher.match('🔥fire');
        expect(result, isNotNull);
        expect(result!.matched, [0, 2]);
      });

      test('handles emoji in word', () {
        final matcher = FuzzyMatcher('fire');
        final result = matcher.match('🔥fire');

        expect(result, isNotNull);
        expect(result!.matched[0], 2);
      });

      test('matches multi-codepoint emoji', () {
        final matcher = FuzzyMatcher('ab');
        final result = matcher.match('a🔥b');

        expect(result, isNotNull);
      });

      test('handles surrogate pairs correctly', () {
        final matcher = FuzzyMatcher('𝐀');
        expect(matcher.astral, true);
        expect(matcher.chars.length, 1);
      });
    });

    group('no match scenarios', () {
      test('when pattern longer than word', () {
        final matcher = FuzzyMatcher('longpattern');
        final result = matcher.match('short');

        expect(result, isNull);
      });

      test('when characters not found', () {
        final matcher = FuzzyMatcher('xyz');
        final result = matcher.match('abc');

        expect(result, isNull);
      });

      test('when two char pattern not found', () {
        final matcher = FuzzyMatcher('zz');
        final result = matcher.match('abcdef');

        expect(result, isNull);
      });

      test('when partial chars found but not all', () {
        final matcher = FuzzyMatcher('abz');
        final result = matcher.match('abcdef');

        expect(result, isNull);
      });
    });

    group('matched positions', () {
      test('returns correct positions for prefix', () {
        final matcher = FuzzyMatcher('abc');
        final result = matcher.match('abcdef');

        expect(result, isNotNull);
        expect(result!.matched, [0, 3]);
      });

      test('returns multiple ranges for non-adjacent matches', () {
        final matcher = FuzzyMatcher('adf');
        final result = matcher.match('abcdef');

        expect(result, isNotNull);
        expect(result!.matched.length, greaterThanOrEqualTo(4));
      });
    });
  });

  group('StrictMatcher', () {
    group('exact prefix match', () {
      test('returns NotFull when not full word', () {
        final matcher = StrictMatcher('get');
        final result = matcher.match('getUser');

        expect(result, isNotNull);
        expect(result!.score, Penalty.notFull);
        expect(result.matched, [0, 3]);
        expect(matcher.score, Penalty.notFull);
        expect(matcher.matched, [0, 3]);
      });

      test('full word exact match returns score 0', () {
        final matcher = StrictMatcher('hello');
        final result = matcher.match('hello');

        expect(result, isNotNull);
        expect(result!.score, 0);
        expect(result.matched, [0, 5]);
      });
    });

    group('case-insensitive prefix match', () {
      test('applies caseFold penalty', () {
        final matcher = StrictMatcher('GET');
        final result = matcher.match('getUser');

        expect(result, isNotNull);
        expect(result!.score, Penalty.caseFold + Penalty.notFull);
        expect(result.matched, [0, 3]);
      });

      test('full word case insensitive', () {
        final matcher = StrictMatcher('HELLO');
        final result = matcher.match('hello');

        expect(result, isNotNull);
        expect(result!.score, Penalty.caseFold);
        expect(result.matched, [0, 5]);
      });
    });

    group('no match scenarios', () {
      test('when word shorter than pattern', () {
        final matcher = StrictMatcher('longpattern');
        final result = matcher.match('short');

        expect(result, isNull);
      });

      test('when prefix does not match', () {
        final matcher = StrictMatcher('abc');
        final result = matcher.match('xyz');

        expect(result, isNull);
      });

      test('when prefix partially matches', () {
        final matcher = StrictMatcher('abz');
        final result = matcher.match('abcdef');

        expect(result, isNull);
      });

      test('when match is not at start', () {
        final matcher = StrictMatcher('User');
        final result = matcher.match('getUser');

        expect(result, isNull);
      });
    });

    group('folded pattern', () {
      test('stores lowercase pattern', () {
        final matcher = StrictMatcher('GetUser');
        expect(matcher.folded, 'getuser');
      });
    });
  });

  group('FuzzyMatcher vs StrictMatcher', () {
    test('FuzzyMatcher finds non-prefix matches', () {
      final fuzzy = FuzzyMatcher('user');
      final strict = StrictMatcher('user');

      final word = 'getUser';
      expect(fuzzy.match(word), isNotNull);
      expect(strict.match(word), isNull);
    });

    test('both find prefix matches', () {
      final fuzzy = FuzzyMatcher('get');
      final strict = StrictMatcher('get');

      final word = 'getUser';
      expect(fuzzy.match(word), isNotNull);
      expect(strict.match(word), isNotNull);
    });
  });
}
