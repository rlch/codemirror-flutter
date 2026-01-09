/// View state - manages viewport, scroll position, and height tracking.
///
/// This module provides [ViewState], which tracks the viewport, scroll
/// position, and height information for efficient rendering of large documents.
library;

import 'dart:math' as math;
import 'package:meta/meta.dart';

import '../state/state.dart';
import '../text/text.dart';
import 'block_info.dart';
import 'height_map.dart';
import 'view_update.dart';
import 'viewport.dart';

// ============================================================================
// ViewState - Manages the view's viewport and scroll state
// ============================================================================

/// Manages viewport, scroll position, and height calculations.
///
/// This class tracks what portion of the document is visible and maintains
/// height information for efficient virtualized rendering.
class ViewState {
  /// The current editor state.
  EditorState state;

  // ============================================================================
  // Viewport state
  // ============================================================================

  /// The main viewport (visible document range).
  Viewport _viewport = const Viewport.empty();

  /// All viewports (main + selection viewports).
  List<Viewport> _viewports = [];

  /// Pixel bounds of the visible area.
  EditorRect pixelViewport = const EditorRect(left: 0, right: 800, top: 0, bottom: 600);

  /// Whether the editor is currently in view.
  bool inView = true;

  /// Ranges within the viewport that are actually visible.
  List<({int from, int to})> visibleRanges = [];

  // ============================================================================
  // Scroll state
  // ============================================================================

  /// Current scroll top position (scaled).
  double scrollTop = 0;

  /// Whether scrolled to the bottom.
  bool scrolledToBottom = false;

  /// Position used as scroll anchor.
  int scrollAnchorPos = 0;

  /// Height at the anchor position.
  double scrollAnchorHeight = -1;

  /// Target to scroll to, if any.
  ScrollTarget? scrollTarget;

  // ============================================================================
  // Geometry
  // ============================================================================

  /// Padding above the document (scaled).
  double paddingTop = 0;

  /// Padding below the document (scaled).
  double paddingBottom = 0;

  /// Width of the content DOM.
  double contentDOMWidth = 0;

  /// Height of the content DOM.
  double contentDOMHeight = 0;

  /// Editor viewport height.
  double editorHeight = 0;

  /// Editor viewport width.
  double editorWidth = 0;

  /// CSS transform scale X.
  double scaleX = 1;

  /// CSS transform scale Y.
  double scaleY = 1;

  // ============================================================================
  // Height tracking
  // ============================================================================

  /// Oracle for estimating line heights.
  late final HeightOracle heightOracle;

  /// Height map tracking document heights.
  late HeightMap heightMap;

  /// Lines within the viewport.
  List<BlockInfo> viewportLines = [];

  // ============================================================================
  // Flags
  // ============================================================================

  /// Whether content needs to be measured.
  bool mustMeasureContent = true;

  /// Whether cursor association needs to be enforced.
  bool mustEnforceCursorAssoc = false;

  /// Whether printing is in progress.
  bool printing = false;

  // ============================================================================
  // Constructor
  // ============================================================================

  ViewState(this.state) {
    // Check if line wrapping is configured
    // In full impl, check contentAttributes facet for cm-lineWrapping class
    final guessWrapping = false; // Will be computed from facets

    heightOracle = HeightOracle(guessWrapping);
    heightOracle.setDoc(state.doc);

    // Create initial height map and apply changes to set document length
    // This matches the JS: HeightMap.empty().applyChanges(..., [new ChangedRange(0, 0, 0, state.doc.length)])
    heightMap = HeightMap.empty().applyChanges(
      [], // decorations
      Text.empty, // oldDoc
      heightOracle,
      [ChangedRange(0, 0, 0, state.doc.length)], // Initial "insert" of full document
    );

    // Initialize viewport
    _viewport = _getViewport(0, null);
    _updateForViewport();
    _updateViewportLines();
    _computeVisibleRanges();
  }

  // ============================================================================
  // Public getters
  // ============================================================================

  /// The current viewport.
  Viewport get viewport => _viewport;

  /// All viewports including selection viewports.
  List<Viewport> get viewports => _viewports;

  /// The visible top position in document coordinates.
  double get visibleTop => pixelViewport.top;

  /// The visible bottom position in document coordinates.
  double get visibleBottom => pixelViewport.bottom;

  /// Total document height.
  double get docHeight => heightMap.height;

  /// Total content height (doc + padding).
  double get contentHeight => docHeight + paddingTop + paddingBottom;

  // ============================================================================
  // Update methods
  // ============================================================================

  /// Update the view state for a view update.
  void update(ViewUpdate update, [ScrollTarget? scrollTarget]) {
    state = update.state;

    // Map scroll anchor through changes
    if (!scrolledToBottom && scrollAnchorHeight >= 0) {
      scrollAnchorPos = update.changes.mapPos(scrollAnchorPos, -1) ?? scrollAnchorPos;
    } else {
      scrollAnchorPos = -1;
      scrollAnchorHeight = heightMap.height;
    }

    // Update height map for content changes
    final prevHeight = heightMap.height;
    // In full impl: apply decoration changes to height map
    if (heightMap.height != prevHeight) {
      update.flags |= UpdateFlag.height;
    }

    // Update viewport
    var newViewport = _mapViewport(_viewport, update.changes);
    if (scrollTarget != null &&
        (scrollTarget.range is int &&
                ((scrollTarget.range as int) < newViewport.from ||
                    (scrollTarget.range as int) > newViewport.to) ||
            !_viewportIsAppropriate(newViewport))) {
      newViewport = _getViewport(0, scrollTarget);
    }

    final viewportChange =
        newViewport.from != _viewport.from || newViewport.to != _viewport.to;
    _viewport = newViewport;
    _updateForViewport();

    if (viewportChange ||
        !update.changes.empty ||
        (update.flags & UpdateFlag.height) != 0) {
      _updateViewportLines();
    }

    update.flags |= _computeVisibleRanges(update.changes);

    if (scrollTarget != null) {
      this.scrollTarget = scrollTarget;
    }

    // Check for cursor association enforcement
    if (!mustEnforceCursorAssoc &&
        update.selectionSet &&
        state.selection.main.empty &&
        state.selection.main.assoc != 0) {
      mustEnforceCursorAssoc = true;
    }
  }

  // ============================================================================
  // Viewport management
  // ============================================================================

  /// Get the viewport for the current scroll position.
  Viewport _getViewport(double bias, ScrollTarget? scrollTarget) {
    // Calculate margin distribution based on bias
    final marginTop = 0.5 - math.max(-0.5, math.min(0.5, bias / VP.margin / 2));
    final topMargin = VP.margin * marginTop;
    final bottomMargin = VP.margin * (1 - marginTop);

    // Find the document positions for the visible range
    final visTop = visibleTop - topMargin;
    final visBottom = visibleBottom + bottomMargin;

    var from = heightMap
        .lineAt(math.max(0, visTop), QueryType.byHeight, heightOracle, 0, 0)
        .from;
    var to = heightMap
        .lineAt(visBottom, QueryType.byHeight, heightOracle, 0, 0)
        .to;

    // If scroll target is set, ensure it's in viewport
    if (scrollTarget != null && scrollTarget.range is int) {
      final head = scrollTarget.range as int;
      if (head < from || head > to) {
        // Adjust viewport to include scroll target
        final viewHeight = editorHeight > 0
            ? editorHeight
            : (pixelViewport.bottom - pixelViewport.top);
        final block =
            heightMap.lineAt(head, QueryType.byPos, heightOracle, 0, 0);

        double topPos;
        if (scrollTarget.y == 'center') {
          topPos = (block.top + block.bottom) / 2 - viewHeight / 2;
        } else if (scrollTarget.y == 'start' ||
            (scrollTarget.y == 'nearest' && head < from)) {
          topPos = block.top;
        } else {
          topPos = block.bottom - viewHeight;
        }

        from = heightMap
            .lineAt(topPos - VP.margin / 2, QueryType.byHeight, heightOracle,
                0, 0)
            .from;
        to = heightMap
            .lineAt(topPos + viewHeight + VP.margin / 2, QueryType.byHeight,
                heightOracle, 0, 0)
            .to;
      }
    }

    return Viewport(from, math.min(state.doc.length, to));
  }

  /// Map a viewport through document changes.
  Viewport _mapViewport(Viewport vp, Object changes) {
    // In full impl, map positions through ChangeSet
    // For now, just return the viewport
    return vp;
  }

  /// Check if the viewport is appropriate for the current scroll position.
  bool _viewportIsAppropriate(Viewport vp, [double bias = 0]) {
    if (!inView) return true;

    final top = heightMap
        .lineAt(vp.from, QueryType.byPos, heightOracle, 0, 0)
        .top;
    final bottom = heightMap
        .lineAt(vp.to, QueryType.byPos, heightOracle, 0, 0)
        .bottom;

    return (vp.from == 0 ||
            top <=
                visibleTop -
                    math.max(
                        VP.minCoverMargin, math.min(-bias, VP.maxCoverMargin))) &&
        (vp.to == state.doc.length ||
            bottom >=
                visibleBottom +
                    math.max(
                        VP.minCoverMargin, math.min(bias, VP.maxCoverMargin))) &&
        (top > visibleTop - 2 * VP.margin &&
            bottom < visibleBottom + 2 * VP.margin);
  }

  /// Update viewports for the current selection.
  void _updateForViewport() {
    final viewports = [_viewport];
    final main = state.selection.main;

    // Add extra viewports for selection endpoints outside main viewport
    for (var i = 0; i <= 1; i++) {
      final pos = i == 0 ? main.anchor : main.head;
      if (!viewports.any((vp) => pos >= vp.from && pos <= vp.to)) {
        final block =
            heightMap.lineAt(pos, QueryType.byPos, heightOracle, 0, 0);
        viewports.add(Viewport(block.from, block.to));
      }
    }

    viewports.sort((a, b) => a.from - b.from);
    _viewports = viewports;
  }

  /// Update the list of viewport lines.
  void _updateViewportLines() {
    viewportLines = [];
    heightMap.forEachLine(
      _viewport.from,
      _viewport.to,
      heightOracle.setDoc(state.doc),
      0,
      0,
      (block) => viewportLines.add(block),
    );
  }

  /// Compute the visible ranges within the viewport.
  int _computeVisibleRanges([Object? changes]) {
    // In full impl: compute ranges not covered by decorations
    // For now, just use the whole viewport
    final newRanges = [
      (from: _viewport.from, to: _viewport.to),
    ];

    var changed = 0;
    if (newRanges.length != visibleRanges.length) {
      changed = UpdateFlag.viewportMoved | UpdateFlag.viewport;
    } else {
      for (var i = 0; i < newRanges.length && (changed & UpdateFlag.viewportMoved) == 0; i++) {
        if (visibleRanges[i].from != newRanges[i].from ||
            visibleRanges[i].to != newRanges[i].to) {
          changed |= UpdateFlag.viewport;
        }
      }
    }

    visibleRanges = newRanges;
    return changed;
  }

  // ============================================================================
  // Block queries
  // ============================================================================

  /// Get the block info for a given position.
  BlockInfo lineBlockAt(int pos) {
    // First check viewport lines
    if (pos >= _viewport.from && pos <= _viewport.to) {
      final line = viewportLines.cast<BlockInfo?>().firstWhere(
            (b) => b!.from <= pos && b.to >= pos,
            orElse: () => null,
          );
      if (line != null) return line;
    }

    // Fall back to height map
    return heightMap.lineAt(pos, QueryType.byPos, heightOracle, 0, 0);
  }

  /// Get the block info at a given height.
  BlockInfo lineBlockAtHeight(double height) {
    // First check viewport lines
    if (viewportLines.isNotEmpty &&
        height >= viewportLines.first.top &&
        height <= viewportLines.last.bottom) {
      final line = viewportLines.cast<BlockInfo?>().firstWhere(
            (l) => l!.top <= height && l.bottom >= height,
            orElse: () => null,
          );
      if (line != null) return line;
    }

    // Fall back to height map
    return heightMap.lineAt(height, QueryType.byHeight, heightOracle, 0, 0);
  }

  /// Get a scroll anchor at the given scroll position.
  BlockInfo scrollAnchorAt(double scrollTop) {
    final block = lineBlockAtHeight(scrollTop + 8);
    return block.from >= _viewport.from || viewportLines.isEmpty
        ? block
        : viewportLines.first;
  }

  /// Get the element (block) at a given height.
  BlockInfo elementAtHeight(double height) {
    return heightMap.blockAt(height, heightOracle, 0, 0);
  }
}

// ============================================================================
// Rect - A simple rectangle helper
// ============================================================================

/// A simple rectangle with left, right, top, bottom bounds.
///
/// Named `EditorRect` to avoid conflict with Flutter's `Rect` class.
@immutable
class EditorRect {
  final double left;
  final double right;
  final double top;
  final double bottom;

  const EditorRect({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;

  @override
  String toString() => 'EditorRect($left, $top, $right, $bottom)';
}
