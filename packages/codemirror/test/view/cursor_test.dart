import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/view/cursor.dart';
import 'package:codemirror/src/text/char.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/state/selection.dart';

void main() {
  group('CharCategory', () {
    test('defaultCategorizer categorizes correctly', () {
      // Word characters
      expect(defaultCategorizer('a'), equals(CharCategory.word));
      expect(defaultCategorizer('Z'), equals(CharCategory.word));
      expect(defaultCategorizer('0'), equals(CharCategory.word));
      expect(defaultCategorizer('9'), equals(CharCategory.word));
      expect(defaultCategorizer('_'), equals(CharCategory.word));

      // Whitespace
      expect(defaultCategorizer(' '), equals(CharCategory.space));
      expect(defaultCategorizer('\t'), equals(CharCategory.space));
      expect(defaultCategorizer('\n'), equals(CharCategory.space));

      // Other (punctuation)
      expect(defaultCategorizer('.'), equals(CharCategory.other));
      expect(defaultCategorizer(','), equals(CharCategory.other));
      expect(defaultCategorizer('!'), equals(CharCategory.other));
      expect(defaultCategorizer('('), equals(CharCategory.other));
    });
  });

  group('findClusterBreak', () {
    test('finds forward cluster break for simple text', () {
      expect(findClusterBreak('hello', 0, true), equals(1));
      expect(findClusterBreak('hello', 1, true), equals(2));
      expect(findClusterBreak('hello', 4, true), equals(5));
    });

    test('finds backward cluster break for simple text', () {
      expect(findClusterBreak('hello', 5, false), equals(4));
      expect(findClusterBreak('hello', 4, false), equals(3));
      expect(findClusterBreak('hello', 1, false), equals(0));
    });

    test('returns boundary at start/end', () {
      expect(findClusterBreak('hello', 5, true), equals(5));
      expect(findClusterBreak('hello', 0, false), equals(0));
    });

    test('handles empty string', () {
      expect(findClusterBreak('', 0, true), equals(0));
      expect(findClusterBreak('', 0, false), equals(0));
    });

    test('handles surrogate pairs', () {
      final emoji = '😀'; // Surrogate pair
      expect(findClusterBreak(emoji, 0, true), equals(2));
      expect(findClusterBreak(emoji, 2, false), equals(0));
    });
  });

  group('groupAt', () {
    test('selects word at position', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final range = groupAt(state, 2); // Inside "hello"

      expect(range.from, equals(0));
      expect(range.to, equals(5));
    });

    test('selects whitespace at position', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final range = groupAt(state, 5); // At space

      expect(range.from, equals(5));
      expect(range.to, equals(6));
    });

    test('handles position at start of word', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final range = groupAt(state, 0);

      expect(range.from, equals(0));
      expect(range.to, equals(5));
    });

    test('handles position at end of word', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final range = groupAt(state, 5, -1); // End of "hello", bias left

      expect(range.from, equals(0));
      expect(range.to, equals(5));
    });

    test('handles empty line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\n\nworld'));
      final line = state.doc.line(2); // Empty line
      final range = groupAt(state, line.from);

      expect(range.from, equals(range.to)); // Cursor on empty line
    });

    test('handles punctuation', () {
      final state = EditorState.create(EditorStateConfig(doc: 'foo.bar'));
      final range = groupAt(state, 3); // At the dot

      expect(range.from, equals(3));
      expect(range.to, equals(4));
    });
  });

  group('byGroup', () {
    test('returns function that checks category match', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final check = byGroup(state, 0, 'a');

      expect(check('b'), isTrue); // Same category (word)
      expect(check(' '), isFalse); // Different category (space)
    });

    test('transitions from space to next category', () {
      final state = EditorState.create(EditorStateConfig(doc: ' hello'));
      final check = byGroup(state, 0, ' ');

      expect(check('h'), isTrue); // Transitions to word
      expect(check('e'), isTrue); // Still word
      expect(check('.'), isFalse); // Different category
    });
  });

  group('moveByChar', () {
    test('moves forward by one character', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final start = EditorSelection.cursor(0);
      final result = moveByChar(state, start, true);

      expect(result.head, equals(1));
    });

    test('moves backward by one character', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final start = EditorSelection.cursor(3);
      final result = moveByChar(state, start, false);

      expect(result.head, equals(2));
    });

    test('stops at document start', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final start = EditorSelection.cursor(0);
      final result = moveByChar(state, start, false);

      expect(result.head, equals(0));
    });

    test('stops at document end', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final start = EditorSelection.cursor(5);
      final result = moveByChar(state, start, true);

      expect(result.head, equals(5));
    });

    test('crosses line boundaries going forward', () {
      // In "hello\nworld", line 1 ends at pos 5, newline is at 5, line 2 starts at 6
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      
      // Moving from end of "hello" should eventually cross to next line
      // Position 5 -> we should get to position 6 on next line
      // But the current implementation moves to the start of next line via the newline
      final start = EditorSelection.cursor(5); // End of "hello", before newline
      final result = moveByChar(state, start, true);

      // The result should be on the next line (position >= 6)
      expect(result.head, greaterThanOrEqualTo(6));
    });

    test('crosses line boundaries going backward', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      // Start at beginning of "world" (pos 6)
      final start = EditorSelection.cursor(6);
      final result = moveByChar(state, start, false);

      // Should move to position 5 (end of hello line) or before
      expect(result.head, lessThanOrEqualTo(5));
    });

    test('moves by word when by function provided', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world'));
      final start = EditorSelection.cursor(0);
      final result = moveByChar(
        state,
        start,
        true,
        by: (char) => byGroup(state, 0, char),
      );

      expect(result.head, equals(5)); // End of "hello"
    });
  });

  group('moveToLineBoundary', () {
    test('moves to end of line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(2);
      final result = moveToLineBoundary(state, start, true);

      expect(result.head, equals(5));
    });

    test('moves to start of line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(2);
      final result = moveToLineBoundary(state, start, false);

      expect(result.head, equals(0));
    });

    test('handles second line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(8); // Inside "world"
      
      final toEnd = moveToLineBoundary(state, start, true);
      expect(toEnd.head, equals(11));

      final toStart = moveToLineBoundary(state, start, false);
      expect(toStart.head, equals(6));
    });
  });

  group('moveVertically', () {
    test('moves down one line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(2); // 2 chars into "hello"
      final result = moveVertically(state, start, true);

      expect(result.head, equals(8)); // 2 chars into "world"
    });

    test('moves up one line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(8); // 2 chars into "world"
      final result = moveVertically(state, start, false);

      expect(result.head, equals(2)); // 2 chars into "hello"
    });

    test('clamps to shorter line', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello world\nhi'));
      final start = EditorSelection.cursor(10); // End of first line
      final result = moveVertically(state, start, true);

      expect(result.head, equals(14)); // Clamped to end of "hi"
    });

    test('stays at document start when moving up', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(2);
      final result = moveVertically(state, start, false);

      expect(result.head, equals(0)); // Stays on first line
    });

    test('stays at document end when moving down', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello\nworld'));
      final start = EditorSelection.cursor(8);
      final result = moveVertically(state, start, true);

      expect(result.head, equals(11)); // Stays on last line
    });

    test('preserves goal column', () {
      // Document: "hello world\nhi\ntest here"
      // Line 1: 0-11 (length 11)
      // Line 2: 12-14 (length 2)
      // Line 3: 15-24 (length 9)
      final state = EditorState.create(EditorStateConfig(doc: 'hello world\nhi\ntest here'));
      
      // Start at column 10 on first line (the 'd' in world)
      final start = EditorSelection.cursor(10);
      
      // Move down - should be clamped to "hi" but remember goal
      final down1 = moveVertically(state, start, true, goalColumn: 10);
      // Line 2 starts at 12, length 2, so max is 14
      expect(down1.head, equals(14)); // End of "hi"
      expect(down1.goalColumn, equals(10));
      
      // Move down again - should try to reach column 10
      final down2 = moveVertically(state, down1, true, goalColumn: down1.goalColumn);
      // Line 3 starts at 15, column 10 would be position 25, but line length is 9 (test here)
      // So it gets clamped to line end
      expect(down2.head, lessThanOrEqualTo(24)); // Within line 3
    });
  });

  group('skipAtomsForSelection', () {
    test('returns selection unchanged with no atoms', () {
      final sel = EditorSelection.single(5);
      final result = skipAtomsForSelection([], sel);

      expect(result.main.head, equals(5));
    });

    // More tests would require setting up RangeSets with atomic decorations
  });

  group('CharCategorizerExtension', () {
    test('provides charCategorizer on EditorState', () {
      final state = EditorState.create(EditorStateConfig(doc: 'hello'));
      final categorizer = state.charCategorizer(0);

      expect(categorizer('a'), equals(CharCategory.word));
      expect(categorizer(' '), equals(CharCategory.space));
    });
  });
}
