/// Mixed-language parsing support.
///
/// This module provides [parseMixed] for embedding languages within each other,
/// such as JavaScript/CSS inside HTML, or code blocks in Markdown.
library;

import 'iter_mode.dart';
import 'node_prop.dart';
import 'node_type.dart';
import 'parser.dart';
import 'syntax_node.dart';
import 'tree.dart';
import 'tree_buffer.dart';
import 'tree_cursor.dart';
import 'tree_fragment.dart';

/// Objects returned by the function passed to [parseMixed] should conform
/// to this interface.
class NestedParse {
  /// The parser to use for the inner region.
  final Parser parser;

  /// When this property is not given, the entire node is parsed with
  /// this parser, and it is mounted as a non-overlay node, replacing
  /// its host node in tree iteration.
  ///
  /// When a list of ranges is given, only those ranges are parsed,
  /// and the tree is mounted as an overlay.
  ///
  /// When a function is given, that function will be called for
  /// descendant nodes of the target node, not including child nodes
  /// that are covered by another nested parse, to determine the
  /// overlay ranges.
  final Object? overlay; // List<Range>? | Range? Function(SyntaxNodeRef)?

  const NestedParse({
    required this.parser,
    this.overlay,
  });
}

/// Create a parse wrapper that, after the inner parse completes,
/// scans its tree for mixed language regions with the `nest`
/// function, runs the resulting inner parses, and then mounts their
/// results onto the tree.
ParseWrapper parseMixed(
    NestedParse? Function(SyntaxNodeRef node, Input input) nest) {
  return (parse, input, fragments, ranges) =>
      _MixedParse(parse, nest, input, fragments, ranges);
}

class _InnerParse {
  final Parser parser;
  final PartialParse parse;
  final List<Range>? overlay;
  final Tree target;
  final int from;

  _InnerParse(this.parser, this.parse, this.overlay, this.target, this.from);
}

class _ActiveOverlay {
  int depth = 0;
  final List<Range> ranges = [];
  final Parser parser;
  final Object Function(SyntaxNodeRef)? predicate;
  final List<_ReusableMount> mounts;
  final int index;
  final int start;
  final Tree target;
  final _ActiveOverlay? prev;

  _ActiveOverlay(this.parser, this.predicate, this.mounts, this.index,
      this.start, this.target, this.prev);
}

class _CoverInfo {
  final List<Range> ranges;
  int depth;
  final _CoverInfo? prev;

  _CoverInfo(this.ranges, this.depth, this.prev);
}

final _stoppedInner = NodeProp<int>(perNode: true);

enum _Cover { none, partial, full }

class _MixedParse implements PartialParse {
  PartialParse? baseParse;
  final List<_InnerParse> inner = [];
  int innerDone = 0;
  Tree? baseTree;
  @override
  int? stoppedAt;

  final NestedParse? Function(SyntaxNodeRef, Input) nest;
  final Input input;
  final List<TreeFragment> fragments;
  final List<Range> ranges;

  _MixedParse(
    PartialParse base,
    this.nest,
    this.input,
    this.fragments,
    this.ranges,
  ) : baseParse = base;

  @override
  Tree? advance() {
    if (baseParse != null) {
      final done = baseParse!.advance();
      if (done == null) return null;
      baseParse = null;
      baseTree = done;
      _startInner();
      if (stoppedAt != null) {
        for (final inner in this.inner) {
          inner.parse.stopAt(stoppedAt!);
        }
      }
    }
    if (innerDone == inner.length) {
      var result = baseTree!;
      if (stoppedAt != null) {
        result = Tree(
          result.type,
          result.children,
          result.positions,
          result.length,
          [...result.propValues, (_stoppedInner, stoppedAt)],
        );
      }
      return result;
    }
    final innerParse = inner[innerDone];
    final done = innerParse.parse.advance();
    if (done != null) {
      innerDone++;
      // Patch the target node with the mounted tree
      final props = Map<int, Object?>.from(innerParse.target.props ?? {});
      // Convert List<Range> to List<({int from, int to})> for MountedTree
      final overlayRanges = innerParse.overlay
          ?.map((r) => (from: r.from, to: r.to))
          .toList();
      props[NodeProp.mounted.id] =
          MountedTree(done, overlayRanges, innerParse.parser);
      innerParse.target.props = props;
    }
    return null;
  }

  @override
  int get parsedPos {
    if (baseParse != null) return 0;
    var pos = input.length;
    for (var i = innerDone; i < inner.length; i++) {
      if (inner[i].from < pos) {
        pos = pos < inner[i].parse.parsedPos ? pos : inner[i].parse.parsedPos;
      }
    }
    return pos;
  }

  @override
  void stopAt(int pos) {
    stoppedAt = pos;
    if (baseParse != null) {
      baseParse!.stopAt(pos);
    } else {
      for (var i = innerDone; i < inner.length; i++) {
        inner[i].parse.stopAt(pos);
      }
    }
  }

  void _startInner() {
    final fragmentCursor = _FragmentCursor(fragments);
    _ActiveOverlay? overlay;
    _CoverInfo? covered;
    final cursor = TreeCursor.fromNode(
      TreeNode(baseTree!, ranges[0].from, 0, null),
      IterMode.includeAnonymous | IterMode.ignoreMounts,
    );

    scan:
    for (;;) {
      var enter = true;
      if (stoppedAt != null && cursor.from >= stoppedAt!) {
        enter = false;
      } else if (fragmentCursor.hasNode(cursor)) {
        if (overlay != null) {
          final match = overlay.mounts.where((m) =>
              m.frag.from <= cursor.from &&
              m.frag.to >= cursor.to &&
              m.mount.overlay != null);
          for (final m in match) {
            for (final r in m.mount.overlay!) {
              final from = r.from + m.pos;
              final to = r.to + m.pos;
              if (from >= cursor.from &&
                  to <= cursor.to &&
                  !overlay.ranges.any((r) => r.from < to && r.to > from)) {
                overlay.ranges.add(Range(from, to));
              }
            }
          }
        }
        enter = false;
      } else if (covered != null) {
        final isCovered =
            _checkCover(covered.ranges, cursor.from, cursor.to);
        if (isCovered != _Cover.none) {
          enter = isCovered != _Cover.full;
        }
      } else if (!cursor.type.isAnonymous) {
        final nested = nest(cursor, input);
        if (nested != null && (cursor.from < cursor.to || nested.overlay == null)) {
          if (cursor.tree == null) {
            _materialize(cursor);
            if (overlay != null) overlay.depth++;
            if (covered != null) covered.depth++;
          }
          final oldMounts =
              fragmentCursor.findMounts(cursor.from, nested.parser);
          if (nested.overlay is Function) {
            overlay = _ActiveOverlay(
              nested.parser,
              nested.overlay as Object Function(SyntaxNodeRef),
              oldMounts,
              inner.length,
              cursor.from,
              cursor.tree!,
              overlay,
            );
          } else {
            var overlayRanges = nested.overlay as List<Range>?;
            var parseRanges = _punchRanges(
              ranges,
              overlayRanges ??
                  (cursor.from < cursor.to
                      ? [Range(cursor.from, cursor.to)]
                      : []),
            );
            if (parseRanges.isNotEmpty) _checkRanges(parseRanges);
            if (parseRanges.isNotEmpty || overlayRanges == null) {
              inner.add(_InnerParse(
                nested.parser,
                parseRanges.isNotEmpty
                    ? nested.parser.startParse(
                        input, _enterFragments(oldMounts, parseRanges), parseRanges)
                    : nested.parser.startParse(''),
                overlayRanges
                    ?.map((r) =>
                        Range(r.from - cursor.from, r.to - cursor.from))
                    .toList(),
                cursor.tree!,
                parseRanges.isNotEmpty ? parseRanges[0].from : cursor.from,
              ));
            }
            if (overlayRanges == null) {
              enter = false;
            } else if (parseRanges.isNotEmpty) {
              covered = _CoverInfo(parseRanges, 0, covered);
            }
          }
        }
      } else if (overlay != null && overlay.predicate != null) {
        final range = overlay.predicate!(cursor);
        if (range is Range) {
          if (range.from < range.to) {
            final last = overlay.ranges.length - 1;
            if (last >= 0 && overlay.ranges[last].to == range.from) {
              overlay.ranges[last] =
                  Range(overlay.ranges[last].from, range.to);
            } else {
              overlay.ranges.add(range);
            }
          }
        } else if (range == true) {
          final fullRange = Range(cursor.from, cursor.to);
          if (fullRange.from < fullRange.to) {
            final last = overlay.ranges.length - 1;
            if (last >= 0 && overlay.ranges[last].to == fullRange.from) {
              overlay.ranges[last] =
                  Range(overlay.ranges[last].from, fullRange.to);
            } else {
              overlay.ranges.add(fullRange);
            }
          }
        }
      }

      if (enter && cursor.firstChild()) {
        if (overlay != null) overlay.depth++;
        if (covered != null) covered.depth++;
      } else {
        for (;;) {
          if (cursor.nextSibling()) break;
          if (!cursor.parent()) break scan;
          if (overlay != null && --overlay.depth == 0) {
            final parseRanges = _punchRanges(ranges, overlay.ranges);
            if (parseRanges.isNotEmpty) {
              _checkRanges(parseRanges);
              inner.insert(
                overlay.index,
                _InnerParse(
                  overlay.parser,
                  overlay.parser.startParse(
                      input, _enterFragments(overlay.mounts, parseRanges), parseRanges),
                  overlay.ranges
                      .map((r) =>
                          Range(r.from - overlay!.start, r.to - overlay.start))
                      .toList(),
                  overlay.target,
                  parseRanges[0].from,
                ),
              );
            }
            overlay = overlay.prev;
          }
          if (covered != null && --covered.depth == 0) {
            covered = covered.prev;
          }
        }
      }
    }
  }
}

_Cover _checkCover(List<Range> covered, int from, int to) {
  for (final range in covered) {
    if (range.from >= to) break;
    if (range.to > from) {
      return range.from <= from && range.to >= to
          ? _Cover.full
          : _Cover.partial;
    }
  }
  return _Cover.none;
}

void _checkRanges(List<Range> ranges) {
  if (ranges.isEmpty || ranges.any((r) => r.from >= r.to)) {
    throw RangeError('Invalid inner parse ranges given: $ranges');
  }
}

List<Range> _punchRanges(List<Range> outer, List<Range> ranges) {
  List<Range>? copy;
  var current = ranges;
  for (var i = 1, j = 0; i < outer.length; i++) {
    final gapFrom = outer[i - 1].to;
    final gapTo = outer[i].from;
    for (; j < current.length; j++) {
      final r = current[j];
      if (r.from >= gapTo) break;
      if (r.to <= gapFrom) continue;
      copy ??= List.from(ranges);
      current = copy;
      if (r.from < gapFrom) {
        copy[j] = Range(r.from, gapFrom);
        if (r.to > gapTo) copy.insert(j + 1, Range(gapTo, r.to));
      } else if (r.to > gapTo) {
        copy[j--] = Range(gapTo, r.to);
      } else {
        copy.removeAt(j--);
      }
    }
  }
  return current;
}

class _ReusableMount {
  final TreeFragment frag;
  final MountedTree mount;
  final int pos;

  _ReusableMount(this.frag, this.mount, this.pos);
}

List<TreeFragment> _enterFragments(
    List<_ReusableMount> mounts, List<Range> ranges) {
  final result = <TreeFragment>[];
  for (final m in mounts) {
    final startPos =
        m.pos + (m.mount.overlay != null ? m.mount.overlay![0].from : 0);
    final endPos = startPos + m.mount.tree.length;
    final from = m.frag.from > startPos ? m.frag.from : startPos;
    final to = m.frag.to < endPos ? m.frag.to : endPos;
    if (m.mount.overlay != null) {
      final overlay =
          m.mount.overlay!.map((r) => Range(r.from + m.pos, r.to + m.pos)).toList();
      final changes = _findCoverChanges(ranges, overlay, from, to);
      for (var i = 0, pos = from;; i++) {
        final last = i == changes.length;
        final end = last ? to : changes[i].from;
        if (end > pos) {
          result.add(TreeFragment(
            pos,
            end,
            m.mount.tree,
            -startPos,
            m.frag.openStart || m.frag.from >= pos,
            m.frag.openEnd || m.frag.to <= end,
          ));
        }
        if (last) break;
        pos = changes[i].to;
      }
    } else {
      result.add(TreeFragment(
        from,
        to,
        m.mount.tree,
        -startPos,
        m.frag.openStart || m.frag.from >= startPos,
        m.frag.openEnd || m.frag.to <= endPos,
      ));
    }
  }
  return result;
}

List<Range> _findCoverChanges(
    List<Range> a, List<Range> b, int from, int to) {
  var iA = 0, iB = 0;
  var inA = false, inB = false;
  var pos = -1000000000;
  final result = <Range>[];
  for (;;) {
    final nextA = iA == a.length ? 1000000000 : (inA ? a[iA].to : a[iA].from);
    final nextB = iB == b.length ? 1000000000 : (inB ? b[iB].to : b[iB].from);
    if (inA != inB) {
      final start = pos > from ? pos : from;
      final end = [nextA, nextB, to].reduce((a, b) => a < b ? a : b);
      if (start < end) result.add(Range(start, end));
    }
    pos = nextA < nextB ? nextA : nextB;
    if (pos == 1000000000) break;
    if (nextA == pos) {
      if (!inA) {
        inA = true;
      } else {
        inA = false;
        iA++;
      }
    }
    if (nextB == pos) {
      if (!inB) {
        inB = true;
      } else {
        inB = false;
        iB++;
      }
    }
  }
  return result;
}

/// Materialize a buffer node into a Tree node.
void _materialize(TreeCursor cursor) {
  final node = cursor.node;
  if (node is! BufferNode) return;

  final stack = <int>[];
  var cur = cursor;
  do {
    stack.add(cur.index);
    cur.parent();
  } while (cur.tree == null);

  final base = cur.tree!;
  final buffer = node.context.buffer;
  final i = base.children.indexOf(buffer);
  if (i < 0) return;

  final buf = base.children[i] as TreeBuffer;
  final b = buf.buffer;
  final newStack = <int>[i];

  Tree split(int startI, int endI, NodeType type, int innerOffset, int length,
      int stackPos) {
    final targetI = stack[stackPos];
    final children = <Object>[];
    final positions = <int>[];
    _sliceBuf(buf, startI, targetI, children, positions, innerOffset);
    final from = b[targetI + 1];
    final to = b[targetI + 2];
    newStack.add(children.length);
    final child = stackPos > 0
        ? split(targetI + 4, b[targetI + 3], buf.set.types[b[targetI]],
            from, to - from, stackPos - 1)
        : node.toTree();
    children.add(child);
    positions.add(from - innerOffset);
    _sliceBuf(buf, b[targetI + 3], endI, children, positions, innerOffset);
    return Tree(type, children, positions, length);
  }

  (base.children as List)[i] =
      split(0, b.length, NodeType.none, 0, buf.length, stack.length - 1);

  // Move cursor back to target node
  for (final index in newStack) {
    final tree = cur.tree!.children[index] as Tree;
    final pos = cur.tree!.positions[index];
    cursor.yieldNode(TreeNode(tree, pos + cur.from, index, cur.treeNode));
  }
}

void _sliceBuf(TreeBuffer buf, int startI, int endI, List<Object> nodes,
    List<int> positions, int off) {
  if (startI < endI) {
    final from = buf.buffer[startI + 1];
    nodes.add(buf.slice(startI, endI, from));
    positions.add(from - off);
  }
}

class _StructureCursor {
  final TreeCursor cursor;
  bool done = false;
  final int offset;

  _StructureCursor(Tree root, this.offset)
      : cursor =
            root.cursor(IterMode.includeAnonymous | IterMode.ignoreMounts);

  void moveTo(int pos) {
    final p = pos - offset;
    while (!done && cursor.from < p) {
      // Try to enter a child that covers position p
      // Note: TypeScript uses IterMode here, but our TreeCursor.enter doesn't support it
      // We'll enter and skip buffers manually by checking cursor.tree
      if (cursor.to >= pos && cursor.enter(p, 1)) {
        // Skip if we entered a buffer (cursor.tree will be null)
        if (cursor.tree == null) {
          cursor.parent();
          if (!cursor.next(false)) {
            done = true;
          }
        }
      } else if (!cursor.next(false)) {
        done = true;
      }
    }
  }

  bool hasNode(TreeCursor other) {
    moveTo(other.from);
    if (!done && cursor.from + offset == other.from && cursor.tree != null) {
      for (var tree = cursor.tree!;;) {
        if (identical(tree, other.tree)) return true;
        if (tree.children.isEmpty ||
            tree.positions[0] != 0 ||
            tree.children[0] is! Tree) break;
        tree = tree.children[0] as Tree;
      }
    }
    return false;
  }
}

class _FragmentCursor {
  TreeFragment? curFrag;
  int curTo = 0;
  int fragI = 0;
  _StructureCursor? inner;
  final List<TreeFragment> fragments;

  _FragmentCursor(this.fragments) {
    if (fragments.isNotEmpty) {
      final first = curFrag = fragments[0];
      curTo = first.tree.prop(_stoppedInner) ?? first.to;
      inner = _StructureCursor(first.tree, -first.offset);
    }
  }

  bool hasNode(TreeCursor node) {
    while (curFrag != null && node.from >= curTo) {
      _nextFrag();
    }
    return curFrag != null &&
        curFrag!.from <= node.from &&
        curTo >= node.to &&
        inner!.hasNode(node);
  }

  void _nextFrag() {
    fragI++;
    if (fragI == fragments.length) {
      curFrag = inner = null;
    } else {
      final frag = curFrag = fragments[fragI];
      curTo = frag.tree.prop(_stoppedInner) ?? frag.to;
      inner = _StructureCursor(frag.tree, -frag.offset);
    }
  }

  List<_ReusableMount> findMounts(int pos, Parser parser) {
    final result = <_ReusableMount>[];
    if (inner != null) {
      inner!.cursor.moveTo(pos, 1);
      for (SyntaxNode? node = inner!.cursor.node;
          node != null;
          node = node.parent) {
        final mount = node.tree?.prop(NodeProp.mounted);
        if (mount != null && mount.parser == parser) {
          for (var i = fragI; i < fragments.length; i++) {
            final frag = fragments[i];
            if (frag.from >= node.to) break;
            if (identical(frag.tree, curFrag!.tree)) {
              result.add(_ReusableMount(frag, mount, node.from - frag.offset));
            }
          }
        }
      }
    }
    return result;
  }
}


