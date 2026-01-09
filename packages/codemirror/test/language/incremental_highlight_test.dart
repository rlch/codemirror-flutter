// ignore_for_file: avoid_relative_lib_imports

/// Test that incremental parsing doesn't lose highlights in distant regions.
import 'package:flutter/material.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';

import '../../lib/src/language/highlight.dart';
import '../../lib/src/language/javascript/javascript.dart';
import '../../lib/src/language/language.dart';
import '../../lib/src/state/facet.dart' show ExtensionList;
import '../../lib/src/state/state.dart';
import '../../lib/src/state/range_set.dart';
import '../../lib/src/view/decoration.dart';
import '../../lib/src/view/editor_view.dart';

void main() {
  ensureStateInitialized();
  ensureLanguageInitialized();

  testWidgets('typing at end preserves padding highlight on line 2',
      (tester) async {
    const initialCode = '''return (
  <Padding padding={EdgeInsetsGeometry.all({ value: 24 })}>
    <Center>
      <Column mainAxisAlignment="center" crossAxisAlignment="center">
        <Text.h1>New Template</Text.h1>
        <SizedBox height={16} />
        <Text>
          Add properties in the sidebar, then use them here like {"{propertyName}"}
        </Text>
      </Column>
    </Center>
  </Padding>
);''';

    final jsxLang = javascript(JavaScriptConfig(jsx: true));
    final key = GlobalKey<EditorViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: EditorView(
              key: key,
              state: EditorState.create(EditorStateConfig(
                doc: initialCode,
                extensions: ExtensionList([
                  jsxLang.extension,
                  syntaxHighlighting(defaultHighlightStyle),
                ]),
              )),
            ),
          ),
        ),
      ),
    );

    // Let initial parsing complete
    await tester.pump(const Duration(milliseconds: 300));

    final view = key.currentState!;

    // Find the position of "Padding" tag (which IS highlighted)
    final paddingTagPos = initialCode.indexOf('<Padding') + 1; // position of 'P'

    // Check if decorations cover the Padding tag name
    bool hasPaddingHighlight() {
      final decos = view.decorations;
      final cursor = decos.iter();
      while (cursor.value != null) {
        // Check for decoration at position 12-19 which covers "Padding"
        if (cursor.from <= paddingTagPos && cursor.to > paddingTagPos) {
          return true;
        }
        cursor.next();
      }
      return false;
    }


    expect(hasPaddingHighlight(), isTrue,
        reason: 'Padding tag should be highlighted initially');

    // Focus editor
    await tester.tap(find.byType(EditableText));
    await tester.pump();

    // Type 12 'a' characters at the end of the Text content
    final insertPos =
        initialCode.indexOf('propertyName}"}') + 'propertyName}"}'.length;
    var currentText = initialCode;

    for (int i = 0; i < 30; i++) {
      currentText = currentText.substring(0, insertPos + i) +
          'a' +
          currentText.substring(insertPos + i);

      await tester.enterText(find.byType(EditableText), currentText);
      // Fast typing - only 50ms between keystrokes
      await tester.pump(const Duration(milliseconds: 50));

      final stillHasHighlight = hasPaddingHighlight();
      if (!stillHasHighlight) {
        fail('Padding highlight lost after ${i + 1} chars');
      }
    }

    // Wait for any async parsing to complete
    await tester.pump(const Duration(milliseconds: 500));

    // The key assertion: Padding tag should STILL be highlighted
    expect(
      hasPaddingHighlight(),
      isTrue,
      reason:
          'Padding tag should still be highlighted after typing at end',
    );

    // Also check closing tags - these are the ones getting lost!
    final closingPaddingPos = currentText.lastIndexOf('</Padding') + 2; // position of 'P'
    final closingCenterPos = currentText.lastIndexOf('</Center') + 2;
    
    bool hasClosingPadding = false;
    bool hasClosingCenter = false;
    final cursor = view.decorations.iter();
    while (cursor.value != null) {
      if (cursor.from <= closingPaddingPos && cursor.to > closingPaddingPos) {
        hasClosingPadding = true;
      }
      if (cursor.from <= closingCenterPos && cursor.to > closingCenterPos) {
        hasClosingCenter = true;
      }
      cursor.next();
    }
    
    expect(hasClosingCenter, isTrue, 
        reason: 'Closing </Center> tag should still be highlighted');
    expect(hasClosingPadding, isTrue, 
        reason: 'Closing </Padding> tag should still be highlighted');
  });
}
