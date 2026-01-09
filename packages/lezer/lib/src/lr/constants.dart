/// Constants for the LR parser.
///
/// This module defines constants needed for parsing actions, state flags,
/// and other parser internals.
library;

import 'package:meta/meta.dart';

/// Parse action constants.
///
/// Parse actions are represented as numbers treated as bitfields
/// holding different pieces of information.
@internal
class Action {
  Action._();

  /// Distinguishes between shift (off) and reduce (on) actions.
  static const int reduceFlag = 1 << 16;

  /// The first 16 bits hold the target state's id for shift actions,
  /// and the reduced term id for reduce actions.
  static const int valueMask = (1 << 16) - 1;

  /// In reduce actions, all bits beyond 18 hold the reduction's depth
  /// (the amount of stack frames it reduces).
  static const int reduceDepthShift = 19;

  /// This is set for reduce actions that reduce two instances of a
  /// repeat term to the term.
  static const int repeatFlag = 1 << 17;

  /// Goto actions are a special kind of shift that don't actually
  /// shift the current token, just add a stack frame.
  static const int gotoFlag = 1 << 17;

  /// Both shifts and reduces can have a stay flag set.
  /// For shift, it means the state should stay the same.
  /// For reduce, it means to return to the state already on the stack.
  static const int stayFlag = 1 << 18;
}

/// State flags for parser states.
@internal
class StateFlag {
  StateFlag._();

  /// Set if this state is part of a skip expression.
  static const int skipped = 1;

  /// Indicates whether this is an accepting state.
  static const int accepting = 2;
}

/// Specialization flags.
@internal
class Specialize {
  Specialize._();

  /// This specialization replaced the original token.
  static const int specialize = 0;

  /// This specialization adds a second interpretation.
  static const int extend = 1;
}

/// Term constants.
@internal
class Term {
  Term._();

  /// The value of the error term is hard coded.
  static const int err = 0;
}

/// Sequence markers.
@internal
class Seq {
  Seq._();

  /// End marker for sequences in uint16 arrays.
  static const int end = 0xffff;

  /// Done marker.
  static const int done = 0;

  /// Next marker.
  static const int next = 1;

  /// Other marker.
  static const int other = 2;
}

/// Memory layout of parse states.
@internal
class ParseState {
  ParseState._();

  /// Flags offset.
  static const int flags = 0;

  /// Actions offset.
  static const int actions = 1;

  /// Skip offset.
  static const int skip = 2;

  /// Tokenizer mask offset.
  static const int tokenizerMask = 3;

  /// Default reduce offset.
  static const int defaultReduce = 4;

  /// Forced reduce offset.
  static const int forcedReduce = 5;

  /// Total size of a state record.
  static const int size = 6;
}

/// Encoding constants for decoding parser data.
@internal
class Encode {
  Encode._();

  /// Code for big values.
  static const int bigValCode = 126;

  /// Big value placeholder.
  static const int bigVal = 0xffff;

  /// Start of encoding range.
  static const int start = 32;

  /// Gap for double quote character.
  static const int gap1 = 34; // '"'

  /// Gap for backslash character.
  static const int gap2 = 92; // '\\'

  /// Base for digit encoding.
  static const int base = 46; // (126 - 32 - 2) / 2
}

/// File version for parser data.
@internal
class FileVersion {
  FileVersion._();

  /// Current file version.
  static const int version = 14;
}

/// Lookahead constants.
@internal
class Lookahead {
  Lookahead._();

  /// Every token is assumed to have looked this far ahead.
  static const int margin = 25;
}

/// Recovery constants.
@internal
class Recover {
  Recover._();

  /// Penalty for inserting a token.
  static const int insert = 200;

  /// Penalty for deleting a token.
  static const int delete = 190;

  /// Penalty for forcing a reduce.
  static const int reduce = 100;

  /// Maximum recovery actions per step.
  static const int maxNext = 4;

  /// Maximum stack depth for insert recovery.
  static const int maxInsertStackDepth = 300;

  /// Stack depth at which insert recovery is dampened.
  static const int dampenInsertStackDepth = 120;

  /// Minimum reduction size considered "big".
  static const int minBigReduction = 2000;
}

/// Parse constants.
@internal
class Rec {
  Rec._();

  /// Recovery distance.
  static const int distance = 5;

  /// Maximum remaining stacks per recovery step.
  static const int maxRemainingPerStep = 3;

  /// Minimum buffer length before pruning.
  static const int minBufferLengthPrune = 500;

  /// Force reduce limit.
  static const int forceReduceLimit = 10;

  /// Stack depth limit before forcing reduction.
  static const int cutDepth = 2800 * 3;

  /// Target stack depth after cutting.
  static const int cutTo = 2000 * 3;

  /// Maximum left-associative reduction count.
  static const int maxLeftAssociativeReductionCount = 300;

  /// Maximum number of parallel stacks.
  static const int maxStackCount = 12;
}
