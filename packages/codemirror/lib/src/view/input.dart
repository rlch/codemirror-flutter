/// Input handling for the editor.
///
/// This module provides [InputState] for managing keyboard, mouse, touch,
/// and IME input events in the editor.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart';
import 'cursor.dart';
import 'keymap.dart';
import 'view_update.dart';

// ============================================================================
// Extension Facets for Input
// ============================================================================

/// Facet that controls whether clicking on the editor adds to the selection
/// (when multiple selections are allowed).
///
/// The default behavior is to add to selection when Cmd (Mac) or Ctrl (other)
/// is pressed.
final Facet<bool Function(PointerDownEvent), List<bool Function(PointerDownEvent)>>
    clickAddsSelectionRange = Facet.define();

/// Facet that controls whether dragging moves or copies the selection.
///
/// The default behavior is to move unless Alt (Mac) or Ctrl (other) is pressed.
final Facet<bool Function(PointerDownEvent), List<bool Function(PointerDownEvent)>>
    dragMovesSelection = Facet.define();

/// Facet for custom mouse selection style handlers.
///
/// When provided, these functions are called on mousedown to determine
/// how selection should be handled.
final Facet<MouseSelectionStyle? Function(dynamic view, PointerDownEvent),
    List<MouseSelectionStyle? Function(dynamic view, PointerDownEvent)>>
    mouseSelectionStyle = Facet.define();

/// Facet for focus change effects.
///
/// Extensions can provide functions that return state effects to be
/// dispatched when the editor's focus state changes.
final Facet<StateEffect<dynamic>? Function(EditorState, bool),
    List<StateEffect<dynamic>? Function(EditorState, bool)>>
    focusChangeEffect = Facet.define();

/// Facet for clipboard input filtering.
///
/// Functions registered with this facet can transform text before it is
/// pasted into the editor.
final Facet<String Function(String, EditorState),
    List<String Function(String, EditorState)>>
    clipboardInputFilter = Facet.define();

/// Facet for clipboard output filtering.
///
/// Functions registered with this facet can transform text before it is
/// copied to the clipboard.
final Facet<String Function(String, EditorState),
    List<String Function(String, EditorState)>>
    clipboardOutputFilter = Facet.define();

/// Input handler signature.
///
/// Called when text is being inserted. Return `true` to indicate the handler
/// consumed the input and prevent default processing.
typedef InputHandler = bool Function(
  dynamic view, // EditorViewState
  int from,
  int to,
  String text,
);

/// Facet for input handlers.
///
/// Input handlers can intercept text insertion before it happens and
/// optionally handle it themselves (by returning `true`).
final Facet<InputHandler, List<InputHandler>> inputHandler = Facet.define();

// ============================================================================
// MouseSelectionStyle
// ============================================================================

/// Interface for custom mouse selection behavior.
///
/// Objects registered with [mouseSelectionStyle] must conform to this
/// interface to handle mouse-driven selection.
abstract class MouseSelectionStyle {
  /// Return a new selection for the mouse gesture.
  ///
  /// The gesture starts with the event that was originally given to the
  /// constructor and ends with the event passed here.
  ///
  /// When [extend] is true, the new selection should extend the start selection.
  /// When [multiple] is true, the new selection should be added to the original.
  EditorSelection get(
    PointerEvent curEvent,
    bool extend,
    bool multiple,
  );

  /// Called when the view is updated while the gesture is in progress.
  ///
  /// May return `true` to indicate that [get] should be called again after
  /// the update.
  bool update(ViewUpdate update);
}

// ============================================================================
// InputState
// ============================================================================

/// Manages input state for the editor.
///
/// This class tracks keyboard, mouse, touch, and IME input state and
/// coordinates event handling between different input sources.
class InputState {
  /// The editor view this input state belongs to.
  final dynamic view;

  /// The last key code that was pressed.
  int lastKeyCode = 0;

  /// The timestamp of the last key press.
  int lastKeyTime = 0;

  /// The timestamp of the last touch event.
  int lastTouchTime = 0;

  /// The timestamp when focus was last gained.
  int lastFocusTime = 0;

  /// Last scroll position (top).
  double lastScrollTop = 0;

  /// Last scroll position (left).
  double lastScrollLeft = 0;

  /// When enabled (>-1), tab presses are not given to key handlers,
  /// leaving the platform's default behavior.
  ///
  /// If >0, the mode expires at that timestamp, and any other keypress
  /// clears it. Esc enables temporary tab focus mode for two seconds
  /// when not otherwise handled.
  int tabFocusMode = -1;

  /// The origin of the last selection change.
  String? lastSelectionOrigin;

  /// The timestamp of the last selection change.
  int lastSelectionTime = 0;

  /// The timestamp of the last context menu.
  int lastContextMenu = 0;

  /// Scroll event handlers.
  final List<bool Function(ScrollNotification)> scrollHandlers = [];

  /// Event handlers organized by type.
  /// @nodoc
  final Map<String, _HandlerSet> handlers = {};

  /// Composition state (-1 = not in composition).
  ///
  /// Otherwise, counts changes made during composition.
  int composing = -1;

  /// Tracks whether the next change should be marked as starting the composition.
  bool? compositionFirstChange;

  /// End time of the previous composition.
  int compositionEndedAt = 0;

  /// Used to detect Enter during composition on Safari.
  bool compositionPendingKey = false;

  /// Used to categorize changes as part of a composition.
  bool compositionPendingChange = false;

  /// Active mouse selection.
  MouseSelection? mouseSelection;

  /// The range being dragged (if any).
  SelectionRange? draggedContent;

  /// Whether the editor was last known to be focused.
  bool notifiedFocused;

  InputState(this.view) : notifiedFocused = false {
    notifiedFocused = _hasFocus;
  }

  bool get _hasFocus {
    // This should be implemented to check the actual focus state
    // For now, return false as default
    return false;
  }

  /// Set the origin for the current selection change.
  void setSelectionOrigin(String origin) {
    lastSelectionOrigin = origin;
    lastSelectionTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// Handle a key event.
  ///
  /// Returns true if the event was handled and should not be processed further.
  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      return _handleKeyDown(event);
    }
    return false;
  }

  bool _handleKeyDown(KeyEvent event) {
    // Track key state
    lastKeyCode = event.logicalKey.keyId;
    lastKeyTime = DateTime.now().millisecondsSinceEpoch;

    // Handle tab focus mode
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        tabFocusMode > -1 &&
        (tabFocusMode == 0 || DateTime.now().millisecondsSinceEpoch <= tabFocusMode)) {
      return false; // Let tab pass through
    }

    // Clear tab focus mode on non-modifier keys
    if (tabFocusMode > 0 &&
        event.logicalKey != LogicalKeyboardKey.escape &&
        !_isModifierKey(event.logicalKey)) {
      tabFocusMode = -1;
    }

    // Try to run keymap handlers
    return runScopeHandlers(view, event, 'editor');
  }

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
        key == LogicalKeyboardKey.metaRight;
  }

  /// Handle Escape key for tab focus mode.
  void handleEscape() {
    if (tabFocusMode == 0) {
      tabFocusMode = DateTime.now().millisecondsSinceEpoch + 2000;
    }
  }

  /// Start a mouse selection gesture.
  void startMouseSelection(MouseSelection selection) {
    mouseSelection?.destroy();
    mouseSelection = selection;
  }

  /// Update input state after a view update.
  void update(ViewUpdate update) {
    mouseSelection?.update(update);
    if (draggedContent != null && update.docChanged) {
      draggedContent = draggedContent!.map(update.changes);
    }
    if (update.transactions.isNotEmpty) {
      lastKeyCode = 0;
      lastSelectionTime = 0;
    }
  }

  /// Dispose of this input state.
  void destroy() {
    mouseSelection?.destroy();
  }
}

/// A set of handlers for a particular event type.
class _HandlerSet {
  /// Observer functions (always run, don't prevent default).
  final List<bool Function(dynamic view, dynamic event)> observers;

  /// Handler functions (may prevent further handling).
  final List<bool Function(dynamic view, dynamic event)> handlers;

  _HandlerSet({
    List<bool Function(dynamic view, dynamic event)>? observers,
    List<bool Function(dynamic view, dynamic event)>? handlers,
  })  : observers = observers ?? [],
        handlers = handlers ?? [];
}

// ============================================================================
// MouseSelection
// ============================================================================

/// Manages an active mouse selection gesture.
class MouseSelection {
  final dynamic view;
  final PointerDownEvent startEvent;
  final MouseSelectionStyle style;
  final bool mustSelect;

  PointerEvent lastEvent;
  bool? dragging;
  bool extend = false;
  bool multiple = false;
  List<RangeSet<RangeValue>> atoms = [];

  Offset _scrollSpeed = Offset.zero;
  Timer? _scrollTimer;

  MouseSelection({
    required this.view,
    required this.startEvent,
    required this.style,
    required this.mustSelect,
  }) : lastEvent = startEvent {
    extend = _isShiftPressed(startEvent);
    multiple = _addsSelectionRange(view, startEvent);
    dragging = _isInPrimarySelection(view, startEvent) && _getClickType(startEvent) == 1 ? null : false;
  }

  /// Start the selection (called after initial setup).
  void start(PointerEvent event) {
    if (dragging == false) {
      select(event);
    }
  }

  /// Handle pointer move events.
  void move(PointerMoveEvent event) {
    if (event.buttons == 0) {
      destroy();
      return;
    }

    if (dragging != null || _distance(startEvent, event) < 10) {
      if (dragging != null) return;
    }

    dragging = false;
    select(lastEvent = event);

    // Handle scroll when dragging near edges
    _updateScrollSpeed(event);
  }

  /// Handle pointer up events.
  void up(PointerUpEvent event) {
    if (dragging == null) select(lastEvent);
    destroy();
  }

  /// Clean up the mouse selection.
  void destroy() {
    _setScrollSpeed(Offset.zero);
    _scrollTimer?.cancel();
    _scrollTimer = null;

    final inputState = (view as dynamic).inputState as InputState?;
    if (inputState != null) {
      inputState.mouseSelection = null;
      inputState.draggedContent = null;
    }
  }

  void _updateScrollSpeed(PointerEvent event) {
    // Calculate scroll speed based on pointer position near edges
    // This would require access to the view's bounds
    // For now, we'll leave this as a placeholder
  }

  void _setScrollSpeed(Offset speed) {
    _scrollSpeed = speed;
    if (speed != Offset.zero) {
      _scrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _scroll(),
      );
    } else {
      _scrollTimer?.cancel();
      _scrollTimer = null;
    }
  }

  void _scroll() {
    // Scroll and update selection
    if (dragging == false) {
      select(lastEvent);
    }
  }

  /// Update the selection based on the current pointer position.
  void select(PointerEvent event) {
    final selection = skipAtomsForSelection(atoms, style.get(event, extend, multiple));
    final state = (view as dynamic).state as EditorState;

    if (mustSelect || !selection.eq(state.selection)) {
      (view as dynamic).dispatch([
        TransactionSpec(
          selection: selection,
          userEvent: 'select.pointer',
        ),
      ]);
    }
  }

  /// Handle view updates during the gesture.
  void update(ViewUpdate update) {
    if (update.transactions.any((tr) => tr.isUserEvent('input.type'))) {
      destroy();
    } else if (style.update(update)) {
      Timer(const Duration(milliseconds: 20), () => select(lastEvent));
    }
  }

  static double _distance(PointerEvent a, PointerEvent b) {
    return (a.position - b.position).distance;
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Check if shift is pressed for extend selection.
bool _isShiftPressed(PointerEvent event) {
  return HardwareKeyboard.instance.isShiftPressed;
}

/// Check if this click should add to selection (multi-select).
bool _addsSelectionRange(dynamic view, PointerEvent event) {
  final state = (view as dynamic).state as EditorState;
  final facet = state.facet(clickAddsSelectionRange);

  if (facet.isNotEmpty) {
    return facet[0](event as PointerDownEvent);
  }

  // Default: Cmd on Mac, Ctrl on other platforms
  if (isMac) {
    return HardwareKeyboard.instance.isMetaPressed;
  }
  return HardwareKeyboard.instance.isControlPressed;
}

/// Check if the click is within the primary selection.
bool _isInPrimarySelection(dynamic view, PointerEvent event) {
  final state = (view as dynamic).state as EditorState;
  final main = state.selection.main;
  return !main.empty;
  // TODO: Check if the actual coordinates are within the selection
}

/// Get the click type (1=single, 2=double, 3=triple).
int _getClickType(PointerEvent event) {
  // For PointerDownEvent, we can track click count
  // For now, always return single click
  return 1;
}

// ============================================================================
// Annotation for focus changes
// ============================================================================

/// Annotation type for focus change markers.
final AnnotationType<bool> isFocusChangeType = Annotation.define<bool>();

/// Create an annotation indicating a focus change.
Annotation<bool> isFocusChange(bool value) => isFocusChangeType.of(value);

/// Create a focus change transaction if needed.
Transaction? focusChangeTransaction(EditorState state, bool focus) {
  final effects = <StateEffect<dynamic>>[];

  for (final getEffect in state.facet(focusChangeEffect)) {
    final effect = getEffect(state, focus);
    if (effect != null) effects.add(effect);
  }

  if (effects.isNotEmpty) {
    return state.update([
      TransactionSpec(
        effects: effects,
        annotations: [isFocusChange(true)],
      ),
    ]);
  }

  return null;
}

// ============================================================================
// Clipboard operations
// ============================================================================

/// Filter clipboard text through registered filters.
String filterClipboardInput(EditorState state, String text) {
  for (final filter in state.facet(clipboardInputFilter)) {
    text = filter(text, state);
  }
  return text;
}

/// Filter clipboard output through registered filters.
String filterClipboardOutput(EditorState state, String text) {
  for (final filter in state.facet(clipboardOutputFilter)) {
    text = filter(text, state);
  }
  return text;
}

/// Handle paste operation.
void doPaste(dynamic view, String input) {
  final state = (view as dynamic).state as EditorState;
  input = filterClipboardInput(state, input);

  if (input.isEmpty) return;

  final text = state.toText(input);
  final changes = state.replaceSelection(text);

  (view as dynamic).dispatch([
    TransactionSpec(
      changes: changes.changes,
      selection: changes.selection,
      userEvent: 'input.paste',
      scrollIntoView: true,
    ),
  ]);
}

/// Get text and ranges for a copy/cut operation.
({String text, List<SelectionRange> ranges, bool linewise}) copiedRange(
  EditorState state,
) {
  final content = <String>[];
  final ranges = <SelectionRange>[];
  var linewise = false;

  for (final range in state.selection.ranges) {
    if (!range.empty) {
      content.add(state.sliceDoc(range.from, range.to));
      ranges.add(range);
    }
  }

  if (content.isEmpty) {
    // Line-wise copy when nothing selected
    var upto = -1;
    for (final range in state.selection.ranges) {
      final line = state.doc.lineAt(range.from);
      if (line.number > upto) {
        content.add(line.text);
        final to = line.to < state.doc.length ? line.to + 1 : line.to;
        ranges.add(EditorSelection.range(line.from, to));
      }
      upto = line.number;
    }
    linewise = true;
  }

  final text = filterClipboardOutput(state, content.join(state.lineBreak));
  return (text: text, ranges: ranges, linewise: linewise);
}

/// Handle cut operation.
void doCut(dynamic view) {
  final result = copiedRange((view as dynamic).state as EditorState);
  if (result.text.isEmpty && !result.linewise) return;

  final state = (view as dynamic).state as EditorState;
  if (!state.isReadOnly) {
    (view as dynamic).dispatch([
      TransactionSpec(
        changes: result.ranges.map((r) => {'from': r.from, 'to': r.to}).toList(),
        scrollIntoView: true,
        userEvent: 'delete.cut',
      ),
    ]);
  }
}
