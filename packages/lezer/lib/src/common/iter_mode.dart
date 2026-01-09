/// Iteration mode flags for tree traversal.
library;

/// Options that control iteration.
///
/// Can be combined with the `|` operator to enable multiple ones.
class IterMode {
  final int value;

  const IterMode._(this.value);

  /// No special iteration mode.
  static const IterMode none = IterMode._(0);

  /// When enabled, iteration will only visit [Tree] objects, not nodes
  /// packed into [TreeBuffer]s.
  static const IterMode excludeBuffers = IterMode._(1);

  /// Enable this to make iteration include anonymous nodes (such as the
  /// nodes that wrap repeated grammar constructs into a balanced tree).
  static const IterMode includeAnonymous = IterMode._(2);

  /// By default, regular mounted nodes replace their base node in iteration.
  /// Enable this to ignore them instead.
  static const IterMode ignoreMounts = IterMode._(4);

  /// This option only applies in enter-style methods.
  ///
  /// It tells the library to not enter mounted overlays if one covers
  /// the given position.
  static const IterMode ignoreOverlays = IterMode._(8);

  /// Check if this mode has a specific flag set.
  bool hasFlag(IterMode flag) => (value & flag.value) != 0;

  /// Combine two modes.
  IterMode operator |(IterMode other) {
    return IterMode._(value | other.value);
  }

  @override
  bool operator ==(Object other) {
    return other is IterMode && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}
