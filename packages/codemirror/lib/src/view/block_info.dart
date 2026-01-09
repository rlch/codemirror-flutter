/// Block info - describes line blocks in the document.
///
/// This module provides [BlockInfo], which represents information about
/// a line block (a single line or a block of collapsed content) in the
/// document, including its position and height.
library;

import 'package:meta/meta.dart';

// ============================================================================
// BlockType - Types of blocks in the document
// ============================================================================

/// The type of a block in the document.
enum BlockType {
  /// Regular text content.
  text,

  /// A widget that replaces some content.
  widgetBefore,

  /// A widget after text.
  widgetAfter,

  /// A widget range (collapsed content).
  widgetRange,
}

// ============================================================================
// BlockInfo - Information about a document block
// ============================================================================

/// Information about a line or block of lines in the document.
///
/// This is used by the view to track the height and position of document
/// content, supporting virtual scrolling of large documents.
@immutable
class BlockInfo {
  /// The start position of this block in the document.
  final int from;

  /// The length of this block in the document.
  final int length;

  /// The vertical position of the top of this block (in pixels).
  final double top;

  /// The height of this block (in pixels).
  final double height;

  /// For composite blocks, the child blocks. Otherwise null.
  /// Can hold: BlockType, List<BlockInfo>, or a widget decoration.
  final Object? _content;

  const BlockInfo(this.from, this.length, this.top, this.height, [this._content]);

  /// The end position of this block in the document.
  int get to => from + length;

  /// The vertical position of the bottom of this block.
  double get bottom => top + height;

  /// The type of this block.
  ///
  /// For composite blocks (lines with multiple sub-blocks), returns
  /// the list of child BlockInfo.
  Object get type {
    if (_content is BlockType) return _content as BlockType;
    if (_content is List<BlockInfo>) return _content as List<BlockInfo>;
    // If _content is a widget decoration, determine type from it
    if (_content != null && _content is! int) return BlockType.widgetBefore;
    return BlockType.text;
  }

  /// For composite blocks, returns the child blocks.
  List<BlockInfo>? get children {
    if (_content is List<BlockInfo>) return _content;
    return null;
  }

  /// If this is a widget block, returns the associated widget.
  /// Returns null for text blocks.
  Object? get widget {
    // In JS, widget blocks store a PointDecoration in _content
    // which has a .widget property. We store the widget directly.
    if (_content is! BlockType && _content is! List<BlockInfo> && _content is! int) {
      return _content;
    }
    return null;
  }

  /// Whether this block is a widget block (not regular text).
  bool get isWidget {
    final t = type;
    if (t is List<BlockInfo>) return false;
    return t == BlockType.widgetBefore ||
        t == BlockType.widgetAfter ||
        t == BlockType.widgetRange;
  }

  /// Create a copy with scaled top and height values.
  BlockInfo scale(double scale) {
    if (scale == 1) return this;
    return BlockInfo(from, length, top * scale, height * scale, _content);
  }

  /// Create a new block with adjusted position.
  BlockInfo withTop(double newTop) {
    if (newTop == top) return this;
    return BlockInfo(from, length, newTop, height, _content);
  }

  /// Create a new block with adjusted height.
  BlockInfo withHeight(double newHeight) {
    if (newHeight == height) return this;
    return BlockInfo(from, length, top, newHeight, _content);
  }

  @override
  String toString() =>
      'BlockInfo($from+$length, top: ${top.toStringAsFixed(1)}, '
      'height: ${height.toStringAsFixed(1)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockInfo &&
          from == other.from &&
          length == other.length &&
          top == other.top &&
          height == other.height;

  @override
  int get hashCode => Object.hash(from, length, top, height);
}
