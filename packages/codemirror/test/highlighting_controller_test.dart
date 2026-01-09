import 'package:flutter/material.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:codemirror/codemirror.dart' hide Text;
import 'package:codemirror/src/state/range_set.dart';
import 'package:codemirror/src/view/decoration.dart';
import 'package:codemirror/src/view/highlighting_controller.dart';

void main() {
  group('HighlightingTextEditingController', () {
    test('buildTextSpan applies decoration at correct position', () {
      // Build a simple RangeSet with a decoration at 0-5
      final deco = Decoration.mark(MarkDecorationSpec(className: 'cm-searchMatch'));
      final builder = RangeSetBuilder<Decoration>();
      builder.add(0, 5, deco);
      final rangeSet = builder.finish();

      // Verify the range is stored correctly
      final cursor = rangeSet.iter();
      expect(cursor.value, isNotNull);
      expect(cursor.from, 0);
      expect(cursor.to, 5);

      // Create controller with this decoration
      final controller = HighlightingTextEditingController(
        text: 'hello world',
        getDecorations: () => rangeSet,
        theme: HighlightTheme.light,
      );

      // Build the text span - need a fake context
      // We can't easily test this without a widget test
    });

    testWidgets('decorations highlight correct text ranges', (tester) async {
      // Build decorations: highlight positions 0-5 (hello) and 12-17 (hello)
      final deco = Decoration.mark(MarkDecorationSpec(className: 'cm-searchMatch'));
      final builder = RangeSetBuilder<Decoration>();
      builder.add(0, 5, deco);
      builder.add(12, 17, deco);
      final rangeSet = builder.finish();

      // Verify ranges in RangeSet
      final cursor = rangeSet.iter();
      expect(cursor.value, isNotNull);
      expect(cursor.from, 0);
      expect(cursor.to, 5);
      cursor.next();
      expect(cursor.value, isNotNull);
      expect(cursor.from, 12);
      expect(cursor.to, 17);

      // Create controller
      final controller = HighlightingTextEditingController(
        text: 'hello world hello',
        getDecorations: () => rangeSet,
        theme: HighlightTheme.light,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the EditableText and inspect its TextSpan
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      
      // The controller.buildTextSpan is called internally by Flutter
      // Let's manually call it and inspect the result
      final span = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(color: Colors.black),
        withComposing: false,
      );

      // Expect structure:
      // - TextSpan "hello" (0-5) with highlight
      // - TextSpan " world " (5-12) no highlight
      // - TextSpan "hello" (12-17) with highlight
      expect(span.children, isNotNull);
      expect(span.children!.length, 3);

      final firstChild = span.children![0] as TextSpan;
      final secondChild = span.children![1] as TextSpan;
      final thirdChild = span.children![2] as TextSpan;

      expect(firstChild.text, 'hello');
      expect(secondChild.text, ' world ');
      expect(thirdChild.text, 'hello');

      // First and third should have background color (highlight)
      expect(firstChild.style?.backgroundColor, isNotNull);
      expect(secondChild.style?.backgroundColor, isNull);
      expect(thirdChild.style?.backgroundColor, isNotNull);
    });

    testWidgets('single decoration at position 6-11', (tester) async {
      // Test: highlight "world" in "hello world hello"
      final deco = Decoration.mark(MarkDecorationSpec(className: 'cm-searchMatch'));
      final builder = RangeSetBuilder<Decoration>();
      builder.add(6, 11, deco);
      final rangeSet = builder.finish();

      final controller = HighlightingTextEditingController(
        text: 'hello world hello',
        getDecorations: () => rangeSet,
        theme: HighlightTheme.light,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
            ),
          ),
        ),
      );

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(color: Colors.black),
        withComposing: false,
      );

      // Expected: "hello " (0-6), "world" (6-11), " hello" (11-17)
      expect(span.children!.length, 3);
      expect((span.children![0] as TextSpan).text, 'hello ');
      expect((span.children![1] as TextSpan).text, 'world');
      expect((span.children![2] as TextSpan).text, ' hello');
    });

    testWidgets('handles overlapping decorations without duplicating text', (tester) async {
      // Simulate: const text = "Hello world, hello universe"
      // Syntax: 0-5 "const", 6-10 "text", 13-40 string literal
      // Search for "hello": matches at 14 (inside string) and 27 (inside string)
      final keyword = Decoration.mark(MarkDecorationSpec(className: 'cm-keyword'));
      final variable = Decoration.mark(MarkDecorationSpec(className: 'cm-variable'));
      final stringLit = Decoration.mark(MarkDecorationSpec(className: 'cm-string'));
      final searchMatch = Decoration.mark(MarkDecorationSpec(className: 'cm-searchMatch'));
      
      // Build syntax decorations
      final syntaxBuilder = RangeSetBuilder<Decoration>();
      syntaxBuilder.add(0, 5, keyword);    // const
      syntaxBuilder.add(6, 10, variable);  // text
      syntaxBuilder.add(13, 40, stringLit); // "Hello world, hello universe"
      final syntaxSet = syntaxBuilder.finish();
      
      // Build search decorations (hello at positions 14-19 and 27-32)
      final searchBuilder = RangeSetBuilder<Decoration>();
      searchBuilder.add(14, 19, searchMatch);  // Hello
      searchBuilder.add(27, 32, searchMatch);  // hello
      final searchSet = searchBuilder.finish();
      
      // Join them
      final rangeSet = RangeSet.join([syntaxSet, searchSet]);
      
      final theText = 'const text = "Hello world, hello universe"';
      final controller = HighlightingTextEditingController(
        text: theText,
        getDecorations: () => rangeSet,
        theme: HighlightTheme.light,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
            ),
          ),
        ),
      );

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(color: Colors.black),
        withComposing: false,
      );

      // The total text from all children should equal the original text length
      final totalTextLen = span.children!.fold<int>(
        0, (sum, child) => sum + ((child as TextSpan).text?.length ?? 0),
      );
      expect(totalTextLen, theText.length, reason: 'Should not duplicate text from overlapping decorations');

      // Concatenated text should exactly match original
      final concatenated = span.children!
          .map((child) => (child as TextSpan).text ?? '')
          .join();
      expect(concatenated, theText);
    });

    testWidgets('full integration: search decorations from EditorView', (tester) async {
      ensureStateInitialized();
      
      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'hello world hello',
          extensions: ExtensionList([search()]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
              highlightTheme: HighlightTheme.light,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final view = editorKey.currentState!;

      // Open search panel and set query
      openSearchPanel(view);
      await tester.pumpAndSettle();

      view.dispatch([
        TransactionSpec(
          effects: [setSearchQuery.of(SearchQuery(search: 'hello'))],
        ),
      ]);
      await tester.pumpAndSettle();

      // Verify the search state is valid
      final searchSt = view.state.field(searchState, false);
      expect(searchSt, isNotNull);
      expect(searchSt!.query.spec.valid, isTrue);

      // Verify view.decorations contains the correct ranges
      final viewDecos = view.decorations;
      final cursor = viewDecos.iter();
      
      expect(cursor.value, isNotNull, reason: 'Should have at least one decoration');
      expect(cursor.from, 0, reason: 'First match should start at 0');
      expect(cursor.to, 5, reason: 'First match should end at 5');
      
      cursor.next();
      expect(cursor.value, isNotNull, reason: 'Should have second decoration');
      expect(cursor.from, 12, reason: 'Second match should start at 12');
      expect(cursor.to, 17, reason: 'Second match should end at 17');
    });

    testWidgets('syntax + semantic tokens merge correctly', (tester) async {
      ensureStateInitialized();
      ensureLanguageInitialized();

      final editorKey = GlobalKey<EditorViewState>();
      EditorState state = EditorState.create(
        EditorStateConfig(
          doc: 'const x = 1;',
          extensions: ExtensionList([
            javascript().extension,
            syntaxHighlighting(defaultHighlightStyle),
            semanticTokensField,
          ]),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(
              key: editorKey,
              state: state,
              onUpdate: (update) => state = update.state,
              highlightTheme: HighlightTheme.light,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final view = editorKey.currentState!;

      // Verify Lezer syntax decorations are present
      final decoSources = view.state.facet(decorationsFacet);
      expect(decoSources.isNotEmpty, isTrue, reason: 'Should have decoration sources');

      final classCounts = <String, int>{};
      for (final source in decoSources) {
        RangeSet<Decoration>? result;
        if (source is RangeSet<Decoration>) {
          result = source;
        } else if (source is Function) {
          result = (source as dynamic)(view) as RangeSet<Decoration>?;
        }
        if (result != null && !result.isEmpty) {
          final cursor = result.iter();
          while (cursor.value != null) {
            final deco = cursor.value!;
            if (deco is MarkDecoration) {
              classCounts[deco.className] = (classCounts[deco.className] ?? 0) + 1;
            }
            cursor.next();
          }
        }
      }

      // Should have Lezer syntax decorations
      expect(classCounts['cm-keyword'], greaterThan(0), reason: 'Should have cm-keyword');
      expect(classCounts['cm-def'], greaterThan(0), reason: 'Should have cm-def');
      expect(classCounts['cm-number'], greaterThan(0), reason: 'Should have cm-number');

      // Now add semantic tokens manually (simulating LSP response)
      final semTokens = [
        SemanticToken(from: 0, to: 5, type: 'keyword', modifiers: []),
        SemanticToken(from: 6, to: 7, type: 'variable', modifiers: ['declaration', 'readonly']),
        SemanticToken(from: 10, to: 11, type: 'number', modifiers: []),
      ];
      final semDecorations = tokensToDecorations(semTokens);

      view.dispatch([
        TransactionSpec(effects: [
          setSemanticTokens.of(SemanticTokensState(
            tokens: semTokens,
            decorations: semDecorations,
            data: [],
            version: 1,
          )),
        ]),
      ]);
      await tester.pump();

      // Verify semantic tokens are in decorations now
      final semState = view.state.field(semanticTokensField, false);
      expect(semState, isNotNull, reason: 'Semantic tokens state should exist');
      expect(semState!.tokens.length, 3, reason: 'Should have 3 semantic tokens');

      // Verify HighlightingTextEditingController builds spans with merged styles
      final editableText = tester.widget<EditableText>(find.byType(EditableText));
      final controller = editableText.controller as HighlightingTextEditingController;
      final textSpan = controller.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false,
      );

      // Total text should match
      final totalTextLen = textSpan.children!.fold<int>(
        0, (sum, child) => sum + ((child as TextSpan).text?.length ?? 0),
      );
      expect(totalTextLen, 12, reason: 'Should have all 12 characters');

      // Verify we have colored spans
      int coloredCount = 0;
      for (final child in textSpan.children ?? []) {
        if (child is TextSpan && child.style?.color != null) {
          coloredCount++;
        }
      }
      expect(coloredCount, greaterThan(0), reason: 'Should have colored spans');

      // Print spans for debugging
      print('TextSpan children with syntax + semantic:');
      for (var i = 0; i < (textSpan.children?.length ?? 0); i++) {
        final child = textSpan.children![i] as TextSpan;
        final text = child.text?.replaceAll('\n', '\\n') ?? '(null)';
        print('  "$text" color=${child.style?.color} fontWeight=${child.style?.fontWeight} fontStyle=${child.style?.fontStyle}');
      }
    });
  });
}
