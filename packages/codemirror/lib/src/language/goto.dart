/// Go to Definition and Find References support for CodeMirror.
///
/// This module provides infrastructure for "Go to Definition" and 
/// "Find References" functionality, allowing users to navigate to 
/// symbol definitions and find all usages.
///
/// Supports all LSP definition-related operations:
/// - Go to Definition (F12)
/// - Go to Declaration
/// - Go to Type Definition (Mod-F12)
/// - Go to Implementation
/// - Find References (Shift-F12)
library;

import 'dart:async';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/keymap.dart';

// ============================================================================
// Definition Kind
// ============================================================================

/// The kind of definition lookup.
///
/// Used to distinguish between different LSP definition operations.
enum DefinitionKind {
  /// Standard definition (textDocument/definition).
  definition,

  /// Declaration (textDocument/declaration).
  /// 
  /// Points to where a symbol is declared (e.g., forward declaration).
  declaration,

  /// Type definition (textDocument/typeDefinition).
  /// 
  /// Points to the type of a variable/expression.
  typeDefinition,

  /// Implementation (textDocument/implementation).
  /// 
  /// Points to implementations of an interface/abstract class.
  implementation,
}

// ============================================================================
// Definition Location
// ============================================================================

/// Represents a location that can be navigated to.
///
/// For locations within the current document, only [pos] is needed.
/// For locations in other files, [uri] specifies the target file.
class DefinitionLocation {
  /// The URI of the file containing the definition.
  /// 
  /// If null, the definition is in the current document.
  final String? uri;

  /// The document position of the definition.
  final int pos;

  /// Optional end position for highlighting the definition range.
  final int? end;

  /// Optional line number (0-indexed) for external files.
  final int? line;

  /// Optional column number (0-indexed) for external files.
  final int? column;

  const DefinitionLocation({
    this.uri,
    required this.pos,
    this.end,
    this.line,
    this.column,
  });

  /// Whether this location is in the current document.
  bool get isLocal => uri == null;

  /// Create a location in the current document.
  factory DefinitionLocation.local(int pos, {int? end}) {
    return DefinitionLocation(pos: pos, end: end);
  }

  /// Create a location in an external file.
  factory DefinitionLocation.external({
    required String uri,
    int? pos,
    int? line,
    int? column,
  }) {
    return DefinitionLocation(
      uri: uri,
      pos: pos ?? 0,
      line: line,
      column: column,
    );
  }

  @override
  String toString() {
    if (uri != null) {
      return 'DefinitionLocation($uri:$line:$column)';
    }
    return 'DefinitionLocation(pos: $pos${end != null ? '-$end' : ''})';
  }
}

/// Result returned by a definition source.
///
/// Can contain a single definition or multiple definitions (for overloaded
/// symbols or when multiple files define the same symbol).
class DefinitionResult {
  /// The definitions found.
  final List<DefinitionLocation> definitions;

  const DefinitionResult(this.definitions);

  /// Create a result with a single definition.
  factory DefinitionResult.single(DefinitionLocation location) {
    return DefinitionResult([location]);
  }

  /// Create an empty result (no definition found).
  static const DefinitionResult empty = DefinitionResult([]);

  /// Whether any definitions were found.
  bool get isEmpty => definitions.isEmpty;
  bool get isNotEmpty => definitions.isNotEmpty;

  /// Get the primary definition (first one).
  DefinitionLocation? get primary => definitions.isNotEmpty ? definitions.first : null;
}

// ============================================================================
// Definition Source
// ============================================================================

/// The type of function that provides definitions for positions.
///
/// Called when the user requests "go to definition" (via Ctrl+click or F12).
/// - [state] is the current editor state
/// - [pos] is the document position to find the definition for
///
/// Should return a [DefinitionResult] with the definition location(s),
/// or null/empty result if no definition is available.
typedef DefinitionSource = FutureOr<DefinitionResult?> Function(
  EditorState state,
  int pos,
);

/// Callback for navigating to a definition.
///
/// This is called when a definition is found and the user should be
/// navigated to it.
/// - [location] is the definition location to navigate to
/// - [state] is the current editor state (for context)
///
/// For local definitions (same document), the default behavior is to
/// move the selection to the definition position.
///
/// For external definitions, the application should handle opening
/// the file and navigating to the position.
typedef DefinitionNavigator = void Function(
  DefinitionLocation location,
  EditorState state,
);

// ============================================================================
// Definition Configuration
// ============================================================================

/// Configuration options for go-to-definition.
class GotoDefinitionOptions {
  /// Custom navigator for handling definition navigation.
  ///
  /// If null, local definitions will move the selection to the
  /// definition position. External definitions will be ignored
  /// unless a navigator is provided.
  final DefinitionNavigator? navigator;

  /// Whether to show an underline when Ctrl+hovering over symbols.
  final bool showHoverUnderline;

  /// Key modifier required for click-to-definition.
  /// Defaults to Ctrl (Cmd on Mac).
  final bool Function(bool ctrl, bool meta, bool alt, bool shift)? clickModifier;

  const GotoDefinitionOptions({
    this.navigator,
    this.showHoverUnderline = true,
    this.clickModifier,
  });

  /// Check if the click modifier is active.
  bool isClickModifierActive({
    required bool ctrl,
    required bool meta,
    required bool alt,
    required bool shift,
  }) {
    if (clickModifier != null) {
      return clickModifier!(ctrl, meta, alt, shift);
    }
    // Default: Ctrl on non-Mac, Cmd on Mac
    return isMac ? meta : ctrl;
  }
}

/// Internal configuration for a definition source.
class GotoDefinitionConfig {
  final DefinitionSource source;
  final GotoDefinitionOptions options;

  const GotoDefinitionConfig({
    required this.source,
    required this.options,
  });
}

// ============================================================================
// Definition Facet
// ============================================================================

/// Facet for collecting go-to-definition configurations.
///
/// This allows EditorView to find all registered definition sources.
final Facet<GotoDefinitionConfig, List<GotoDefinitionConfig>> gotoDefinitionFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up go-to-definition support.
///
/// The [source] callback is called when the user requests "go to definition"
/// (via Ctrl+click, Cmd+click on Mac, or F12). It should return a
/// [DefinitionResult] with the definition location(s), or null if no
/// definition is found.
///
/// Example:
/// ```dart
/// gotoDefinition((state, pos) async {
///   final result = await lspClient.definition(state.doc, pos);
///   if (result == null) return null;
///   return DefinitionResult.single(DefinitionLocation(
///     uri: result.uri,
///     pos: result.range.start,
///     line: result.line,
///     column: result.column,
///   ));
/// })
/// ```
///
/// Returns an extension that can be added to the editor state.
Extension gotoDefinition(
  DefinitionSource source, [
  GotoDefinitionOptions options = const GotoDefinitionOptions(),
]) {
  final config = GotoDefinitionConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    gotoDefinitionFacet.of(config),
  ]);
}

// ============================================================================
// Definition Commands
// ============================================================================

/// State effect to trigger go-to-definition at a position.
final StateEffectType<int> _triggerDefinitionEffect = StateEffect.define<int>();

/// Get the trigger definition effect type for use in EditorView.
StateEffectType<int> get triggerDefinitionEffect => _triggerDefinitionEffect;

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

/// Command to go to definition at the current cursor position.
///
/// This can be bound to F12 or another key.
bool goToDefinitionCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;
  
  // Dispatch effect to trigger definition lookup
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerDefinitionEffect.of(pos)],
    ),
  ]));
  
  return true;
}

/// Default keymap for go-to-definition.
final List<KeyBinding> gotoDefinitionKeymap = [
  KeyBinding(key: 'F12', run: goToDefinitionCommand),
  KeyBinding(key: 'Mod-b', run: goToDefinitionCommand),  // VSCode style
];

/// Extension that adds the default go-to-definition keymap.
Extension gotoDefinitionKeymapExt() {
  return keymap.of(gotoDefinitionKeymap);
}

// ============================================================================
// Find References
// ============================================================================

/// Result returned by a references source.
///
/// Contains all locations where the symbol is referenced.
class ReferencesResult {
  /// The reference locations found.
  final List<DefinitionLocation> references;

  const ReferencesResult(this.references);

  /// Create an empty result (no references found).
  static const ReferencesResult empty = ReferencesResult([]);

  /// Whether any references were found.
  bool get isEmpty => references.isEmpty;
  bool get isNotEmpty => references.isNotEmpty;
  
  /// Number of references found.
  int get length => references.length;
}

/// The type of function that provides references for positions.
///
/// Called when the user requests "find references" (via Shift+F12).
/// - [state] is the current editor state
/// - [pos] is the document position to find references for
///
/// Should return a [ReferencesResult] with the reference locations,
/// or null/empty result if no references are available.
typedef ReferencesSource = FutureOr<ReferencesResult?> Function(
  EditorState state,
  int pos,
);

/// Callback for displaying references.
///
/// This is called when references are found and should be shown to the user.
/// The application should display a list/panel of references that the user
/// can click to navigate to.
typedef ReferencesDisplay = void Function(
  ReferencesResult result,
  EditorState state,
  int originPos,
);

/// Configuration options for find-references.
class FindReferencesOptions {
  /// Custom display handler for showing references.
  ///
  /// If null, references will be logged but not displayed.
  /// Applications should provide this to show a references panel/list.
  final ReferencesDisplay? display;

  const FindReferencesOptions({
    this.display,
  });
}

/// Internal configuration for a references source.
class FindReferencesConfig {
  final ReferencesSource source;
  final FindReferencesOptions options;

  const FindReferencesConfig({
    required this.source,
    required this.options,
  });
}

/// Facet for collecting find-references configurations.
final Facet<FindReferencesConfig, List<FindReferencesConfig>> findReferencesFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up find-references support.
///
/// The [source] callback is called when the user requests "find references"
/// (via Shift+F12). It should return a [ReferencesResult] with all locations
/// where the symbol at the given position is referenced.
///
/// Example:
/// ```dart
/// findReferences(
///   (state, pos) async {
///     final refs = await lspClient.references(state.doc, pos);
///     return ReferencesResult(refs.map((r) => DefinitionLocation(
///       uri: r.uri,
///       pos: r.range.start,
///       line: r.line,
///       column: r.column,
///     )).toList());
///   },
///   FindReferencesOptions(
///     display: (result, state, pos) {
///       showReferencesPanel(result.references);
///     },
///   ),
/// )
/// ```
Extension findReferences(
  ReferencesSource source, [
  FindReferencesOptions options = const FindReferencesOptions(),
]) {
  final config = FindReferencesConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    findReferencesFacet.of(config),
  ]);
}

/// Command to find references at the current cursor position.
///
/// This can be bound to Shift+F12.
bool findReferencesCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;
  
  // Dispatch effect to trigger references lookup
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerReferencesEffect.of(pos)],
    ),
  ]));
  
  return true;
}

/// State effect to trigger find-references at a position.
final StateEffectType<int> _triggerReferencesEffect = StateEffect.define<int>();

/// Get the trigger references effect type for use in EditorView.
StateEffectType<int> get triggerReferencesEffect => _triggerReferencesEffect;

/// Default keymap for find-references.
final List<KeyBinding> findReferencesKeymap = [
  KeyBinding(key: 'Shift-F12', run: findReferencesCommand),
];

/// Extension that adds the default find-references keymap.
Extension findReferencesKeymapExt() {
  return keymap.of(findReferencesKeymap);
}

// ============================================================================
// Go to Declaration
// ============================================================================

/// The type of function that provides declarations for positions.
///
/// Called when the user requests "go to declaration".
/// Unlike definitions, declarations point to forward declarations,
/// header files, or where a symbol is first introduced.
typedef DeclarationSource = FutureOr<DefinitionResult?> Function(
  EditorState state,
  int pos,
);

/// Internal configuration for a declaration source.
class GotoDeclarationConfig {
  final DeclarationSource source;
  final GotoDefinitionOptions options;

  const GotoDeclarationConfig({
    required this.source,
    required this.options,
  });
}

/// Facet for collecting go-to-declaration configurations.
final Facet<GotoDeclarationConfig, List<GotoDeclarationConfig>> gotoDeclarationFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up go-to-declaration support.
///
/// The [source] callback is called when the user requests "go to declaration".
/// This is useful for languages that distinguish between declaration and
/// definition (e.g., C/C++ header vs source files).
Extension gotoDeclaration(
  DeclarationSource source, [
  GotoDefinitionOptions options = const GotoDefinitionOptions(),
]) {
  final config = GotoDeclarationConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    gotoDeclarationFacet.of(config),
  ]);
}

/// State effect to trigger go-to-declaration at a position.
final StateEffectType<int> _triggerDeclarationEffect = StateEffect.define<int>();

/// Get the trigger declaration effect type for use in EditorView.
StateEffectType<int> get triggerDeclarationEffect => _triggerDeclarationEffect;

/// Command to go to declaration at the current cursor position.
bool goToDeclarationCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;
  
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerDeclarationEffect.of(pos)],
    ),
  ]));
  
  return true;
}

// ============================================================================
// Go to Type Definition
// ============================================================================

/// The type of function that provides type definitions for positions.
///
/// Called when the user requests "go to type definition" (Mod-F12).
/// Returns the location of the type of the symbol at the given position.
typedef TypeDefinitionSource = FutureOr<DefinitionResult?> Function(
  EditorState state,
  int pos,
);

/// Internal configuration for a type definition source.
class GotoTypeDefinitionConfig {
  final TypeDefinitionSource source;
  final GotoDefinitionOptions options;

  const GotoTypeDefinitionConfig({
    required this.source,
    required this.options,
  });
}

/// Facet for collecting go-to-type-definition configurations.
final Facet<GotoTypeDefinitionConfig, List<GotoTypeDefinitionConfig>> gotoTypeDefinitionFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up go-to-type-definition support.
///
/// The [source] callback is called when the user requests "go to type definition".
/// This navigates to the definition of the type of a variable or expression.
///
/// Example:
/// ```dart
/// gotoTypeDefinition((state, pos) async {
///   final result = await lspClient.typeDefinition(state.doc, pos);
///   if (result == null) return null;
///   return DefinitionResult.single(DefinitionLocation(
///     uri: result.uri,
///     pos: result.range.start,
///   ));
/// })
/// ```
Extension gotoTypeDefinition(
  TypeDefinitionSource source, [
  GotoDefinitionOptions options = const GotoDefinitionOptions(),
]) {
  final config = GotoTypeDefinitionConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    gotoTypeDefinitionFacet.of(config),
  ]);
}

/// State effect to trigger go-to-type-definition at a position.
final StateEffectType<int> _triggerTypeDefinitionEffect = StateEffect.define<int>();

/// Get the trigger type definition effect type for use in EditorView.
StateEffectType<int> get triggerTypeDefinitionEffect => _triggerTypeDefinitionEffect;

/// Command to go to type definition at the current cursor position.
///
/// Typically bound to Mod-F12.
bool goToTypeDefinitionCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;
  
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerTypeDefinitionEffect.of(pos)],
    ),
  ]));
  
  return true;
}

/// Default keymap for go-to-type-definition.
final List<KeyBinding> gotoTypeDefinitionKeymap = [
  KeyBinding(key: 'Mod-F12', run: goToTypeDefinitionCommand),
];

/// Extension that adds the default go-to-type-definition keymap.
Extension gotoTypeDefinitionKeymapExt() {
  return keymap.of(gotoTypeDefinitionKeymap);
}

// ============================================================================
// Go to Implementation
// ============================================================================

/// The type of function that provides implementations for positions.
///
/// Called when the user requests "go to implementation".
/// Returns locations where an interface or abstract method is implemented.
typedef ImplementationSource = FutureOr<DefinitionResult?> Function(
  EditorState state,
  int pos,
);

/// Internal configuration for an implementation source.
class GotoImplementationConfig {
  final ImplementationSource source;
  final GotoDefinitionOptions options;

  const GotoImplementationConfig({
    required this.source,
    required this.options,
  });
}

/// Facet for collecting go-to-implementation configurations.
final Facet<GotoImplementationConfig, List<GotoImplementationConfig>> gotoImplementationFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up go-to-implementation support.
///
/// The [source] callback is called when the user requests "go to implementation".
/// This navigates to implementations of interfaces, abstract classes, or methods.
///
/// Example:
/// ```dart
/// gotoImplementation((state, pos) async {
///   final result = await lspClient.implementation(state.doc, pos);
///   if (result == null) return null;
///   return DefinitionResult(result.map((loc) => DefinitionLocation(
///     uri: loc.uri,
///     pos: loc.range.start,
///   )).toList());
/// })
/// ```
Extension gotoImplementation(
  ImplementationSource source, [
  GotoDefinitionOptions options = const GotoDefinitionOptions(),
]) {
  final config = GotoImplementationConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    gotoImplementationFacet.of(config),
  ]);
}

/// State effect to trigger go-to-implementation at a position.
final StateEffectType<int> _triggerImplementationEffect = StateEffect.define<int>();

/// Get the trigger implementation effect type for use in EditorView.
StateEffectType<int> get triggerImplementationEffect => _triggerImplementationEffect;

/// Command to go to implementation at the current cursor position.
bool goToImplementationCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;
  
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerImplementationEffect.of(pos)],
    ),
  ]));
  
  return true;
}

/// Default keymap for go-to-implementation.
final List<KeyBinding> gotoImplementationKeymap = [
  KeyBinding(key: 'Ctrl-F12', run: goToImplementationCommand),
];

/// Extension that adds the default go-to-implementation keymap.
Extension gotoImplementationKeymapExt() {
  return keymap.of(gotoImplementationKeymap);
}

// ============================================================================
// Combined Keymap
// ============================================================================

/// Combined keymap for all definition-related navigation.
///
/// - F12: Go to Definition
/// - Mod-b: Go to Definition (VSCode style)
/// - Mod-F12: Go to Type Definition
/// - Ctrl-F12: Go to Implementation
/// - Shift-F12: Find References
final List<KeyBinding> allDefinitionKeymap = [
  ...gotoDefinitionKeymap,
  ...gotoTypeDefinitionKeymap,
  ...gotoImplementationKeymap,
  ...findReferencesKeymap,
];

/// Extension that adds keymaps for all definition-related navigation.
Extension allDefinitionKeymapExt() {
  return keymap.of(allDefinitionKeymap);
}
