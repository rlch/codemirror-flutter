/// Height map - estimates and tracks line heights for virtualized rendering.
///
/// This module provides [HeightOracle] for estimating line heights and
/// [HeightMap] for tracking the actual heights of rendered lines.
library;

import 'dart:math' as math;

import '../text/text.dart';
import 'block_info.dart';
import 'view_update.dart';

// ============================================================================
// HeightOracle - Estimates line heights
// ============================================================================

/// Oracle for estimating line heights.
///
/// This tracks the measured line height, character width, and whether
/// line wrapping is enabled to provide height estimates for unrendered
/// content.
class HeightOracle {
  /// The measured line height.
  double lineHeight = 14.0;

  /// The measured character width.
  double charWidth = 7.0;

  /// The measured text height (may differ from line height).
  double textHeight = 14.0;

  /// The estimated number of characters per line (for wrapping).
  double lineLength = 30.0;

  /// Whether line wrapping is enabled.
  bool lineWrapping;

  /// Height per character for wrapping lines.
  double get heightPerChar =>
      lineWrapping ? lineHeight / lineLength : 0;

  /// Height per line (non-wrapping).
  double get heightPerLine => lineHeight;

  HeightOracle([this.lineWrapping = false]);

  /// Set the document for this oracle.
  ///
  /// Returns this oracle (for chaining).
  HeightOracle setDoc(Text doc) {
    // Store doc length for potential calculations
    return this;
  }

  /// Check if the oracle needs to refresh based on whitespace style.
  bool mustRefreshForWrapping(String whiteSpace) {
    final wrapping = whiteSpace == 'pre-wrap' || whiteSpace == 'break-spaces';
    return wrapping != lineWrapping;
  }

  /// Check if the oracle needs to refresh based on measured heights.
  bool mustRefreshForHeights(List<double> heights) {
    if (heights.isEmpty) return false;

    // Check if any measured height differs significantly from estimate
    for (final h in heights) {
      if ((h - lineHeight).abs() > 2) return true;
    }
    return false;
  }

  /// Refresh the oracle with new measurements.
  ///
  /// Returns true if values changed significantly.
  bool refresh(
    String whiteSpace,
    double lineHeight,
    double charWidth,
    double textHeight,
    double lineLength,
    List<double> heights,
  ) {
    final wrapping = whiteSpace == 'pre-wrap' || whiteSpace == 'break-spaces';
    final changed = this.lineHeight != lineHeight ||
        this.charWidth != charWidth ||
        this.textHeight != textHeight ||
        lineWrapping != wrapping;

    this.lineHeight = lineHeight;
    this.charWidth = charWidth;
    this.textHeight = textHeight;
    this.lineLength = lineLength;
    lineWrapping = wrapping;

    return changed;
  }

  /// Estimate the height of a range of text.
  double heightForRange(int from, int to) {
    final length = to - from;
    if (lineWrapping && lineLength > 0) {
      return ((length / lineLength).ceil()) * lineHeight;
    }
    return lineHeight;
  }

  /// Estimate the height of a line given its length.
  double heightForLine(int length) {
    if (!lineWrapping || lineLength <= 0) return lineHeight;
    return math.max(1, (length / lineLength).ceil()) * lineHeight;
  }
}

// ============================================================================
// QueryType - How to query the height map
// ============================================================================

/// How to query a position in the height map.
enum QueryType {
  /// Query by document position.
  byPos,

  /// Query by pixel height.
  byHeight,
}

// ============================================================================
// HeightMap - Tracks document heights
// ============================================================================

/// A data structure tracking heights of document content.
///
/// This is a tree structure that allows efficient queries and updates
/// of line heights, supporting virtualized rendering of large documents.
abstract class HeightMap {
  /// The length of the content covered by this height map.
  int get length;

  /// The total height of this height map.
  double get height;

  /// Create an empty height map.
  factory HeightMap.empty() = HeightMapLine.empty;

  /// Apply changes to the height map.
  HeightMap applyChanges(
    List<Object> decorations, // DecorationSet in full impl
    Text oldDoc,
    HeightOracle oracle,
    List<Object> changes, // ChangedRange in full impl
  );

  /// Update heights based on measured values.
  HeightMap updateHeight(
    HeightOracle oracle,
    int offset,
    bool force,
    Object measured, // MeasuredHeights in full impl
  );

  /// Get the block at a given position.
  BlockInfo blockAt(double height, HeightOracle oracle, int top, int offset);

  /// Get the line at a given position or height.
  BlockInfo lineAt(
    num value,
    QueryType type,
    HeightOracle oracle,
    int top,
    int offset,
  );

  /// Iterate over all lines in a range.
  void forEachLine(
    int from,
    int to,
    HeightOracle oracle,
    int top,
    int offset,
    void Function(BlockInfo block) callback,
  );
}

// ============================================================================
// HeightMapLine - A single line in the height map
// ============================================================================

/// A height map node representing a single line.
class HeightMapLine implements HeightMap {
  @override
  final int length;

  @override
  double height;

  /// Whether this line's height has been measured.
  bool measured;

  HeightMapLine(this.length, this.height, [this.measured = false]);

  /// Create an empty line.
  factory HeightMapLine.empty() => HeightMapLine(0, 0);

  @override
  HeightMap applyChanges(
    List<Object> decorations,
    Text oldDoc,
    HeightOracle oracle,
    List<Object> changes,
  ) {
    // Simplified implementation - just estimate heights for changed ranges
    // Full implementation would handle decorations and block widgets
    if (changes.isEmpty) return this;

    // Compute new length from changes
    // Each ChangedRange has (fromA, toA, fromB, toB) - the change replaces
    // oldDoc[fromA:toA] with newDoc[fromB:toB]
    var newLength = length;
    for (final change in changes) {
      if (change is ChangedRange) {
        newLength += (change.toB - change.fromB) - (change.toA - change.fromA);
      }
    }
    return HeightMapLine(newLength, oracle.heightForLine(newLength));
  }

  @override
  HeightMap updateHeight(
    HeightOracle oracle,
    int offset,
    bool force,
    Object measured,
  ) {
    // Update height based on measured values
    if (force) {
      height = oracle.heightForLine(length);
      measured = false;
    }
    return this;
  }

  @override
  BlockInfo blockAt(double height, HeightOracle oracle, int top, int offset) {
    return BlockInfo(offset, length, top.toDouble(), this.height);
  }

  @override
  BlockInfo lineAt(
    num value,
    QueryType type,
    HeightOracle oracle,
    int top,
    int offset,
  ) {
    return BlockInfo(offset, length, top.toDouble(), height);
  }

  @override
  void forEachLine(
    int from,
    int to,
    HeightOracle oracle,
    int top,
    int offset,
    void Function(BlockInfo block) callback,
  ) {
    if (from <= offset + length && to >= offset) {
      callback(BlockInfo(offset, length, top.toDouble(), height));
    }
  }
}

// ============================================================================
// HeightMapBranch - A branch node in the height map tree
// ============================================================================

/// A branch node in the height map, containing multiple children.
class HeightMapBranch implements HeightMap {
  final List<HeightMap> children;

  @override
  int get length => children.fold(0, (sum, c) => sum + c.length);

  @override
  double get height => children.fold(0.0, (sum, c) => sum + c.height);

  HeightMapBranch(this.children);

  @override
  HeightMap applyChanges(
    List<Object> decorations,
    Text oldDoc,
    HeightOracle oracle,
    List<Object> changes,
  ) {
    // Simplified: rebuild with new content
    // Full implementation would surgically update changed regions
    return HeightMapLine(
      oldDoc.length,
      oracle.heightForLine(oldDoc.length),
    );
  }

  @override
  HeightMap updateHeight(
    HeightOracle oracle,
    int offset,
    bool force,
    Object measured,
  ) {
    // Update all children
    for (var i = 0; i < children.length; i++) {
      children[i] = children[i].updateHeight(oracle, offset, force, measured);
      offset += children[i].length;
    }
    return this;
  }

  @override
  BlockInfo blockAt(double height, HeightOracle oracle, int top, int offset) {
    var y = top.toDouble();
    for (final child in children) {
      if (y + child.height > height) {
        return child.blockAt(height, oracle, y.toInt(), offset);
      }
      y += child.height;
      offset += child.length;
    }
    // Return last block if past end
    return children.last.blockAt(
      height,
      oracle,
      (y - children.last.height).toInt(),
      offset - children.last.length,
    );
  }

  @override
  BlockInfo lineAt(
    num value,
    QueryType type,
    HeightOracle oracle,
    int top,
    int offset,
  ) {
    var y = top.toDouble();
    var pos = offset;

    for (final child in children) {
      final childEnd = pos + child.length;
      final childBottom = y + child.height;

      if (type == QueryType.byPos) {
        if (value < childEnd) {
          return child.lineAt(value, type, oracle, y.toInt(), pos);
        }
      } else {
        if (value < childBottom) {
          return child.lineAt(value, type, oracle, y.toInt(), pos);
        }
      }

      y = childBottom;
      pos = childEnd;
    }

    // Return last line if past end
    return children.last.lineAt(
      value,
      type,
      oracle,
      (y - children.last.height).toInt(),
      pos - children.last.length,
    );
  }

  @override
  void forEachLine(
    int from,
    int to,
    HeightOracle oracle,
    int top,
    int offset,
    void Function(BlockInfo block) callback,
  ) {
    var y = top.toDouble();
    var pos = offset;

    for (final child in children) {
      final childEnd = pos + child.length;
      if (childEnd >= from && pos <= to) {
        child.forEachLine(from, to, oracle, y.toInt(), pos, callback);
      }
      y += child.height;
      pos = childEnd;
      if (pos > to) break;
    }
  }
}

// ============================================================================
// MeasuredHeights - Heights measured from rendered content
// ============================================================================

/// Heights measured from rendered document content.
class MeasuredHeights {
  /// The document position where measurement started.
  final int from;

  /// The measured heights of each visible line.
  final List<double> heights;

  MeasuredHeights(this.from, this.heights);
}

// ============================================================================
// Height change tracking
// ============================================================================

/// Flag indicating whether heights changed during an update.
bool _heightChangeFlag = false;

/// Get and clear the height change flag.
bool get heightChangeFlag {
  final result = _heightChangeFlag;
  return result;
}

/// Clear the height change flag.
void clearHeightChangeFlag() {
  _heightChangeFlag = false;
}

/// Set the height change flag.
void setHeightChangeFlag() {
  _heightChangeFlag = true;
}
