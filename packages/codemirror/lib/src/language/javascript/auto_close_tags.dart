/// Auto-closing JSX tags extension for CodeMirror.
///
/// This module provides automatic closing of JSX tags when `>` or `/` is typed.
/// Ported from @codemirror/lang-html autoCloseTags.
library;

import 'package:lezer/lezer.dart' show SyntaxNode;

import '../../state/change.dart';
import '../../state/facet.dart' hide EditorState, Transaction;
import '../../state/selection.dart';
import '../../state/state.dart';
import '../../state/transaction.dart' hide Transaction;
import '../../text/text.dart';
import '../../view/editor_view.dart';
import '../language.dart';

/// Extension that will automatically insert close tags when a `>` or
/// `/` is typed in JSX context.
///
/// When you type `>` after `<div`, it inserts `</div>`.
/// When you type `/` after `</`, it completes to `</div>`.
final Extension jsxAutoCloseTags = EditorView.inputHandler.of(_handleInput);

/// Self-closing HTML tags that shouldn't get close tags in JSX.
const _selfClosers = {
  'area', 'base', 'br', 'col', 'command', 'embed', 'frame', 'hr',
  'img', 'input', 'keygen', 'link', 'meta', 'param', 'source',
  'track', 'wbr', 'menuitem',
};

bool _handleInput(
  dynamic view,
  int from,
  int to,
  String text,
) {
  final v = view as EditorViewState;
  
  // Match JS: skip if composing, read-only, not at cursor, or wrong character
  if (v.composing || v.compositionStarted || v.state.isReadOnly) return false;
  if (from != to) return false;
  if (text != '>' && text != '/') return false;
  
  // Create a hypothetical state with the typed character applied
  // This mirrors the reference's insertTransaction() approach
  final baseTransaction = v.state.update([
    TransactionSpec(
      changes: ChangeSpec(from: from, to: to, insert: text),
      selection: EditorSelection.single(from + text.length),
    ),
  ]);
  final baseState = baseTransaction.state as EditorState;
  
  // Now check for tag closing in the resulting state
  final closeTags = baseState.changeByRange((range) {
    final doc = baseState.doc;
    
    // Match JS: didType check uses range.from - 1, range.to (not just head - 1)
    final didType = doc.sliceString(range.from - 1, range.to) == text;
    if (!didType) return ChangeByRangeResult(range: range);
    
    final head = range.head;
    final tree = syntaxTree(baseState);
    final after = tree.resolveInner(head, -1);
    String? name;
    
    if (text == '>') {
      // Handle > - close tag after opening tag
      // Tree structure: JSXElement > JSXOpenTag > JSXEndTag
      // We're at JSXEndTag (the ">"), need to check JSXElement for close tag
      if (after.name == 'JSXEndTag') {
        final openTag = after.parent; // JSXOpenTag
        if (openTag != null && openTag.name == 'JSXOpenTag') {
          final element = openTag.parent; // JSXElement
          // Check if the element doesn't already have a close tag
          if (element != null && 
              element.lastChild?.name != 'JSXCloseTag' &&
              element.lastChild?.name != 'JSXSelfCloseEndTag') {
            name = _elementName(doc, element, head);
            if (name != null && name.isNotEmpty && !_selfClosers.contains(name.toLowerCase())) {
              // Check if there's already a ">" after cursor (avoid doubling)
              final insertTo = head + (doc.sliceString(head, head + 1) == '>' ? 1 : 0);
              final insert = '</$name>';
              return ChangeByRangeResult(
                range: range,
                changes: ChangeSpec(from: head, to: insertTo, insert: insert),
              );
            }
          }
        }
      }
    } else if (text == '/') {
      // Handle / - complete close tag like "</" -> "</div>"
      // Tree structure: JSXElement > JSXCloseTag > JSXStartCloseTag
      // We're at JSXStartCloseTag (the "</"), need JSXElement to get the tag name
      if (after.name == 'JSXStartCloseTag') {
        final closeTag = after.parent; // JSXCloseTag (incomplete)
        if (closeTag != null) {
          final element = closeTag.parent; // JSXElement
          // Verify we're right after the "</" (position head - 2)
          // Match JS: also check element doesn't already have a complete close tag
          if (element != null && 
              after.from == head - 2 &&
              element.lastChild?.name != 'JSXCloseTag') {
            name = _elementName(doc, element, head);
            if (name != null && name.isNotEmpty && !_selfClosers.contains(name.toLowerCase())) {
              // Check if there's already a ">" after cursor
              final insertTo = head + (doc.sliceString(head, head + 1) == '>' ? 1 : 0);
              final insert = '$name>';
              return ChangeByRangeResult(
                range: EditorSelection.cursor(head + insert.length, assoc: -1),
                changes: ChangeSpec(from: head, to: insertTo, insert: insert),
              );
            }
          }
        }
      }
    }
    
    return ChangeByRangeResult(range: range);
  });
  
  // Match JS: if no close tag needed, return false to let default handling run
  if (closeTags.changes.empty) {
    return false;
  }
  
  // Match JS: dispatch both transactions together
  // JS does: view.dispatch([base, state.update(closeTags, {...})])
  final closeTransaction = baseState.update([
    TransactionSpec(
      changes: closeTags.changes,
      selection: closeTags.selection,
      userEvent: 'input.complete',
      scrollIntoView: true,
    ),
  ]);
  
  v.dispatchTransactions([baseTransaction, closeTransaction]);
  
  return true;
}

/// Get the element/tag name from a JSX element node.
String? _elementName(Text doc, SyntaxNode element, int max) {
  // Look for the opening tag first
  SyntaxNode? openTag;
  for (var child = element.firstChild; child != null; child = child.nextSibling) {
    if (child.name == 'JSXOpenTag' || child.name == 'JSXSelfClosingTag') {
      openTag = child;
      break;
    }
  }
  
  if (openTag == null) return null;
  
  // Find the tag name within the opening tag
  // Tree structure can be:
  //   JSXOpenTag > JSXBuiltin > JSXIdentifier  (for built-in tags like div)
  //   JSXOpenTag > JSXIdentifier  (for custom components)
  //   JSXOpenTag > JSXMemberExpression  (for Foo.Bar)
  for (var child = openTag.firstChild; child != null; child = child.nextSibling) {
    final name = child.name;
    
    // JSXBuiltin wraps built-in HTML tags - look inside it
    if (name == 'JSXBuiltin') {
      final inner = child.firstChild;
      if (inner != null) {
        final end = inner.to > max ? max : inner.to;
        return doc.sliceString(inner.from, end);
      }
    }
    
    // Direct identifier for custom components
    if (name == 'JSXIdentifier' || 
        name == 'JSXLowerIdentifier' ||
        name == 'JSXMemberExpression' ||
        name == 'JSXNamespacedName') {
      final end = child.to > max ? max : child.to;
      return doc.sliceString(child.from, end);
    }
  }
  
  return null;
}
