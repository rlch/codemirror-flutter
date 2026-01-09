/// Parser interface for Lezer parsers.
///
/// This module provides the [Parser] abstract class and related interfaces.
library;

import 'tree.dart';
import 'tree_fragment.dart';

/// Interface for an in-progress parse.
///
/// Can be moved forward piece-by-piece.
abstract class PartialParse {
  /// Advance the parse state by some amount.
  ///
  /// Returns the finished syntax tree when the parse completes.
  Tree? advance();

  /// The position up to which the document has been parsed.
  int get parsedPos;

  /// Tell the parse to not advance beyond the given position.
  ///
  /// [advance] will return a tree when the parse has reached the position.
  void stopAt(int pos);

  /// Reports whether [stopAt] has been called on this parse.
  int? get stoppedAt;
}

/// Interface for accessing document content during parsing.
abstract class Input {
  /// The length of the document.
  int get length;

  /// Get the chunk after the given position.
  ///
  /// The returned string should start at [from] and, if that isn't the
  /// end of the document, may be of any length greater than zero.
  String chunk(int from);

  /// Indicates whether the chunks already end at line breaks.
  ///
  /// When true, client code that wants to work by-line can avoid
  /// re-scanning them for line breaks.
  bool get lineChunks;

  /// Read the part of the document between the given positions.
  String read(int from, int to);
}

/// Simple string-based input implementation.
class StringInput implements Input {
  final String string;

  StringInput(this.string);

  @override
  int get length => string.length;

  @override
  String chunk(int from) => string.substring(from);

  @override
  bool get lineChunks => false;

  @override
  String read(int from, int to) => string.substring(from, to);
}

/// A superclass that parsers should extend.
abstract class Parser {
  /// Start a parse for a single tree.
  ///
  /// This is the method concrete parser implementations must implement.
  PartialParse createParse(
    Input input,
    List<TreeFragment> fragments,
    List<Range> ranges,
  );

  /// Start a parse, returning a [PartialParse] object.
  ///
  /// [fragments] can be passed in to make the parse incremental.
  ///
  /// By default, the entire input is parsed. You can pass [ranges],
  /// which should be a sorted array of non-empty, non-overlapping
  /// ranges, to parse only those ranges.
  PartialParse startParse(
    Object /* Input | String */ input, [
    List<TreeFragment>? fragments,
    List<Range>? ranges,
  ]) {
    final inp = input is String ? StringInput(input) : input as Input;
    final rangeList = ranges == null
        ? [Range(0, inp.length)]
        : ranges.isEmpty
            ? [Range(0, 0)]
            : ranges.map((r) => Range(r.from, r.to)).toList();
    return createParse(inp, fragments ?? [], rangeList);
  }

  /// Run a full parse, returning the resulting tree.
  Tree parse(
    Object /* Input | String */ input, [
    List<TreeFragment>? fragments,
    List<Range>? ranges,
  ]) {
    final parse = startParse(input, fragments, ranges);
    while (true) {
      final done = parse.advance();
      if (done != null) return done;
    }
  }
}

/// Parse wrapper functions are supported by some parsers to inject
/// additional parsing logic.
typedef ParseWrapper = PartialParse Function(
  PartialParse inner,
  Input input,
  List<TreeFragment> fragments,
  List<Range> ranges,
);
