import 'package:test/test.dart';
import 'package:codemirror/src/view/attributes.dart';

void main() {
  group('Attrs typedef and helpers', () {
    group('combineAttrs', () {
      test('copies simple attributes', () {
        final target = <String, String>{'id': 'foo'};
        combineAttrs({'data-x': '1'}, target);
        expect(target, {'id': 'foo', 'data-x': '1'});
      });

      test('merges class attributes with space', () {
        final target = <String, String>{'class': 'foo'};
        combineAttrs({'class': 'bar'}, target);
        expect(target['class'], 'foo bar');
      });

      test('merges style attributes with semicolon', () {
        final target = <String, String>{'style': 'color: red'};
        combineAttrs({'style': 'font-size: 14px'}, target);
        expect(target['style'], 'color: red;font-size: 14px');
      });

      test('overrides other attributes', () {
        final target = <String, String>{'id': 'old', 'class': 'foo'};
        combineAttrs({'id': 'new', 'class': 'bar'}, target);
        expect(target['id'], 'new');
        expect(target['class'], 'foo bar');
      });

      test('handles empty source', () {
        final target = <String, String>{'id': 'foo'};
        combineAttrs(<String, String>{}, target);
        expect(target, {'id': 'foo'});
      });

      test('handles empty target', () {
        final target = <String, String>{};
        combineAttrs({'id': 'foo', 'class': 'bar'}, target);
        expect(target, {'id': 'foo', 'class': 'bar'});
      });

      test('returns modified target', () {
        final target = <String, String>{'id': 'foo'};
        final result = combineAttrs({'data-x': '1'}, target);
        expect(identical(result, target), isTrue);
      });
    });

    group('attrsEq', () {
      test('equal maps are equal', () {
        expect(attrsEq({'a': '1', 'b': '2'}, {'a': '1', 'b': '2'}), isTrue);
      });

      test('different values are not equal', () {
        expect(attrsEq({'a': '1'}, {'a': '2'}), isFalse);
      });

      test('different keys are not equal', () {
        expect(attrsEq({'a': '1'}, {'b': '1'}), isFalse);
      });

      test('different lengths are not equal', () {
        expect(attrsEq({'a': '1', 'b': '2'}, {'a': '1'}), isFalse);
      });

      test('null maps are equal', () {
        expect(attrsEq(null, null), isTrue);
      });

      test('null and empty are equal', () {
        expect(attrsEq(null, {}), isTrue);
        expect(attrsEq({}, null), isTrue);
      });

      test('identical maps are equal', () {
        final map = {'a': '1'};
        expect(attrsEq(map, map), isTrue);
      });

      test('ignores specified key', () {
        expect(
          attrsEq({'a': '1', 'class': 'foo'}, {'a': '1', 'class': 'bar'}, 'class'),
          isTrue,
        );
      });

      test('still compares non-ignored keys', () {
        expect(
          attrsEq({'a': '1', 'class': 'foo'}, {'a': '2', 'class': 'bar'}, 'class'),
          isFalse,
        );
      });

      test('handles ignore key not present', () {
        expect(attrsEq({'a': '1'}, {'a': '1'}, 'class'), isTrue);
        expect(attrsEq({'a': '1'}, {'a': '1', 'class': 'x'}, 'class'), isTrue);
      });
    });

    group('parseClasses', () {
      test('parses space-separated classes', () {
        expect(parseClasses('foo bar baz'), {'foo', 'bar', 'baz'});
      });

      test('handles multiple spaces', () {
        expect(parseClasses('foo   bar'), {'foo', 'bar'});
      });

      test('handles leading/trailing spaces', () {
        expect(parseClasses('  foo bar  '), {'foo', 'bar'});
      });

      test('handles empty string', () {
        expect(parseClasses(''), isEmpty);
      });

      test('handles single class', () {
        expect(parseClasses('foo'), {'foo'});
      });
    });

    group('joinClasses', () {
      test('joins classes with space', () {
        final result = joinClasses({'foo', 'bar', 'baz'});
        expect(result.split(' ').toSet(), {'foo', 'bar', 'baz'});
      });

      test('handles empty set', () {
        expect(joinClasses({}), '');
      });

      test('handles single class', () {
        expect(joinClasses({'foo'}), 'foo');
      });
    });

    group('mergeClasses', () {
      test('merges two class strings', () {
        final result = mergeClasses('foo bar', 'baz qux');
        final classes = result.split(' ').toSet();
        expect(classes, containsAll(['foo', 'bar', 'baz', 'qux']));
      });

      test('deduplicates classes', () {
        final result = mergeClasses('foo bar', 'bar baz');
        final classes = result.split(' ').toSet();
        expect(classes.length, 3);
        expect(classes, containsAll(['foo', 'bar', 'baz']));
      });

      test('handles empty strings', () {
        expect(mergeClasses('foo', '').split(' ').toSet(), {'foo'});
        expect(mergeClasses('', 'foo').split(' ').toSet(), {'foo'});
      });
    });

    group('hasClass', () {
      test('returns true when class is present', () {
        expect(hasClass('foo bar baz', 'bar'), isTrue);
      });

      test('returns false when class is absent', () {
        expect(hasClass('foo bar baz', 'qux'), isFalse);
      });

      test('does not match partial class names', () {
        expect(hasClass('foobar', 'foo'), isFalse);
      });
    });

    group('addClass', () {
      test('adds class when not present', () {
        final result = addClass('foo bar', 'baz');
        expect(hasClass(result, 'baz'), isTrue);
      });

      test('does not duplicate existing class', () {
        final result = addClass('foo bar', 'foo');
        final count = result.split(' ').where((c) => c == 'foo').length;
        expect(count, 1);
      });

      test('handles empty string', () {
        expect(addClass('', 'foo'), 'foo');
      });
    });

    group('removeClass', () {
      test('removes class when present', () {
        final result = removeClass('foo bar baz', 'bar');
        expect(hasClass(result, 'bar'), isFalse);
        expect(hasClass(result, 'foo'), isTrue);
        expect(hasClass(result, 'baz'), isTrue);
      });

      test('handles class not present', () {
        final result = removeClass('foo bar', 'baz');
        expect(hasClass(result, 'foo'), isTrue);
        expect(hasClass(result, 'bar'), isTrue);
      });

      test('handles removing only class', () {
        expect(removeClass('foo', 'foo'), '');
      });
    });

    group('toggleClass', () {
      test('adds class when not present', () {
        final result = toggleClass('foo', 'bar');
        expect(hasClass(result, 'foo'), isTrue);
        expect(hasClass(result, 'bar'), isTrue);
      });

      test('removes class when present', () {
        final result = toggleClass('foo bar', 'bar');
        expect(hasClass(result, 'foo'), isTrue);
        expect(hasClass(result, 'bar'), isFalse);
      });
    });
  });
}
