/// Syntax node interfaces and implementations.
///
/// This module provides [SyntaxNode] and [SyntaxNodeRef] interfaces for
/// working with syntax tree nodes.
library;

import 'package:meta/meta.dart';

import 'iter_mode.dart';
import 'node_prop.dart';
import 'node_type.dart';
import 'tree.dart';
import 'tree_buffer.dart';
import 'tree_cursor.dart';

/// A syntax node ref provides access to a node's properties without
/// necessarily holding a reference to the node itself.
///
/// Used by [TreeCursor] which can act as a [SyntaxNodeRef].
abstract class SyntaxNodeRef {
  /// The start position of this node.
  int get from;

  /// The end position of this node.
  int get to;

  /// The type of this node.
  NodeType get type;

  /// The name of this node's type.
  String get name => type.name;

  /// The [Tree] object for this node, if it is a tree.
  Tree? get tree;
  
  /// Retrieve a stable [SyntaxNode] at this position.
  SyntaxNode get node;

  /// Match this node's context against a list of parent names.
  bool matchContext(List<String> context);
}

/// A syntax node represents a specific node in a syntax tree.
///
/// It provides navigation to related nodes (parent, children, siblings)
/// and access to the node's properties.
abstract class SyntaxNode implements SyntaxNodeRef {
  /// The parent of this node, if any.
  SyntaxNode? get parent;

  /// The first child of this node, if any.
  SyntaxNode? get firstChild;

  /// The last child of this node, if any.
  SyntaxNode? get lastChild;

  /// The first child that ends after [pos], if any.
  SyntaxNode? childAfter(int pos);

  /// The last child that starts before [pos], if any.
  SyntaxNode? childBefore(int pos);

  /// Enter the child at [pos], or return null if none exists.
  SyntaxNode? enter(int pos, int side, {IterMode mode});

  /// The next sibling of this node, if any.
  SyntaxNode? get nextSibling;

  /// The previous sibling of this node, if any.
  SyntaxNode? get prevSibling;

  /// Resolve the innermost node at [pos].
  SyntaxNode resolve(int pos, [int side = 0]);

  /// Resolve the innermost node at [pos], entering overlays.
  SyntaxNode resolveInner(int pos, [int side = 0]);

  /// Enter any unfinished nodes at the given position.
  SyntaxNode enterUnfinishedNodesBefore(int pos);

  /// Convert to a tree node.
  Tree toTree();

  /// Get a prop from this node.
  T? prop<T>(NodeProp<T> prop);

  /// Get the node for direct access to sibling navigation.
  @internal
  int get index;

  /// Get a cursor positioned at this node.
  TreeCursor cursor([IterMode mode = IterMode.none]);
  
  /// Get the first child with the given type, optionally after a specific node
  /// and before another.
  /// 
  /// [type] can be a node name or group name.
  /// If [before] is provided, only children after the first match of [before] are included.
  /// If [after] is provided, only children before the first match of [after] are included.
  SyntaxNode? getChild(String type, [String? before, String? after]);

  /// Get all children matching a type or group name.
  ///
  /// [type] can be a node name or group name.
  /// If [before] is provided, only children after the first match of [before] are included.
  /// If [after] is provided, only children before the first match of [after] are included.
  List<SyntaxNode> getChildren(String type, [String? before, String? after]);
}

/// Mixin that provides default implementations for getChild/getChildren.
mixin SyntaxNodeMixin implements SyntaxNode {
  @override
  SyntaxNode? getChild(String type, [String? before, String? after]) {
    final children = getChildren(type, before, after);
    return children.isEmpty ? null : children.first;
  }

  @override
  List<SyntaxNode> getChildren(String type, [String? before, String? after]) {
    final cur = cursor();
    final result = <SyntaxNode>[];
    if (!cur.firstChild()) return result;
    
    if (before != null) {
      var found = false;
      while (!found) {
        found = cur.type.is_(before);
        if (!cur.nextSibling()) return result;
      }
    }
    
    while (true) {
      if (after != null && cur.type.is_(after)) return result;
      if (cur.type.is_(type)) result.add(cur.node);
      if (!cur.nextSibling()) return after == null ? result : [];
    }
  }
}

/// A syntax node backed by a [Tree].
class TreeNode with SyntaxNodeMixin implements SyntaxNode {
  /// The tree backing this node.
  final Tree _tree;

  /// Offset in the document.
  final int _from;

  /// Index in parent's children list.
  @override
  final int index;

  /// Parent tree node.
  final TreeNode? _parent;

  TreeNode(this._tree, this._from, this.index, this._parent);

  @override
  NodeType get type => _tree.type;

  @override
  String get name => type.name;

  @override
  int get from => _from;

  @override
  int get to => _from + _tree.length;

  @override
  Tree? get tree => _tree;

  @override
  SyntaxNode? get parent => _parent;

  @override
  SyntaxNode? get firstChild =>
      nextChild(0, 1, 0, Side.dontCare, IterMode.none);

  @override
  SyntaxNode? get lastChild =>
      nextChild(_tree.children.length - 1, -1, 0, Side.dontCare, IterMode.none);

  @override
  SyntaxNode? childAfter(int pos) =>
      nextChild(0, 1, pos, Side.after, IterMode.none);

  @override
  SyntaxNode? childBefore(int pos) =>
      nextChild(_tree.children.length - 1, -1, pos, Side.before, IterMode.none);

  @override
  SyntaxNode? enter(int pos, int side, {IterMode mode = IterMode.none}) {
    final mounted = MountedTree.get(_tree);
    if (mounted != null && !mode.hasFlag(IterMode.ignoreMounts)) {
      if (mounted.overlay != null) {
        // Handle overlay mounts
        if (!mode.hasFlag(IterMode.ignoreOverlays)) {
          for (final range in mounted.overlay!) {
            if (pos >= range.from + _from && pos <= range.to + _from) {
              // Enter the mounted tree at the overlaid position
              final inner = TreeNode(
                mounted.tree,
                range.from + _from,
                0,
                this,
              );
              return inner.enter(pos, side, mode: mode);
            }
          }
        }
      } else {
        // Full mount - replace this node
        final inner = TreeNode(mounted.tree, _from, index, _parent);
        return inner.enter(pos, side, mode: mode);
      }
    }

    // TypeScript always passes 0, 1 for starting index and direction
    // The side parameter is used by Side.check to filter children
    return nextChild(0, 1, pos, side, mode);
  }

  @internal
  SyntaxNode? nextChild(
      int i, int dir, int pos, int side, IterMode mode) {
    TreeNode parent = this;
    
    // Outer loop - climbs up through anonymous parents when children exhausted
    for (;;) {
      final tree = parent._tree;
      final children = tree.children;
      final positions = tree.positions;
      final e = dir > 0 ? children.length : -1;
      
      for (; i != e; i += dir) {
        if (i < 0 || i >= children.length) break;
        
        final child = children[i];
        final childStart = positions[i] + parent._from;
        final childEnd = childStart +
            (child is Tree ? child.length : (child as TreeBuffer).length);

        // Check if child matches position criteria
        if (!Side.check(side, pos, childStart, childEnd)) continue;

        if (child is TreeBuffer) {
          if (!mode.hasFlag(IterMode.excludeBuffers)) {
            // Return a buffer node
            final context = BufferContext(child, parent, i, childStart);
            final bufferChild = context.findChild(0, child.buffer.length, dir, pos, side);
            if (bufferChild >= 0) {
              return BufferNode(context, null, bufferChild);
            }
          }
        } else {
          final treeChild = child as Tree;
          if (!treeChild.type.isAnonymous ||
              mode.hasFlag(IterMode.includeAnonymous)) {
            return TreeNode(treeChild, childStart, i, parent);
          } else {
            // Recurse into anonymous node
            final inner = TreeNode(treeChild, childStart, i, parent);
            final result = inner.nextChild(
              dir > 0 ? 0 : treeChild.children.length - 1,
              dir,
              pos,
              side,
              mode,
            );
            if (result != null) return result;
          }
        }
      }
      
      // Children exhausted - check if we should climb to parent
      if (mode.hasFlag(IterMode.includeAnonymous) || !parent.type.isAnonymous) {
        return null;
      }
      
      // Climb up to parent and continue scanning from parent's position
      if (parent.index >= 0) {
        i = parent.index + dir;
      } else {
        i = dir < 0 ? -1 : (parent._parent?._tree.children.length ?? 0);
      }
      final grandParent = parent._parent;
      if (grandParent == null) return null;
      parent = grandParent;
    }
  }

  @override
  SyntaxNode? get nextSibling {
    return _parent?.nextChild(index + 1, 1, 0, Side.dontCare, IterMode.none);
  }

  @override
  SyntaxNode? get prevSibling {
    return _parent?.nextChild(index - 1, -1, 0, Side.dontCare, IterMode.none);
  }

  @override
  SyntaxNode resolve(int pos, [int side = 0]) {
    return _resolveNode(this, pos, side, false);
  }

  @override
  SyntaxNode resolveInner(int pos, [int side = 0]) {
    return _resolveNode(this, pos, side, true);
  }

  @override
  SyntaxNode enterUnfinishedNodesBefore(int pos) {
    var scan = firstChild;
    SyntaxNode? result = this;
    while (scan != null) {
      if (scan.to == pos) {
        result = scan;
        scan = scan.lastChild;
      } else if (scan.from < pos) {
        scan = scan.nextSibling;
      } else {
        break;
      }
    }
    return result!;
  }

  @override
  Tree toTree() => _tree;

  @override
  T? prop<T>(NodeProp<T> prop) => _tree.prop(prop);

  @override
  bool matchContext(List<String> context) {
    return _matchNodeContext(parent, context, context.length - 1);
  }

  @override
  TreeCursor cursor([IterMode mode = IterMode.none]) {
    return TreeCursor.fromNode(this, mode);
  }

  @override
  SyntaxNode get node => this;

  @override
  String toString() =>
      '${type.name}($from..$to)${_tree.children.isEmpty ? '' : '...'}';
}

/// Context for a buffer node.
class BufferContext {
  final TreeBuffer buffer;
  final TreeNode parent;
  final int index;
  /// The document position where this buffer starts.
  final int start;

  BufferContext(this.buffer, this.parent, this.index, this.start);

  /// Find a child in the buffer.
  int findChild(int from, int to, int dir, int pos, int side) {
    return buffer.findChild(from, to, dir, pos - start, side);
  }
}

/// A syntax node backed by a [TreeBuffer].
class BufferNode with SyntaxNodeMixin implements SyntaxNode {
  /// The buffer context.
  final BufferContext context;

  /// Parent buffer node.
  @internal
  final BufferNode? bufferParent;

  /// Index in the buffer.
  @override
  final int index;

  BufferNode(this.context, this.bufferParent, this.index);

  @override
  NodeType get type {
    return context.buffer.set.types[context.buffer.buffer[index]];
  }

  @override
  String get name => type.name;

  @override
  int get from => context.buffer.buffer[index + 1] + context.start;

  @override
  int get to => context.buffer.buffer[index + 2] + context.start;

  @override
  Tree? get tree => null;

  /// The endIndex for this node - points to the next sibling in the buffer.
  int get _endIndex => context.buffer.buffer[index + 3];

  @override
  SyntaxNode? get parent => bufferParent ?? context.parent;

  @override
  SyntaxNode? get firstChild {
    // No children if endIndex points right after this node's header
    if (_endIndex <= index + 4) return null;
    return BufferNode(context, this, index + 4);
  }

  @override
  SyntaxNode? get lastChild {
    if (_endIndex <= index + 4) return null;
    return _findChild(index + 4, _endIndex, -1, 0, Side.dontCare);
  }

  @override
  SyntaxNode? childAfter(int pos) {
    if (_endIndex <= index + 4) return null;
    return _findChild(index + 4, _endIndex, 1, pos, Side.after);
  }

  @override
  SyntaxNode? childBefore(int pos) {
    if (_endIndex <= index + 4) return null;
    return _findChild(index + 4, _endIndex, -1, pos, Side.before);
  }

  SyntaxNode? _findChild(int from, int to, int dir, int pos, int side) {
    // Adjust position to buffer-relative coordinates
    // context.start is where this buffer starts in the document
    final adjustedPos = pos - context.start;
    final found = context.buffer.findChild(from, to, dir, adjustedPos, side);
    return found >= 0 ? BufferNode(context, this, found) : null;
  }

  @override
  SyntaxNode? enter(int pos, int side, {IterMode mode = IterMode.none}) {
    if (_endIndex <= index + 4) return null;
    // TypeScript: side > 0 ? 1 : -1
    return _findChild(
      index + 4,
      _endIndex,
      side > 0 ? 1 : -1,
      pos,
      side,
    );
  }

  /// Get a sibling from outside this buffer (in the tree).
  SyntaxNode? _externalSibling(int dir) {
    // If we have a parent within the buffer, we can't get external siblings
    if (bufferParent != null) return null;
    // Ask the tree parent for the next/prev child after/before this buffer
    return context.parent.nextChild(context.index + dir, dir, 0, Side.dontCare, IterMode.none);
  }

  @override
  SyntaxNode? get nextSibling {
    final buf = context.buffer;
    final after = buf.buffer[index + 3]; // endIndex points to next sibling position
    final parentEnd = bufferParent != null 
        ? buf.buffer[bufferParent!.index + 3] 
        : buf.buffer.length;
    if (after < parentEnd) {
      return BufferNode(context, bufferParent, after);
    }
    return _externalSibling(1);
  }

  @override
  SyntaxNode? get prevSibling {
    final buf = context.buffer;
    final parentStart = bufferParent != null ? bufferParent!.index + 4 : 0;
    if (index == parentStart) {
      return _externalSibling(-1);
    }
    // Find previous sibling by scanning forward from parent start
    final found = buf.findChild(parentStart, index, -1, 0, Side.dontCare);
    return found >= 0 ? BufferNode(context, bufferParent, found) : null;
  }

  @override
  SyntaxNode resolve(int pos, [int side = 0]) {
    return _resolveNode(context.parent, pos, side, false);
  }

  @override
  SyntaxNode resolveInner(int pos, [int side = 0]) {
    return _resolveNode(context.parent, pos, side, true);
  }

  @override
  SyntaxNode enterUnfinishedNodesBefore(int pos) {
    // Buffer nodes can't have unfinished nodes
    return this;
  }

  @override
  Tree toTree() {
    // Convert buffer node to a tree
    final children = <Object>[];
    final positions = <int>[];

    var child = firstChild;
    while (child != null) {
      children.add(child.toTree());
      positions.add(child.from - from);
      child = child.nextSibling;
    }

    return Tree(type, children, positions, to - from);
  }

  @override
  T? prop<T>(NodeProp<T> prop) => type.prop(prop);

  @override
  bool matchContext(List<String> context) {
    return _matchBufferContext(this, context, context.length - 1);
  }

  @override
  TreeCursor cursor([IterMode mode = IterMode.none]) {
    return TreeCursor.fromBufferNode(this, mode);
  }

  @override
  SyntaxNode get node => this;

  @override
  String toString() => '${type.name}($from..$to)';
}

/// Helper to resolve a node at a position.
SyntaxNode _resolveNode(
    SyntaxNode node, int pos, int side, bool enterOverlay) {
  // Walk up to find the smallest node containing pos
  var cur = node;
  while (true) {
    // Match TypeScript: node.from == node.to ||
    //                   (side < 1 ? node.from >= pos : node.from > pos) ||
    //                   (side > -1 ? node.to <= pos : node.to < pos)
    if (cur.from == cur.to ||
        (side < 1 ? cur.from >= pos : cur.from > pos) ||
        (side > -1 ? cur.to <= pos : cur.to < pos)) {
      final parent = cur.parent;
      if (parent == null) break;
      cur = parent;
    } else {
      break;
    }
  }

  // Walk down to find the deepest node at pos
  while (true) {
    final child = cur.enter(
      pos,
      side,
      mode: enterOverlay ? IterMode.none : IterMode.ignoreOverlays,
    );
    if (child == null) break;
    cur = child;
  }

  return cur;
}

/// Match a tree node against a context.
bool _matchNodeContext(
    SyntaxNode? node, List<String> context, int contextIndex) {
  for (var cx = node; cx != null && contextIndex >= 0; cx = cx.parent) {
    if (!cx.type.isAnonymous) {
      if (context[contextIndex].isNotEmpty &&
          context[contextIndex] != cx.name) {
        return false;
      }
      contextIndex--;
    }
  }
  return contextIndex < 0;
}

/// Match a buffer node against a context.
bool _matchBufferContext(
    BufferNode node, List<String> context, int contextIndex) {
  // First check buffer parents
  var cur = node.bufferParent;
  while (cur != null && contextIndex >= 0) {
    if (!cur.type.isAnonymous) {
      if (context[contextIndex].isNotEmpty &&
          context[contextIndex] != cur.name) {
        return false;
      }
      contextIndex--;
    }
    cur = cur.bufferParent;
  }
  // Then check tree parents
  return _matchNodeContext(node.context.parent, context, contextIndex);
}
