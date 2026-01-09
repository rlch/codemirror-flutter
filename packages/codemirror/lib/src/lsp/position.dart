/// Position types and utilities for LSP integration.
///
/// Provides conversions between character offsets and line/character positions.
library;

/// A position in a text document expressed as line and character offset.
///
/// Line and character are both zero-indexed.
/// 
/// Named `LspPosition` to avoid conflicts with other Position types.
class LspPosition {
  /// Zero-indexed line number.
  final int line;

  /// Zero-indexed character offset within the line.
  final int character;

  const LspPosition({required this.line, required this.character});

  /// Create a position at the start of the document.
  const LspPosition.zero() : line = 0, character = 0;

  @override
  bool operator ==(Object other) =>
      other is LspPosition && line == other.line && character == other.character;

  @override
  int get hashCode => Object.hash(line, character);

  @override
  String toString() => 'LspPosition($line:$character)';

  /// Returns true if this position is before [other].
  bool isBefore(LspPosition other) {
    if (line < other.line) return true;
    if (line > other.line) return false;
    return character < other.character;
  }

  /// Returns true if this position is after [other].
  bool isAfter(LspPosition other) {
    if (line > other.line) return true;
    if (line < other.line) return false;
    return character > other.character;
  }
}

/// A range in a text document expressed as start and end positions.
/// 
/// Named `LspRange` to avoid conflicts with other Range types.
class LspRange {
  /// The start position (inclusive).
  final LspPosition start;

  /// The end position (exclusive).
  final LspPosition end;

  const LspRange({required this.start, required this.end});

  /// Create a zero-length range at the given position.
  LspRange.collapsed(LspPosition pos) : start = pos, end = pos;

  @override
  bool operator ==(Object other) =>
      other is LspRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LspRange($start-$end)';

  /// Returns true if this range contains [position].
  bool contains(LspPosition position) {
    return !position.isBefore(start) && position.isBefore(end);
  }

  /// Returns true if this range is empty (start equals end).
  bool get isEmpty => start == end;
}

/// Utilities for converting between offsets and positions.
extension LspPositionConversions on String {
  /// Convert a character offset to a line/character position.
  ///
  /// Returns a position with line and character both zero-indexed.
  LspPosition offsetToLspPosition(int offset) {
    var line = 0;
    var character = 0;
    final clampedOffset = offset.clamp(0, length);
    
    for (var i = 0; i < clampedOffset; i++) {
      if (this[i] == '\n') {
        line++;
        character = 0;
      } else {
        character++;
      }
    }
    return LspPosition(line: line, character: character);
  }

  /// Convert a line/character position to a character offset.
  ///
  /// If the position is beyond the document, returns the document length.
  int lspPositionToOffset(LspPosition position) {
    var offset = 0;
    var line = 0;
    
    // Find the start of the target line
    while (line < position.line && offset < length) {
      if (this[offset] == '\n') line++;
      offset++;
    }
    
    // Add the character offset within the line
    return (offset + position.character).clamp(0, length);
  }

  /// Get the position at the end of the document.
  LspPosition get endLspPosition {
    return offsetToLspPosition(length);
  }

  /// Get the number of lines in the document.
  int get lineCount {
    if (isEmpty) return 1;
    var count = 1;
    for (var i = 0; i < length; i++) {
      if (this[i] == '\n') count++;
    }
    return count;
  }
}
