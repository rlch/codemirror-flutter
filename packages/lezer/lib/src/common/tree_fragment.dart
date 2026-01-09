/// Tree fragments for incremental parsing.
///
/// This module provides [TreeFragment] for tracking reusable parts of
/// old trees during incremental parsing.
library;

import 'tree.dart';

/// Represents a changed range in the document.
class ChangedRange {
  /// The start of the change in the start document.
  final int fromA;

  /// The end of the change in the start document.
  final int toA;

  /// The start of the replacement in the new document.
  final int fromB;

  /// The end of the replacement in the new document.
  final int toB;

  const ChangedRange({
    required this.fromA,
    required this.toA,
    required this.fromB,
    required this.toB,
  });
}

/// Flags for fragment openness.
class _Open {
  _Open._();
  static const int start = 1;
  static const int end = 2;
}

/// Tree fragments are used during incremental parsing to track parts
/// of old trees that can be reused in a new parse.
///
/// An array of fragments is used to track regions of an old tree whose
/// nodes might be reused in new parses.
class TreeFragment {
  /// The start of the unchanged range pointed to by this fragment.
  ///
  /// This refers to an offset in the _updated_ document.
  final int from;

  /// The end of the unchanged range.
  final int to;

  /// The tree that this fragment is based on.
  final Tree tree;

  /// The offset between the fragment's tree and the document.
  ///
  /// Add this when going from document to tree positions, subtract it
  /// to go from tree to document positions.
  final int offset;

  /// Internal openness flags.
  final int _open;

  /// Construct a tree fragment.
  ///
  /// You'll usually want to use [addTree] and [applyChanges] instead.
  TreeFragment(
    this.from,
    this.to,
    this.tree,
    this.offset, [
    bool openStart = false,
    bool openEnd = false,
  ]) : _open = (openStart ? _Open.start : 0) | (openEnd ? _Open.end : 0);

  /// Whether the start of the fragment represents the start of a parse,
  /// or the end of a change.
  bool get openStart => (_open & _Open.start) > 0;

  /// Whether the end of the fragment represents the end of a
  /// full-document parse, or the start of a change.
  bool get openEnd => (_open & _Open.end) > 0;

  /// Create a set of fragments from a freshly parsed tree, or update
  /// an existing set by replacing overlapping fragments.
  ///
  /// When [partial] is true, the parse is treated as incomplete, and
  /// the resulting fragment has [openEnd] set to true.
  static List<TreeFragment> addTree(
    Tree tree, [
    List<TreeFragment> fragments = const [],
    bool partial = false,
  ]) {
    final result = [TreeFragment(0, tree.length, tree, 0, false, partial)];
    for (final f in fragments) {
      if (f.to > tree.length) result.add(f);
    }
    return result;
  }

  /// Apply a set of edits to an array of fragments.
  ///
  /// Removes or splits fragments as necessary to remove edited ranges,
  /// and adjusts offsets for fragments that moved.
  static List<TreeFragment> applyChanges(
    List<TreeFragment> fragments,
    List<ChangedRange> changes, [
    int minGap = 128,
  ]) {
    if (changes.isEmpty) return fragments;

    final result = <TreeFragment>[];
    var fI = 1;
    TreeFragment? nextF = fragments.isNotEmpty ? fragments[0] : null;

    for (var cI = 0, pos = 0, off = 0;;) {
      final nextC = cI < changes.length ? changes[cI] : null;
      final nextPos = nextC?.fromA ?? 1000000000;

      if (nextPos - pos >= minGap) {
        while (nextF != null && nextF.from < nextPos) {
          TreeFragment? cut = nextF;
          if (pos >= cut.from || nextPos <= cut.to || off != 0) {
            final fFrom = (cut.from < pos ? pos : cut.from) - off;
            final fTo = (cut.to > nextPos ? nextPos : cut.to) - off;
            cut = fFrom >= fTo
                ? null
                : TreeFragment(
                    fFrom, fTo, cut.tree, cut.offset + off, cI > 0, nextC != null);
          }
          if (cut != null) result.add(cut);
          if (nextF.to > nextPos) break;
          nextF = fI < fragments.length ? fragments[fI++] : null;
        }
      }
      if (nextC == null) break;
      pos = nextC.toA;
      off = nextC.toA - nextC.toB;
      cI++;
    }
    return result;
  }
}
