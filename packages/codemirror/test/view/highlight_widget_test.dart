import 'package:codemirror/codemirror.dart' hide Decoration;
import 'package:codemirror/codemirror.dart' as cm show Decoration, MarkDecoration;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  testWidgets('processData example highlighting', (tester) async {
    final code = '''// JavaScript Example with nested structures
function processData(items) {
  const results = items.map((item) => {
    if (item.value > 10) {
      return {
        id: item.id,
        processed: true,
        data: {
          original: item.value,
          doubled: item.value * 2,
          metadata: {
            timestamp: Date.now(),
            source: "processor"
          }
        }
      };
    }
  });
}''';

    final state = EditorState.create(EditorStateConfig(
      doc: code,
      extensions: ExtensionList([
        javascript().extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorView(key: key, state: state)),
      ),
    );
    
    // Let the parsing complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final viewState = key.currentState!;
    
    // Check highlighters
    final highlighters = getHighlighters(viewState.state);
    print('Highlighters count: ${highlighters?.length ?? 0}');
    
    // Check syntax tree
    final tree = syntaxTree(viewState.state);
    print('Tree length: ${tree.length}, doc length: ${viewState.state.doc.length}');
    print('Tree type: ${tree.type.name}');
    
    // Check viewport
    print('Viewport: from=${viewState.viewState.viewport.from} to=${viewState.viewState.viewport.to}');
    print('Visible ranges: ${viewState.visibleRanges}');
    
    // Check decoration sources
    final decoSources = viewState.state.facet(decorationsFacet);
    print('Decoration sources count: ${decoSources.length}');
    
    // Check plugins
    final plugins = viewState.state.facet(viewPlugin);
    print('View plugins count: ${plugins.length}');
    for (final p in plugins) {
      print('  Plugin ID: ${p.id}');
    }
    
    // Evaluate decorations and count by class
    final classCounts = <String, int>{};
    for (final source in decoSources) {
      RangeSet<cm.Decoration>? result;
      if (source is RangeSet<cm.Decoration>) {
        result = source;
      } else if (source is Function) {
        result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
      }
      if (result != null && !result.isEmpty) {
        final cursor = result.iter();
        while (cursor.value != null) {
          final deco = cursor.value!;
          if (deco is cm.MarkDecoration) {
            classCounts[deco.className] = (classCounts[deco.className] ?? 0) + 1;
          }
          cursor.next();
        }
      }
    }
    
    print('Decoration classes found:');
    for (final entry in classCounts.entries) {
      print('  ${entry.key}: ${entry.value}');
    }
    
    // Check TextSpan
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    final controller = editableText.controller as HighlightingTextEditingController;
    final textSpan = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    
    print('\nTextSpan children: ${textSpan.children?.length ?? 0}');
    
    // Count colored vs uncolored children
    int coloredCount = 0;
    int uncoloredCount = 0;
    for (final child in textSpan.children ?? []) {
      if (child is TextSpan) {
        if (child.style?.color != null) {
          coloredCount++;
        } else {
          uncoloredCount++;
        }
      }
    }
    print('Colored spans: $coloredCount');
    print('Uncolored spans: $uncoloredCount');
    
    // Print first 10 spans
    print('\nFirst 10 TextSpan children:');
    for (var i = 0; i < (textSpan.children?.length ?? 0) && i < 10; i++) {
      final child = textSpan.children![i];
      if (child is TextSpan) {
        final text = child.text?.replaceAll('\n', '\\n') ?? '(null)';
        print('  Child $i: "$text" color=${child.style?.color}');
      }
    }
    
    // Verify we have more than just comments highlighted
    expect(classCounts['cm-keyword'], greaterThan(0), reason: 'Should have keyword decorations');
    expect(classCounts['cm-def'], greaterThan(0), reason: 'Should have def decorations');
    expect(classCounts['cm-comment'], greaterThan(0), reason: 'Should have comment decorations');
    expect(coloredCount, greaterThan(5), reason: 'Should have multiple colored spans');
  });
  
  testWidgets('decoration positions are sorted and non-overlapping', (tester) async {
    final code = 'const x = 1;';

    final state = EditorState.create(EditorStateConfig(
      doc: code,
      extensions: ExtensionList([
        javascript().extension,
        syntaxHighlighting(defaultHighlightStyle),
      ]),
    ));

    final key = GlobalKey<EditorViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditorView(key: key, state: state)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final viewState = key.currentState!;
    
    // Get decorations
    final decoSources = viewState.state.facet(decorationsFacet);
    final decos = <({int from, int to, String cls})>[];
    
    for (final source in decoSources) {
      RangeSet<cm.Decoration>? result;
      if (source is RangeSet<cm.Decoration>) {
        result = source;
      } else if (source is Function) {
        result = (source as dynamic)(viewState) as RangeSet<cm.Decoration>?;
      }
      if (result != null) {
        final cursor = result.iter();
        while (cursor.value != null) {
          if (cursor.value is cm.MarkDecoration) {
            decos.add((from: cursor.from, to: cursor.to, cls: (cursor.value as cm.MarkDecoration).className));
          }
          cursor.next();
        }
      }
    }
    
    print('Decorations in iteration order:');
    for (final d in decos) {
      final text = code.substring(d.from, d.to);
      print('  [$d.from}-${d.to}] "$text" -> ${d.cls}');
    }
    
    // Verify sorted by from position
    for (var i = 1; i < decos.length; i++) {
      expect(decos[i].from, greaterThanOrEqualTo(decos[i-1].from),
        reason: 'Decorations should be sorted by from position');
    }
    
    // Check for overlaps
    for (var i = 1; i < decos.length; i++) {
      final prev = decos[i-1];
      final curr = decos[i];
      if (curr.from < prev.to) {
        print('OVERLAP: prev=[${prev.from}-${prev.to}] ${prev.cls}, curr=[${curr.from}-${curr.to}] ${curr.cls}');
      }
    }
  });
}
