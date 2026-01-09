import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:codemirror/src/lsp/semantic_tokens.dart';
import 'package:codemirror/src/state/state.dart';
import 'package:codemirror/src/text/text.dart';

void main() {
  group('Semantic Tokens', () {
    group('decodeSemanticTokens', () {
      test('decodes simple tokens correctly', () {
        final legend = SemanticTokensLegend(
          tokenTypes: ['function', 'variable', 'keyword'],
          tokenModifiers: ['declaration', 'readonly'],
        );

        // JavaScript: "const foo = bar()"
        //             ^^^^^     keyword (index 2)
        //                   ^^^  variable (index 1)
        //                       ^^^  function (index 0)
        final doc = Text.of(['const foo = bar()']);

        // LSP format: [deltaLine, deltaStart, length, tokenType, tokenModifiers]
        final data = [
          0, 0, 5, 2, 0, // "const" - keyword at col 0
          0, 6, 3, 1, 1, // "foo" - variable at col 6, declaration modifier (bit 0)
          0, 6, 3, 0, 0, // "bar" - function at col 12
        ];

        final tokens = decodeSemanticTokens(data, legend, doc);

        expect(tokens.length, 3);

        // "const"
        expect(tokens[0].from, 0);
        expect(tokens[0].to, 5);
        expect(tokens[0].type, 'keyword');
        expect(tokens[0].modifiers, isEmpty);

        // "foo"
        expect(tokens[1].from, 6);
        expect(tokens[1].to, 9);
        expect(tokens[1].type, 'variable');
        expect(tokens[1].modifiers, ['declaration']);

        // "bar"
        expect(tokens[2].from, 12);
        expect(tokens[2].to, 15);
        expect(tokens[2].type, 'function');
        expect(tokens[2].modifiers, isEmpty);
      });

      test('handles multi-line documents', () {
        final legend = SemanticTokensLegend(
          tokenTypes: ['function', 'variable', 'keyword', 'string'],
          tokenModifiers: [],
        );

        // JavaScript:
        // function greet(name) {
        //   return "Hello, " + name;
        // }
        final doc = Text.of([
          'function greet(name) {',
          '  return "Hello, " + name;',
          '}',
        ]);

        final data = [
          0, 0, 8, 2, 0, // "function" - keyword, line 0, col 0
          0, 9, 5, 0, 0, // "greet" - function, line 0, col 9
          0, 6, 4, 1, 0, // "name" - variable, line 0, col 15
          1, 2, 6, 2, 0, // "return" - keyword, line 1, col 2
          0, 7, 9, 3, 0, // "\"Hello, \"" - string, line 1, col 9
          0, 12, 4, 1, 0, // "name" - variable, line 1, col 21
        ];

        final tokens = decodeSemanticTokens(data, legend, doc);

        expect(tokens.length, 6);

        // Line 0: "function"
        expect(tokens[0].type, 'keyword');
        expect(doc.sliceString(tokens[0].from, tokens[0].to), 'function');

        // Line 0: "greet"
        expect(tokens[1].type, 'function');
        expect(doc.sliceString(tokens[1].from, tokens[1].to), 'greet');

        // Line 0: "name" (parameter)
        expect(tokens[2].type, 'variable');
        expect(doc.sliceString(tokens[2].from, tokens[2].to), 'name');

        // Line 1: "return"
        expect(tokens[3].type, 'keyword');
        expect(doc.sliceString(tokens[3].from, tokens[3].to), 'return');

        // Line 1: string
        expect(tokens[4].type, 'string');
        expect(doc.sliceString(tokens[4].from, tokens[4].to), '"Hello, "');

        // Line 1: "name" (usage)
        expect(tokens[5].type, 'variable');
        expect(doc.sliceString(tokens[5].from, tokens[5].to), 'name');
      });

      test('handles multiple modifiers with bit flags', () {
        final legend = SemanticTokensLegend(
          tokenTypes: ['variable'],
          tokenModifiers: ['declaration', 'readonly', 'static'],
        );

        final doc = Text.of(['CONST_VALUE']);

        // Modifiers: declaration (bit 0) + readonly (bit 1) + static (bit 2) = 0b111 = 7
        final data = [0, 0, 11, 0, 7];

        final tokens = decodeSemanticTokens(data, legend, doc);

        expect(tokens.length, 1);
        expect(tokens[0].type, 'variable');
        expect(tokens[0].modifiers, containsAll(['declaration', 'readonly', 'static']));
      });

      test('handles unknown token type gracefully', () {
        final legend = SemanticTokensLegend(
          tokenTypes: ['function'],
          tokenModifiers: [],
        );

        final doc = Text.of(['unknown']);

        // Token type index 99 is out of bounds
        final data = [0, 0, 7, 99, 0];

        final tokens = decodeSemanticTokens(data, legend, doc);

        expect(tokens.length, 1);
        expect(tokens[0].type, 'unknown');
      });
    });

    group('tokensToDecorations', () {
      test('creates decorations with correct classes', () {
        final tokens = [
          SemanticToken(from: 0, to: 5, type: 'keyword', modifiers: []),
          SemanticToken(from: 6, to: 9, type: 'variable', modifiers: ['declaration']),
        ];

        final theme = SemanticTokensTheme(classPrefix: 'tok-');
        final decorations = tokensToDecorations(tokens, theme: theme);

        expect(decorations.isEmpty, false);
      });

      test('returns empty set for empty tokens', () {
        final decorations = tokensToDecorations([]);
        expect(decorations.isEmpty, true);
      });
    });

    group('SemanticTokensTheme', () {
      test('generates correct class names', () {
        final theme = SemanticTokensTheme(
          classPrefix: 'cm-',
          includeModifiers: true,
        );

        final token = SemanticToken(
          from: 0,
          to: 5,
          type: 'function',
          modifiers: ['async', 'declaration'],
        );

        final className = theme.getClass(token);
        expect(className, contains('cm-function'));
        expect(className, contains('cm-async'));
        expect(className, contains('cm-declaration'));
      });

      test('uses custom type classes when provided', () {
        final theme = SemanticTokensTheme(
          classPrefix: 'tok-',
          typeClasses: {'function': 'my-func-class'},
        );

        final token = SemanticToken(from: 0, to: 5, type: 'function', modifiers: []);
        final className = theme.getClass(token);
        expect(className, 'my-func-class');
      });

      test('excludes modifiers when disabled', () {
        final theme = SemanticTokensTheme(
          classPrefix: 'tok-',
          includeModifiers: false,
        );

        final token = SemanticToken(
          from: 0,
          to: 5,
          type: 'variable',
          modifiers: ['readonly', 'declaration'],
        );

        final className = theme.getClass(token);
        expect(className, 'tok-variable');
        expect(className, isNot(contains('readonly')));
      });
    });

    group('applySemanticTokensEdits', () {
      test('applies insert edit', () {
        final data = [0, 0, 5, 0, 0, 0, 6, 3, 1, 0];
        final edits = [
          SemanticTokensEdit(start: 5, deleteCount: 0, data: [0, 10, 4, 2, 0]),
        ];

        final result = applySemanticTokensEdits(data, edits);

        expect(result.length, 15);
        expect(result.sublist(5, 10), [0, 10, 4, 2, 0]);
      });

      test('applies delete edit', () {
        final data = [0, 0, 5, 0, 0, 0, 6, 3, 1, 0, 0, 10, 4, 2, 0];
        final edits = [
          SemanticTokensEdit(start: 5, deleteCount: 5, data: null),
        ];

        final result = applySemanticTokensEdits(data, edits);

        expect(result.length, 10);
        expect(result, [0, 0, 5, 0, 0, 0, 10, 4, 2, 0]);
      });

      test('applies replace edit', () {
        final data = [0, 0, 5, 0, 0, 0, 6, 3, 1, 0];
        final edits = [
          SemanticTokensEdit(start: 5, deleteCount: 5, data: [0, 7, 4, 2, 1]),
        ];

        final result = applySemanticTokensEdits(data, edits);

        expect(result.length, 10);
        expect(result.sublist(5), [0, 7, 4, 2, 1]);
      });

      test('applies multiple edits correctly', () {
        final data = [0, 0, 5, 0, 0, 0, 6, 3, 1, 0, 0, 10, 4, 2, 0];
        final edits = [
          SemanticTokensEdit(start: 0, deleteCount: 5, data: [0, 0, 6, 0, 0]),
          SemanticTokensEdit(start: 10, deleteCount: 5, data: [0, 11, 5, 2, 0]),
        ];

        final result = applySemanticTokensEdits(data, edits);

        expect(result.length, 15);
        expect(result.sublist(0, 5), [0, 0, 6, 0, 0]);
        expect(result.sublist(10, 15), [0, 11, 5, 2, 0]);
      });
    });

    group('SemanticTokensState', () {
      test('state field stores tokens correctly', () {
        final state = EditorState.create(EditorStateConfig(
          doc: 'const x = 1',
          extensions: semanticTokensField,
        ));

        final tokenState = state.field(semanticTokensField);
        expect(tokenState, isNotNull);
        expect(tokenState!.tokens, isEmpty);
        expect(tokenState.decorations.isEmpty, true);
      });
    });

    group('generateSemanticTokensCss', () {
      test('generates light theme CSS', () {
        final css = generateSemanticTokensCss(prefix: 'cm-semantic-', dark: false);

        expect(css, contains('.cm-semantic-keyword'));
        expect(css, contains('.cm-semantic-function'));
        expect(css, contains('.cm-semantic-variable'));
        expect(css, contains('.cm-semantic-comment'));
        expect(css, contains('font-style: italic'));
      });

      test('generates dark theme CSS', () {
        final css = generateSemanticTokensCss(prefix: 'tok-', dark: true);

        expect(css, contains('.tok-keyword'));
        expect(css, contains('#569cd6')); // Dark theme keyword color
      });
    });
  });

  group('Mock LSP Client Integration', () {
    test('MockSemanticTokensClient returns valid tokens', () async {
      final client = MockSemanticTokensClient(
        documentContent: 'function hello() { return 42; }',
      );

      final result = await client.requestSemanticTokensFull(client.documentUri);

      expect(result, isNotNull);
      expect(result!.data, isNotEmpty);

      final tokens = decodeSemanticTokens(
        result.data,
        client.legend,
        Text.of([client.documentContent]),
      );

      expect(tokens, isNotEmpty);
      // Should have at least function name and keyword
      expect(tokens.any((t) => t.type == 'function'), true);
      expect(tokens.any((t) => t.type == 'keyword'), true);
    });
  });
}

/// A mock LSP client for testing semantic tokens.
class MockSemanticTokensClient implements SemanticTokensClient {
  final String documentContent;
  int _version = 0;

  MockSemanticTokensClient({required this.documentContent});

  @override
  SemanticTokensLegend get legend => SemanticTokensLegend(
        tokenTypes: [
          'namespace',
          'type',
          'class',
          'enum',
          'interface',
          'struct',
          'typeParameter',
          'parameter',
          'variable',
          'property',
          'enumMember',
          'event',
          'function',
          'method',
          'macro',
          'keyword',
          'modifier',
          'comment',
          'string',
          'number',
          'regexp',
          'operator',
          'decorator',
        ],
        tokenModifiers: [
          'declaration',
          'definition',
          'readonly',
          'static',
          'deprecated',
          'abstract',
          'async',
          'modification',
          'documentation',
          'defaultLibrary',
        ],
      );

  @override
  String get documentUri => 'file:///test.js';

  @override
  Future<SemanticTokensResult?> requestSemanticTokensFull(String uri) async {
    // Simulate simple JS tokenization for "function hello() { return 42; }"
    // This is a mock - real LSP would do proper analysis
    final data = <int>[];

    // Find and tokenize known patterns
    final content = documentContent;

    // "function" keyword at start
    if (content.startsWith('function')) {
      data.addAll([0, 0, 8, 15, 0]); // keyword
    }

    // Find function name after "function "
    final funcMatch = RegExp(r'function\s+(\w+)').firstMatch(content);
    if (funcMatch != null) {
      final name = funcMatch.group(1)!;
      final col = funcMatch.start + 9; // after "function "
      data.addAll([0, col, name.length, 12, 1]); // function, declaration modifier
    }

    // Find "return" keyword
    final returnIdx = content.indexOf('return');
    if (returnIdx != -1) {
      // Calculate line/col delta from last token
      final lastTokenEnd = funcMatch != null ? funcMatch.end : 8;
      data.addAll([0, returnIdx - lastTokenEnd + 4, 6, 15, 0]); // keyword
    }

    // Find number
    final numMatch = RegExp(r'\d+').firstMatch(content);
    if (numMatch != null) {
      data.addAll([0, 7, numMatch.group(0)!.length, 19, 0]); // number
    }

    _version++;
    return SemanticTokensResult(
      resultId: 'v$_version',
      data: data,
    );
  }

  @override
  Future<SemanticTokensResult?> requestSemanticTokensRange(
    String uri,
    int startLine,
    int startChar,
    int endLine,
    int endChar,
  ) async {
    // For simplicity, just return full tokens
    return requestSemanticTokensFull(uri);
  }

  @override
  Future<SemanticTokensDeltaResult?> requestSemanticTokensDelta(
    String uri,
    String previousResultId,
  ) async {
    // Return null to indicate delta not supported
    return null;
  }
}
