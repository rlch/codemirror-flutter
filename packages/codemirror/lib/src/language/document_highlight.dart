/// Document Highlight support for CodeMirror.
///
/// This module provides infrastructure for highlighting all occurrences
/// of the symbol under the cursor, providing visual feedback for
/// symbol references.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Color;

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/decoration.dart' show Decoration, MarkDecorationSpec;
import '../view/view_plugin.dart' show decorationsFacet;
import '../view/editor_view.dart' show EditorViewState;

// ============================================================================
// Highlight Kind
// ============================================================================

/// The kind of document highlight.
enum HighlightKind {
  /// A textual occurrence (default).
  text,

  /// A read-access of a symbol (e.g., reading a variable).
  read,

  /// A write-access of a symbol (e.g., writing to a variable).
  write,
}

// ============================================================================
// Document Highlight
// ============================================================================

/// A highlighted range in the document.
class DocumentHighlight {
  /// The start position of the highlight.
  final int from;

  /// The end position of the highlight.
  final int to;

  /// The kind of highlight.
  final HighlightKind kind;

  const DocumentHighlight({
    required this.from,
    required this.to,
    this.kind = HighlightKind.text,
  });

  @override
  String toString() => 'DocumentHighlight($from-$to, $kind)';
}

/// Result returned by a document highlight source.
class DocumentHighlightResult {
  /// The highlighted ranges.
  final List<DocumentHighlight> highlights;

  const DocumentHighlightResult(this.highlights);

  /// Create an empty result.
  static const DocumentHighlightResult empty = DocumentHighlightResult([]);

  /// Whether any highlights were found.
  bool get isEmpty => highlights.isEmpty;
  bool get isNotEmpty => highlights.isNotEmpty;
}

// ============================================================================
// Document Highlight Source
// ============================================================================

/// The type of function that provides document highlights.
///
/// Called when the cursor moves to a new position.
/// - [state] is the current editor state
/// - [pos] is the document position of the cursor
///
/// Should return a [DocumentHighlightResult] with the highlight ranges,
/// or null if no highlights are available.
typedef DocumentHighlightSource = FutureOr<DocumentHighlightResult?> Function(
  EditorState state,
  int pos,
);

// ============================================================================
// Document Highlight Configuration
// ============================================================================

/// Configuration options for document highlight.
class DocumentHighlightOptions {
  /// Delay in milliseconds before requesting highlights after cursor movement.
  /// 
  /// Helps debounce rapid cursor movements.
  final int delay;

  /// Color for text/default highlights.
  final Color? textColor;

  /// Color for read-access highlights.
  final Color? readColor;

  /// Color for write-access highlights.
  final Color? writeColor;

  /// Whether to highlight the symbol under cursor itself.
  final bool highlightCursor;

  const DocumentHighlightOptions({
    this.delay = 150,
    this.textColor,
    this.readColor,
    this.writeColor,
    this.highlightCursor = true,
  });

  /// Get the color for a highlight kind.
  Color colorForKind(HighlightKind kind, {required bool isDark}) {
    switch (kind) {
      case HighlightKind.text:
        return textColor ?? (isDark 
            ? const Color(0x33FFFFFF) 
            : const Color(0x22000000));
      case HighlightKind.read:
        return readColor ?? (isDark 
            ? const Color(0x3397C4FF) 
            : const Color(0x330066CC));
      case HighlightKind.write:
        return writeColor ?? (isDark 
            ? const Color(0x44FFCC00) 
            : const Color(0x33CC6600));
    }
  }
}

/// Internal configuration for document highlight.
class DocumentHighlightConfig {
  final DocumentHighlightSource source;
  final DocumentHighlightOptions options;

  const DocumentHighlightConfig({
    required this.source,
    required this.options,
  });
}

// ============================================================================
// Document Highlight Facet
// ============================================================================

/// Facet for collecting document highlight configurations.
final Facet<DocumentHighlightConfig, List<DocumentHighlightConfig>>
    documentHighlightFacet = Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up document highlight support.
///
/// The [source] callback is called when the cursor moves to highlight
/// all occurrences of the symbol at the cursor position.
///
/// Example:
/// ```dart
/// documentHighlight((state, pos) async {
///   final highlights = await lspClient.documentHighlight(state.doc, pos);
///   if (highlights == null) return null;
///   return DocumentHighlightResult(highlights.map((h) => DocumentHighlight(
///     from: h.range.start,
///     to: h.range.end,
///     kind: h.kind == 2 ? HighlightKind.read 
///         : h.kind == 3 ? HighlightKind.write 
///         : HighlightKind.text,
///   )).toList());
/// })
/// ```
Extension documentHighlight(
  DocumentHighlightSource source, [
  DocumentHighlightOptions options = const DocumentHighlightOptions(),
]) {
  ensureDocumentHighlightInitialized();
  
  final config = DocumentHighlightConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    documentHighlightFacet.of(config),
    _highlightState,
    decorationsFacet.of((EditorViewState view) {
      final field = view.state.field(_highlightState, false);
      return field?.decorations ?? Decoration.none;
    }),
  ]);
}

// ============================================================================
// Highlight State
// ============================================================================

/// State field for tracking current document highlights.
late final StateField<DocumentHighlightState> _highlightState;

/// Get the highlight state field.
StateField<DocumentHighlightState> get highlightStateField => _highlightState;

/// The current document highlight state.
class DocumentHighlightState {
  /// The position where highlights were computed.
  final int? pos;

  /// The current highlights.
  final List<DocumentHighlight> highlights;

  /// Decoration set for rendering.
  final RangeSet<Decoration> decorations;

  const DocumentHighlightState({
    this.pos,
    this.highlights = const [],
    required this.decorations,
  });

  /// Empty state with no highlights.
  static DocumentHighlightState get empty => DocumentHighlightState(
        decorations: RangeSet.empty<Decoration>(),
      );
}

/// State effect to set document highlights.
final StateEffectType<List<DocumentHighlight>> _setHighlightsEffect =
    StateEffect.define<List<DocumentHighlight>>();

/// Get the set highlights effect type.
StateEffectType<List<DocumentHighlight>> get setHighlightsEffect => 
    _setHighlightsEffect;

/// State effect to clear document highlights.
final StateEffectType<void> _clearHighlightsEffect = StateEffect.define<void>();

/// Get the clear highlights effect type.
StateEffectType<void> get clearHighlightsEffect => _clearHighlightsEffect;

// ============================================================================
// Initialization
// ============================================================================

bool _highlightInitialized = false;

/// Ensure document highlight module is initialized.
void ensureDocumentHighlightInitialized() {
  if (_highlightInitialized) return;
  _highlightInitialized = true;

  _highlightState = StateField.define(StateFieldConfig(
    create: (_) => DocumentHighlightState.empty,
    update: (state, tr) {
      final transaction = tr as txn.Transaction;
      
      // Check for highlight effects
      for (final effect in transaction.effects) {
        if (effect.is_(_setHighlightsEffect)) {
          final highlights = effect.value as List<DocumentHighlight>;
          return _buildHighlightState(
            highlights,
            transaction.state as EditorState,
          );
        }
        if (effect.is_(_clearHighlightsEffect)) {
          return DocumentHighlightState.empty;
        }
      }
      
      // If document changed, clear highlights
      if (transaction.docChanged) {
        return DocumentHighlightState.empty;
      }
      
      // If selection changed significantly, clear highlights
      if (transaction.selection != null) {
        final newPos = (transaction.state as EditorState).selection.main.head;
        if (state.pos != null) {
          // Check if cursor moved outside the highlighted ranges
          final inRange = state.highlights.any(
            (h) => newPos >= h.from && newPos <= h.to
          );
          if (!inRange) {
            return DocumentHighlightState.empty;
          }
        }
      }
      
      return state;
    },
  ));
}

/// Build highlight state with decorations.
DocumentHighlightState _buildHighlightState(
  List<DocumentHighlight> highlights,
  EditorState state,
) {
  if (highlights.isEmpty) {
    return DocumentHighlightState.empty;
  }

  // Get highlight options for colors (reserved for future theme-based styling)
  // final configs = state.facet(documentHighlightFacet);
  // final options = configs.isNotEmpty 
  //     ? configs.first.options 
  //     : const DocumentHighlightOptions();

  // Build decorations
  final builder = RangeSetBuilder<Decoration>();
  
  // Sort highlights by position
  final sorted = highlights.toList()
    ..sort((a, b) => a.from.compareTo(b.from));

  for (final highlight in sorted) {
    // Use a mark decoration with background color
    // Note: actual color will be applied in the view based on theme
    final decoration = Decoration.mark(MarkDecorationSpec(
      className: 'cm-documentHighlight cm-documentHighlight-${highlight.kind.name}',
      spec: {
        'highlightKind': highlight.kind.index,
      },
    ));
    builder.add(highlight.from, highlight.to, decoration);
  }

  return DocumentHighlightState(
    pos: state.selection.main.head,
    highlights: highlights,
    decorations: builder.finish(),
  );
}

/// Create a transaction spec that sets document highlights.
TransactionSpec setDocumentHighlights(List<DocumentHighlight> highlights) {
  return TransactionSpec(
    effects: [_setHighlightsEffect.of(highlights)],
  );
}

/// Create a transaction spec that clears document highlights.
TransactionSpec clearDocumentHighlights() {
  return TransactionSpec(
    effects: [_clearHighlightsEffect.of(null)],
  );
}
