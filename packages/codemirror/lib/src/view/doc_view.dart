/// Document view - manages the document content display.
///
/// This module provides [DocView], which manages the view tree for document
/// content. In Flutter, this coordinates widget building and updates.
library;

import 'package:meta/meta.dart';

import '../state/change.dart';
import '../state/range_set.dart';
import 'content_view.dart';
import 'decoration.dart';
import 'editor_view.dart';
import 'view_plugin.dart';
import 'view_state.dart';
import 'view_update.dart';

// ============================================================================
// DocView - Root of the document view tree
// ============================================================================

/// The root view for document content.
///
/// DocView manages the view tree that represents the visible document.
/// It handles:
/// - Updating the view tree when the document changes
/// - Managing decorations that style the content
/// - Tracking which parts of the document are visible
/// - Coordinating with the viewport for virtualized rendering
///
/// ## Architecture
///
/// In Flutter, DocView doesn't directly manage DOM like in CodeMirror.
/// Instead, it maintains a logical view tree that maps to Flutter widgets:
///
/// ```
/// DocView
///   └── BlockView (line 1)
///         └── LineView
///               └── TextView / WidgetView
///   └── BlockView (line 2)
///         ...
/// ```
class DocView extends ContentView {
  /// Children are BlockView instances.
  @override
  final List<ContentView> children = [];

  /// Active decorations for this document.
  List<DecorationSet> decorations = [];

  /// Which decorations are dynamic (functions).
  List<bool> dynamicDecorationMap = [false];

  /// Range being composed via IME.
  ({int from, int to})? hasComposition;

  /// Views marked for composition handling.
  final Set<ContentView> markedForComposition = {};

  /// Edit context formatting decorations.
  DecorationSet editContextFormatting = Decoration.none;

  /// Whether the last composition was after cursor.
  bool lastCompositionAfterCursor = false;

  /// Minimum content width seen.
  double minWidth = 0;

  /// Start of min width range.
  int minWidthFrom = 0;

  /// End of min width range.
  int minWidthTo = 0;

  /// Timestamp of last update.
  int lastUpdate = DateTime.now().millisecondsSinceEpoch;

  /// The view state.
  final ViewState _viewState;

  DocView(this._viewState);

  @override
  int get length => _viewState.state.doc.length;

  /// Initialize the doc view.
  void init() {
    updateDeco();
    updateInner([ChangedRange(0, 0, 0, length)], 0);
  }

  /// Update the document view.
  ///
  /// Returns true if the view was changed.
  bool update(ViewUpdate update) {
    var changedRanges = update.changedRanges;

    // Reset min width tracking if changed ranges touch it
    if (minWidth > 0 && changedRanges.isNotEmpty) {
      final touchesMinWidth = changedRanges.any(
        (r) => r.toA >= minWidthFrom && r.fromA <= minWidthTo,
      );
      if (touchesMinWidth) {
        minWidth = 0;
        minWidthFrom = 0;
        minWidthTo = 0;
      } else {
        minWidthFrom = update.changes.mapPos(minWidthFrom, 1) ?? 0;
        minWidthTo = update.changes.mapPos(minWidthTo, 1) ?? 0;
      }
    }

    // Update edit context formatting
    editContextFormatting = editContextFormatting.map(update.changes);

    // Handle composition
    if (hasComposition != null) {
      markedForComposition.clear();
      final from = hasComposition!.from;
      final to = hasComposition!.to;
      changedRanges = ChangedRange(
        from,
        to,
        update.changes.mapPos(from, -1) ?? from,
        update.changes.mapPos(to, 1) ?? to,
      ).addToSet(List.of(changedRanges));
    }
    hasComposition = null;

    // Update decorations
    final prevDeco = decorations;
    final deco = updateDeco();
    final decoDiff = _findChangedDeco(prevDeco, deco, update.changes);
    changedRanges = ChangedRange.extendWithRanges(changedRanges, decoDiff);

    // Check if anything needs updating
    if ((flags & ViewFlag.dirty) == 0 && changedRanges.isEmpty) {
      return false;
    }

    updateInner(changedRanges, update.startState.doc.length);
    if (update.transactions.isNotEmpty) {
      lastUpdate = DateTime.now().millisecondsSinceEpoch;
    }
    return true;
  }

  /// Internal update method.
  @internal
  void updateInner(List<ChangedRange> changes, int oldLength) {
    _viewState.mustMeasureContent = true;
    updateChildren(changes, oldLength);
    flags &= ~ViewFlag.dirty;
  }

  /// Update child views for changed ranges.
  @internal
  void updateChildren(List<ChangedRange> changes, int oldLength) {
    final cursor = childCursor(oldLength);

    for (var i = changes.length - 1; i >= 0; i--) {
      final range = changes[i];
      // Build content for this range
      // In a full implementation, this would use ContentBuilder
      // to create TextView, WidgetView, etc.

      final toPos = cursor.findPos(range.toA, 1);
      final fromPos = cursor.findPos(range.fromA, -1);

      // For now, mark the range as needing rebuild
      for (var j = fromPos.i; j <= toPos.i && j < children.length; j++) {
        children[j].markDirty(true);
      }
    }
  }

  /// Update the decorations list.
  @internal
  List<DecorationSet> updateDeco() {
    // Get the EditorViewState to access facets
    final view = _viewState as EditorViewState;
    
    // Collect decorations from the decorations facet
    var i = 1;
    final allDeco = <DecorationSet>[];
    
    for (final source in view.state.facet(decorationsFacet)) {
      final bool dynamic;
      final DecorationSet deco;
      
      if (source is RangeSet<Decoration>) {
        dynamic = false;
        deco = source;
      } else if (source is RangeSet<Decoration> Function(EditorViewState)) {
        dynamic = true;
        deco = source(view);
      } else {
        // Unknown type, skip
        continue;
      }
      
      // Track whether this decoration source is dynamic
      while (dynamicDecorationMap.length <= i) {
        dynamicDecorationMap.add(false);
      }
      dynamicDecorationMap[i++] = dynamic;
      allDeco.add(deco);
    }
    
    // Collect outer decorations (higher precedence)
    var dynamicOuter = false;
    final outerDeco = <DecorationSet>[];
    for (final source in view.state.facet(outerDecorationsFacet)) {
      if (source is RangeSet<Decoration>) {
        outerDeco.add(source);
      } else if (source is RangeSet<Decoration> Function(EditorViewState)) {
        dynamicOuter = true;
        outerDeco.add(source(view));
      }
    }
    
    if (outerDeco.isNotEmpty) {
      while (dynamicDecorationMap.length <= i) {
        dynamicDecorationMap.add(false);
      }
      dynamicDecorationMap[i++] = dynamicOuter;
      allDeco.add(RangeSet.join(outerDeco));
    }
    
    // Build final decorations list
    decorations = [
      editContextFormatting,
      ...allDeco,
      computeBlockGapDeco(),
      // TODO: Add lineGapDeco when implemented
    ];
    
    // Ensure dynamicDecorationMap is sized correctly
    while (dynamicDecorationMap.length < decorations.length) {
      dynamicDecorationMap.add(false);
    }
    
    return decorations;
  }

  /// Compute decorations for block gaps (virtualized content).
  @internal
  DecorationSet computeBlockGapDeco() {
    final deco = <Range<Decoration>>[];
    final viewports = _viewState.viewports;

    var pos = 0;
    for (var i = 0;; i++) {
      final next = i < viewports.length ? viewports[i] : null;
      final end = next != null ? next.from - 1 : length;

      if (end > pos) {
        // Create gap decoration
        // In full implementation, this would create a BlockGapWidget
        deco.add(
          Decoration.replace(ReplaceDecorationSpec(
            block: true,
            inclusive: true,
            isBlockGap: true,
          )).range(pos, end),
        );
      }

      if (next == null) break;
      pos = next.to + 1;
    }

    return Decoration.createSet(deco);
  }

  @override
  EditorRect? coordsAt(int pos, int side) {
    // Delegate to the appropriate child
    for (var off = length, i = children.length - 1; i >= 0; i--) {
      final child = children[i];
      final end = off - child.breakAfter;
      final start = end - child.length;

      if (end < pos) break;

      if (start <= pos) {
        final coords = child.coordsAt(pos - start, side);
        if (coords != null) return coords;
      }

      off = start;
    }
    return null;
  }

  @override
  ChildCursor childCursor([int? pos]) {
    // Move back to start of last element when possible
    var i = children.length;
    var currentPos = pos ?? length;
    if (i > 0) {
      currentPos -= children[--i].length;
    }
    return ChildCursor(children, currentPos, i);
  }

  @override
  ContentView split(int at) {
    throw UnsupportedError('DocView cannot be split');
  }

  /// Get the visible line heights for measurement.
  List<double> measureVisibleLineHeights(({int from, int to}) viewport) {
    final result = <double>[];
    final from = viewport.from;
    final to = viewport.to;

    for (var pos = 0, i = 0; i < children.length; i++) {
      final child = children[i];
      final end = pos + child.length;

      if (end > to) break;
      if (pos >= from) {
        // In full implementation, get actual measured height
        result.add(_viewState.heightOracle.lineHeight);
      }

      pos = end + child.breakAfter;
    }

    return result;
  }

  /// Measure text size for height calculations.
  ({double lineHeight, double charWidth, double textHeight}) measureTextSize() {
    // Find a line view to measure
    for (final child in children) {
      if (child is LineView) {
        final measure = child.measureTextSize();
        if (measure != null) return measure;
      }
    }

    // Fall back to height oracle defaults
    return (
      lineHeight: _viewState.heightOracle.lineHeight,
      charWidth: _viewState.heightOracle.charWidth,
      textHeight: _viewState.heightOracle.lineHeight,
    );
  }

  /// Check if a line has embedded widgets.
  bool lineHasWidget(int pos) {
    final result = childCursor().findPos(pos);
    if (result.i >= children.length) return false;

    bool scan(ContentView child) {
      if (child.isWidget) return true;
      return child.children.any(scan);
    }

    return scan(children[result.i]);
  }

  /// Find the nearest content view for a position.
  ContentView? nearest(int pos) {
    final result = childPos(pos);
    if (result.i < children.length) {
      return children[result.i];
    }
    return null;
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Decoration comparator for finding changed ranges.
class _DecorationComparator implements RangeComparator<Decoration> {
  final List<int> changes = [];

  @override
  void compareRange(int from, int to, List<Decoration> activeA, List<Decoration> activeB) {
    addRange(from, to, changes);
  }

  @override
  void comparePoint(int from, int to, Decoration? pointA, Decoration? pointB) {
    addRange(from, to, changes);
  }

  @override
  void boundChange(int pos) {
    addRange(pos, pos, changes);
  }
}

/// Find ranges where decorations differ.
List<int> _findChangedDeco(
  List<DecorationSet> a,
  List<DecorationSet> b,
  ChangeSet diff,
) {
  final comp = _DecorationComparator();
  RangeSet.compare(a, b, textDiff: diff, comparator: comp);
  return comp.changes;
}

// ============================================================================
// LineView - Represents a line of text
// ============================================================================

/// A view representing a single line of text.
///
/// LineView is a container for the inline content of a line, including
/// text spans and inline widgets.
class LineView extends ContentView {
  @override
  final List<ContentView> children = [];

  @override
  int length = 0;

  @override
  EditorRect? coordsAt(int pos, int side) {
    // Delegate to children
    for (final child in children) {
      if (pos <= child.length) {
        return child.coordsAt(pos, side);
      }
      pos -= child.length;
    }
    return null;
  }

  @override
  ContentView split(int at) {
    final newLine = LineView();
    var pos = 0;
    var splitIndex = 0;

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final end = pos + child.length;

      if (end > at) {
        if (pos < at) {
          // Split this child
          final after = child.split(at - pos);
          newLine.children.add(after);
          after.setParent(newLine);
          newLine.length += after.length;
        } else {
          // Move whole child
          newLine.children.add(child);
          child.setParent(newLine);
          newLine.length += child.length;
        }
        if (splitIndex == 0) splitIndex = i;
      }

      pos = end;
    }

    if (splitIndex > 0) {
      length = at;
      children.removeRange(splitIndex, children.length);
    }

    return newLine;
  }

  /// Append content to this line.
  void append(ContentView content, int openStart) {
    children.add(content);
    content.setParent(this);
    length += content.length;
  }

  /// Measure text size using this line's content.
  ({double lineHeight, double charWidth, double textHeight})? measureTextSize() {
    // In full implementation, measure using actual rendered content
    return null;
  }

  /// Find a line view containing a position.
  static LineView? find(ContentView parent, int pos) {
    for (final child in parent.children) {
      if (child is LineView) {
        if (pos <= child.length) return child;
        pos -= child.length + child.breakAfter;
      } else {
        final found = find(child, pos);
        if (found != null) return found;
        pos -= child.length + child.breakAfter;
      }
    }
    return null;
  }
}

// ============================================================================
// TextView - Represents a span of text
// ============================================================================

/// A view representing a span of plain text.
class TextView extends ContentView {
  /// The text content.
  String text;

  TextView(this.text);

  @override
  int get length => text.length;

  @override
  List<ContentView> get children => noChildren;

  @override
  EditorRect? coordsAt(int pos, int side) {
    // In full implementation, calculate coordinates
    return null;
  }

  @override
  ContentView split(int at) {
    final after = TextView(text.substring(at));
    text = text.substring(0, at);
    return after;
  }

  @override
  bool merge(int from, int to, ContentView? source, bool hasStart,
      int openStart, int openEnd) {
    if (source is! TextView) return false;
    text = text.substring(0, from) + source.text + text.substring(to);
    return true;
  }

  @override
  String toString() => 'Text[$text]';
}

// ============================================================================
// MarkView - Represents styled content
// ============================================================================

/// A view representing styled (marked) content.
class MarkView extends ContentView {
  /// The mark decoration.
  final MarkDecoration mark;

  @override
  final List<ContentView> children;

  @override
  int length;

  MarkView(this.mark, this.children, this.length) {
    for (final child in children) {
      child.setParent(this);
    }
  }

  @override
  EditorRect? coordsAt(int pos, int side) {
    for (final child in children) {
      if (pos <= child.length) {
        return child.coordsAt(pos, side);
      }
      pos -= child.length;
    }
    return null;
  }

  @override
  ContentView split(int at) {
    final newChildren = <ContentView>[];
    var newLength = 0;
    var pos = 0;

    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final end = pos + child.length;

      if (end > at) {
        if (pos < at) {
          final after = child.split(at - pos);
          newChildren.add(after);
          newLength += after.length;
        } else {
          newChildren.add(child);
          newLength += child.length;
        }
      }

      pos = end;
    }

    final newMark = MarkView(mark, newChildren, newLength);
    length = at;
    return newMark;
  }
}

// ============================================================================
// WidgetView - Represents an embedded widget
// ============================================================================

/// A view representing an embedded widget.
class WidgetView extends ContentView {
  /// The widget type.
  final WidgetType widget;

  /// Widget length (usually 0 for inline, or the replaced range length).
  @override
  final int length;

  /// Whether this is a block widget.
  final bool block;

  /// Side for zero-length widgets.
  final int side;

  WidgetView(this.widget, {this.length = 0, this.block = false, this.side = 0});

  @override
  List<ContentView> get children => noChildren;

  @override
  bool get isWidget => true;

  @override
  bool get isHidden => widget.isHidden;

  @override
  EditorRect? coordsAt(int pos, int side) {
    // In full implementation, get widget coordinates
    return null;
  }

  @override
  ContentView split(int at) {
    throw UnsupportedError('WidgetView cannot be split');
  }

  @override
  int getSide() => side;

  @override
  bool become(ContentView other) {
    if (other is WidgetView && widget.compare(other.widget) && block == other.block) {
      return true;
    }
    return false;
  }
}
