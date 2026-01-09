/// Keymap system for key binding management.
///
/// This module provides [KeyBinding] for defining keyboard shortcuts and
/// the [keymap] facet for registering them with the editor.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';

// ============================================================================
// Command type
// ============================================================================

/// A command is a function that takes an [EditorView] and returns whether
/// it was able to perform some action.
///
/// Commands are typically bound to keyboard shortcuts via [KeyBinding].
///
/// When a command function returns `false`, it indicates that the command
/// did not apply in the current situation and other handlers should be tried.
/// When it returns `true`, it means the command handled the event.
typedef Command = bool Function(dynamic view);

// ============================================================================
// Platform detection
// ============================================================================

/// Whether we're running on macOS.
@internal
bool get isMac {
  try {
    return Platform.isMacOS;
  } catch (_) {
    // Platform not available (e.g., in web)
    return false;
  }
}

/// Whether we're running on Windows.
@internal
bool get isWindows {
  try {
    return Platform.isWindows;
  } catch (_) {
    return false;
  }
}

/// Whether we're running on Linux.
@internal
bool get isLinux {
  try {
    return Platform.isLinux;
  } catch (_) {
    return false;
  }
}

/// The current platform name.
@internal
String get currentPlatform {
  if (isMac) return 'mac';
  if (isWindows) return 'win';
  if (isLinux) return 'linux';
  return 'key';
}

// ============================================================================
// KeyBinding
// ============================================================================

/// Key bindings associate key names with [Command]-style functions.
///
/// Key names may be strings like `"Shift-Ctrl-Enter"`—a key identifier
/// prefixed with zero or more modifiers. Key identifiers are based on
/// the strings from Flutter's [LogicalKeyboardKey.keyLabel].
///
/// Modifiers can be given in any order:
/// - `Shift-` (or `s-`)
/// - `Alt-` (or `a-`)
/// - `Ctrl-` (or `c-` or `Control-`)
/// - `Cmd-` (or `m-` or `Meta-`)
///
/// When a key binding contains multiple key names separated by spaces,
/// it represents a multi-stroke binding, which will fire when the user
/// presses the given keys after each other.
///
/// You can use `Mod-` as a shorthand for `Cmd-` on Mac and `Ctrl-` on
/// other platforms. So `Mod-b` is `Ctrl-b` on Linux but `Cmd-b` on macOS.
///
/// Example:
/// ```dart
/// KeyBinding(
///   key: 'Mod-s',
///   run: (view) {
///     saveDocument();
///     return true;
///   },
/// )
/// ```
class KeyBinding {
  /// The key name to use for this binding.
  ///
  /// If the platform-specific property ([mac], [win], or [linux]) for the
  /// current platform is used as well in the binding, that one takes precedence.
  /// If [key] isn't defined and the platform-specific binding isn't either,
  /// the binding is ignored.
  final String? key;

  /// Key to use specifically on macOS.
  final String? mac;

  /// Key to use specifically on Windows.
  final String? win;

  /// Key to use specifically on Linux.
  final String? linux;

  /// The command to execute when this binding is triggered.
  ///
  /// When the command function returns `false`, further bindings will be
  /// tried for the key.
  final Command? run;

  /// When given, this defines a second binding, using the (possibly
  /// platform-specific) key name prefixed with `Shift-` to activate
  /// this command.
  final Command? shift;

  /// When this property is present, the function is called for every
  /// key that is not a multi-stroke prefix.
  final bool Function(dynamic view, KeyEvent event)? any;

  /// By default, key bindings apply when focus is on the editor content
  /// (the `"editor"` scope).
  ///
  /// Some extensions, mostly those that define their own panels, might want
  /// to allow you to register bindings local to that panel. Such bindings
  /// should use a custom scope name. You may also assign multiple scope names
  /// to a binding, separating them by spaces.
  final String? scope;

  /// When set to true (the default is false), this will always prevent the
  /// further handling for the bound key, even if the command(s) return false.
  ///
  /// This can be useful for cases where the native behavior of the key is
  /// annoying or irrelevant but the command doesn't always apply (such as,
  /// Mod-u for undo selection, which would cause the browser to view source
  /// instead when no selection can be undone).
  final bool preventDefault;

  /// When set to true, `stopPropagation` will be called on keyboard events
  /// that have their `preventDefault` called in response to this key binding.
  final bool stopPropagation;

  const KeyBinding({
    this.key,
    this.mac,
    this.win,
    this.linux,
    this.run,
    this.shift,
    this.any,
    this.scope,
    this.preventDefault = false,
    this.stopPropagation = false,
  });

  /// Get the appropriate key for the current platform.
  String? get platformKey {
    if (isMac && mac != null) return mac;
    if (isWindows && win != null) return win;
    if (isLinux && linux != null) return linux;
    return key;
  }
}

// ============================================================================
// Keymap Facet
// ============================================================================

/// Facet used for registering keymaps.
///
/// You can add multiple keymaps to an editor. Their priorities determine
/// their precedence (the ones specified early or with high priority get
/// checked first). When a handler has returned `true` for a given key,
/// no further handlers are called.
///
/// Example:
/// ```dart
/// EditorState.create(
///   EditorStateConfig(
///     extensions: keymap.of([
///       KeyBinding(key: 'Mod-s', run: saveDocument),
///       KeyBinding(key: 'Mod-z', run: undo),
///     ]),
///   ),
/// )
/// ```
final Facet<List<KeyBinding>, List<List<KeyBinding>>> keymap = Facet.define();

// ============================================================================
// Key Name Normalization
// ============================================================================

/// Normalize a key name to a canonical form.
///
/// Parses a key name like "Ctrl-Shift-A" and returns a normalized version
/// with modifiers in a consistent order: Alt-Ctrl-Meta-Shift-key.
String normalizeKeyName(String name, [String platform = 'key']) {
  final parts = name.split(RegExp(r'-(?!$)'));
  var result = parts.last;

  // Handle "Space" as an alias for " "
  if (result == 'Space') result = ' ';

  bool alt = false, ctrl = false, shift = false, meta = false;

  for (var i = 0; i < parts.length - 1; i++) {
    final mod = parts[i].toLowerCase();
    if (mod == 'cmd' || mod == 'meta' || mod == 'm') {
      meta = true;
    } else if (mod == 'a' || mod == 'alt') {
      alt = true;
    } else if (mod == 'c' || mod == 'ctrl' || mod == 'control') {
      ctrl = true;
    } else if (mod == 's' || mod == 'shift') {
      shift = true;
    } else if (mod == 'mod') {
      if (platform == 'mac') {
        meta = true;
      } else {
        ctrl = true;
      }
    } else {
      throw ArgumentError('Unrecognized modifier name: $mod');
    }
  }

  // Build normalized name in order: Alt-Ctrl-Meta-Shift
  final buffer = StringBuffer();
  if (alt) buffer.write('Alt-');
  if (ctrl) buffer.write('Ctrl-');
  if (meta) buffer.write('Meta-');
  if (shift) buffer.write('Shift-');
  buffer.write(result);

  return buffer.toString();
}

/// Add modifier prefixes to a key name based on the keyboard state.
///
/// Returns the key in normalized order (Alt-Ctrl-Meta-Shift-key) to match
/// how bindings are registered in the keymap.
String modifiers(String name, KeyEvent event, [bool includeShift = true]) {
  final keyboard = HardwareKeyboard.instance;
  // Build in normalized order: Alt-Ctrl-Meta-Shift
  final buffer = StringBuffer();
  if (keyboard.isAltPressed) buffer.write('Alt-');
  if (keyboard.isControlPressed) buffer.write('Ctrl-');
  if (keyboard.isMetaPressed) buffer.write('Meta-');
  if (includeShift && keyboard.isShiftPressed) buffer.write('Shift-');
  buffer.write(name);
  return buffer.toString();
}

// ============================================================================
// Binding - Internal representation of a resolved key binding
// ============================================================================

/// A resolved binding with its handlers and flags.
@internal
class Binding {
  /// Whether to prevent default browser behavior.
  bool preventDefault;

  /// Whether to stop event propagation.
  bool stopPropagation;

  /// The list of command functions to run.
  final List<Command> run;

  Binding({
    this.preventDefault = false,
    this.stopPropagation = false,
    List<Command>? run,
  }) : run = run ?? [];
}

/// A keymap organized by scope.
///
/// In each scope, keys are mapped to [Binding] objects.
/// The `_any` property is used for bindings that apply to all keys.
@internal
typedef Keymap = Map<String, Map<String, Binding>>;

// ============================================================================
// Keymap Building
// ============================================================================

/// Cached keymaps to avoid rebuilding for the same bindings.
final _keymapCache = Expando<Keymap>();

/// Get or build the keymap for a state.
@internal
Keymap getKeymap(EditorState state) {
  final bindings = state.facet(keymap);

  // Check cache
  final cachedMap = _keymapCache[bindings];
  if (cachedMap != null) return cachedMap;

  // Flatten and build the keymap
  final allBindings = bindings.expand((list) => list).toList();
  final map = buildKeymap(allBindings);
  _keymapCache[bindings] = map;
  return map;
}

/// Build a keymap from a list of key bindings.
@internal
Keymap buildKeymap(List<KeyBinding> bindings, [String? platform]) {
  platform ??= currentPlatform;
  final Keymap bound = {};
  final Map<String, bool> isPrefix = {};

  void checkPrefix(String name, bool is_) {
    final current = isPrefix[name];
    if (current == null) {
      isPrefix[name] = is_;
    } else if (current != is_) {
      throw ArgumentError(
        'Key binding $name is used both as a regular binding and as a multi-stroke prefix',
      );
    }
  }

  void add(
    String scope,
    String key,
    Command? command, {
    bool preventDefault = false,
    bool stopPropagation = false,
  }) {
    final scopeObj = bound.putIfAbsent(scope, () => {});
    final parts = key.split(RegExp(r' (?!$)')).map((k) => normalizeKeyName(k, platform!)).toList();

    // Register prefixes for multi-stroke bindings
    for (var i = 1; i < parts.length; i++) {
      final prefix = parts.sublist(0, i).join(' ');
      checkPrefix(prefix, true);

      if (scopeObj[prefix] == null) {
        scopeObj[prefix] = Binding(
          preventDefault: true,
          stopPropagation: false,
          run: [
            (view) {
              _storedPrefix = _PrefixState(prefix, scope);
              Future.delayed(const Duration(milliseconds: 4000), () {
                if (_storedPrefix?.prefix == prefix) _storedPrefix = null;
              });
              return true;
            },
          ],
        );
      }
    }

    final full = parts.join(' ');
    checkPrefix(full, false);

    final binding = scopeObj.putIfAbsent(
      full,
      () => Binding(run: scopeObj['_any']?.run.toList() ?? []),
    );
    if (command != null) binding.run.add(command);
    if (preventDefault) binding.preventDefault = true;
    if (stopPropagation) binding.stopPropagation = true;
  }

  for (final b in bindings) {
    final scopes = b.scope?.split(' ') ?? ['editor'];

    // Handle "any" bindings - these need special treatment
    // We'll register them to be called for all keys in the scope
    if (b.any != null) {
      for (final scope in scopes) {
        final scopeObj = bound.putIfAbsent(scope, () => {});
        scopeObj.putIfAbsent('_any', () => Binding());
        // Note: "any" handlers are called via the runHandlers logic
      }
    }

    // Get the platform-specific key
    String? name;
    if (platform == 'mac' && b.mac != null) {
      name = b.mac;
    } else if (platform == 'win' && b.win != null) {
      name = b.win;
    } else if (platform == 'linux' && b.linux != null) {
      name = b.linux;
    } else {
      name = b.key;
    }

    if (name == null) continue;

    for (final scope in scopes) {
      add(
        scope,
        name,
        b.run,
        preventDefault: b.preventDefault,
        stopPropagation: b.stopPropagation,
      );
      if (b.shift != null) {
        add(
          scope,
          'Shift-$name',
          b.shift,
          preventDefault: b.preventDefault,
          stopPropagation: b.stopPropagation,
        );
      }
    }
  }

  return bound;
}

// ============================================================================
// Multi-stroke prefix handling
// ============================================================================

class _PrefixState {
  final String prefix;
  final String scope;

  _PrefixState(this.prefix, this.scope);
}

_PrefixState? _storedPrefix;

/// The current key event being handled (for "any" handlers).
KeyEvent? _currentKeyEvent;

// ============================================================================
// Handler Running
// ============================================================================

/// Modifier key codes that shouldn't clear prefixes.
const modifierKeyCodes = <int>[
  16, // Shift
  17, // Control
  18, // Alt
  20, // CapsLock
  91, // Meta (left)
  92, // Meta (right)
  224, // Meta (Firefox)
  225, // AltGraph
];

/// Check if a logical key is a modifier.
bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight ||
      key == LogicalKeyboardKey.capsLock;
}

/// Run the key handlers registered for a given scope.
///
/// The event should be a key down event. Returns true if any of the
/// handlers handled it.
bool runScopeHandlers(dynamic view, KeyEvent event, String scope) {
  final state = view.state as EditorState;
  return runHandlers(getKeymap(state), event, view, scope);
}

/// Run handlers for a key event.
@internal
bool runHandlers(Keymap map, KeyEvent event, dynamic view, String scope) {
  _currentKeyEvent = event;

  final name = _keyName(event);
  final isChar = name.length == 1 && name != ' ';
  final keyboard = HardwareKeyboard.instance;
  
  final scopeObj = map[scope];

  var prefix = '';
  var handled = false;
  var prevented = false;

  // Check for stored prefix
  if (_storedPrefix != null && _storedPrefix!.scope == scope) {
    prefix = '${_storedPrefix!.prefix} ';
    if (!_isModifierKey(event.logicalKey)) {
      prevented = true;
      _storedPrefix = null;
    }
  }

  final ran = <Command>{};

  bool runFor(Binding? binding) {
    if (binding == null) return false;

    for (final cmd in binding.run) {
      if (ran.contains(cmd)) continue;
      ran.add(cmd);
      if (cmd(view)) {
        return true;
      }
    }

    if (binding.preventDefault) {
      prevented = true;
    }
    return false;
  }

  if (scopeObj != null) {
    // Try with modifiers
    // When other modifiers are pressed (Meta/Ctrl/Alt), always include Shift in the lookup
    // because bindings like "Mod-Shift-z" expect Shift to be part of the key name
    final hasOtherModifiers = keyboard.isAltPressed || keyboard.isMetaPressed || keyboard.isControlPressed;
    final includeShift = !isChar || (isChar && hasOtherModifiers && keyboard.isShiftPressed);
    final lookupKey = prefix + modifiers(name, event, includeShift);
    if (runFor(scopeObj[lookupKey])) {
      handled = true;
    }
    // Try alternate key name if it's a modified character (without shift for natural character variations)
    else if (isChar && hasOtherModifiers && !handled) {
      final baseName = _baseKeyName(event);
      if (baseName != null && baseName != name) {
        if (runFor(scopeObj[prefix + modifiers(baseName, event, true)])) {
          handled = true;
        }
      }
    }
    // Try "any" handlers
    if (!handled && runFor(scopeObj['_any'])) {
      handled = true;
    }
  }

  if (prevented) handled = true;
  _currentKeyEvent = null;
  return handled;
}

/// Get the key name from a Flutter key event.
String _keyName(KeyEvent event) {
  // Get the logical key label
  final label = event.logicalKey.keyLabel;

  // Convert to a form compatible with our key names
  if (label.isEmpty) {
    // Use key ID name for special keys
    final debugName = event.logicalKey.debugName;
    if (debugName != null) {
      // Convert "Arrow Down" to "ArrowDown", "Page Up" to "PageUp", etc.
      return debugName.replaceAll(' ', '');
    }
    return '';
  }

  // For single character keys, return the lowercase version
  if (label.length == 1) {
    return label.toLowerCase();
  }

  // For named keys like "Arrow Down", "Page Up", etc., remove spaces
  return label.replaceAll(' ', '');
}

/// Get the base (unshifted) key name.
String? _baseKeyName(KeyEvent event) {
  // For physical key, try to get the unshifted version
  final keyId = event.physicalKey.usbHidUsage;

  // Map common keys - this is a simplified version
  // A full implementation would need a complete keycode mapping
  if (keyId >= 0x00070004 && keyId <= 0x0007001d) {
    // a-z
    return String.fromCharCode(0x61 + (keyId - 0x00070004));
  }
  if (keyId >= 0x0007001e && keyId <= 0x00070027) {
    // 1-0
    final digit = (keyId - 0x0007001e + 1) % 10;
    return digit.toString();
  }

  return null;
}

// ============================================================================
// Standard keymaps
// ============================================================================

/// Create a keymap extension from a list of key bindings.
///
/// This is a convenience function that wraps [keymap.of].
Extension keymapOf(List<KeyBinding> bindings) {
  return keymap.of(bindings);
}

// Note: defaultKeymap, standardKeymap, emacsStyleKeymap are defined in
// commands/commands.dart with actual command bindings.
