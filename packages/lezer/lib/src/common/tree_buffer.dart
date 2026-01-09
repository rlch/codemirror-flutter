/// Tree buffer for compact storage of syntax tree nodes.
///
/// This module provides [TreeBuffer] which stores multiple small nodes
/// in a flat buffer format for memory efficiency.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'node_set.dart';

/// A TreeBuffer stores nodes in a dense, flat buffer format.
///
/// This is used to efficiently store many small nodes without the
/// overhead of individual [Tree] objects.
class TreeBuffer {
  /// The buffer data.
  ///
  /// Contains groups of 4 integers: type id, start, end, size.
  @internal
  final Uint16List buffer;

  /// The total length covered by this buffer.
  final int length;

  /// The node set this buffer refers to.
  final NodeSet set;

  /// Create a tree buffer.
  TreeBuffer(this.buffer, this.length, this.set);

  @override
  String toString() {
    final result = StringBuffer();
    _toString(result, 0, buffer.length, 0);
    return result.toString();
  }

  void _toString(StringBuffer result, int from, int to, int offset) {
    for (var i = from; i < to;) {
      final id = buffer[i];
      final start = buffer[i + 1] + offset;
      // end is kept for debugging but not currently used
      // final end = buffer[i + 2] + offset;
      final endIndex = buffer[i + 3];

      final type = set.types[id];
      if (result.isNotEmpty) result.write(',');
      result.write(type.name);

      // If endIndex > i + 4, this node has children
      if (endIndex > i + 4) {
        result.write('(');
        _toString(result, i + 4, endIndex, start);
        result.write(')');
      }

      i = endIndex; // Move to next sibling
    }
  }

  /// Find a child at a specific range within this buffer.
  @internal
  int findChild(
    int startIndex,
    int endIndex,
    int dir,
    int pos,
    int side,
  ) {
    var pick = -1;
    for (var i = startIndex; i != endIndex; i = buffer[i + 3]) {
      if (Side.check(side, pos, buffer[i + 1], buffer[i + 2])) {
        pick = i;
        if (dir > 0) break;
      }
    }
    return pick;
  }

  /// Create a new TreeBuffer containing a slice of this buffer.
  ///
  /// [startI] and [endI] are buffer indices (not positions).
  /// [offset] is subtracted from position values in the new buffer.
  TreeBuffer slice(int startI, int endI, int offset) {
    final newBuffer = Uint16List(endI - startI);
    for (var i = startI, j = 0; i < endI;) {
      newBuffer[j] = buffer[i]; // type
      newBuffer[j + 1] = buffer[i + 1] - offset; // start
      newBuffer[j + 2] = buffer[i + 2] - offset; // end
      newBuffer[j + 3] = buffer[i + 3] - startI; // endIndex adjusted
      final nextI = buffer[i + 3];
      j += 4;
      i += 4;
      // Skip to next sibling or advance within children
      while (i < nextI && i < endI) {
        newBuffer[j] = buffer[i];
        newBuffer[j + 1] = buffer[i + 1] - offset;
        newBuffer[j + 2] = buffer[i + 2] - offset;
        newBuffer[j + 3] = buffer[i + 3] - startI;
        j += 4;
        i += 4;
      }
    }
    final newLength = buffer[startI + 2] - offset;
    return TreeBuffer(newBuffer, newLength, set);
  }
}

/// Side constants for child finding.
@internal
class Side {
  Side._();
  
  /// Strictly before position: `from < pos`
  static const int before = -2;
  
  /// Ends at or after pos, starts before pos: `to >= pos && from < pos`
  static const int atOrBefore = -1;
  
  /// Strictly contains position: `from < pos && to > pos`
  static const int around = 0;
  
  /// Starts at or before pos, ends after pos: `from <= pos && to > pos`
  static const int atOrAfter = 1;
  
  /// Strictly after position: `to > pos`
  static const int after = 2;
  
  /// Always match
  static const int dontCare = 4;
  
  /// Check if a child at [from]-[to] matches the side constraint for [pos].
  static bool check(int side, int pos, int from, int to) {
    switch (side) {
      case before: return from < pos;
      case atOrBefore: return to >= pos && from < pos;
      case around: return from < pos && to > pos;
      case atOrAfter: return from <= pos && to > pos;
      case after: return to > pos;
      case dontCare: return true;
      default: return true;
    }
  }
}
