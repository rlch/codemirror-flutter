/// Tree cursor for efficient syntax tree traversal.
///
/// This module provides [TreeCursor] which allows efficient traversal
/// of syntax trees without allocating node objects.
library;

import 'package:meta/meta.dart';

import 'iter_mode.dart';
import 'node_type.dart';
import 'syntax_node.dart';
import 'tree.dart';
import 'tree_buffer.dart';

/// A tree cursor provides an efficient way to traverse a syntax tree.
///
/// Unlike [SyntaxNode] objects, cursors don't allocate memory for each
/// node position, making them more efficient for traversal.
class TreeCursor implements SyntaxNodeRef {
  /// The iteration mode.
  @internal
  final IterMode mode;

  /// The current tree node (when not in a buffer).
  TreeNode _tree;

  /// The current buffer context (when in a buffer).
  @internal
  BufferContext? buffer;

  /// Stack of buffer indices for nested buffer navigation.
  @internal
  List<int> stack = [];

  /// Current index in the buffer.
  @internal
  int index = 0;

  /// Cached buffer node.
  @internal
  BufferNode? bufferNode;

  TreeCursor._(this._tree, this.mode);

  /// Internal access to the current tree node.
  @internal
  TreeNode get treeNode => _tree;

  /// Internal method to yield a tree node.
  @internal
  bool yieldNode(TreeNode node) => _yield(node);

  /// Create a cursor from a tree.
  factory TreeCursor.fromTree(Tree tree, [IterMode mode = IterMode.none]) {
    return TreeCursor._(TreeNode(tree, 0, 0, null), mode);
  }

  /// Create a cursor from a tree node.
  factory TreeCursor.fromNode(TreeNode node, [IterMode mode = IterMode.none]) {
    return TreeCursor._(node, mode);
  }

  /// Create a cursor from a buffer node.
  factory TreeCursor.fromBufferNode(BufferNode node, [IterMode mode = IterMode.none]) {
    final cursor = TreeCursor._(node.context.parent, mode);
    cursor.buffer = node.context;
    // Build the stack by walking up the buffer parent chain
    for (BufferNode? n = node.bufferParent; n != null; n = n.bufferParent) {
      cursor.stack.insert(0, n.index);
    }
    cursor.bufferNode = node;
    cursor.index = node.index;
    return cursor;
  }

  @override
  String get name => type.name;

  @override
  NodeType get type {
    return buffer != null
        ? buffer!.buffer.set.types[buffer!.buffer.buffer[index]]
        : _tree.type;
  }

  @override
  int get from {
    return buffer != null
        ? buffer!.buffer.buffer[index + 1] + buffer!.start
        : _tree.from;
  }

  @override
  int get to {
    return buffer != null
        ? buffer!.buffer.buffer[index + 2] + buffer!.start
        : _tree.to;
  }

  @override
  Tree? get tree => buffer != null ? null : _tree.tree;

  /// Move to the first child of the current node.
  bool firstChild() => _enterChild(1, 0, Side.dontCare);

  /// Move to the last child of the current node.
  bool lastChild() => _enterChild(-1, 0, Side.dontCare);

  /// Move to the first child covering [pos].
  bool childAfter(int pos) => _enterChild(1, pos, Side.after);

  /// Move to the last child before [pos].
  bool childBefore(int pos) => _enterChild(-1, pos, Side.before);

  /// Enter the child at [pos] with the given [side].
  bool enter(int pos, int side) => _enterChild(side < 0 ? -1 : 1, pos, side);

  bool _enterChild(int dir, int pos, int side) {
    if (buffer != null) {
      return _enterBuffer(dir, pos, side);
    }
    return _enterTree(dir, pos, side);
  }

  bool _enterTree(int dir, int pos, int side) {
    final tree = _tree.tree;
    if (tree == null) return false;
    final children = tree.children;
    final positions = tree.positions;

    for (var i = dir > 0 ? 0 : children.length - 1;
        i >= 0 && i < children.length;
        i += dir) {
      final child = children[i];
      final childStart = positions[i] + _tree.from;
      final childEnd = childStart +
          (child is Tree ? child.length : (child as TreeBuffer).length);

      // Check position constraints
      if (!_checkSide(childStart, childEnd, pos, side)) continue;

      if (child is TreeBuffer) {
        if (mode.hasFlag(IterMode.excludeBuffers)) continue;

        final ctx = BufferContext(child, _tree, i, childStart);
        final found =
            ctx.findChild(0, child.buffer.length, dir, pos, side);
        if (found >= 0) {
          return _yieldBuf(ctx, found);
        }
      } else {
        final treeChild = child as Tree;
        if (!mode.hasFlag(IterMode.includeAnonymous) &&
            treeChild.type.isAnonymous) {
          // Enter anonymous node transparently
          final newTree = TreeNode(treeChild, childStart, i, _tree);
          final oldTree = _tree;
          _tree = newTree;
          if (_enterTree(dir, pos, side)) return true;
          _tree = oldTree;
        } else {
          return _yield(TreeNode(treeChild, childStart, i, _tree));
        }
      }
    }
    return false;
  }

  bool _enterBuffer(int dir, int pos, int side) {
    final buf = buffer!;
    final endIndex = buf.buffer.buffer[index + 3];
    // If endIndex points right after the header (index + 4), there are no children
    if (endIndex <= index + 4) return false;

    final start = index + 4;
    // endIndex is the direct value from the buffer, not a size to add
    final found = buf.findChild(start, endIndex, dir, pos, side);
    if (found >= 0) {
      stack.add(index);
      return _yieldBuf(buf, found);
    }
    return false;
  }

  bool _checkSide(int from, int to, int pos, int side) {
    return Side.check(side, pos, from, to);
  }

  bool _yield(TreeNode node) {
    buffer = null;
    _tree = node;
    return true;
  }

  bool _yieldBuf(BufferContext ctx, int index) {
    buffer = ctx;
    this.index = index;
    return true;
  }

  /// Move to the parent of the current node.
  bool parent() {
    if (buffer != null) {
      if (stack.isNotEmpty) {
        index = stack.removeLast();
        return true;
      }
      // Exit buffer to tree - move to the buffer's parent TreeNode
      // TypeScript: let parent = (this.mode & IterMode.IncludeAnonymous) ? this.buffer.parent : this.buffer.parent.nextSignificantParent()
      final bufParent = buffer!.parent;
      buffer = null;
      if (mode.hasFlag(IterMode.includeAnonymous)) {
        return _yield(bufParent);
      }
      // Skip anonymous parents
      return _yieldSignificantParent(bufParent);
    }

    final parent = _tree.parent as TreeNode?;
    if (parent == null) return false;
    _tree = parent;
    return true;
  }
  
  /// Yield the first non-anonymous node starting from [node], going up the tree.
  bool _yieldSignificantParent(TreeNode node) {
    var cur = node;
    while (cur.type.isAnonymous && cur.parent != null) {
      cur = cur.parent as TreeNode;
    }
    return _yield(cur);
  }

  /// Move to the next sibling of the current node.
  bool nextSibling() => _sibling(1);

  /// Move to the previous sibling of the current node.
  bool prevSibling() => _sibling(-1);

  bool _sibling(int dir) {
    if (buffer != null) {
      return _bufferSibling(dir);
    }

    final parent = _tree.parent as TreeNode?;
    if (parent == null) return false;

    final nextIndex = _tree.index + dir;
    final parentTree = parent.tree;
    if (parentTree == null ||
        nextIndex < 0 ||
        nextIndex >= parentTree.children.length) {
      return false;
    }

    final child = parentTree.children[nextIndex];
    final childStart = parentTree.positions[nextIndex] + parent.from;

    if (child is TreeBuffer) {
      if (mode.hasFlag(IterMode.excludeBuffers)) {
        // Skip buffer
        final newTree = TreeNode(parentTree, parent.from, parent.index, 
            parent.parent as TreeNode?);
        _tree = TreeNode(Tree.empty, childStart, nextIndex, newTree);
        return _sibling(dir);
      }
      final ctx = BufferContext(child, parent, nextIndex, childStart);
      // For dir > 0: enter at first top-level node (index 0)
      // For dir < 0: find the last top-level node by scanning
      int bufIndex;
      if (dir > 0) {
        bufIndex = 0;
      } else {
        // Find the last top-level node in the buffer
        bufIndex = 0;
        var cur = 0;
        while (cur < child.buffer.length) {
          bufIndex = cur;
          cur = child.buffer[cur + 3]; // endIndex points to next sibling
        }
      }
      return _yieldBuf(ctx, bufIndex);
    }

    final treeChild = child as Tree;
    if (!mode.hasFlag(IterMode.includeAnonymous) && treeChild.type.isAnonymous) {
      // Enter anonymous node transparently - we need to find the first/last 
      // non-anonymous child inside it (same as nextChild does)
      final anonNode = TreeNode(treeChild, childStart, nextIndex, parent);
      final innerChild = anonNode.nextChild(
        dir < 0 ? treeChild.children.length - 1 : 0,
        dir,
        0,
        Side.dontCare,
        mode,
      );
      if (innerChild != null) {
        if (innerChild is TreeNode) {
          buffer = null;
          return _yield(innerChild);
        } else {
          final bufNode = innerChild as BufferNode;
          buffer = bufNode.context;
          index = bufNode.index;
          stack.clear();
          for (BufferNode? n = bufNode.bufferParent; n != null; n = n.bufferParent) {
            stack.insert(0, n.index);
          }
          return true;
        }
      }
      // If anonymous node is empty, try next sibling
      _tree = anonNode;
      return _sibling(dir);
    }

    return _yield(TreeNode(treeChild, childStart, nextIndex, parent));
  }

  bool _bufferSibling(int dir) {
    final buf = buffer!;
    final d = stack.length - 1;

    if (dir < 0) {
      final parentStart = d < 0 ? 0 : stack[d] + 4;
      if (index != parentStart) {
        // Find previous sibling by scanning forward
        return _yieldBuf(buf, buf.buffer.findChild(parentStart, index, -1, 0, Side.dontCare));
      }
    } else {
      final after = buf.buffer.buffer[index + 3];
      final parentEnd = d < 0 ? buf.buffer.buffer.length : buf.buffer.buffer[stack[d] + 3];
      if (after < parentEnd) {
        return _yieldBuf(buf, after);
      }
    }
    // At edge of buffer - try to find tree sibling
    // TypeScript: return d < 0 ? this.yield(this.buffer.parent.nextChild(...)) : false
    return d < 0 ? _yieldTreeSibling(buf.parent, buf.index, dir) : false;
  }

  /// Move to a tree sibling from a buffer context.
  /// Returns false without modifying state if there's no sibling.
  bool _yieldTreeSibling(TreeNode parent, int bufferIndex, int dir) {
    // Find the next child in the tree
    final sibling = parent.nextChild(bufferIndex + dir, dir, 0, Side.dontCare, mode);
    if (sibling == null) return false;
    
    if (sibling is TreeNode) {
      buffer = null;
      return _yield(sibling);
    } else {
      // sibling is BufferNode - set up buffer context
      final bufSibling = sibling as BufferNode;
      buffer = bufSibling.context;
      index = bufSibling.index;
      stack.clear();
      // Build stack from buffer parent chain
      for (BufferNode? n = bufSibling.bufferParent; n != null; n = n.bufferParent) {
        stack.insert(0, n.index);
      }
      return true;
    }
  }

  /// Move forward in pre-order traversal.
  bool next([bool enter = true]) => _move(1, enter);

  /// Move backward in pre-order traversal.
  bool prev([bool enter = true]) => _move(-1, enter);

  bool _move(int dir, bool enter) {
    if (enter && _enterChild(dir, 0, Side.dontCare)) return true;
    while (true) {
      if (_sibling(dir)) return true;
      if (!parent()) return false;
    }
  }

  /// Move to the innermost node covering [pos].
  TreeCursor moveTo(int pos, [int side = 0]) {
    // Move up to a node that actually holds the position
    while (from == to ||
        (side < 1 ? from >= pos : from > pos) ||
        (side > -1 ? to <= pos : to < pos)) {
      if (!parent()) break;
    }
    // Then scan down into child nodes
    while (_enterChild(1, pos, side)) {}
    return this;
  }

  /// Get the current node.
  @override
  SyntaxNode get node {
    if (buffer == null) return _tree;

    // Try to reuse cached node or parts of its parent chain
    final cache = bufferNode;
    BufferNode? result;
    var depth = 0;
    
    if (cache != null && cache.context == buffer) {
      // Scan through the stack trying to find a match in the cached parent chain
      scan: for (var idx = index, d = stack.length; d >= 0;) {
        for (BufferNode? c = cache; c != null; c = c.bufferParent) {
          if (c.index == idx) {
            if (idx == index) return c;
            result = c;
            depth = d + 1;
            break scan;
          }
        }
        d--;
        idx = d >= 0 ? stack[d] : -1;
      }
    }
    
    // Build remaining path through buffer, reusing 'result' as the starting parent
    for (var i = depth; i < stack.length; i++) {
      result = BufferNode(buffer!, result, stack[i]);
    }
    return bufferNode = BufferNode(buffer!, result, index);
  }

  /// Iterate over all nodes under the cursor.
  void iterate(
    bool Function(SyntaxNodeRef node) enter, [
    void Function(SyntaxNodeRef node)? leave,
  ]) {
    var depth = 0;
    while (true) {
      var mustLeave = false;
      if (type.isAnonymous || enter(this) != false) {
        if (firstChild()) {
          depth++;
          continue;
        }
        if (!type.isAnonymous) mustLeave = true;
      }
      while (true) {
        if (mustLeave && leave != null) leave(this);
        mustLeave = type.isAnonymous;
        if (depth == 0) return;
        if (nextSibling()) break;
        parent();
        depth--;
        mustLeave = true;
      }
    }
  }

  @override
  bool matchContext(List<String> context) {
    if (buffer == null) return _tree.matchContext(context);

    // Build context from buffer stack
    var contextIndex = context.length - 1;
    for (var i = stack.length - 1; i >= 0 && contextIndex >= 0; i--) {
      final typeId = buffer!.buffer.buffer[stack[i]];
      final nodeType = buffer!.buffer.set.types[typeId];
      if (!nodeType.isAnonymous) {
        if (context[contextIndex].isNotEmpty &&
            context[contextIndex] != nodeType.name) {
          return false;
        }
        contextIndex--;
      }
    }
    return _matchNodeContext(_tree, context, contextIndex);
  }
}

/// Match context helper.
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
