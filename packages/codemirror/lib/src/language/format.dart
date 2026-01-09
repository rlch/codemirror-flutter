/// Document Formatting support for CodeMirror.
///
/// This module provides infrastructure for formatting documents,
/// either the entire document or a selected range.
library;

import 'dart:async';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/keymap.dart';

// ============================================================================
// Format Edit
// ============================================================================

/// A single text edit returned by a formatter.
class FormatEdit {
  /// The start position of the edit.
  final int from;

  /// The end position of the edit (exclusive).
  final int to;

  /// The new text to insert at this range.
  final String newText;

  const FormatEdit({
    required this.from,
    required this.to,
    required this.newText,
  });

  /// Create an insert edit (no text replaced).
  factory FormatEdit.insert(int pos, String text) {
    return FormatEdit(from: pos, to: pos, newText: text);
  }

  /// Create a delete edit (text removed, nothing inserted).
  factory FormatEdit.delete(int from, int to) {
    return FormatEdit(from: from, to: to, newText: '');
  }

  /// Create a replace edit.
  factory FormatEdit.replace(int from, int to, String newText) {
    return FormatEdit(from: from, to: to, newText: newText);
  }

  @override
  String toString() => 'FormatEdit($from-$to: "$newText")';
}

/// Result returned by a format source.
class FormatResult {
  /// The edits to apply to the document.
  ///
  /// Edits should not overlap and should be sorted by position.
  final List<FormatEdit> edits;

  const FormatResult(this.edits);

  /// Create an empty result (no changes).
  static const FormatResult empty = FormatResult([]);

  /// Create a result that replaces the entire document.
  factory FormatResult.replaceAll(String newText, int docLength) {
    return FormatResult([FormatEdit(from: 0, to: docLength, newText: newText)]);
  }

  /// Whether any edits were returned.
  bool get isEmpty => edits.isEmpty;
  bool get isNotEmpty => edits.isNotEmpty;
}

// ============================================================================
// Format Source
// ============================================================================

/// The type of function that formats a document.
///
/// Called when the user requests document formatting.
/// - [state] is the current editor state
///
/// Should return a [FormatResult] with the edits to apply,
/// or null if formatting is not available.
typedef DocumentFormatSource = FutureOr<FormatResult?> Function(
  EditorState state,
);

/// The type of function that formats a range of the document.
///
/// Called when the user requests range formatting.
/// - [state] is the current editor state
/// - [from] is the start of the range to format
/// - [to] is the end of the range to format
///
/// Should return a [FormatResult] with the edits to apply,
/// or null if formatting is not available.
typedef RangeFormatSource = FutureOr<FormatResult?> Function(
  EditorState state,
  int from,
  int to,
);

/// The type of function that formats on typing specific characters.
///
/// Called after the user types a trigger character (e.g., ';', '}').
/// - [state] is the current editor state
/// - [pos] is the position where the character was typed
/// - [char] is the character that was typed
///
/// Should return a [FormatResult] with the edits to apply,
/// or null if no formatting should occur.
typedef OnTypeFormatSource = FutureOr<FormatResult?> Function(
  EditorState state,
  int pos,
  String char,
);

// ============================================================================
// Format Configuration
// ============================================================================

/// Configuration options for document formatting.
class DocumentFormattingOptions {
  /// Whether to format on save.
  ///
  /// When true, the document will be formatted before save events.
  /// The application must call [formatOnSave] in its save handler.
  final bool formatOnSave;

  /// Tab size for formatting (passed to the formatter).
  final int tabSize;

  /// Whether to use spaces instead of tabs.
  final bool insertSpaces;

  /// Additional formatter-specific options.
  final Map<String, dynamic> options;

  const DocumentFormattingOptions({
    this.formatOnSave = false,
    this.tabSize = 2,
    this.insertSpaces = true,
    this.options = const {},
  });
}

/// Configuration options for on-type formatting.
class OnTypeFormattingOptions {
  /// Characters that trigger on-type formatting.
  ///
  /// Common triggers: ';', '}', '\n'
  final List<String> triggerCharacters;

  const OnTypeFormattingOptions({
    this.triggerCharacters = const [],
  });
}

/// Internal configuration for document formatting.
class DocumentFormattingConfig {
  final DocumentFormatSource? documentSource;
  final RangeFormatSource? rangeSource;
  final OnTypeFormatSource? onTypeSource;
  final DocumentFormattingOptions options;
  final OnTypeFormattingOptions onTypeOptions;

  const DocumentFormattingConfig({
    this.documentSource,
    this.rangeSource,
    this.onTypeSource,
    this.options = const DocumentFormattingOptions(),
    this.onTypeOptions = const OnTypeFormattingOptions(),
  });
}

// ============================================================================
// Formatting Facet
// ============================================================================

/// Facet for collecting document formatting configurations.
final Facet<DocumentFormattingConfig, List<DocumentFormattingConfig>>
    documentFormattingFacet = Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up document formatting support.
///
/// The [source] callback is called when the user requests "Format Document"
/// (via Shift+Alt+F or a command). It should return a [FormatResult] with
/// the edits to apply.
///
/// Example:
/// ```dart
/// documentFormatting((state) async {
///   final formatted = await lspClient.formatDocument(
///     state.doc.toString(),
///     tabSize: 2,
///     insertSpaces: true,
///   );
///   if (formatted == null) return null;
///   return FormatResult.replaceAll(formatted, state.doc.length);
/// })
/// ```
///
/// Returns an extension that can be added to the editor state.
Extension documentFormatting(
  DocumentFormatSource source, [
  DocumentFormattingOptions options = const DocumentFormattingOptions(),
]) {
  final config = DocumentFormattingConfig(
    documentSource: source,
    options: options,
  );

  return ExtensionList([
    documentFormattingFacet.of(config),
  ]);
}

/// Set up range formatting support.
///
/// The [source] callback is called when the user requests "Format Selection".
/// It receives the selection range and should return edits for that range.
Extension rangeFormatting(
  RangeFormatSource source, [
  DocumentFormattingOptions options = const DocumentFormattingOptions(),
]) {
  final config = DocumentFormattingConfig(
    rangeSource: source,
    options: options,
  );

  return ExtensionList([
    documentFormattingFacet.of(config),
  ]);
}

/// Set up on-type formatting support.
///
/// The [source] callback is called after typing trigger characters.
/// Useful for auto-formatting after semicolons, closing braces, etc.
Extension onTypeFormatting(
  OnTypeFormatSource source, [
  OnTypeFormattingOptions options = const OnTypeFormattingOptions(),
]) {
  final config = DocumentFormattingConfig(
    onTypeSource: source,
    onTypeOptions: options,
  );

  return ExtensionList([
    documentFormattingFacet.of(config),
  ]);
}

// ============================================================================
// Format State Effects
// ============================================================================

/// State effect to trigger document formatting.
final StateEffectType<void> _formatDocumentEffect = StateEffect.define<void>();

/// Get the format document effect type for use in EditorView.
StateEffectType<void> get formatDocumentEffect => _formatDocumentEffect;

/// State effect to trigger range formatting.
final StateEffectType<({int from, int to})> _formatRangeEffect =
    StateEffect.define<({int from, int to})>();

/// Get the format range effect type for use in EditorView.
StateEffectType<({int from, int to})> get formatRangeEffect => _formatRangeEffect;

// ============================================================================
// Format Commands
// ============================================================================

/// Extract state and dispatch from command target.
/// 
/// Supports both EditorViewState (production) and record type (tests).
(EditorState, void Function(txn.Transaction)) _extractTarget(dynamic target) {
  if (target is ({EditorState state, void Function(txn.Transaction) dispatch})) {
    return (target.state, target.dispatch);
  }
  return (
    (target as dynamic).state as EditorState,
    (txn.Transaction tr) => (target as dynamic).dispatchTransaction(tr),
  );
}

/// Command to format the entire document.
///
/// Typically bound to Shift+Alt+F.
bool formatDocumentCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);

  dispatch(state.update([
    TransactionSpec(
      effects: [_formatDocumentEffect.of(null)],
    ),
  ]));

  return true;
}

/// Command to format the current selection.
///
/// If no selection, formats the current line.
bool formatSelectionCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final sel = state.selection.main;

  int from, to;
  if (sel.empty) {
    // No selection - format current line
    final line = state.doc.lineAt(sel.head);
    from = line.from;
    to = line.to;
  } else {
    // Extend to full lines
    final startLine = state.doc.lineAt(sel.from);
    final endLine = state.doc.lineAt(sel.to);
    from = startLine.from;
    to = endLine.to;
  }

  dispatch(state.update([
    TransactionSpec(
      effects: [_formatRangeEffect.of((from: from, to: to))],
    ),
  ]));

  return true;
}

/// Default keymap for document formatting.
final List<KeyBinding> documentFormattingKeymap = [
  KeyBinding(key: 'Shift-Alt-f', run: formatDocumentCommand),
  KeyBinding(mac: 'Shift-Alt-f', run: formatDocumentCommand),
  KeyBinding(key: 'Ctrl-Shift-i', run: formatDocumentCommand), // Alternative
];

/// Extension that adds the default formatting keymap.
Extension documentFormattingKeymapExt() {
  return keymap.of(documentFormattingKeymap);
}

// ============================================================================
// Apply Format Edits
// ============================================================================

/// Apply format edits to create a transaction spec.
///
/// Handles the conversion from [FormatResult] to [ChangeSpec].
/// Edits are applied in reverse order to preserve positions.
TransactionSpec applyFormatEdits(
  EditorState state,
  FormatResult result, {
  bool preserveCursor = true,
}) {
  if (result.isEmpty) {
    return const TransactionSpec();
  }

  // Sort edits by position (descending) to apply from end to start
  final sortedEdits = result.edits.toList()
    ..sort((a, b) => b.from.compareTo(a.from));

  // Convert to ChangeSpec
  final changes = sortedEdits.map((edit) {
    return ChangeSpec(
      from: edit.from,
      to: edit.to,
      insert: edit.newText,
    );
  }).toList();

  // Calculate new cursor position if preserving
  EditorSelection? newSelection;
  if (preserveCursor) {
    final cursorPos = state.selection.main.head;
    var newCursorPos = cursorPos;

    // Adjust cursor for each edit
    for (final edit in sortedEdits) {
      if (edit.to <= cursorPos) {
        // Edit is before cursor - adjust by length difference
        final delta = edit.newText.length - (edit.to - edit.from);
        newCursorPos += delta;
      } else if (edit.from < cursorPos) {
        // Edit overlaps cursor - move to end of new text
        newCursorPos = edit.from + edit.newText.length;
      }
    }

    newSelection = EditorSelection.single(newCursorPos.clamp(0, state.doc.length));
  }

  return TransactionSpec(
    changes: changes.length == 1 ? changes.first : ChangeSet.of(changes, state.doc.length),
    selection: newSelection,
    userEvent: 'format',
  );
}

/// Utility to format and apply in one step.
///
/// Returns a future that completes with the transaction to dispatch,
/// or null if no formatting was available.
Future<TransactionSpec?> formatDocument(EditorState state) async {
  final configs = state.facet(documentFormattingFacet);
  // ignore: avoid_print
  print('[formatDocument] configs.length = ${configs.length}');

  for (final config in configs) {
    // ignore: avoid_print
    print('[formatDocument] checking config, documentSource=${config.documentSource != null}');
    if (config.documentSource != null) {
      try {
        // ignore: avoid_print
        print('[formatDocument] calling documentSource...');
        final result = await Future.value(config.documentSource!(state));
        // ignore: avoid_print
        print('[formatDocument] documentSource returned: ${result?.edits.length ?? "null"} edits');
        if (result != null && result.isNotEmpty) {
          return applyFormatEdits(state, result);
        }
      } catch (e, stack) {
        // Log error instead of silently swallowing
        // ignore: avoid_print
        print('[formatDocument] Error: $e');
        // ignore: avoid_print
        print('[formatDocument] Stack: $stack');
      }
    }
  }

  return null;
}

/// Utility to format a range and apply in one step.
Future<TransactionSpec?> formatRange(EditorState state, int from, int to) async {
  final configs = state.facet(documentFormattingFacet);

  for (final config in configs) {
    if (config.rangeSource != null) {
      try {
        final result = await Future.value(config.rangeSource!(state, from, to));
        if (result != null && result.isNotEmpty) {
          return applyFormatEdits(state, result);
        }
      } catch (e) {
        // Continue to next source on error
      }
    }
  }

  // Fall back to document formatting if no range formatter
  return formatDocument(state);
}

/// Check if on-type formatting should trigger for a character.
Future<TransactionSpec?> checkOnTypeFormatting(
  EditorState state,
  int pos,
  String char,
) async {
  final configs = state.facet(documentFormattingFacet);

  for (final config in configs) {
    if (config.onTypeSource != null &&
        config.onTypeOptions.triggerCharacters.contains(char)) {
      try {
        final result = await Future.value(config.onTypeSource!(state, pos, char));
        if (result != null && result.isNotEmpty) {
          return applyFormatEdits(state, result);
        }
      } catch (e) {
        // Continue to next source on error
      }
    }
  }

  return null;
}
