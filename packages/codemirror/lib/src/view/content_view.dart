/// Content view - base class for the view tree.
///
/// This module provides the [ContentView] abstract class and supporting
/// types for building the document view tree. In Flutter, this manages
/// the widget tree structure for rendering document content.
library;

import 'package:meta/meta.dart';

import '../text/text.dart';
import 'view_state.dart';

// ============================================================================
// ViewFlag - Bit flags for view node status
// ============================================================================

/// Bit flags for tracking the dirty status of a view node.
abstract final class ViewFlag {
  /// At least one child is dirty.
  static const int childDirty = 1;

  /// The node itself isn't in sync with its child list.
  static const int nodeDirty = 2;

  /// The node's attributes might have changed.
  static const int attrsDirty = 4;

  /// Mask for all dirty flags.
  static const int dirty = 7;

  /// Set temporarily during a doc view update on nodes around composition.
  static const int composition = 8;
}

// ============================================================================
// ContentView - Base class for view tree nodes
// ============================================================================

/// An empty list of content views.
const List<ContentView> noChildren = [];

/// Base class for nodes in the document view tree.
///
/// In the original CodeMirror, this manages DOM nodes. In Flutter, we use
/// this to manage the logical structure of the document view, which maps
/// to Flutter widgets during rendering.
///
/// The view tree mirrors the document structure:
/// - [DocView] at the root
/// - [BlockView] for line blocks
/// - [TextView] for text content
/// - [WidgetView] for embedded widgets
abstract class ContentView {
  /// Parent view in the tree.
  ContentView? parent;

  /// Bit flags for dirty status.
  int flags = ViewFlag.nodeDirty;

  /// The length of content this view represents.
  int get length;

  /// Child views.
  List<ContentView> get children;

  /// Line break after this view (0 or 1).
  int breakAfter = 0;

  /// Override DOM text for composition handling.
  @internal
  Text? get overrideDOMText => null;

  /// Get the position at the start of this view.
  int get posAtStart {
    return parent != null ? parent!.posBefore(this) : 0;
  }

  /// Get the position at the end of this view.
  int get posAtEnd {
    return posAtStart + length;
  }

  /// Get the position before a child view.
  int posBefore(ContentView view) {
    var pos = posAtStart;
    for (final child in children) {
      if (identical(child, view)) return pos;
      pos += child.length + child.breakAfter;
    }
    throw RangeError('Invalid child in posBefore');
  }

  /// Get the position after a child view.
  int posAfter(ContentView view) {
    return posBefore(view) + view.length;
  }

  /// Get coordinates at a position within this view.
  ///
  /// Returns a rectangle directly before (when side < 0), after
  /// (side > 0), or directly on (when supported) the given position.
  EditorRect? coordsAt(int pos, int side);

  /// Synchronize this view with its children.
  ///
  /// In Flutter, this is used to update the widget tree structure.
  void sync(dynamic view, {SyncTrack? track}) {
    if (flags & ViewFlag.nodeDirty != 0) {
      // Full sync - rebuild widget tree
      for (final child in children) {
        if (child.flags & ViewFlag.dirty != 0) {
          child.sync(view, track: track);
          child.flags &= ~ViewFlag.dirty;
        }
      }
    } else if (flags & ViewFlag.childDirty != 0) {
      // Partial sync - only update dirty children
      for (final child in children) {
        if (child.flags & ViewFlag.dirty != 0) {
          child.sync(view, track: track);
          child.flags &= ~ViewFlag.dirty;
        }
      }
    }
  }

  /// Find the local position from an absolute position.
  int localPosFromAbsolute(int absPos) {
    return absPos - posAtStart;
  }

  /// Get bounds around a range within this view's subtree.
  ContentBounds? domBoundsAround(int from, int to, [int offset = 0]) {
    var fromI = -1, fromStart = -1, toI = -1, toEnd = -1;

    for (var i = 0, pos = offset, prevEnd = offset; i < children.length; i++) {
      final child = children[i];
      final end = pos + child.length;

      if (pos < from && end > to) {
        return child.domBoundsAround(from, to, pos);
      }

      if (end >= from && fromI == -1) {
        fromI = i;
        fromStart = pos;
      }

      if (pos > to) {
        toI = i;
        toEnd = prevEnd;
        break;
      }

      prevEnd = end;
      pos = end + child.breakAfter;
    }

    return ContentBounds(
      from: fromStart,
      to: toEnd < 0 ? offset + length : toEnd,
      startIndex: fromI > 0 ? fromI - 1 : 0,
      endIndex: toI < children.length && toI >= 0 ? toI : children.length,
    );
  }

  /// Mark this view as dirty.
  void markDirty([bool andParent = false]) {
    flags |= ViewFlag.nodeDirty;
    markParentsDirty(andParent);
  }

  /// Mark parent views as having dirty children.
  void markParentsDirty(bool childList) {
    for (var parent = this.parent; parent != null; parent = parent.parent) {
      if (childList) parent.flags |= ViewFlag.nodeDirty;
      if (parent.flags & ViewFlag.childDirty != 0) return;
      parent.flags |= ViewFlag.childDirty;
      childList = false;
    }
  }

  /// Set the parent of this view.
  void setParent(ContentView newParent) {
    if (!identical(parent, newParent)) {
      parent = newParent;
      if (flags & ViewFlag.dirty != 0) {
        markParentsDirty(true);
      }
    }
  }

  /// Get the root view of the tree.
  ContentView get rootView {
    var v = this;
    while (true) {
      final p = v.parent;
      if (p == null) return v;
      v = p;
    }
  }

  /// Replace a range of children with new children.
  void replaceChildren(int from, int to, [List<ContentView>? newChildren]) {
    final insertChildren = newChildren ?? noChildren;
    markDirty();

    // Destroy removed children
    for (var i = from; i < to; i++) {
      final child = children[i];
      if (identical(child.parent, this) && !insertChildren.contains(child)) {
        child.destroy();
      }
    }

    // Splice in new children
    if (insertChildren.length < 250) {
      children.replaceRange(from, to, insertChildren);
    } else {
      final newList = <ContentView>[];
      newList.addAll(children.sublist(0, from));
      newList.addAll(insertChildren);
      newList.addAll(children.sublist(to));
      children
        ..clear()
        ..addAll(newList);
    }

    // Set parent for new children
    for (final child in insertChildren) {
      child.setParent(this);
    }
  }

  /// Get a cursor for iterating children from a position.
  ChildCursor childCursor([int? pos]) {
    return ChildCursor(children, pos ?? length, children.length);
  }

  /// Find the child at a position.
  ChildPos childPos(int pos, [int bias = 1]) {
    return childCursor().findPos(pos, bias);
  }

  /// Whether this view is editable.
  bool get isEditable => true;

  /// Whether this view is a widget.
  bool get isWidget => false;

  /// Whether this view is hidden.
  bool get isHidden => false;

  /// Try to merge content from another view.
  bool merge(int from, int to, ContentView? source, bool hasStart,
      int openStart, int openEnd) {
    return false;
  }

  /// Try to become another view (reuse its content).
  bool become(ContentView other) {
    return false;
  }

  /// Check if this view can reuse another view's DOM.
  bool canReuseDOM(ContentView other) {
    return runtimeType == other.runtimeType &&
        !((flags | other.flags) & ViewFlag.composition != 0);
  }

  /// Split this view at a position.
  ContentView split(int at);

  /// Get the side of this view (for zero-length views).
  int getSide() => 0;

  /// Destroy this view and its children.
  void destroy() {
    for (final child in children) {
      if (identical(child.parent, this)) {
        child.destroy();
      }
    }
    parent = null;
  }

  @override
  String toString() {
    final name = runtimeType.toString().replaceAll('View', '');
    if (children.isNotEmpty) {
      return '$name(${children.join(', ')})';
    }
    if (length > 0) {
      return '$name[$length]';
    }
    return name + (breakAfter != 0 ? '#' : '');
  }
}

// ============================================================================
// ChildCursor - For iterating through children
// ============================================================================

/// Cursor for efficiently iterating through children of a content view.
class ChildCursor {
  /// The children list.
  final List<ContentView> children;

  /// Current position.
  int pos;

  /// Current index.
  int i;

  /// Offset within current child.
  int off = 0;

  ChildCursor(this.children, this.pos, this.i);

  /// Find a position within children.
  ChildPos findPos(int pos, [int bias = 1]) {
    while (true) {
      if (pos > this.pos ||
          (pos == this.pos &&
              (bias > 0 || i == 0 || children[i - 1].breakAfter != 0))) {
        off = pos - this.pos;
        return ChildPos(i, off);
      }
      final next = children[--i];
      this.pos -= next.length + next.breakAfter;
    }
  }
}

/// Result of finding a child position.
class ChildPos {
  /// Index of the child.
  final int i;

  /// Offset within the child.
  final int off;

  const ChildPos(this.i, this.off);
}

// ============================================================================
// ContentBounds - Bounds of content within a view
// ============================================================================

/// Bounds of content within a view.
class ContentBounds {
  /// Start position.
  final int from;

  /// End position.
  final int to;

  /// Start child index.
  final int startIndex;

  /// End child index.
  final int endIndex;

  const ContentBounds({
    required this.from,
    required this.to,
    required this.startIndex,
    required this.endIndex,
  });
}

// ============================================================================
// SyncTrack - For tracking sync operations
// ============================================================================

/// Tracks DOM changes during sync for selection handling.
class SyncTrack {
  /// The node being tracked.
  final dynamic node;

  /// Whether it was written to.
  bool written = false;

  SyncTrack(this.node);
}

// ============================================================================
// Helper functions for view manipulation
// ============================================================================

/// Replace a range of content views within a parent.
void replaceRange(
  ContentView parent,
  int fromI,
  int fromOff,
  int toI,
  int toOff,
  List<ContentView> insert,
  int breakAtStart,
  int openStart,
  int openEnd,
) {
  final children = parent.children;
  final before = children.isNotEmpty && fromI < children.length
      ? children[fromI]
      : null;
  final last = insert.isNotEmpty ? insert.last : null;
  final breakAtEnd = last?.breakAfter ?? breakAtStart;

  // Change within a single child
  if (fromI == toI &&
      before != null &&
      breakAtStart == 0 &&
      breakAtEnd == 0 &&
      insert.length < 2 &&
      before.merge(
          fromOff, toOff, insert.isNotEmpty ? last : null, fromOff == 0, openStart, openEnd)) {
    return;
  }

  if (toI < children.length) {
    var after = children[toI];
    // Make sure the end of the child after the update is preserved
    if (toOff < after.length || (after.breakAfter != 0 && last?.breakAfter != 0)) {
      if (fromI == toI) {
        after = after.split(toOff);
        toOff = 0;
      }
      // Try to merge with last replacing element
      if (breakAtEnd == 0 &&
          last != null &&
          after.merge(0, toOff, last, true, 0, openEnd)) {
        insert[insert.length - 1] = after;
      } else {
        if (toOff > 0 || (after.children.isNotEmpty && after.children[0].length == 0)) {
          after.merge(0, toOff, null, false, 0, openEnd);
        }
        insert.add(after);
      }
    } else if (after.breakAfter != 0) {
      if (last != null) {
        last.breakAfter = 1;
      } else {
        breakAtStart = 1;
      }
    }
    toI++;
  }

  if (before != null) {
    before.breakAfter = breakAtStart;
    if (fromOff > 0) {
      if (breakAtStart == 0 &&
          insert.isNotEmpty &&
          before.merge(fromOff, before.length, insert[0], false, openStart, 0)) {
        before.breakAfter = insert.removeAt(0).breakAfter;
      } else if (fromOff < before.length ||
          (before.children.isNotEmpty && before.children.last.length == 0)) {
        before.merge(fromOff, before.length, null, false, openStart, 0);
      }
      fromI++;
    }
  }

  // Try to merge widgets on boundaries
  while (fromI < toI && insert.isNotEmpty) {
    if (children[toI - 1].become(insert.last)) {
      toI--;
      insert.removeLast();
      openEnd = insert.isNotEmpty ? 0 : openStart;
    } else if (children[fromI].become(insert.first)) {
      fromI++;
      insert.removeAt(0);
      openStart = insert.isNotEmpty ? 0 : openEnd;
    } else {
      break;
    }
  }

  if (insert.isEmpty &&
      fromI > 0 &&
      toI < children.length &&
      children[fromI - 1].breakAfter == 0 &&
      children[toI].merge(0, 0, children[fromI - 1], false, openStart, openEnd)) {
    fromI--;
  }

  if (fromI < toI || insert.isNotEmpty) {
    parent.replaceChildren(fromI, toI, insert);
  }
}

/// Merge children into a content view.
void mergeChildrenInto(
  ContentView parent,
  int from,
  int to,
  List<ContentView> insert,
  int openStart,
  int openEnd,
) {
  final cur = parent.childCursor();
  final toPos = cur.findPos(to, 1);
  final toI = toPos.i;
  final toOff = toPos.off;

  final fromPos = cur.findPos(from, -1);
  final fromI = fromPos.i;
  final fromOff = fromPos.off;

  // Calculate delta length for tracking purposes
  // var dLen = from - to;
  // for (final view in insert) {
  //   dLen += view.length;
  // }
  // Note: Would need to update parent.length if tracked separately

  replaceRange(parent, fromI, fromOff, toI, toOff, insert, 0, openStart, openEnd);
}
