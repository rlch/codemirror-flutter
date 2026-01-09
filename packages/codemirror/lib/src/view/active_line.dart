/// Active line highlighting extension.
///
/// This module provides [highlightActiveLine], an extension that marks
/// lines containing a cursor with a background highlight.
library;

import 'package:flutter/widgets.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import 'block_info.dart';
import 'theme.dart' show editorTheme;

// ============================================================================
// Facet for active line highlighting
// ============================================================================

/// Facet that enables active line highlighting.
///
/// When this facet has a true value, the editor will highlight the
/// line(s) containing cursor(s).
final Facet<bool, bool> showActiveLine = Facet.define(FacetConfig(
  combine: (values) => values.isNotEmpty && values.any((v) => v),
));

// ============================================================================
// highlightActiveLine() - Extension factory
// ============================================================================

/// Mark lines that have a cursor on them with a background highlight.
///
/// ## Example
///
/// ```dart
/// EditorState.create(EditorStateConfig(
///   extensions: highlightActiveLine(),
/// ))
/// ```
///
/// This works in combination with [highlightActiveLineGutter] from
/// the gutter module to provide complete active line highlighting.
Extension highlightActiveLine() {
  return showActiveLine.of(true);
}

// ============================================================================
// ActiveLineBackground - Widget that paints active line backgrounds
// ============================================================================

/// A widget that paints active line background highlights.
///
/// This should be positioned behind the text content. It builds a Column
/// with one row per line, matching the structure of the gutter for alignment.
/// 
/// When [lineBlocks] is provided (from measured line heights), the heights
/// will account for soft-wrapped lines. Otherwise falls back to [lineHeight].
class ActiveLineBackground extends StatelessWidget {
  /// The editor state.
  final EditorState state;

  /// The fixed line height (fallback when lineBlocks is not provided).
  final double lineHeight;

  /// Optional line blocks with measured heights for soft-wrapping support.
  final List<BlockInfo>? lineBlocks;

  /// Background color for active lines.
  final Color? color;

  const ActiveLineBackground({
    super.key,
    required this.state,
    this.lineHeight = 20.0,
    this.lineBlocks,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Check if active line highlighting is enabled
    final enabled = state.facet(showActiveLine);
    if (!enabled) return const SizedBox.shrink();

    // Get the active line color from theme
    final theme = state.facet(editorTheme);
    final activeColor = color ?? theme.activeLineColor;
    if (activeColor == null) return const SizedBox.shrink();

    // Get the set of line numbers that have cursors (1-indexed)
    final activeLineNumbers = <int>{};
    for (final range in state.selection.ranges) {
      final lineNum = state.doc.lineAt(range.head).number;
      activeLineNumbers.add(lineNum);
    }

    // Build a Column with one row per line in the document
    final totalLines = state.doc.lines;
    final blocks = lineBlocks;
    
    // Use OverflowBox to allow unconstrained layout, then clip
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var lineNum = 1; lineNum <= totalLines; lineNum++)
              Container(
                // Use measured height from lineBlocks if available, else fixed height
                height: (blocks != null && lineNum <= blocks.length)
                    ? blocks[lineNum - 1].height
                    : lineHeight,
                color: activeLineNumbers.contains(lineNum) ? activeColor : null,
              ),
          ],
        ),
      ),
    );
  }
}
