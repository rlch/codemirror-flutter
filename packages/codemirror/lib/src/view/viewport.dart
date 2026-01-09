/// Viewport - represents the visible portion of the document.
///
/// This module provides the [Viewport] class which tracks which portion
/// of the document is currently visible on screen.
library;

import 'package:meta/meta.dart';

// ============================================================================
// Viewport - The visible document range
// ============================================================================

/// Represents a viewport range in the document.
///
/// A viewport tracks which portion of the document should be rendered.
/// The editor only renders content within the viewport (plus some margin)
/// to support efficient display of large documents.
@immutable
class Viewport {
  /// The start position in the document.
  final int from;

  /// The end position in the document.
  final int to;

  const Viewport(this.from, this.to);

  /// Create an empty viewport starting at position 0.
  const Viewport.empty() : from = 0, to = 0;

  /// The length of this viewport.
  int get length => to - from;

  /// Whether this viewport is empty.
  bool get isEmpty => from >= to;

  /// Check if a position is within this viewport.
  bool contains(int pos) => pos >= from && pos <= to;

  /// Check if a range overlaps with this viewport.
  bool overlaps(int start, int end) => start <= to && end >= from;

  /// Create a copy with updated bounds.
  Viewport copyWith({int? from, int? to}) {
    return Viewport(from ?? this.from, to ?? this.to);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Viewport && from == other.from && to == other.to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'Viewport($from, $to)';
}

// ============================================================================
// ScrollTarget - Where to scroll to
// ============================================================================

/// A target position to scroll to.
///
/// Created by effects like [EditorView.scrollIntoView].
@immutable
class ScrollTarget {
  /// The range to scroll into view.
  final Object range; // SelectionRange in full impl

  /// Vertical scroll strategy ('nearest', 'start', 'end', 'center').
  final String y;

  /// Horizontal scroll strategy.
  final String x;

  /// Extra vertical margin.
  final double yMargin;

  /// Extra horizontal margin.
  final double xMargin;

  /// Whether this is a snapshot restoration (absolute position).
  final bool isSnapshot;

  const ScrollTarget(
    this.range, {
    this.y = 'nearest',
    this.x = 'nearest',
    this.yMargin = 5,
    this.xMargin = 5,
    this.isSnapshot = false,
  });

  /// Create a scroll target from a single position.
  factory ScrollTarget.fromPos(int pos, {String y = 'nearest'}) {
    return ScrollTarget(pos, y: y);
  }

  /// Map this scroll target through document changes.
  ScrollTarget map(Object changes) {
    // In full impl, map the range through changes
    // For now, return unchanged
    return this;
  }

  /// Clip this scroll target to valid positions in the given state.
  ScrollTarget clip(Object state) {
    // In full impl, ensure range is within doc bounds
    return this;
  }
}

// ============================================================================
// ViewportConstants - Constants for viewport management
// ============================================================================

/// Constants for viewport management.
abstract final class VP {
  /// Margin around the viewport to render (in pixels).
  static const int margin = 1000;

  /// Minimum cover margin required.
  static const int minCoverMargin = 10;

  /// Maximum cover margin.
  static const int maxCoverMargin = margin ~/ 4;

  /// Maximum DOM height before scaling kicks in.
  static const int maxDOMHeight = 7000000;

  /// Maximum horizontal gap before collapsing.
  static const int maxHorizGap = 2000000;
}
