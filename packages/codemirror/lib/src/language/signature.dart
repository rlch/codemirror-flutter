/// Signature Help support for CodeMirror.
///
/// This module provides infrastructure for displaying function signature
/// hints as the user types, showing parameter information and highlighting
/// the active parameter.
library;

import 'dart:async';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import '../state/transaction.dart' hide Transaction;
import '../state/transaction.dart' as txn show Transaction;
import '../view/keymap.dart';

// ============================================================================
// Signature Information Types
// ============================================================================

/// Information about a single parameter in a signature.
class ParameterInfo {
  /// The label/name of the parameter (e.g., "int count" or just "count").
  final String label;

  /// Optional documentation for this parameter.
  final String? documentation;

  const ParameterInfo({
    required this.label,
    this.documentation,
  });

  @override
  String toString() => 'ParameterInfo($label)';
}

/// Information about a function signature.
class SignatureInfo {
  /// The full signature label (e.g., "void print(Object? object)").
  final String label;

  /// Optional documentation for the function.
  final String? documentation;

  /// The parameters of the signature.
  final List<ParameterInfo> parameters;

  /// The index of the active parameter (0-based).
  /// 
  /// This indicates which parameter the cursor is currently positioned at.
  /// A value of -1 means no parameter is active.
  final int activeParameter;

  const SignatureInfo({
    required this.label,
    this.documentation,
    this.parameters = const [],
    this.activeParameter = 0,
  });

  /// Create a copy with a different active parameter.
  SignatureInfo withActiveParameter(int index) {
    return SignatureInfo(
      label: label,
      documentation: documentation,
      parameters: parameters,
      activeParameter: index.clamp(-1, parameters.length - 1),
    );
  }

  @override
  String toString() => 'SignatureInfo($label, active: $activeParameter)';
}

/// Result returned by a signature help source.
///
/// Contains one or more signatures (for overloaded functions) and
/// indicates which signature and parameter are currently active.
class SignatureResult {
  /// The available signatures.
  final List<SignatureInfo> signatures;

  /// The index of the active signature (0-based).
  final int activeSignature;

  /// The position in the document where the signature help was triggered.
  /// 
  /// Used to track when signature help should be dismissed.
  final int triggerPos;

  const SignatureResult({
    required this.signatures,
    this.activeSignature = 0,
    required this.triggerPos,
  });

  /// Create an empty result (no signatures).
  static const SignatureResult empty = SignatureResult(
    signatures: [],
    triggerPos: 0,
  );

  /// Whether any signatures were found.
  bool get isEmpty => signatures.isEmpty;
  bool get isNotEmpty => signatures.isNotEmpty;

  /// Get the active signature.
  SignatureInfo? get active =>
      signatures.isNotEmpty && activeSignature >= 0 && activeSignature < signatures.length
          ? signatures[activeSignature]
          : null;

  /// Create a copy with a different active signature.
  SignatureResult withActiveSignature(int index) {
    return SignatureResult(
      signatures: signatures,
      activeSignature: index.clamp(0, signatures.length - 1),
      triggerPos: triggerPos,
    );
  }

  @override
  String toString() =>
      'SignatureResult(${signatures.length} signatures, active: $activeSignature)';
}

// ============================================================================
// Signature Help Source
// ============================================================================

/// The type of function that provides signature help.
///
/// Called when signature help is requested (e.g., after typing '(').
/// - [state] is the current editor state
/// - [pos] is the document position where signature help was triggered
///
/// Should return a [SignatureResult] with available signatures,
/// or null if no signature help is available at this position.
typedef SignatureSource = FutureOr<SignatureResult?> Function(
  EditorState state,
  int pos,
);

/// Callback for updating the active parameter as the cursor moves.
///
/// Called when the cursor position changes while signature help is active.
/// - [state] is the current editor state
/// - [result] is the current signature result
/// - [cursorPos] is the new cursor position
///
/// Should return an updated [SignatureResult] with the correct active
/// parameter, or null to dismiss signature help.
typedef SignatureUpdater = FutureOr<SignatureResult?> Function(
  EditorState state,
  SignatureResult result,
  int cursorPos,
);

// ============================================================================
// Signature Help Configuration
// ============================================================================

/// Configuration options for signature help.
class SignatureHelpOptions {
  /// Characters that trigger signature help when typed.
  /// 
  /// Defaults to ['(', ','] which covers most programming languages.
  final List<String> triggerCharacters;

  /// Characters that dismiss signature help when typed.
  /// 
  /// Defaults to [')'] to close when the function call ends.
  final List<String> retriggerCharacters;

  /// Optional updater to recalculate active parameter when cursor moves.
  /// 
  /// If not provided, a simple comma-counting heuristic is used.
  final SignatureUpdater? updater;

  /// Whether signature help should automatically show on trigger characters.
  /// 
  /// Defaults to true.
  final bool autoTrigger;

  /// Delay in milliseconds before showing signature help after trigger.
  /// 
  /// Defaults to 0 (immediate).
  final int delay;

  const SignatureHelpOptions({
    this.triggerCharacters = const ['(', ','],
    this.retriggerCharacters = const [')'],
    this.updater,
    this.autoTrigger = true,
    this.delay = 0,
  });
}

/// Internal configuration for a signature help source.
class SignatureHelpConfig {
  final SignatureSource source;
  final SignatureHelpOptions options;

  const SignatureHelpConfig({
    required this.source,
    required this.options,
  });
}

// ============================================================================
// Signature Help Facet
// ============================================================================

/// Facet for collecting signature help configurations.
///
/// This allows EditorView to find all registered signature sources.
final Facet<SignatureHelpConfig, List<SignatureHelpConfig>> signatureHelpFacet =
    Facet.define(
  FacetConfig(
    combine: (configs) => configs.toList(),
  ),
);

/// Set up signature help support.
///
/// The [source] callback is called when signature help is triggered
/// (by typing '(' or invoking the command). It should return a
/// [SignatureResult] with the available signatures.
///
/// Example:
/// ```dart
/// signatureHelp((state, pos) async {
///   final result = await lspClient.signatureHelp(state.doc, pos);
///   if (result == null) return null;
///   return SignatureResult(
///     signatures: result.signatures.map((s) => SignatureInfo(
///       label: s.label,
///       documentation: s.documentation,
///       parameters: s.parameters.map((p) => ParameterInfo(
///         label: p.label,
///         documentation: p.documentation,
///       )).toList(),
///       activeParameter: s.activeParameter,
///     )).toList(),
///     activeSignature: result.activeSignature,
///     triggerPos: pos,
///   );
/// })
/// ```
///
/// Returns an extension that can be added to the editor state.
Extension signatureHelp(
  SignatureSource source, [
  SignatureHelpOptions options = const SignatureHelpOptions(),
]) {
  final config = SignatureHelpConfig(
    source: source,
    options: options,
  );

  return ExtensionList([
    signatureHelpFacet.of(config),
  ]);
}

// ============================================================================
// Signature Help State Effects
// ============================================================================

/// State effect to trigger signature help at a position.
final StateEffectType<int> _triggerSignatureEffect = StateEffect.define<int>();

/// Get the trigger signature effect type for use in EditorView.
StateEffectType<int> get triggerSignatureEffect => _triggerSignatureEffect;

/// State effect to dismiss signature help.
final StateEffectType<void> _dismissSignatureEffect = StateEffect.define<void>();

/// Get the dismiss signature effect type for use in EditorView.
StateEffectType<void> get dismissSignatureEffect => _dismissSignatureEffect;

// ============================================================================
// Signature Help Commands
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

/// Command to trigger signature help at the current cursor position.
///
/// This can be bound to Ctrl+Shift+Space or another key.
bool triggerSignatureHelpCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);
  final pos = state.selection.main.head;

  // Dispatch effect to trigger signature help
  dispatch(state.update([
    TransactionSpec(
      effects: [_triggerSignatureEffect.of(pos)],
    ),
  ]));

  return true;
}

/// Command to dismiss signature help.
bool dismissSignatureHelpCommand(dynamic target) {
  final (state, dispatch) = _extractTarget(target);

  dispatch(state.update([
    TransactionSpec(
      effects: [_dismissSignatureEffect.of(null)],
    ),
  ]));

  return true;
}

/// Default keymap for signature help.
final List<KeyBinding> signatureHelpKeymap = [
  KeyBinding(key: 'Ctrl-Shift-Space', run: triggerSignatureHelpCommand),
  KeyBinding(mac: 'Cmd-Shift-Space', run: triggerSignatureHelpCommand),
];

/// Extension that adds the default signature help keymap.
Extension signatureHelpKeymapExt() {
  return keymap.of(signatureHelpKeymap);
}

// ============================================================================
// Active Parameter Detection
// ============================================================================

/// Simple heuristic to detect the active parameter index.
///
/// Counts commas between the trigger position and cursor position,
/// accounting for nested parentheses and string literals.
int detectActiveParameter(String text, int triggerPos, int cursorPos) {
  if (cursorPos <= triggerPos) return 0;

  final substring = text.substring(triggerPos, cursorPos);
  int paramIndex = 0;
  int parenDepth = 0;
  int bracketDepth = 0;
  int braceDepth = 0;
  bool inString = false;
  String? stringChar;

  for (var i = 0; i < substring.length; i++) {
    final char = substring[i];

    // Handle string literals
    if (!inString && (char == '"' || char == "'" || char == '`')) {
      inString = true;
      stringChar = char;
      continue;
    }
    if (inString) {
      if (char == stringChar && (i == 0 || substring[i - 1] != r'\')) {
        inString = false;
        stringChar = null;
      }
      continue;
    }

    // Track nesting
    switch (char) {
      case '(':
        parenDepth++;
      case ')':
        parenDepth--;
      case '[':
        bracketDepth++;
      case ']':
        bracketDepth--;
      case '{':
        braceDepth++;
      case '}':
        braceDepth--;
      case ',':
        // Only count commas at the top level of this function call
        if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0) {
          paramIndex++;
        }
    }

    // If we've closed more parens than opened, we've left the function call
    if (parenDepth < 0) {
      return -1;
    }
  }

  return paramIndex;
}

/// Check if the cursor is still within a function call.
///
/// Returns true if the cursor is between the opening '(' and closing ')'.
bool isWithinFunctionCall(String text, int triggerPos, int cursorPos) {
  if (cursorPos < triggerPos) return false;

  final substring = text.substring(triggerPos, cursorPos);
  int parenDepth = 0;
  bool inString = false;
  String? stringChar;

  for (var i = 0; i < substring.length; i++) {
    final char = substring[i];

    // Handle string literals
    if (!inString && (char == '"' || char == "'" || char == '`')) {
      inString = true;
      stringChar = char;
      continue;
    }
    if (inString) {
      if (char == stringChar && (i == 0 || substring[i - 1] != r'\')) {
        inString = false;
        stringChar = null;
      }
      continue;
    }

    switch (char) {
      case '(':
        parenDepth++;
      case ')':
        parenDepth--;
    }

    // If depth goes negative, we've exited the function call
    if (parenDepth < 0) {
      return false;
    }
  }

  return true;
}
