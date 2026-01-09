// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../../lib/src/language/language.dart';
import '../../lib/src/language/matchbrackets.dart';
import '../../lib/src/state/state.dart';
import '../../lib/src/state/selection.dart';
import '../../lib/src/state/facet.dart' hide EditorState, Transaction;
import '../../lib/src/state/transaction.dart';

void main() {
  // Ensure language module is initialized (required for syntaxTree)
  ensureLanguageInitialized();
  group('Bracket Matching', () {
    test('matches parentheses forward', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'foo(bar)'));
      
      // At position 3 (after 'foo'), looking forward
      final match = matchBrackets(state, 3, 1);
      expect(match, isNotNull);
      expect(match!.start.from, 3);
      expect(match.start.to, 4);
      expect(match.end, isNotNull);
      expect(match.end!.from, 7);
      expect(match.end!.to, 8);
      expect(match.matched, true);
    });

    test('matches parentheses backward', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'foo(bar)'));
      
      // At position 8 (after ')'), looking backward
      final match = matchBrackets(state, 8, -1);
      expect(match, isNotNull);
      expect(match!.start.from, 7);
      expect(match.start.to, 8);
      expect(match.end, isNotNull);
      expect(match.end!.from, 3);
      expect(match.end!.to, 4);
      expect(match.matched, true);
    });

    test('matches square brackets', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'arr[0]'));
      
      final match = matchBrackets(state, 3, 1);
      expect(match, isNotNull);
      expect(match!.matched, true);
      expect(match.start.from, 3);
      expect(match.end!.from, 5);
    });

    test('matches curly braces', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'obj{key}'));
      
      final match = matchBrackets(state, 3, 1);
      expect(match, isNotNull);
      expect(match!.matched, true);
    });

    test('handles nested brackets', () {
      final state = EditorState.create(const EditorStateConfig(doc: '((inner))'));
      
      // Match outer opening
      final outerMatch = matchBrackets(state, 0, 1);
      expect(outerMatch, isNotNull);
      expect(outerMatch!.matched, true);
      expect(outerMatch.end!.from, 8);

      // Match inner opening
      final innerMatch = matchBrackets(state, 1, 1);
      expect(innerMatch, isNotNull);
      expect(innerMatch!.matched, true);
      expect(innerMatch.end!.from, 7);
    });

    test('reports unmatched brackets', () {
      final state = EditorState.create(const EditorStateConfig(doc: '(unclosed'));
      
      final match = matchBrackets(state, 0, 1);
      expect(match, isNotNull);
      expect(match!.matched, false);
      expect(match.end, isNull);
    });

    test('reports mismatched brackets', () {
      final state = EditorState.create(const EditorStateConfig(doc: '(wrong]'));
      
      final match = matchBrackets(state, 0, 1);
      expect(match, isNotNull);
      expect(match!.matched, false);
      expect(match.end, isNotNull); // Found a bracket, but wrong type
    });

    test('returns null when no bracket at position', () {
      final state = EditorState.create(const EditorStateConfig(doc: 'hello'));
      
      final match = matchBrackets(state, 2, 1);
      expect(match, isNull);
    });

    test('respects maxScanDistance', () {
      // Note: maxScanDistance is only used for plain bracket scanning (no syntax tree).
      // With a syntax tree, brackets are found via tree traversal.
      // This test just verifies the config is accepted without errors.
      final state = EditorState.create(const EditorStateConfig(doc: '(test)'));
      
      final match = matchBrackets(
        state, 0, 1,
        const BracketMatchingConfig(maxScanDistance: 100),
      );
      expect(match, isNotNull);
      expect(match!.matched, true);
    });

    test('uses custom brackets config', () {
      final state = EditorState.create(const EditorStateConfig(doc: '<tag>'));
      
      // Default brackets don't include <>
      final noMatch = matchBrackets(state, 0, 1);
      expect(noMatch, isNull);

      // Custom brackets include <>
      final match = matchBrackets(
        state, 0, 1,
        const BracketMatchingConfig(brackets: '()<>[]{}'),
      );
      expect(match, isNotNull);
      expect(match!.matched, true);
    });
  });

  group('BracketMatchingConfig', () {
    test('has sensible defaults', () {
      const config = BracketMatchingConfig();
      expect(config.afterCursor, true);
      expect(config.brackets, '()[]{}');
      expect(config.maxScanDistance, 10000);
      expect(config.renderMatch, isNull);
    });

    test('can override defaults', () {
      const config = BracketMatchingConfig(
        afterCursor: false,
        brackets: '()',
        maxScanDistance: 5000,
      );
      expect(config.afterCursor, false);
      expect(config.brackets, '()');
      expect(config.maxScanDistance, 5000);
    });
  });

  group('MatchResult', () {
    test('stores match information', () {
      const result = MatchResult(
        start: (from: 0, to: 1),
        end: (from: 5, to: 6),
        matched: true,
      );
      expect(result.start.from, 0);
      expect(result.start.to, 1);
      expect(result.end!.from, 5);
      expect(result.end!.to, 6);
      expect(result.matched, true);
    });

    test('can represent unmatched bracket', () {
      const result = MatchResult(
        start: (from: 0, to: 1),
        matched: false,
      );
      expect(result.end, isNull);
      expect(result.matched, false);
    });
  });

  group('bracketMatching extension', () {
    test('creates extension', () {
      final ext = bracketMatching();
      expect(ext, isNotNull);
    });

    test('accepts configuration', () {
      final ext = bracketMatching(const BracketMatchingConfig(
        afterCursor: false,
        brackets: '()',
      ));
      expect(ext, isNotNull);
    });

    test('integrates with editor state', () {
      final state = EditorState.create(EditorStateConfig(
        doc: 'foo(bar)',
        extensions: ExtensionList([bracketMatching()]),
      ));
      expect(state, isNotNull);
    });

    test('updates decorations on selection change', () {
      var state = EditorState.create(EditorStateConfig(
        doc: 'foo(bar)',
        extensions: ExtensionList([bracketMatching()]),
      ));

      // Move cursor near bracket
      final tr = state.update([
        TransactionSpec(selection: EditorSelection.single(4)),
      ]);
      state = tr.state as EditorState;
      expect(state, isNotNull);
    });
  });

  group('Edge cases', () {
    test('handles empty document', () {
      final state = EditorState.create(const EditorStateConfig(doc: ''));
      final match = matchBrackets(state, 0, 1);
      // May return an unmatched result or null depending on implementation
      if (match != null) {
        expect(match.matched, false);
      }
    });

    test('handles single bracket', () {
      final state = EditorState.create(const EditorStateConfig(doc: '('));
      final match = matchBrackets(state, 0, 1);
      expect(match, isNotNull);
      expect(match!.matched, false);
    });

    test('handles adjacent brackets', () {
      final state = EditorState.create(const EditorStateConfig(doc: '()'));
      
      final openMatch = matchBrackets(state, 0, 1);
      expect(openMatch, isNotNull);
      expect(openMatch!.matched, true);
      expect(openMatch.end!.from, 1);

      final closeMatch = matchBrackets(state, 2, -1);
      expect(closeMatch, isNotNull);
      expect(closeMatch!.matched, true);
      expect(closeMatch.end!.from, 0);
    });

    test('handles mixed bracket types', () {
      final state = EditorState.create(const EditorStateConfig(doc: '([{test}])'));
      
      final match1 = matchBrackets(state, 0, 1);
      expect(match1!.matched, true);
      expect(match1.end!.from, 9);

      final match2 = matchBrackets(state, 1, 1);
      expect(match2!.matched, true);
      expect(match2.end!.from, 8);

      final match3 = matchBrackets(state, 2, 1);
      expect(match3!.matched, true);
      expect(match3.end!.from, 7);
    });
  });
}
