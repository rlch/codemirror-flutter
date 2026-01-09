/// Rename Symbol support for CodeMirror.
///
/// This module provides infrastructure for renaming symbols across
/// a document, with support for previewing changes before applying.
library;

import 'dart:async';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/keymap.dart';

// ============================================================================
// Rename Location
// ============================================================================

/// A location where a symbol should be renamed.
class RenameLocation {
  /// The start position of the symbol occurrence.
  final int from;

  /// The end position of the symbol occurrence.
  final int to;

  /// Optional URI for cross-file renames.
  /// 
  /// If null, the location is in the current document.
  final String? uri;

  const RenameLocation({
    required this.from,
    required this.to,
    this.uri,
  });

  /// Whether this location is in the current document.
  bool get isLocal => uri == null;

  @override
  String toString() => uri != null 
      ? 'RenameLocation($uri:$from-$to)' 
      : 'RenameLocation($from-$to)';
}

/// Result returned by a rename preparation request.
///
/// Contains information about whether rename is possible and
/// the range/placeholder text for the rename input.
class PrepareRenameResult {
  /// The range of the symbol to rename.
  final int from;
  final int to;

  /// The current name of the symbol (used as placeholder).
  final String placeholder;

  /// Optional error message if rename is not possible.
  final String? error;

  const PrepareRenameResult({
    required this.from,
    required this.to,
    required this.placeholder,
    this.error,
  });

  /// Create a result indicating rename is not possible.
  factory PrepareRenameResult.error(String message) {
    return PrepareRenameResult(
      from: 0,
      to: 0,
      placeholder: '',
      error: message,
    );
  }

  /// Whether rename is possible.
  bool get canRename => error == null;
}

/// Result returned by a rename request.
///
/// Contains all the locations where the symbol should be renamed.
class RenameResult {
  /// Locations to rename in the current document.
  final List<RenameLocation> locations;

  /// Locations to rename in other documents (workspace edits).
  /// 
  /// Map from URI to list of locations in that file.
  final Map<String, List<RenameLocation>> workspaceEdits;

  const RenameResult({
    required this.locations,
    this.workspaceEdits = const {},
  });

  /// Create an empty result (nothing to rename).
  static const RenameResult empty = RenameResult(locations: []);

  /// Whether any locations were found.
  bool get isEmpty => locations.isEmpty && workspaceEdits.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Whether this rename affects multiple files.
  bool get isWorkspaceRename => workspaceEdits.isNotEmpty;

  /// Total number of locations to rename.
  int get totalLocations => 
      locations.length + 
      workspaceEdits.values.fold(0, (sum, locs) => sum + locs.length);
}

// ============================================================================
// Rename Source
// ============================================================================

/// The type of function that prepares a rename operation.
///
/// Called when the user initiates rename (F2) to check if rename
/// is possible and get the symbol range.
/// - [state] is the current editor state
/// - [pos] is the document position of the symbol
///
/// Should return a [PrepareRenameResult] with the symbol range,
/// or null/error if rename is not available.
typedef PrepareRenameSource = FutureOr<PrepareRenameResult?> Function(
  EditorState state,
  int pos,
);

/// The type of function that performs a rename operation.
///
/// Called after the user enters a new name to get all locations
/// that should be renamed.
/// - [state] is the current editor state
/// - [pos] is the document position of the symbol
/// - [newName] is the new name entered by the user
///
/// Should return a [RenameResult] with all locations to rename.
typedef RenameSource = FutureOr<RenameResult?> Function(
  EditorState state,
  int pos,
  String newName,
);

/// Callback for handling workspace (cross-file) renames.
///
/// Called when a rename affects files other than the current document.
/// The application should handle applying edits to other files.
typedef WorkspaceRenameHandler = Future<bool> Function(
  Map<String, List<RenameLocation>> edits,
  String newName,
);

// ============================================================================
// Rename Configuration
// ============================================================================

/// Configuration options for rename symbol.
class RenameOptions {
  /// Optional prepare source to check if rename is possible.
  /// 
  /// If not provided, rename assumes it's always possible and
  /// uses the word at cursor as the placeholder.
  final PrepareRenameSource? prepareSource;

  /// Handler for workspace (cross-file) renames.
  /// 
  /// If not provided, only local renames are supported.
  final WorkspaceRenameHandler? workspaceHandler;

  /// Whether to show a preview before applying the rename.
  final bool showPreview;

  const RenameOptions({
    this.prepareSource,
    this.workspaceHandler,
    this.showPreview = false,
  });
}

/// Internal configuration for rename symbol.
class RenameConfig {
  final RenameSource source;
  final RenameOptions options;

  const RenameConfig({
    required this.source,
    required this.options,
  });
}

// ============================================================================
// Rename Facet
// ============================================================================

/// Facet for collecting rename configurations.
final Facet<RenameConfig, List<RenameConfig>> renameFacet = Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up rename symbol support.
///
/// The [source] callback is called when the user confirms a rename
/// with a new name. It should return a [RenameResult] with all
/// locations where the symbol should be renamed.
///
/// Example:
/// ```dart
/// renameSymbol(
///   (state, pos, newName) async {
///     final result = await lspClient.rename(state.doc, pos, newName);
///     if (result == null) return null;
///     return RenameResult(
///       locations: result.changes.map((c) => RenameLocation(
///         from: c.range.start,
///         to: c.range.end,
///       )).toList(),
///     );
///   },
///   RenameOptions(
///     prepareSource: (state, pos) async {
///       final prep = await lspClient.prepareRename(state.doc, pos);
///       if (prep == null) return null;
///       return PrepareRenameResult(
///         from: prep.range.start,
///         to: prep.range.end,
///         placeholder: prep.placeholder,
///       );
///     },
///   ),
/// )
/// ```
Extension renameSymbol(
  RenameSource source, [
  RenameOptions options = const RenameOptions(),
]) {
  final config = RenameConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    renameFacet.of(config),
  ]);
}

// ============================================================================
// Rename State Effects
// ============================================================================

/// State effect to trigger rename at a position.
final StateEffectType<int> _triggerRenameEffect = StateEffect.define<int>();

/// Get the trigger rename effect type for use in EditorView.
StateEffectType<int> get triggerRenameEffect => _triggerRenameEffect;

/// State effect to apply a rename.
final StateEffectType<({String newName, List<RenameLocation> locations})> 
    _applyRenameEffect = StateEffect.define();

/// Get the apply rename effect type for use in EditorView.
StateEffectType<({String newName, List<RenameLocation> locations})> 
    get applyRenameEffect => _applyRenameEffect;

/// State effect to cancel rename.
final StateEffectType<void> _cancelRenameEffect = StateEffect.define<void>();

/// Get the cancel rename effect type for use in EditorView.
StateEffectType<void> get cancelRenameEffect => _cancelRenameEffect;

// ============================================================================
// Rename Commands
// ============================================================================

/// Extract state and dispatch from command target.
/// 
/// Supports both EditorViewState (production) and record type (tests).
(EditorState, void Function(txn.Transaction)) _extractTarget(dynamic target) {
  if (target is ({EditorState state, void Function(txn.Transaction) dispatch})) {
    return (target.state, target.dispatch);
  }
  return (
    (target as dynamic).state as EditorState,
    (txn.Transaction tr) => (target as dynamic).dispatchTransaction(tr),
  );
}

/// Command to trigger rename at the current cursor position.
///
/// Typically bound to F2.
bool renameSymbolCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;

  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerRenameEffect.of(pos)],
    ),
  ]));

  return true;
}

/// Default keymap for rename symbol.
final List<KeyBinding> renameKeymap = [
  KeyBinding(key: 'F2', run: renameSymbolCommand),
];

/// Extension that adds the default rename keymap.
Extension renameKeymapExt() {
  return keymap.of(renameKeymap);
}

// ============================================================================
// Apply Rename Edits
// ============================================================================

/// Apply rename edits to create a transaction spec.
///
/// Replaces all occurrences with the new name, preserving cursor position.
TransactionSpec applyRenameEdits(
  EditorState state,
  List<RenameLocation> locations,
  String newName,
) {
  if (locations.isEmpty) {
    return const TransactionSpec();
  }

  // Filter to local locations only
  final localLocations = locations.where((l) => l.isLocal).toList();
  if (localLocations.isEmpty) {
    return const TransactionSpec();
  }

  // Sort by position (descending) to apply from end to start
  final sortedLocations = localLocations.toList()
    ..sort((a, b) => b.from.compareTo(a.from));

  // Convert to ChangeSpec
  final changes = sortedLocations.map((loc) {
    return ChangeSpec(
      from: loc.from,
      to: loc.to,
      insert: newName,
    );
  }).toList();

  // Calculate new cursor position
  final cursorPos = state.selection.main.head;
  var newCursorPos = cursorPos;

  for (final loc in sortedLocations) {
    final oldLen = loc.to - loc.from;
    final delta = newName.length - oldLen;
    
    if (loc.to <= cursorPos) {
      // Location is before cursor - adjust by length difference
      newCursorPos += delta;
    } else if (loc.from < cursorPos && cursorPos <= loc.to) {
      // Cursor is within this location - move to end of new name
      newCursorPos = loc.from + newName.length;
    }
  }

  return TransactionSpec(
    changes: changes.length == 1 
        ? changes.first 
        : ChangeSet.of(changes, state.doc.length),
    selection: EditorSelection.single(
      newCursorPos.clamp(0, state.doc.length + 
          (newName.length - (sortedLocations.first.to - sortedLocations.first.from)) * 
          sortedLocations.length),
    ),
    userEvent: 'rename',
  );
}
