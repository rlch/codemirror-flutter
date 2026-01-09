/// Syntax tree structure.
///
/// This module provides [Tree] which represents a piece of syntax tree.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'iter_mode.dart';
import 'node_prop.dart';
import 'node_set.dart';
import 'node_type.dart';
import 'syntax_node.dart';
import 'tree_buffer.dart';
import 'tree_cursor.dart';

/// The default maximum length of a [TreeBuffer] node.
const int defaultBufferLength = 1024;

/// Special record markers in the buffer.
class _SpecialRecord {
  _SpecialRecord._();
  static const int reuse = -1;
  static const int contextChange = -3;
  static const int lookAhead = -4;
}

/// Cutoff depth for flat node handling.
class _CutOff {
  _CutOff._();
  static const int depth = 2500;
}

/// Buffer cursor interface for Tree.build.
abstract class BufferCursor {
  /// Current position in the buffer.
  int get pos;

  /// Node ID at current position.
  int get id;

  /// Start position of current node.
  int get start;

  /// End position of current node.
  int get end;

  /// Size of current node.
  int get size;

  /// Move to next node.
  void next();

  /// Fork this cursor.
  BufferCursor fork();
}

/// Build data for Tree.build.
class BuildData {
  final Object /* BufferCursor | List<int> */ buffer;
  final NodeSet nodeSet;
  final int topID;
  final int start;
  final int bufferStart;
  final int length;
  final int maxBufferLength;
  final List<Tree> reused;
  final int minRepeatType;

  BuildData({
    required this.buffer,
    required this.nodeSet,
    required this.topID,
    this.start = 0,
    this.bufferStart = 0,
    int? length,
    int? maxBufferLength,
    List<Tree>? reused,
    int? minRepeatType,
  })  : length = length ?? 0,
        maxBufferLength = maxBufferLength ?? defaultBufferLength,
        reused = reused ?? const [],
        minRepeatType = minRepeatType ?? nodeSet.types.length;
}

/// A simple range.
class Range {
  final int from;
  final int to;

  const Range(this.from, this.to);
}

/// A piece of syntax tree.
///
/// There are two ways to approach these trees: the way they are actually
/// stored in memory, and the convenient way.
///
/// Syntax trees are stored as a tree of [Tree] and [TreeBuffer] objects.
/// By packing detail information into [TreeBuffer] leaf nodes, the
/// representation is made a lot more memory-efficient.
///
/// However, when you want to actually work with tree nodes, this
/// representation is very awkward, so most client code will want to use
/// the [TreeCursor] or [SyntaxNode] interface instead, which provides
/// a view on some part of this data structure, and can be used to move
/// around to adjacent nodes.
class Tree {
  /// The type of the top node.
  final NodeType type;

  /// This node's child nodes.
  final List<Object /* Tree | TreeBuffer */> children;

  /// The positions (offsets relative to the start of this tree) of
  /// the children.
  final List<int> positions;

  /// The total length of this tree.
  final int length;

  /// Per-node props on this tree.
  @internal
  Map<int, Object?>? props;

  /// Construct a new tree.
  ///
  /// See also [Tree.build].
  Tree(
    this.type,
    this.children,
    this.positions,
    this.length, [
    List<(Object /* NodeProp | int */, Object?)>? propsList,
  ]) {
    if (propsList != null && propsList.isNotEmpty) {
      props = {};
      for (final (prop, value) in propsList) {
        props![prop is int ? prop : (prop as NodeProp).id] = value;
      }
    }
  }

  @override
  String toString() {
    final mounted = MountedTree.get(this);
    if (mounted != null && mounted.overlay == null) {
      return mounted.tree.toString();
    }
    final buffer = StringBuffer();
    var first = true;
    for (final ch in children) {
      final str = ch.toString();
      if (str.isNotEmpty) {
        if (!first) buffer.write(',');
        buffer.write(str);
        first = false;
      }
    }
    final childrenStr = buffer.toString();
    if (type.name.isEmpty) {
      return childrenStr;
    }
    final nameStr = (RegExp(r'\W').hasMatch(type.name) && !type.isError)
        ? '"${type.name}"'
        : type.name;
    return childrenStr.isEmpty ? nameStr : '$nameStr($childrenStr)';
  }

  /// The empty tree.
  static final empty = Tree(NodeType.none, [], [], 0);

  /// Build a tree from a buffer.
  ///
  /// This is used by the LR parser to construct trees from parse buffers.
  static Tree build({
    required Object /* BufferCursor | List<int> */ buffer,
    required NodeSet nodeSet,
    required int topID,
    int start = 0,
    int bufferStart = 0,
    int? length,
    int? maxBufferLength,
    List<Tree>? reused,
    int? minRepeatType,
  }) {
    return _buildTree(BuildData(
      buffer: buffer,
      nodeSet: nodeSet,
      topID: topID,
      start: start,
      bufferStart: bufferStart,
      length: length,
      maxBufferLength: maxBufferLength,
      reused: reused,
      minRepeatType: minRepeatType,
    ));
  }

  /// Get a [TreeCursor] positioned at the top of the tree.
  ///
  /// [mode] can be used to control which nodes the cursor visits.
  TreeCursor cursor([IterMode mode = IterMode.none]) {
    return TreeCursor.fromTree(this, mode);
  }

  /// Get a [TreeCursor] pointing into this tree at the given position
  /// and side.
  TreeCursor cursorAt(int pos, [int side = 0, IterMode mode = IterMode.none]) {
    final cursor = TreeCursor.fromTree(this, mode);
    cursor.moveTo(pos, side);
    return cursor;
  }

  /// Get a [SyntaxNode] object for the top of the tree.
  SyntaxNode get topNode => TreeNode(this, 0, 0, null);

  /// Get the [SyntaxNode] at the given position.
  ///
  /// If [side] is -1, this will move into nodes that end at the position.
  /// If 1, it'll move into nodes that start at the position.
  /// With 0, it'll only enter nodes that cover the position from both sides.
  ///
  /// Note that this will not enter overlays. You often want [resolveInner]
  /// instead.
  SyntaxNode resolve(int pos, [int side = 0]) {
    final node = _resolveNode(_cachedNode ?? topNode, pos, side, false);
    _cachedNode = node;
    return node;
  }

  /// Like [resolve], but will enter overlaid nodes, producing a syntax
  /// node pointing into the innermost overlaid tree at the given position.
  SyntaxNode resolveInner(int pos, [int side = 0]) {
    final node = _resolveNode(_cachedInnerNode ?? topNode, pos, side, true);
    _cachedInnerNode = node;
    return node;
  }

  /// Iterate over all nodes around a position, including those in overlays.
  ///
  /// Returns an iterator that will produce all nodes, from small to big,
  /// around the given position.
  NodeIterator resolveStack(int pos, [int side = 0]) {
    return _stackIterator(this, pos, side);
  }

  /// Iterate over the tree and its children.
  ///
  /// Calls [enter] for any node that touches the [from]/[to] region before
  /// running over such a node's children, and [leave] when leaving the node.
  /// When [enter] returns false, that node will not have its children
  /// iterated over.
  void iterate({
    required bool Function(SyntaxNodeRef node) enter,
    void Function(SyntaxNodeRef node)? leave,
    int from = 0,
    int? to,
    IterMode mode = IterMode.none,
  }) {
    final toPos = to ?? length;
    final anon = mode.hasFlag(IterMode.includeAnonymous);
    final cursor = this.cursor(mode | IterMode.includeAnonymous);

    while (true) {
      var entered = false;
      if (cursor.from <= toPos &&
          cursor.to >= from &&
          (!anon && cursor.type.isAnonymous || enter(cursor) != false)) {
        if (cursor.firstChild()) continue;
        entered = true;
      }
      while (true) {
        if (entered && leave != null && (anon || !cursor.type.isAnonymous)) {
          leave(cursor);
        }
        if (cursor.nextSibling()) break;
        if (!cursor.parent()) return;
        entered = true;
      }
    }
  }

  /// Get the value of the given [NodeProp] for this node.
  ///
  /// Works with both per-node and per-type props.
  T? prop<T>(NodeProp<T> prop) {
    return !prop.perNode
        ? type.prop(prop)
        : props != null
            ? props![prop.id] as T?
            : null;
  }

  /// Returns the node's per-node props in a format that can be passed
  /// to the [Tree] constructor.
  List<(Object, Object?)> get propValues {
    final result = <(Object, Object?)>[];
    if (props != null) {
      for (final entry in props!.entries) {
        result.add((entry.key, entry.value));
      }
    }
    return result;
  }

  /// Balance the direct children of this tree.
  ///
  /// Produces a copy which may have children grouped into subtrees with
  /// type [NodeType.none].
  Tree balance({
    Tree Function(List<Object> children, List<int> positions, int length)?
        makeTree,
  }) {
    if (children.length <= _Balance.branchFactor) return this;
    return _balanceRange(
      NodeType.none,
      children,
      positions,
      0,
      children.length,
      0,
      length,
      (children, positions, length) =>
          Tree(type, children, positions, length, propValues),
      makeTree ??
          (children, positions, length) =>
              Tree(NodeType.none, children, positions, length),
    );
  }

  // Cached nodes for faster repeated access
  SyntaxNode? _cachedNode;
  SyntaxNode? _cachedInnerNode;
}

/// Constants for tree balancing.
class _Balance {
  _Balance._();
  static const int branchFactor = 8;
}

/// Resolve a node at a position.
SyntaxNode _resolveNode(SyntaxNode node, int pos, int side, bool enterOverlay) {
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
    final child = cur.enter(pos, side,
        mode: enterOverlay ? IterMode.none : IterMode.ignoreOverlays);
    if (child == null) break;
    cur = child;
  }

  return cur;
}

/// Create a stack iterator.
NodeIterator _stackIterator(Tree tree, int pos, int side) {
  // Simplified implementation - just returns the resolved node as a single-item iterator
  final node = tree.resolveInner(pos, side);
  return _SingleNodeIterator(node);
}

class _SingleNodeIterator implements NodeIterator {
  @override
  final SyntaxNode node;

  @override
  NodeIterator? next;

  _SingleNodeIterator(this.node) {
    // Build the chain up to root
    var cur = node.parent;
    NodeIterator? prev = this;
    while (cur != null) {
      final iter = _SingleNodeIterator._(cur, prev);
      prev!.next = iter;
      prev = iter;
      cur = cur.parent;
    }
  }

  _SingleNodeIterator._(this.node, this.next);
}

/// Balance a range of nodes.
Tree _balanceRange(
  NodeType balanceType,
  List<Object> children,
  List<int> positions,
  int from,
  int to,
  int start,
  int length,
  Tree Function(List<Object> children, List<int> positions, int length)? mkTop,
  Tree Function(List<Object> children, List<int> positions, int length) mkTree,
) {
  var total = 0;
  for (var i = from; i < to; i++) {
    total += _nodeSize(balanceType, children[i]);
  }

  final maxChild = ((total * 1.5) / _Balance.branchFactor).ceil();
  final localChildren = <Object>[];
  final localPositions = <int>[];

  void divide(
    List<Object> children,
    List<int> positions,
    int from,
    int to,
    int offset,
  ) {
    for (var i = from; i < to;) {
      final groupFrom = i;
      final groupStart = positions[i];
      var groupSize = _nodeSize(balanceType, children[i]);
      i++;
      for (; i < to; i++) {
        final nextSize = _nodeSize(balanceType, children[i]);
        if (groupSize + nextSize >= maxChild) break;
        groupSize += nextSize;
      }
      if (i == groupFrom + 1) {
        if (groupSize > maxChild) {
          final only = children[groupFrom] as Tree;
          divide(only.children, only.positions, 0, only.children.length,
              positions[groupFrom] + offset);
          continue;
        }
        localChildren.add(children[groupFrom]);
      } else {
        final len = positions[i - 1] +
            (children[i - 1] is Tree
                ? (children[i - 1] as Tree).length
                : (children[i - 1] as TreeBuffer).length) -
            groupStart;
        localChildren.add(_balanceRange(balanceType, children, positions,
            groupFrom, i, groupStart, len, null, mkTree));
      }
      localPositions.add(groupStart + offset - start);
    }
  }

  divide(children, positions, from, to, 0);
  return (mkTop ?? mkTree)(localChildren, localPositions, length);
}

/// Cache for node sizes.
final _nodeSizeCache = Expando<int>();

int _nodeSize(NodeType balanceType, Object node) {
  if (!balanceType.isAnonymous || node is TreeBuffer) return 1;
  final tree = node as Tree;
  if (tree.type != balanceType) return 1;

  var size = _nodeSizeCache[tree];
  if (size == null) {
    size = 1;
    for (final child in tree.children) {
      if (child is! Tree || child.type != balanceType) {
        size = 1;
        break;
      }
      size = size! + _nodeSize(balanceType, child);
    }
    _nodeSizeCache[tree] = size;
  }
  return size!;
}

/// Iterator for nodes at a position.
abstract class NodeIterator {
  SyntaxNode get node;
  NodeIterator? next;
}

/// Flat buffer cursor implementation.
class _FlatBufferCursor implements BufferCursor {
  final List<int> buffer;
  int index;

  _FlatBufferCursor(this.buffer, this.index);

  @override
  int get id => buffer[index - 4];

  @override
  int get start => buffer[index - 3];

  @override
  int get end => buffer[index - 2];

  @override
  int get size => buffer[index - 1];

  @override
  int get pos => index;

  @override
  void next() => index -= 4;

  @override
  BufferCursor fork() => _FlatBufferCursor(buffer, index);
}

/// Build a tree from buffer data.
Tree _buildTree(BuildData data) {
  final nodeSet = data.nodeSet;
  final maxBufferLength = data.maxBufferLength;
  final reused = data.reused;
  final minRepeatType = data.minRepeatType;

  var cursor = data.buffer is List<int>
      ? _FlatBufferCursor(data.buffer as List<int>, (data.buffer as List<int>).length)
      : data.buffer as BufferCursor;

  final types = nodeSet.types;
  var contextHash = 0;
  var lookAhead = 0;

  Tree makeTree(
    NodeType type,
    List<Object> children,
    List<int> positions,
    int length,
    int lookAhead,
    int contextHash,
  ) {
    final props = <(Object, Object?)>[];
    if (lookAhead > 25) {
      props.add((NodeProp.lookAhead, lookAhead));
    }
    if (contextHash != 0) {
      props.add((NodeProp.contextHash, contextHash));
    }
    return Tree(type, children, positions, length, props.isEmpty ? null : props);
  }

  Tree Function(List<Object>, List<int>, int) makeBalanced(NodeType type, int ctxHash) {
    return (List<Object> children, List<int> positions, int length) {
      var la = 0;
      final lastI = children.length - 1;
      if (lastI >= 0) {
        final last = children[lastI];
        if (last is Tree) {
          if (lastI == 0 && last.type == type && last.length == length) return last;
          final laProp = last.prop(NodeProp.lookAhead);
          if (laProp != null) {
            la = positions[lastI] + last.length + laProp;
          }
        }
      }
      return makeTree(type, children, positions, length, la, ctxHash);
    };
  }

  void makeRepeatLeaf(
    List<Object> children,
    List<int> positions,
    int base,
    int i,
    int from,
    int to,
    int type,
    int la,
    int ctxHash,
  ) {
    final localChildren = <Object>[];
    final localPositions = <int>[];
    while (children.length > i) {
      localChildren.add(children.removeLast());
      localPositions.add(positions.removeLast() + base - from);
    }
    children.add(makeTree(nodeSet.types[type], localChildren, localPositions, to - from, la - to, ctxHash));
    positions.add(from - base);
  }

  /// Find buffer size for nodes that can fit in a TreeBuffer.
  /// 
  /// Scans through the buffer to find previous siblings that fit together
  /// in a TreeBuffer, and don't contain any reused nodes (which can't be
  /// stored in a buffer).
  /// 
  /// If [inRepeat] is > -1, ignore node boundaries of that type for nesting,
  /// but make sure the end falls either at the start ([maxSize]) or before 
  /// such a node.
  ({int size, int start, int skip})? findBufferSize(int maxSize, int inRepeat) {
    final fork = cursor.fork();
    var size = 0;
    var start = 0;
    var skip = 0;
    final minStart = fork.end - maxBufferLength;
    var result = (size: 0, start: 0, skip: 0);
    
    final minPos = fork.pos - maxSize;
    scan: while (fork.pos > minPos) {
      final nodeSize = fork.size;
      // Pretend nested repeat nodes of the same type don't exist
      if (fork.id == inRepeat && nodeSize >= 0) {
        // Except that we store the current state as a valid return value.
        result = (size: size, start: start, skip: skip);
        skip += 4;
        size += 4;
        fork.next();
        continue;
      }
      final startPos = fork.pos - nodeSize;
      if (nodeSize < 0 || startPos < minPos || fork.start < minStart) break;
      var localSkipped = fork.id >= minRepeatType ? 4 : 0;
      final nodeStart = fork.start;
      fork.next();
      while (fork.pos > startPos) {
        if (fork.size < 0) {
          if (fork.size == _SpecialRecord.contextChange || 
              fork.size == _SpecialRecord.lookAhead) {
            localSkipped += 4;
          } else {
            break scan;
          }
        } else if (fork.id >= minRepeatType) {
          localSkipped += 4;
        }
        fork.next();
      }
      start = nodeStart;
      size += nodeSize;
      skip += localSkipped;
    }
    if (inRepeat < 0 || size == maxSize) {
      result = (size: size, start: start, skip: skip);
    }
    return result.size > 4 ? result : null;
  }

  /// Copy nodes to a buffer (for TreeBuffer creation).
  int copyToBuffer(int bufferStart, Uint16List buffer, int index) {
    final id = cursor.id;
    final start = cursor.start;
    final end = cursor.end;
    final size = cursor.size;
    cursor.next();
    if (size >= 0 && id < minRepeatType) {
      final startIndex = index;
      if (size > 4) {
        final endPos = cursor.pos - (size - 4);
        while (cursor.pos > endPos) {
          index = copyToBuffer(bufferStart, buffer, index);
        }
      }
      buffer[--index] = startIndex;
      buffer[--index] = end - bufferStart;
      buffer[--index] = start - bufferStart;
      buffer[--index] = id;
    } else if (size == _SpecialRecord.contextChange) {
      contextHash = id;
    } else if (size == _SpecialRecord.lookAhead) {
      lookAhead = id;
    }
    return index;
  }

  /// Take flat nodes for very deep trees.
  void takeFlatNode(
    int parentStart,
    int minPos,
    List<Object> children,
    List<int> positions,
  ) {
    final nodes = <int>[];
    var nodeCount = 0, stopAt = -1;
    while (cursor.pos > minPos) {
      final id = cursor.id;
      final start = cursor.start;
      final end = cursor.end;
      final size = cursor.size;
      if (size > 4) {
        cursor.next();
      } else if (stopAt > -1 && start < stopAt) {
        break;
      } else {
        if (stopAt < 0) stopAt = end - maxBufferLength;
        nodes.addAll([id, start, end]);
        nodeCount++;
        cursor.next();
      }
    }
    if (nodeCount > 0) {
      final buffer = Uint16List(nodeCount * 4);
      final start = nodes[nodes.length - 2];
      for (var i = nodes.length - 3, j = 0; i >= 0; i -= 3) {
        buffer[j++] = nodes[i];
        buffer[j++] = nodes[i + 1] - start;
        buffer[j++] = nodes[i + 2] - start;
        buffer[j++] = j;
      }
      children.add(TreeBuffer(buffer, nodes[2] - start, nodeSet));
      positions.add(start - parentStart);
    }
  }

  void takeNode(
    int parentStart,
    int minPos,
    List<Object> children,
    List<int> positions,
    int inRepeat,
    int depth,
  ) {
    final id = cursor.id;
    final start = cursor.start;
    final end = cursor.end;
    final size = cursor.size;
    final lookAheadAtStart = lookAhead;
    final contextAtStart = contextHash;
    
    if (size < 0) {
      cursor.next();
      if (size == _SpecialRecord.reuse) {
        children.add(reused[id]);
        positions.add(start - parentStart);
        return;
      } else if (size == _SpecialRecord.contextChange) {
        contextHash = id;
        return;
      } else if (size == _SpecialRecord.lookAhead) {
        lookAhead = id;
        return;
      } else {
        throw RangeError('Unrecognized record size: $size');
      }
    }

    final type = types[id];
    Object node;
    var startPos = start - parentStart;

    // Check if we can create a TreeBuffer
    final bufferInfo = (end - start <= maxBufferLength) ? findBufferSize(cursor.pos - minPos, inRepeat) : null;
    
    if (bufferInfo != null) {
      // Small enough for a buffer, and no reused nodes inside
      final bufferData = Uint16List(bufferInfo.size - bufferInfo.skip);
      final endPos = cursor.pos - bufferInfo.size;
      var index = bufferData.length;
      while (cursor.pos > endPos) {
        index = copyToBuffer(bufferInfo.start, bufferData, index);
      }
      node = TreeBuffer(bufferData, end - bufferInfo.start, nodeSet);
      startPos = bufferInfo.start - parentStart;
    } else {
      // Make it a node
      final endPos = cursor.pos - size;
      cursor.next();

      final localChildren = <Object>[];
      final localPositions = <int>[];
      final localInRepeat = id >= minRepeatType ? id : -1;
      var lastGroup = 0, lastEnd = end;

      while (cursor.pos > endPos) {
        if (localInRepeat >= 0 && cursor.id == localInRepeat && cursor.size >= 0) {
          if (cursor.end <= lastEnd - maxBufferLength) {
            makeRepeatLeaf(localChildren, localPositions, start, lastGroup, cursor.end, lastEnd,
                localInRepeat, lookAheadAtStart, contextAtStart);
            lastGroup = localChildren.length;
            lastEnd = cursor.end;
          }
          cursor.next();
        } else if (depth > _CutOff.depth) {
          takeFlatNode(start, endPos, localChildren, localPositions);
        } else {
          takeNode(start, endPos, localChildren, localPositions, localInRepeat, depth + 1);
        }
      }
      
      if (localInRepeat >= 0 && lastGroup > 0 && lastGroup < localChildren.length) {
        makeRepeatLeaf(localChildren, localPositions, start, lastGroup, start, lastEnd,
            localInRepeat, lookAheadAtStart, contextAtStart);
      }
      
      // Reverse to get children in correct order
      final reversedChildren = localChildren.reversed.toList();
      final reversedPositions = localPositions.reversed.toList();

      if (localInRepeat > -1 && lastGroup > 0) {
        final make = makeBalanced(type, contextAtStart);
        node = _balanceRange(
          type,
          reversedChildren,
          reversedPositions,
          0,
          reversedChildren.length,
          0,
          end - start,
          make,
          make,
        );
      } else {
        node = makeTree(
          type,
          reversedChildren,
          reversedPositions,
          end - start,
          lookAheadAtStart - end,
          contextAtStart,
        );
      }
    }

    children.add(node);
    positions.add(startPos);
  }

  final children = <Object>[];
  final positions = <int>[];

  while (cursor.pos > 0) {
    takeNode(data.start, data.bufferStart, children, positions, -1, 0);
  }

  // Compute length if not provided (before reversing!)
  var length = data.length;
  if (length == 0 && children.isNotEmpty) {
    final first = children[0];
    final firstLen = first is Tree ? first.length : (first as TreeBuffer).length;
    length = positions[0] + firstLen;
  }

  // Reverse the final lists
  final reversedChildren = children.reversed.toList();
  final reversedPositions = positions.reversed.toList();

  final topType = types[data.topID];
  return makeTree(
    topType,
    reversedChildren,
    reversedPositions,
    length,
    0,
    0,
  );
}

/// A weak map that can store values per syntax node.
///
/// This uses the tree or buffer identity to key values, so nodes
/// that represent the same position in different tree instances
/// won't share values.
class NodeWeakMap<T> {
  final Expando<Object> _map = Expando<Object>();

  void _setBuffer(TreeBuffer buffer, int index, T value) {
    var inner = _map[buffer] as Map<int, T>?;
    if (inner == null) {
      inner = <int, T>{};
      _map[buffer] = inner;
    }
    inner[index] = value;
  }

  T? _getBuffer(TreeBuffer buffer, int index) {
    final inner = _map[buffer] as Map<int, T>?;
    return inner?[index];
  }

  /// Set the value for this syntax node.
  void set(SyntaxNode node, T value) {
    if (node is BufferNode) {
      _setBuffer(node.context.buffer, node.index, value);
    } else if (node is TreeNode) {
      _map[node.tree!] = value;
    }
  }

  /// Retrieve value for this syntax node, if it exists in the map.
  T? get(SyntaxNode node) {
    if (node is BufferNode) {
      return _getBuffer(node.context.buffer, node.index);
    } else if (node is TreeNode) {
      return _map[node.tree!] as T?;
    }
    return null;
  }

  /// Set the value for the node that a cursor currently points to.
  void cursorSet(TreeCursor cursor, T value) {
    if (cursor.buffer != null) {
      _setBuffer(cursor.buffer!.buffer, cursor.index, value);
    } else {
      _map[cursor.tree!] = value;
    }
  }

  /// Retrieve the value for the node that a cursor currently points to.
  T? cursorGet(TreeCursor cursor) {
    if (cursor.buffer != null) {
      return _getBuffer(cursor.buffer!.buffer, cursor.index);
    }
    return _map[cursor.tree!] as T?;
  }
}
