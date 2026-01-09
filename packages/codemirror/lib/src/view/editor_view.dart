/// Editor view - the main editor widget.
///
/// This module provides [EditorView], the Flutter widget that renders
/// the code editor and handles user input.
library;

import 'dart:async';
import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart' hide Viewport, Decoration;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../lint/lint.dart' show Diagnostic, diagnosticsAtPos, DiagnosticTooltip;
import 'tooltip.dart' show hoverTooltipFacet, HoverTooltipConfig, HoverTooltip, TooltipView, HoverTooltipWidget;
import '../language/goto.dart' show gotoDefinitionFacet, GotoDefinitionConfig, GotoDefinitionOptions, DefinitionLocation, DefinitionResult, findReferencesFacet, FindReferencesOptions, ReferencesResult, triggerDefinitionEffect;
import '../language/signature.dart' show signatureHelpFacet, SignatureResult, SignatureInfo, detectActiveParameter, isWithinFunctionCall;
import '../language/format.dart' as format show formatDocumentEffect, formatRangeEffect, formatDocument, formatRange, checkOnTypeFormatting, documentFormattingFacet;
import '../language/rename.dart' show renameFacet, PrepareRenameResult, RenameLocation, triggerRenameEffect, applyRenameEdits;
import '../language/document_highlight.dart' show documentHighlightFacet, DocumentHighlightResult, setDocumentHighlights, clearDocumentHighlights, highlightStateField, ensureDocumentHighlightInitialized;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:flutter/gestures.dart' show TapDragUpDetails;
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../state/change.dart';
import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/selection.dart';
import '../state/state.dart';
import '../state/transaction.dart';
import '../autocomplete/autocomplete.dart' show completionState, applyCompletion;
import '../autocomplete/config.dart' show completionConfig;
import '../autocomplete/tooltip.dart' show CompletionTooltipController;
import 'active_line.dart' show ActiveLineBackground;
import 'block_info.dart';
import 'decoration.dart';
import 'gutter.dart';
import 'highlighting_controller.dart';
import 'input.dart' as input;
import 'input.dart' show InputState, InputHandler, focusChangeTransaction;
import 'panel.dart';
import 'tooltip_positioning.dart';
import 'anchored_overlay.dart';
import 'view_plugin.dart';
import 'view_state.dart';
import 'view_update.dart';
import 'viewport.dart';

// ============================================================================
// EditorViewConfig - Configuration for creating an EditorView
// ============================================================================

/// Configuration for creating an [EditorView].
class EditorViewConfig {
  /// The initial editor state.
  ///
  /// If not provided, a new state will be created from the other config options.
  final EditorState? state;

  /// Initial document content (used if state is not provided).
  final String? doc;

  /// Initial selection (used if state is not provided).
  final EditorSelection? selection;

  /// Extensions to use (used if state is not provided).
  final Extension? extensions;

  /// Custom dispatch handler.
  ///
  /// Called instead of the default dispatch behavior when transactions
  /// are dispatched. Must call [EditorView.update] to actually apply changes.
  final void Function(List<Transaction> transactions, EditorView view)?
      dispatchTransactions;

  /// Initial scroll target.
  final StateEffect<ScrollTarget>? scrollTo;

  /// Whether the editor should be read-only.
  final bool readOnly;

  /// Whether the editor should auto-focus.
  final bool autofocus;

  const EditorViewConfig({
    this.state,
    this.doc,
    this.selection,
    this.extensions,
    this.dispatchTransactions,
    this.scrollTo,
    this.readOnly = false,
    this.autofocus = false,
  });
}

// ============================================================================
// EditorView - The main editor widget
// ============================================================================

/// A code editor widget.
///
/// [EditorView] is a Flutter widget that displays an editable code editor.
/// It manages an [EditorState] and handles user input to dispatch
/// [Transaction]s that update the state.
///
/// ## Basic Usage
///
/// ```dart
/// EditorView(
///   state: EditorState.create(
///     EditorStateConfig(doc: 'Hello, World!'),
///   ),
///   onUpdate: (update) {
///     print('Document changed: ${update.docChanged}');
///   },
/// )
/// ```
///
/// ## State Management
///
/// The editor can be used in two modes:
///
/// 1. **Controlled**: Pass a [state] and handle updates via [onUpdate]
/// 2. **Uncontrolled**: Let the widget manage state internally
class EditorView extends StatefulWidget {
  /// The editor state to display.
  ///
  /// If not provided, an empty state will be created.
  final EditorState? state;

  /// Configuration for the editor.
  final EditorViewConfig? config;

  /// Called when the editor state changes.
  final void Function(ViewUpdate update)? onUpdate;

  /// Called when a key event is received.
  final KeyEventResult Function(FocusNode, KeyEvent)? onKey;

  /// Custom text style for the editor content.
  final TextStyle? style;

  /// Padding around the editor content.
  final EdgeInsets padding;

  /// Whether the editor should auto-focus.
  final bool autofocus;

  /// Whether the editor is read-only.
  final bool readOnly;

  /// Cursor color.
  final Color? cursorColor;

  /// Selection color.
  final Color? selectionColor;

  /// Background color.
  final Color? backgroundColor;
  
  /// Theme for syntax highlighting.
  ///
  /// Defaults to [HighlightTheme.light]. Use [HighlightTheme.dark] for
  /// dark backgrounds.
  final HighlightTheme highlightTheme;

  const EditorView({
    super.key,
    this.state,
    this.config,
    this.onUpdate,
    this.onKey,
    this.style,
    this.padding = const EdgeInsets.all(8),
    this.autofocus = false,
    this.readOnly = false,
    this.cursorColor,
    this.selectionColor,
    this.backgroundColor,
    this.highlightTheme = HighlightTheme.defaultLight,
  });

  @override
  State<EditorView> createState() => EditorViewState();

  // ============================================================================
  // Static facets and effects
  // ============================================================================

  /// Facet controlling whether the editor content is editable.
  static final editable = Facet.define<bool, bool>(
    FacetConfig(combine: (values) => values.isEmpty || values.first),
  );

  /// Facet for update listeners.
  static final updateListener = Facet.define<void Function(ViewUpdate), List<void Function(ViewUpdate)>>();

  /// Facet for input handlers.
  ///
  /// Input handlers can intercept text insertion and handle it themselves.
  /// Return `true` to prevent default text insertion.
  static final Facet<InputHandler, List<InputHandler>> inputHandler = input.inputHandler;

  /// Effect to scroll a position into view.
  static final scrollIntoView = StateEffect.define<ScrollTarget>();

  /// Create an effect that scrolls a position into view.
  static StateEffect<ScrollTarget> scrollIntoViewEffect(
    int pos, {
    String y = 'nearest',
    String x = 'nearest',
    double yMargin = 5,
    double xMargin = 5,
  }) {
    return scrollIntoView.of(ScrollTarget(
      EditorSelection.cursor(pos),
      y: y,
      x: x,
      yMargin: yMargin,
      xMargin: xMargin,
    ));
  }
}

// ============================================================================
// EditorViewState - The stateful widget implementation
// ============================================================================

// ============================================================================
// EditorViewSelectionGestureDetectorBuilder
// ============================================================================

/// Custom gesture detector builder for EditorView.
class _EditorViewSelectionGestureDetectorBuilder
    extends TextSelectionGestureDetectorBuilder {
  final EditorViewState _editorState;
  
  _EditorViewSelectionGestureDetectorBuilder({
    required EditorViewState state,
  }) : _editorState = state, super(delegate: state);
  
  @override
  void onSingleTapUp(TapDragUpDetails details) {
    // Check for Ctrl+click (Cmd+click on Mac) for go-to-definition
    final keyboard = HardwareKeyboard.instance;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isDefinitionClick = isMac 
        ? keyboard.isMetaPressed 
        : keyboard.isControlPressed;
    
    if (isDefinitionClick && _editorState.mounted) {
      // Get position from click
      final pos = _editorState.posAtCoords(details.globalPosition);
      if (pos != null) {
        _editorState._triggerGoToDefinition(pos);
        return;
      }
    }
    
    super.onSingleTapUp(details);
  }
}

/// State for [EditorView].
///
/// This is exposed as a public class so that it can be accessed via
/// a GlobalKey for imperative operations.
class EditorViewState extends State<EditorView>
    implements
        TextInputClient,
        DeltaTextInputClient,
        TextSelectionGestureDetectorBuilderDelegate {
  /// The current editor state.
  late EditorState _state;

  /// View state managing viewport and heights.
  late ViewState _viewState;

  /// Input state managing keyboard, mouse, and touch input.
  late InputState _inputState;

  /// Text editing controller for input handling (with syntax highlighting).
  late final HighlightingTextEditingController _textController;

  /// Focus node for keyboard input.
  late final FocusNode _focusNode;

  /// Text input connection for IME.
  TextInputConnection? _textInputConnection;

  /// Whether we're currently updating from our own dispatch.
  bool _updating = false;

  /// Scroll controller for the content.
  late final ScrollController _scrollController;
  
  /// Plugin instances for this view.
  List<PluginInstance> _plugins = [];
  
  /// Map from plugin spec to instance for fast lookup.
  final Map<ViewPlugin<PluginValue>, PluginInstance?> _pluginMap = {};
  
  /// Cached decorations from the facet.
  RangeSet<Decoration> _decorations = RangeSet.empty();
  
  /// Gesture detector builder for mouse/touch selection.
  late _EditorViewSelectionGestureDetectorBuilder _selectionGestureDetectorBuilder;
  
  /// Global key for the EditableText widget.
  final GlobalKey<EditableTextState> _editableTextKey = GlobalKey<EditableTextState>();
  
  /// Completion popup controller.
  CompletionTooltipController? _completionTooltipController;
  
  /// Hover tooltip controller (using follow_the_leader).
  final AnchoredOverlayController _hoverTooltipController = AnchoredOverlayController();
  
  /// Timer for delayed hover tooltip.
  Timer? _hoverTimer;
  
  /// Current Ctrl+hover link range (for underline decoration).
  ({int from, int to})? _ctrlHoverRange;
  
  /// Last hover position for Ctrl+hover tracking.
  Offset? _lastHoverOffset;
  
  /// Whether we're showing the link cursor.
  bool _showingLinkCursor = false;
  
  /// Signature help controller (using follow_the_leader).
  final AnchoredOverlayController _signatureHelpController = AnchoredOverlayController();
  
  /// Current signature help result.
  SignatureResult? _signatureResult;
  
  /// Expose signature result for testing.
  @visibleForTesting
  SignatureResult? get signatureResult => _signatureResult;
  
  /// Expose text controller for testing selection divergence scenarios.
  @visibleForTesting
  TextEditingController get textControllerForTest => _textController;
  
  /// Simulate text input with diverged Flutter selection.
  /// 
  /// This is for testing the bug where Flutter's selection differs from
  /// CodeMirror's selection when text is typed.
  @visibleForTesting
  void simulateTextChangeWithDivergedSelection({
    required String newText,
    required TextSelection flutterSelection,
  }) {
    _textController.removeListener(_onTextChanged);
    _textController.value = TextEditingValue(
      text: newText,
      selection: flutterSelection,
    );
    _textController.addListener(_onTextChanged);
    _onTextChanged();
  }
  
  /// Timer for delayed signature help.
  Timer? _signatureTimer;
  
  /// Timer for debounced signature help re-query on cursor movement.
  Timer? _signatureReQueryTimer;
  
  /// Rename input overlay entry.
  OverlayEntry? _renameInputEntry;
  
  /// Position where rename was triggered.
  int? _renamePos;
  
  /// Prepared rename result.
  PrepareRenameResult? _preparedRename;
  
  /// Timer for delayed document highlight.
  Timer? _highlightTimer;
  
  /// Last position where highlights were requested.
  int? _lastHighlightPos;

  // ============================================================================
  // TextSelectionGestureDetectorBuilderDelegate implementation
  // ============================================================================
  
  @override
  GlobalKey<EditableTextState> get editableTextKey => _editableTextKey;
  
  @override
  bool get forcePressEnabled => false;
  
  @override
  bool get selectionEnabled => true;

  // ============================================================================
  // Getters
  // ============================================================================

  /// The current editor state.
  EditorState get state => _state;

  /// The view state.
  ViewState get viewState => _viewState;

  /// The input state.
  InputState get inputState => _inputState;

  /// The current viewport.
  Viewport get viewport => _viewState.viewport;

  /// The visible ranges within the viewport.
  List<({int from, int to})> get visibleRanges => _viewState.visibleRanges;

  /// Whether the editor is in view.
  bool get inView => _viewState.inView;

  /// Whether the editor has focus.
  bool get hasFocus => _focusNode.hasFocus;

  /// Indicates whether the user is currently composing text via
  /// [IME](https://en.wikipedia.org/wiki/Input_method).
  bool get composing => _inputState.composing > 0;

  /// Indicates whether the user is currently in composing state. Note
  /// that a composing state is different from a composed state. Both
  /// return true when we have pending IME input.
  bool get compositionStarted => _inputState.composing >= 0;

  /// Get the current combined decorations.
  RangeSet<Decoration> get decorations => _decorations;
  
  /// Fixed line height for the editor.
  /// 
  /// We use 20.0 as the standard line height (14px font * ~1.43 multiplier).
  /// Using an integer avoids fractional pixel alignment issues between
  /// the gutter and content.
  static const double fixedLineHeight = 20.0;
  
  /// Get the line height. Uses the fixed value for consistency.
  double get lineHeight => fixedLineHeight;
  
  // ============================================================================
  // Coordinate Conversion Helpers
  // ============================================================================

  /// Get RenderEditable for coordinate operations.
  RenderEditable? get _renderEditable => _editableTextKey.currentState?.renderEditable;

  /// Converts global screen coordinates to text layout coordinates.
  /// 
  /// Global space: Screen coordinates.
  /// Text layout space: y=0 is document start (document coordinates).
  /// 
  /// Note: The RenderEditable is inside a SingleChildScrollView, so its
  /// globalToLocal already accounts for scroll position in the transform chain.
  /// We should NOT manually add scroll offset here.
  Offset? _globalToTextLayoutCoords(Offset globalPosition) {
    final renderEditable = _renderEditable;
    if (renderEditable == null) return null;
    
    // globalToLocal handles the scroll view transform automatically,
    // returning coordinates in the RenderEditable's local space.
    return renderEditable.globalToLocal(globalPosition);
  }

  /// Converts text layout coordinates to global screen coordinates.
  /// 
  /// Text layout space: y=0 is document start (document coordinates).
  /// Global space: Screen coordinates.
  /// 
  /// Note: The RenderEditable is inside a SingleChildScrollView, so its
  /// localToGlobal already accounts for scroll position in the transform chain.
  /// We should NOT manually subtract scroll offset here.
  Offset? _textLayoutToGlobalCoords(Offset textLayoutPosition) {
    final renderEditable = _renderEditable;
    if (renderEditable == null) return null;
    
    // The text layout position is in the RenderEditable's local coordinate system.
    // localToGlobal handles the scroll view transform automatically.
    return renderEditable.localToGlobal(textLayoutPosition);
  }

  /// Get coordinates for a document position.
  /// Returns the offset in global coordinates, or null if position is not visible.
  Offset? coordsAtPos(int pos) {
    final renderEditable = _renderEditable;
    if (renderEditable == null) return null;
    
    final textPosition = TextPosition(offset: pos.clamp(0, _state.doc.length));
    
    // Get position in text layout coordinate system
    final caretRect = renderEditable.getLocalRectForCaret(textPosition);
    
    // Convert text layout coords to global
    return _textLayoutToGlobalCoords(Offset(caretRect.left, caretRect.top));
  }
  
  /// Generate line blocks for the document.
  /// Used by gutters to know line positions.
  /// 
  /// When soft-wrapping is enabled, this measures actual line heights
  /// from the RenderEditable to account for wrapped lines.
  List<BlockInfo> _getLineBlocks() {
    final doc = _state.doc;
    final blocks = <BlockInfo>[];
    
    // Try to get actual measured line heights from RenderEditable
    final measuredHeights = _measureLineHeights();
    
    if (measuredHeights != null && measuredHeights.length == doc.lines) {
      var top = 0.0;
      for (var i = 1; i <= doc.lines; i++) {
        final line = doc.line(i);
        final height = measuredHeights[i - 1];
        blocks.add(BlockInfo(line.from, line.length, top, height));
        top += height;
      }
    } else {
      // Fallback to fixed line height
      final lh = lineHeight;
      var top = 0.0;
      for (var i = 1; i <= doc.lines; i++) {
        final line = doc.line(i);
        blocks.add(BlockInfo(line.from, line.length, top, lh));
        top += lh;
      }
    }
    
    return blocks;
  }
  
  /// Measure actual line heights from the RenderEditable.
  /// Returns a list of heights for each line, or null if measurement fails
  /// or the render object hasn't been laid out yet.
  List<double>? _measureLineHeights() {
    final editableState = _editableTextKey.currentState;
    if (editableState == null) return null;
    
    final renderEditable = editableState.renderEditable;
    
    // Check if render object is attached and laid out - if not, return null to use fallback
    if (!renderEditable.attached || !renderEditable.hasSize) return null;
    
    final doc = _state.doc;
    final numLines = doc.lines;
    if (numLines == 0) return null;
    
    final heights = <double>[];
    
    for (var i = 1; i <= numLines; i++) {
      final line = doc.line(i);
      
      // Get the rect at the start of the line
      final startRect = renderEditable.getLocalRectForCaret(
        TextPosition(offset: line.from),
      );
      
      // Get the rect at the end of the line (or start of next line)
      final endPos = i < numLines ? doc.line(i + 1).from : doc.length;
      final endRect = renderEditable.getLocalRectForCaret(
        TextPosition(offset: endPos),
      );
      
      // Calculate height: difference between line tops, 
      // or use the caret height for the last line
      double height;
      if (i < numLines) {
        height = endRect.top - startRect.top;
      } else {
        // For the last line, use the caret height
        height = startRect.height;
      }
      
      // Ensure minimum height
      if (height < fixedLineHeight) {
        height = fixedLineHeight;
      }
      
      heights.add(height);
    }
    
    return heights;
  }
  
  // ============================================================================
  // Plugin Access
  // ============================================================================
  
  /// Get the value of a specific view plugin, if present.
  ///
  /// Note that plugins that crash can be dropped from a view, so even when
  /// you know you registered a given plugin, it is recommended to check
  /// the return value of this method.
  V? plugin<V extends PluginValue>(ViewPlugin<V> plugin) {
    var known = _pluginMap[plugin];
    if (known == null || known.spec != plugin) {
      // Find the plugin instance
      known = _plugins.cast<PluginInstance?>().firstWhere(
        (p) => p?.spec == plugin,
        orElse: () => null,
      );
      _pluginMap[plugin] = known;
    }
    if (known == null) return null;
    // Ensure plugin is updated and return value
    known.update(this);
    return known.value as V?;
  }

  // ============================================================================
  // Lifecycle
  // ============================================================================

  @override
  void initState() {
    super.initState();
    
    // Initialize gesture detector builder for mouse/touch selection
    _selectionGestureDetectorBuilder = _EditorViewSelectionGestureDetectorBuilder(state: this);

    // Initialize state
    _state = widget.state ??
        widget.config?.state ??
        EditorState.create(
          EditorStateConfig(
            doc: widget.config?.doc ?? '',
            selection: widget.config?.selection,
            extensions: widget.config?.extensions,
          ),
        );

    _viewState = ViewState(_state);
    _inputState = InputState(this);
    
    // Initialize plugins from the viewPlugin facet
    _initPlugins();
    
    // Initial decoration collection
    _updateDecorations();

    // Initialize controllers with syntax highlighting support
    _textController = HighlightingTextEditingController(
      text: _state.doc.toString(),
      getDecorations: () => _decorations,
      theme: widget.highlightTheme,
    );
    _textController.addListener(_onTextChanged);

    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        // Check if modifier key changed for Ctrl+hover underline
        _checkCtrlHoverState();
        // Try our keymap first
        final result = handleKey(event);
        
        // If we didn't handle the key, Flutter's EditableText might move the cursor.
        // Schedule a post-frame check to update signature help based on new cursor position.
        if (result == KeyEventResult.ignored && _signatureResult != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _signatureResult != null) {
              _updateSignatureHelp();
            }
          });
        }
        
        return result;
      },
    );
    _focusNode.addListener(_onFocusChanged);

    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // Initialize completion tooltip controller
    _completionTooltipController = CompletionTooltipController(
      onAccept: (option) {
        applyCompletion(this, option);
      },
    );
    
    // Schedule a rebuild after first frame to get accurate line measurements
    // (RenderEditable needs to complete layout before we can measure line heights)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }
  
  /// Initialize plugins from the state's viewPlugin facet.
  void _initPlugins() {
    final specs = _state.facet(viewPlugin);
    _plugins = specs.map((spec) => PluginInstance(spec)).toList();
    for (final plugin in _plugins) {
      plugin.update(this);
    }
  }
  
  /// Update the cached decorations from the facet.
  void _updateDecorations() {
    final sources = _state.facet(decorationsFacet);
    final allDeco = <RangeSet<Decoration>>[];
    
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source is RangeSet<Decoration>) {
        allDeco.add(source);
      } else if (source is Function) {
        // Call the function with this view - handles both typed and dynamic functions
        try {
          final result = source(this);
          if (result is RangeSet<Decoration>) {
            allDeco.add(result);
          }
        } catch (e) {
          // Log but continue - bad decoration source shouldn't crash editor
          logException(_state, e, 'decoration source');
        }
      }
    }
    
    _decorations = allDeco.isEmpty ? RangeSet.empty() : RangeSet.join(allDeco);
  }
  
  /// Update plugins after a view update.
  void _updatePlugins(ViewUpdate update) {
    final oldPluginSpecs = update.startState.facet(viewPlugin);
    final newPluginSpecs = update.state.facet(viewPlugin);
    
    if (!_listsEqual(oldPluginSpecs, newPluginSpecs)) {
      // Plugin set changed, rebuild
      final newPlugins = <PluginInstance>[];
      for (final spec in newPluginSpecs) {
        // Try to find existing instance
        final existing = _plugins.cast<PluginInstance?>().firstWhere(
          (p) => p?.spec == spec,
          orElse: () => null,
        );
        newPlugins.add(existing ?? PluginInstance(spec));
      }
      
      // Destroy removed plugins
      for (final old in _plugins) {
        if (!newPlugins.contains(old)) {
          old.destroy(this);
        }
      }
      
      _plugins = newPlugins;
      _pluginMap.clear();
    }
    
    // Mark all plugins for update
    for (final plugin in _plugins) {
      plugin.mustUpdate = update;
    }
    
    // Update all plugins
    for (final plugin in _plugins) {
      plugin.update(this);
    }
    
    // Update decorations after plugins are updated
    final oldDecorations = _decorations;
    _updateDecorations();
    
    // If decorations changed, notify the text controller to rebuild
    if (!identical(oldDecorations, _decorations)) {
      _textController.notifyListeners();
    }
  }
  
  /// Check if two lists are equal.
  bool _listsEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(EditorView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If highlight theme changed, recreate the text controller
    if (widget.highlightTheme != oldWidget.highlightTheme) {
      _textController.removeListener(_onTextChanged);
      _textController.dispose();
      _textController = HighlightingTextEditingController(
        text: _state.doc.toString(),
        getDecorations: () => _decorations,
        theme: widget.highlightTheme,
      );
      _textController.addListener(_onTextChanged);
      setState(() {});
    }

    // If external state changed, update our state
    if (widget.state != null && widget.state != _state) {
      // Destroy old plugins
      for (final plugin in _plugins) {
        plugin.destroy(this);
      }
      _plugins = [];
      _pluginMap.clear();
      _decorations = RangeSet.empty();
      
      // Update state synchronously BEFORE setState so that when build()
      // is called, decorations are already correct for the new document
      _state = widget.state!;
      _viewState = ViewState(_state);
      _inputState.destroy();
      _inputState = InputState(this);
      
      // Re-initialize gesture detector builder
      _selectionGestureDetectorBuilder = _EditorViewSelectionGestureDetectorBuilder(state: this);
      
      // Reinitialize plugins and decorations for new state
      _initPlugins();
      _updateDecorations();
      
      // Now sync controller and trigger rebuild
      setState(() {
        _syncTextController();
      });
    }
  }

  @override
  void dispose() {
    // Destroy all plugins
    for (final plugin in _plugins) {
      plugin.destroy(this);
    }
    _plugins = [];
    
    _inputState.destroy();
    _completionTooltipController?.dispose();
    _completionTooltipController = null;
    _hideHoverTooltip();
    _hoverTooltipController.dispose();
    _hoverTimer?.cancel();
    _hideSignatureHelp();
    _signatureHelpController.dispose();
    _signatureTimer?.cancel();
    _signatureReQueryTimer?.cancel();
    _hideRenameInput();
    _highlightTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textInputConnection?.close();
    super.dispose();
  }
  
  // ============================================================================
  // Hover Tooltip
  // ============================================================================
  
  /// The last hover position, used to check if we're still hovering the same spot.
  int? _lastHoverPos;
  
  /// Pending async tooltip futures.
  List<Future<HoverTooltip?>>? _pendingTooltips;
  
  void _onHover(PointerHoverEvent event) {
    _hoverTimer?.cancel();
    _lastHoverOffset = event.position;
    
    // Check for Ctrl+hover (Cmd on Mac) for go-to-definition underline
    final keyboard = HardwareKeyboard.instance;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isCtrlHeld = isMac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    
    // Get document position and side using Flutter's built-in API
    final result = posAtCoordsWithSide(event.position);
    if (result == null) return;
    final (pos, side) = result;
    
    // Handle Ctrl+hover underline
    _updateCtrlHoverUnderline(pos, isCtrlHeld);
    
    // Check for diagnostics at this position
    final diagnostics = diagnosticsAtPos(_state, pos);
    
    // Check for registered hover tooltip sources
    final hoverConfigs = _state.facet(hoverTooltipFacet);
    
    // If nothing to show, hide tooltip after delay
    if (diagnostics.isEmpty && hoverConfigs.isEmpty) {
      _hoverTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          _hideHoverTooltip();
        }
      });
      return;
    }
    
    // If tooltip is already showing for same position, keep it
    if (_hoverTooltipController.isShowing && _lastHoverPos == pos) {
      return;
    }
    
    // Moving to a new position - hide old tooltip immediately
    if (_hoverTooltipController.isShowing) {
      _hideHoverTooltip();
    }
    
    // Get the anchor position for tooltip placement
    final anchorPos = diagnostics.isNotEmpty ? diagnostics.first.from : pos;
    // Use coordsAtPos for consistent coordinate conversion
    final globalAnchor = coordsAtPos(anchorPos) ?? Offset.zero;
    
    // Determine hover delay from config (default 300ms)
    var hoverDelay = 300;
    if (hoverConfigs.isNotEmpty) {
      hoverDelay = hoverConfigs.first.hoverTime;
    }
    
    // Show tooltip after delay
    _hoverTimer = Timer(Duration(milliseconds: hoverDelay), () {
      if (mounted) {
        _showHoverTooltipAt(pos, side, diagnostics, hoverConfigs, globalAnchor);
      }
    });
  }
  
  void _onHoverExit(PointerExitEvent event) {
    _hoverTimer?.cancel();
    _pendingTooltips = null;
    _lastHoverOffset = null;
    _clearCtrlHoverUnderline();
    // Hide tooltip when exiting editor (with short delay to allow moving to tooltip)
    _hoverTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _hideHoverTooltip();
      }
    });
  }
  
  // ============================================================================
  // Ctrl+Hover Underline (Go to Definition)
  // ============================================================================
  
  /// Update the Ctrl+hover underline decoration.
  void _updateCtrlHoverUnderline(int pos, bool isCtrlHeld) {
    // Check if go-to-definition is available
    final configs = _state.facet(gotoDefinitionFacet);
    if (configs.isEmpty) {
      _clearCtrlHoverUnderline();
      return;
    }
    
    // Check if any config has showHoverUnderline enabled
    final showUnderline = configs.any((c) => c.options.showHoverUnderline);
    if (!showUnderline || !isCtrlHeld) {
      _clearCtrlHoverUnderline();
      return;
    }
    
    // Get word at position
    final word = _state.wordAt(pos);
    if (word == null || word.empty) {
      _clearCtrlHoverUnderline();
      return;
    }
    
    // If already showing underline for same range, skip
    if (_ctrlHoverRange != null && 
        _ctrlHoverRange!.from == word.from && 
        _ctrlHoverRange!.to == word.to) {
      return;
    }
    
    // Update underline range and trigger redraw
    _ctrlHoverRange = (from: word.from, to: word.to);
    _showingLinkCursor = true;
    _textController.linkRange = _ctrlHoverRange;
    setState(() {});
  }
  
  /// Clear the Ctrl+hover underline.
  void _clearCtrlHoverUnderline() {
    if (_ctrlHoverRange != null || _showingLinkCursor) {
      _ctrlHoverRange = null;
      _showingLinkCursor = false;
      _textController.linkRange = null;
      setState(() {});
    }
  }
  
  /// Check and update Ctrl+hover state when modifier keys change.
  void _checkCtrlHoverState() {
    if (_lastHoverOffset == null) return;
    
    final keyboard = HardwareKeyboard.instance;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final isCtrlHeld = isMac ? keyboard.isMetaPressed : keyboard.isControlPressed;
    
    if (!isCtrlHeld) {
      _clearCtrlHoverUnderline();
      return;
    }
    
    // Re-calculate position and update underline
    final pos = posAtCoords(_lastHoverOffset!);
    if (pos != null) {
      _updateCtrlHoverUnderline(pos, true);
    }
  }
  
  /// Show hover tooltip at position, combining diagnostics and registered sources.
  Future<void> _showHoverTooltipAt(
    int pos,
    int side,
    List<Diagnostic> diagnostics,
    List<HoverTooltipConfig> hoverConfigs,
    Offset fallbackAnchor,
  ) async {
    _lastHoverPos = pos;
    
    // Collect tooltips from all sources
    final tooltips = <Widget>[];
    int? anchorPos; // Position to anchor the tooltip (start of symbol)
    
    // Add diagnostic tooltip if present
    if (diagnostics.isNotEmpty) {
      tooltips.add(DiagnosticTooltip(diagnostics: diagnostics));
      anchorPos = diagnostics.first.from;
    }
    
    // Query registered hover sources asynchronously
    if (hoverConfigs.isNotEmpty) {
      final futures = <Future<HoverTooltip?>>[];
      for (final config in hoverConfigs) {
        final result = config.source(_state, pos, side);
        if (result is Future) {
          // Async result - cast it properly
          futures.add(Future.value(result).then((v) => v as HoverTooltip?));
        } else if (result != null) {
          // Sync result
          final tooltip = result as HoverTooltip;
          final view = tooltip.create(context);
          tooltips.add(view.widget);
          anchorPos ??= tooltip.pos; // Use first tooltip's pos as anchor
        }
      }
      
      // Handle async results
      if (futures.isNotEmpty) {
        _pendingTooltips = futures;
        final results = await Future.wait(futures);
        
        // Check if we're still at the same position
        if (_lastHoverPos != pos || _pendingTooltips != futures) {
          return;
        }
        _pendingTooltips = null;
        
        for (final tooltip in results) {
          if (tooltip != null) {
            final view = tooltip.create(context);
            tooltips.add(view.widget);
            anchorPos ??= tooltip.pos; // Use first tooltip's pos as anchor
          }
        }
      }
    }
    
    if (tooltips.isEmpty) {
      _hideHoverTooltip();
      return;
    }
    
    // Calculate anchor position from tooltip's pos, not hover position
    // Use coordsAtPos for consistency with other tooltip positioning
    Offset globalAnchor = fallbackAnchor;
    if (anchorPos != null) {
      final coords = coordsAtPos(anchorPos);
      if (coords != null) {
        globalAnchor = coords;
      }
    }
    
    _showCombinedHoverTooltip(tooltips, globalAnchor);
  }
  
  /// Show combined hover tooltip with smart positioning.
  /// 
  /// Uses follow_the_leader for positioning that:
  /// - Positions below symbol by default
  /// - Flips above if would overflow bottom (based on actual content size)
  /// - Handles horizontal overflow automatically
  void _showCombinedHoverTooltip(List<Widget> tooltipWidgets, Offset globalAnchor) {
    _hideHoverTooltip();
    
    const maxWidth = 500.0;
    const maxHeight = 300.0;
    
    // Combine multiple tooltip widgets
    Widget content;
    if (tooltipWidgets.length == 1) {
      content = tooltipWidgets.first;
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: tooltipWidgets,
      );
    }
    
    _hoverTooltipController.show(
      context: context,
      anchor: globalAnchor,
      anchorSize: Size(1, lineHeight),
      aligner: const BelowFirstAligner(),
      onHoverEnter: () => _hoverTimer?.cancel(),
      onHoverExit: () {
        // Delay hiding to allow user to move back to tooltip
        _hoverTimer?.cancel();
        _hoverTimer = Timer(const Duration(milliseconds: 100), () {
          if (mounted) {
            _hideHoverTooltip();
          }
        });
      },
      child: LimitedBox(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        child: SingleChildScrollView(
          child: content,
        ),
      ),
    );
  }
  
  void _hideHoverTooltip() {
    _lastHoverPos = null;
    _pendingTooltips = null;
    _hoverTooltipController.hide();
  }
  
  /// Get the Overlay's global position offset.
  /// 
  /// When positioning overlays, we need to account for the fact that the
  /// Overlay might not be at screen origin (0,0). For example, if there's
  /// a sidebar to the left, the Overlay starts at X=100, so we need to
  /// subtract 100 from global X coordinates to get correct overlay-local positions.
  Offset _getOverlayOffset() {
    final overlay = Overlay.of(context);
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox?;
    return overlayRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
  }

  // ============================================================================
  // Public methods
  // ============================================================================

  /// Dispatch a transaction to update the editor state.
  ///
  /// This is the primary way to make changes to the editor. Pass one or
  /// more [TransactionSpec]s to create and apply a transaction.
  void dispatch(List<TransactionSpec> specs) {
    if (specs.isEmpty) return;
    final tr = _state.update(specs);
    _dispatchTransaction([tr]);
  }

  /// Dispatch a single transaction.
  void dispatchTransaction(Transaction tr) {
    _dispatchTransaction([tr]);
  }

  /// Dispatch multiple transactions at once.
  ///
  /// This matches the JS `view.dispatch([tr1, tr2, ...])` pattern where
  /// multiple transactions are applied together as a single operation.
  void dispatchTransactions(List<Transaction> transactions) {
    if (transactions.isEmpty) return;
    _dispatchTransaction(transactions);
  }

  /// Format the document using the configured document formatting source.
  ///
  /// Returns a future that completes when formatting is done.
  /// If no formatting source is configured, this is a no-op.
  Future<void> formatDocument() async {
    debugPrint('[EditorViewState.formatDocument] Starting format...');
    final spec = await format.formatDocument(_state);
    debugPrint('[EditorViewState.formatDocument] Got spec: ${spec != null ? "non-null" : "null"}, mounted=$mounted');
    if (spec != null && mounted) {
      debugPrint('[EditorViewState.formatDocument] Dispatching changes...');
      dispatch([spec]);
      debugPrint('[EditorViewState.formatDocument] Done');
    }
  }

  /// Apply transactions to update the view.
  ///
  /// This is called by the dispatch handler to actually apply changes.
  /// Normally you should use [dispatch] instead.
  void update(List<Transaction> transactions) {
    if (transactions.isEmpty) return;

    _updating = true;
    try {
      // Verify transaction chain
      EditorState currentState = _state;
      for (final tr in transactions) {
        if (!identical(tr.startState, currentState)) {
          throw RangeError(
            'Trying to update state with a transaction that doesn\'t start '
            'from the previous state.',
          );
        }
        currentState = tr.state as EditorState;
      }

      // Create view update
      final viewUpdate = ViewUpdate.create(
        currentState,
        transactions,
      );

      // Update our state FIRST so plugins see the new state
      _state = currentState;
      
      // Check for format effects before updating view
      _handleFormatEffects(transactions);
      
      // Update view state and input state
      _viewState.update(viewUpdate);
      _inputState.update(viewUpdate);
      
      // Update plugins (they need access to the new state via _view.state)
      _updatePlugins(viewUpdate);

      // Sync UI
      setState(() {
        _syncTextController();
      });

      // Notify listeners
      widget.onUpdate?.call(viewUpdate);

      // Call update listeners from facets
      final listeners = _state.facet(EditorView.updateListener);
      for (final listener in listeners) {
        listener(viewUpdate);
      }
      
      // Update completion popup
      _updateCompletionPopup();
      
      // Update signature help if active and cursor moved
      if (_signatureResult != null) {
        _updateSignatureHelp();
      }
      
      // Update document highlights on cursor change
      if (viewUpdate.selectionSet) {
        _scheduleDocumentHighlight();
      }
    } finally {
      _updating = false;
    }
  }
  
  /// Update the completion popup based on current state.
  void _updateCompletionPopup() {
    final cState = _state.field(completionState, false);
    final controller = _completionTooltipController;
    if (controller == null) return;
    
    if (cState == null || cState.open == null) {
      // Hide completion popup
      if (controller.isShowing) {
        controller.hide();
      }
      return;
    }
    
    final dialog = cState.open!;
    if (dialog.options.isEmpty) {
      if (controller.isShowing) {
        controller.hide();
      }
      return;
    }
    
    // Get cursor position for the anchor
    final tooltipPos = dialog.tooltip.pos;
    final globalAnchor = coordsAtPos(tooltipPos);
    if (globalAnchor == null) {
      if (controller.isShowing) {
        controller.hide();
      }
      return;
    }
    
    // Convert global coords to overlay-local coords
    final overlayOffset = _getOverlayOffset();
    final anchor = globalAnchor - overlayOffset;
    
    final config = _state.facet(completionConfig);
    
    // Show or update the completion popup
    if (controller.isShowing) {
      controller.update(
        dialog: dialog,
        id: cState.id,
        config: config,
        anchor: anchor,
        lineHeight: lineHeight,
      );
    } else {
      controller.show(
        context: context,
        dialog: dialog,
        id: cState.id,
        config: config,
        anchor: anchor,
        lineHeight: lineHeight,
      );
    }
  }

  /// Set a completely new state, reinitializing the view.
  void setState_(EditorState newState) {
    setState(() {
      _state = newState;
      _viewState = ViewState(_state);
      _inputState.destroy();
      _inputState = InputState(this);
      _syncTextController();
    });
  }

  /// Focus the editor.
  void focus() {
    _focusNode.requestFocus();
  }

  /// Get the block info at a document position.
  BlockInfo lineBlockAt(int pos) {
    return _viewState.lineBlockAt(pos);
  }

  /// Handle a key event.
  ///
  /// Returns [KeyEventResult.handled] if the event was handled by a keymap
  /// binding, [KeyEventResult.ignored] otherwise.
  KeyEventResult handleKey(KeyEvent event) {
    // First let the widget's onKey handler try
    if (widget.onKey != null) {
      final result = widget.onKey!(_focusNode, event);
      if (result == KeyEventResult.handled) {
        return result;
      }
    }

    // Then try our keymap handlers via InputState
    if (_inputState.handleKeyEvent(event)) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Get the document position at the given global coordinates.
  /// 
  /// Returns null if the position cannot be determined.
  int? posAtCoords(Offset globalPosition) {
    final renderEditable = _renderEditable;
    if (renderEditable == null) return null;
    
    // Use Flutter's built-in API - it handles coordinate conversion internally
    return renderEditable.getPositionForPoint(globalPosition).offset;
  }
  
  /// Get the document position and side at the given global coordinates.
  /// 
  /// Returns (pos, side) where side is -1 if before position, 1 if after.
  (int pos, int side)? posAtCoordsWithSide(Offset globalPosition) {
    final renderEditable = _renderEditable;
    if (renderEditable == null) return null;
    
    // Use Flutter's built-in API
    final pos = renderEditable.getPositionForPoint(globalPosition).offset;
    
    // Determine side by comparing click position to caret position
    final textLayoutPos = _globalToTextLayoutCoords(globalPosition);
    if (textLayoutPos == null) return (pos, 1);
    
    final posCoords = renderEditable.getLocalRectForCaret(TextPosition(offset: pos));
    final side = textLayoutPos.dx < posCoords.left ? -1 : 1;
    return (pos, side);
  }

  // ============================================================================
  // Go to Definition
  // ============================================================================
  
  /// Trigger go-to-definition at the given position.
  /// 
  /// This is the public API for programmatically triggering go-to-definition.
  /// Use this when implementing custom keyboard shortcuts or UI buttons.
  void triggerGoToDefinition(int pos) => _triggerGoToDefinition(pos);
  
  /// Internal implementation of go-to-definition.
  void _triggerGoToDefinition(int pos) async {
    final configs = _state.facet(gotoDefinitionFacet);
    if (configs.isEmpty) return;
    
    // Query all definition sources
    for (final config in configs) {
      try {
        final result = await Future.value(config.source(_state, pos));
        if (result != null && result.isNotEmpty) {
          final location = result.primary!;
          _navigateToDefinition(location, config.options);
          return;
        }
      } catch (e) {
        // Continue to next source on error
      }
    }
  }
  
  /// Navigate to a definition location.
  void _navigateToDefinition(DefinitionLocation location, GotoDefinitionOptions options) {
    if (options.navigator != null) {
      options.navigator!(location, _state);
      return;
    }
    
    // Default navigation for local definitions
    if (location.isLocal) {
      // Select the definition range (or just position cursor if no end)
      final end = location.end ?? location.pos;
      dispatch([
        TransactionSpec(
          selection: EditorSelection.single(location.pos, end),
          scrollIntoView: true,
          userEvent: 'select.gotoDefinition',
        ),
      ]);
    }
    // External definitions require a custom navigator
  }

  // ============================================================================
  // Find References
  // ============================================================================
  
  /// Trigger find-references at the given position.
  void triggerFindReferences(int pos) async {
    final configs = _state.facet(findReferencesFacet);
    if (configs.isEmpty) return;
    
    // Query all references sources
    for (final config in configs) {
      try {
        final result = await Future.value(config.source(_state, pos));
        if (result != null && result.isNotEmpty) {
          _displayReferences(result, pos, config.options);
          return;
        }
      } catch (e) {
        // Continue to next source on error
      }
    }
  }
  
  /// Display references result.
  void _displayReferences(ReferencesResult result, int originPos, FindReferencesOptions options) {
    if (options.display != null) {
      options.display!(result, _state, originPos);
    }
    // Without a display handler, references are silently ignored
    // Applications should provide a display callback to show results
  }

  // ============================================================================
  // Signature Help
  // ============================================================================
  
  /// Trigger signature help at the given position.
  void _triggerSignatureHelp(int pos) async {
    final configs = _state.facet(signatureHelpFacet);
    if (configs.isEmpty) return;
    
    // Query all signature sources
    for (final config in configs) {
      try {
        final sourceResult = config.source(_state, pos);
        final result = await sourceResult;
        if (result != null && result.isNotEmpty) {
          _signatureResult = result;
          _showSignatureHelp(result);
          return;
        }
      } catch (e, st) {
        // Continue to next source on error
      }
    }
  }
  
  /// Update signature help based on cursor movement.
  /// 
  /// Re-queries the signature source with debounce to let the server decide
  /// if signature help should still be shown at the new cursor position.
  void _updateSignatureHelp() {
    final result = _signatureResult;
    if (result == null) return;
    
    // Read cursor position from text controller (may be ahead of _state after arrow key movement)
    final controllerSelection = _textController.selection;
    final cursorPos = controllerSelection.isValid 
        ? controllerSelection.extentOffset 
        : _state.selection.main.head;
    final docText = _textController.text;
    
    // Quick local check - if we've clearly exited the function call, hide immediately
    if (!isWithinFunctionCall(docText, result.triggerPos, cursorPos)) {
      _hideSignatureHelp();
      return;
    }
    
    // Detect active parameter for immediate UI update
    final activeParam = detectActiveParameter(docText, result.triggerPos, cursorPos);
    if (activeParam < 0) {
      _hideSignatureHelp();
      return;
    }
    
    // Update the signature with new active parameter (immediate feedback)
    final activeSignature = result.active;
    if (activeSignature != null) {
      final updated = SignatureResult(
        signatures: result.signatures.map((sig) {
          if (identical(sig, activeSignature)) {
            return sig.withActiveParameter(activeParam);
          }
          return sig;
        }).toList(),
        activeSignature: result.activeSignature,
        triggerPos: result.triggerPos,
      );
      _signatureResult = updated;
      _showSignatureHelp(updated);
    }
    
    // Debounced re-query: ask the source if signature help is still valid
    // This catches cases the local paren-tracking misses (e.g., nested calls, comments)
    _signatureReQueryTimer?.cancel();
    _signatureReQueryTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _signatureResult == null) return;
      _reQuerySignatureHelp(cursorPos);
    });
  }
  
  /// Re-query the signature source to verify signature help is still valid.
  void _reQuerySignatureHelp(int pos) async {
    final configs = _state.facet(signatureHelpFacet);
    if (configs.isEmpty) {
      _hideSignatureHelp();
      return;
    }
    
    // Query sources - if any returns a valid result, keep showing
    for (final config in configs) {
      try {
        final result = await config.source(_state, pos);
        if (result != null && result.isNotEmpty) {
          // Valid result - update with fresh data
          _signatureResult = result;
          _showSignatureHelp(result);
          return;
        }
      } catch (e) {
        // Continue to next source on error
      }
    }
    
    // No source returned valid signatures - dismiss
    _hideSignatureHelp();
  }
  
  /// Show signature help tooltip.
  void _showSignatureHelp(SignatureResult result) {
    // Hide previous tooltip overlay only (don't clear _signatureResult - caller manages that)
    _signatureReQueryTimer?.cancel();
    _signatureReQueryTimer = null;
    _signatureHelpController.hide();
    
    final signature = result.active;
    if (signature == null) return;
    
    // Get cursor position for anchor
    final cursorPos = _state.selection.main.head;
    final anchor = coordsAtPos(cursorPos);
    if (anchor == null) return;
    
    const maxWidth = 500.0;
    
    _signatureHelpController.show(
      context: context,
      anchor: anchor,
      anchorSize: Size(1, lineHeight),
      aligner: const AboveFirstAligner(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: _SignatureHelpTooltip(
          signature: signature,
          maxWidth: maxWidth,
        ),
      ),
    );
  }
  
  /// Hide signature help tooltip.
  void _hideSignatureHelp() {
    _signatureReQueryTimer?.cancel();
    _signatureReQueryTimer = null;
    _signatureResult = null;
    _signatureHelpController.hide();
  }
  
  /// Check if a typed character should trigger signature help.
  void _checkSignatureTrigger(String insert, int pos) {
    final configs = _state.facet(signatureHelpFacet);
    if (configs.isEmpty) return;
    
    for (final config in configs) {
      if (!config.options.autoTrigger) continue;
      
      // Check for trigger characters
      if (config.options.triggerCharacters.contains(insert)) {
        final delay = config.options.delay;
        if (delay > 0) {
          _signatureTimer?.cancel();
          _signatureTimer = Timer(Duration(milliseconds: delay), () {
            if (mounted) {
              _triggerSignatureHelp(pos);
            }
          });
        } else {
          _triggerSignatureHelp(pos);
        }
        return;
      }
      
      // Check for retrigger (dismiss) characters
      if (config.options.retriggerCharacters.contains(insert)) {
        _hideSignatureHelp();
        return;
      }
    }
  }

  // ============================================================================
  // Document Formatting
  // ============================================================================
  
  /// Handle format and rename effects from transactions.
  void _handleFormatEffects(List<Transaction> transactions) {
    for (final tr in transactions) {
      for (final effect in tr.effects) {
        if (effect.is_(format.formatDocumentEffect)) {
          _triggerFormatDocument();
        } else if (effect.is_(format.formatRangeEffect)) {
          final range = effect.value as ({int from, int to});
          _triggerFormatRange(range.from, range.to);
        } else if (effect.is_(triggerRenameEffect)) {
          final pos = effect.value as int;
          _triggerRename(pos);
        } else if (effect.is_(triggerDefinitionEffect)) {
          final pos = effect.value as int;
          _triggerGoToDefinition(pos);
        }
      }
    }
  }
  
  /// Trigger document formatting.
  void _triggerFormatDocument() async {
    final spec = await format.formatDocument(_state);
    if (spec != null && mounted) {
      dispatch([spec]);
    }
  }
  
  /// Trigger range formatting.
  void _triggerFormatRange(int from, int to) async {
    final spec = await format.formatRange(_state, from, to);
    if (spec != null && mounted) {
      dispatch([spec]);
    }
  }
  
  /// Check if on-type formatting should trigger for a character.
  void _checkOnTypeFormatting(String char, int pos) async {
    final configs = _state.facet(format.documentFormattingFacet);
    if (configs.isEmpty) return;
    
    // Check if any config has this trigger character
    final hasTrigger = configs.any((c) => 
        c.onTypeOptions.triggerCharacters.contains(char));
    if (!hasTrigger) return;
    
    final spec = await format.checkOnTypeFormatting(_state, pos, char);
    if (spec != null && mounted) {
      dispatch([spec]);
    }
  }

  // ============================================================================
  // Rename Symbol
  // ============================================================================
  
  /// Trigger rename at the given position.
  void _triggerRename(int pos) async {
    final configs = _state.facet(renameFacet);
    if (configs.isEmpty) return;
    
    final config = configs.first;
    _renamePos = pos;
    
    // Prepare rename - check if possible and get symbol range
    PrepareRenameResult? prepResult;
    if (config.options.prepareSource != null) {
      prepResult = await Future.value(config.options.prepareSource!(_state, pos));
      if (prepResult == null || !prepResult.canRename) {
        _renamePos = null;
        return;
      }
    } else {
      // No prepare source - use word at position
      final word = _state.wordAt(pos);
      if (word == null || word.empty) {
        _renamePos = null;
        return;
      }
      final text = _state.doc.sliceString(word.from, word.to);
      prepResult = PrepareRenameResult(
        from: word.from,
        to: word.to,
        placeholder: text,
      );
    }
    
    _preparedRename = prepResult;
    _showRenameInput(prepResult);
  }
  
  /// Show the rename input UI.
  void _showRenameInput(PrepareRenameResult prepResult) {
    _hideRenameInput();
    
    // Get position for the input
    final anchor = coordsAtPos(prepResult.from);
    if (anchor == null) return;
    
    // Get overlay offset to convert global coords to overlay-local coords
    final overlayOffset = _getOverlayOffset();
    final localAnchor = anchor - overlayOffset;
    
    final controller = TextEditingController(text: prepResult.placeholder);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: prepResult.placeholder.length,
    );
    
    _renameInputEntry = OverlayEntry(
      builder: (overlayContext) {
        return _RenameInputWidget(
          anchor: localAnchor,
          lineHeight: lineHeight,
          initialValue: prepResult.placeholder,
          controller: controller,
          onSubmit: (newName) {
            _performRename(newName);
          },
          onCancel: () {
            _hideRenameInput();
          },
        );
      },
    );
    
    Overlay.of(context).insert(_renameInputEntry!);
  }
  
  /// Perform the rename with the new name.
  void _performRename(String newName) async {
    final pos = _renamePos;
    final prepResult = _preparedRename;
    _hideRenameInput();
    
    if (pos == null || prepResult == null) return;
    if (newName.isEmpty || newName == prepResult.placeholder) return;
    
    final configs = _state.facet(renameFacet);
    if (configs.isEmpty) return;
    
    final config = configs.first;
    
    try {
      final result = await Future.value(config.source(_state, pos, newName));
      if (result == null || result.isEmpty) return;
      if (!mounted) return;
      
      // Handle workspace edits if handler provided
      if (result.isWorkspaceRename && config.options.workspaceHandler != null) {
        final success = await config.options.workspaceHandler!(
          result.workspaceEdits,
          newName,
        );
        if (!success) return;
      }
      
      // Apply local edits
      if (result.locations.isNotEmpty) {
        final spec = applyRenameEdits(_state, result.locations, newName);
        dispatch([spec]);
      }
    } catch (e) {
      // Rename failed - could show error
    }
  }
  
  /// Hide the rename input UI.
  void _hideRenameInput() {
    _renameInputEntry?.remove();
    _renameInputEntry?.dispose();
    _renameInputEntry = null;
    _renamePos = null;
    _preparedRename = null;
  }

  // ============================================================================
  // Document Highlight
  // ============================================================================
  
  /// Schedule document highlight request with debouncing.
  void _scheduleDocumentHighlight() {
    _highlightTimer?.cancel();
    
    final configs = _state.facet(documentHighlightFacet);
    if (configs.isEmpty) return;
    
    final pos = _state.selection.main.head;
    
    // Skip if position hasn't changed significantly
    if (_lastHighlightPos == pos) return;
    
    final delay = configs.first.options.delay;
    
    _highlightTimer = Timer(Duration(milliseconds: delay), () {
      if (mounted) {
        _requestDocumentHighlight(pos);
      }
    });
  }
  
  /// Request document highlights at position.
  void _requestDocumentHighlight(int pos) async {
    final configs = _state.facet(documentHighlightFacet);
    if (configs.isEmpty) return;
    
    _lastHighlightPos = pos;
    
    // Check if we're on a word
    final word = _state.wordAt(pos);
    if (word == null || word.empty) {
      // Clear highlights if not on a word
      dispatch([clearDocumentHighlights()]);
      return;
    }
    
    // Query highlight source
    final config = configs.first;
    try {
      final result = await Future.value(config.source(_state, pos));
      
      // Check if position is still the same
      if (_lastHighlightPos != pos || !mounted) return;
      
      if (result == null || result.isEmpty) {
        dispatch([clearDocumentHighlights()]);
      } else {
        dispatch([setDocumentHighlights(result.highlights)]);
      }
    } catch (e) {
      // Clear on error
      if (mounted) {
        dispatch([clearDocumentHighlights()]);
      }
    }
  }

  // ============================================================================
  // Private methods
  // ============================================================================

  void _dispatchTransaction(List<Transaction> transactions) {
    final customDispatch =
        widget.config?.dispatchTransactions;

    if (customDispatch != null) {
      customDispatch(transactions, widget);
    } else {
      update(transactions);
    }
  }

  void _syncTextController() {
    final text = _state.doc.toString();
    
    // Temporarily remove listener to avoid re-entrancy when modifying controller
    _textController.removeListener(_onTextChanged);
    try {
      if (_textController.text != text) {
        debugPrint('[CM] _syncTextController: text changed, updating controller');
        _textController.text = text;
      }

      // Sync selection - clamp to text length to avoid RangeError
      final sel = _state.selection.main;
      final textLength = text.length;
      final textSelection = TextSelection(
        baseOffset: sel.anchor.clamp(0, textLength),
        extentOffset: sel.head.clamp(0, textLength),
      );
      if (_textController.selection != textSelection) {
        debugPrint('[CM] _syncTextController: selection mismatch - controller=${_textController.selection} state=${textSelection}');
        _textController.selection = textSelection;
      }
    } finally {
      _textController.addListener(_onTextChanged);
    }
  }

  void _onTextChanged() {
    if (_updating) return;

    final newText = _textController.text;
    final oldText = _state.doc.toString();
    final flutterSelection = _textController.selection;

    // Check for text changes
    if (newText != oldText) {
      // Find the changed region
      var from = 0;
      var toOld = oldText.length;
      var toNew = newText.length;

      // Find common prefix
      while (from < toOld && from < toNew && oldText[from] == newText[from]) {
        from++;
      }

      // Find common suffix
      while (toOld > from &&
          toNew > from &&
          oldText[toOld - 1] == newText[toNew - 1]) {
        toOld--;
        toNew--;
      }

      final insert = newText.substring(from, toNew);
      
      // FIX: For simple insertions, use our cursor position instead of Flutter's.
      // Flutter's TextEditingController selection can diverge from our state due to
      // timing issues between the native text input system and our state sync.
      // Our cursor is the authoritative position for where text should be inserted.
      // Only apply this correction when:
      // 1. It's a simple insert (toOld == from, nothing being replaced)
      // 2. The positions actually differ
      // 3. The correction doesn't create an invalid range (ourCursor must be <= doc length)
      final isSimpleInsert = toOld == from && insert.isNotEmpty;
      final ourCursor = _state.selection.main.head;
      if (isSimpleInsert && from != ourCursor && ourCursor <= oldText.length) {
        debugPrint('[CM] _onTextChanged: correcting insertion pos from $from to $ourCursor');
        from = ourCursor;
        // Also adjust toOld to match, keeping it a simple insert
        toOld = ourCursor;
      }
      
      debugPrint('[CM] _onTextChanged: from=$from toOld=$toOld insert="${insert.replaceAll('\n', '\\n')}" flutterSel=$flutterSelection currentCursor=$ourCursor');

      // Check input handlers first
      final handlers = _state.facet(input.inputHandler);
      var handled = false;
      for (final handler in handlers) {
        if (handler(this, from, toOld, insert)) {
          handled = true;
          debugPrint('[CM] _onTextChanged: handled by inputHandler');
          break;
        }
      }

      if (!handled) {
        debugPrint('[CM] _onTextChanged: dispatching, new cursor will be ${from + insert.length}');
        dispatch([
          TransactionSpec(
            changes: ChangeSpec(from: from, to: toOld, insert: insert),
            selection: EditorSelection.single(from + insert.length),
            userEvent: 'input.type',
          ),
        ]);
        debugPrint('[CM] _onTextChanged: after dispatch, cursor is ${_state.selection.main.head}');
      }
      
      // Check for signature help and on-type formatting triggers
      // For single-char inserts, check that character
      // For multi-char inserts (e.g., paste), check the last character
      if (insert.isNotEmpty) {
        final lastChar = insert[insert.length - 1];
        _checkSignatureTrigger(lastChar, from + insert.length);
        if (insert.length == 1) {
          _checkOnTypeFormatting(insert, from + insert.length);
        }
      }
    } else if (flutterSelection.isValid) {
      // Text didn't change but selection may have - check for selection-only changes
      final currentSelection = _state.selection;
      final newAnchor = flutterSelection.baseOffset.clamp(0, newText.length);
      final newHead = flutterSelection.extentOffset.clamp(0, newText.length);
      
      // If completion is open, ignore selection changes from text controller
      // (EditableText internally moves cursor on arrow keys, which would close completion)
      final cState = _state.field(completionState, false);
      if (cState != null && cState.open != null && !cState.open!.disabled) {
        return;
      }
      
      // Only dispatch if selection actually changed
      if (currentSelection.main.anchor != newAnchor || 
          currentSelection.main.head != newHead) {

        dispatch([
          TransactionSpec(
            selection: EditorSelection.create([
              EditorSelection.range(newAnchor, newHead),
            ]),
            userEvent: 'select',
          ),
        ]);
      }
    }
  }

  void _onSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    if (_updating) return;
    
    debugPrint('[CM] _onSelectionChanged: selection=$selection cause=$cause currentCursor=${_state.selection.main.head}');
    
    final cState = _state.field(completionState, false);
    
    // If completion is open, ignore keyboard-triggered selection changes
    if (cState != null && cState.open != null && !cState.open!.disabled) {
      if (cause == SelectionChangedCause.keyboard) {
        // Also sync text controller selection back to our state to reject the change
        final sel = _state.selection.main;
        final correctSelection = TextSelection(
          baseOffset: sel.anchor.clamp(0, _state.doc.length),
          extentOffset: sel.head.clamp(0, _state.doc.length),
        );
        if (_textController.selection != correctSelection) {
          _updating = true;
          _textController.selection = correctSelection;
          _updating = false;
        }
        debugPrint('[CM] Ignored (completion open)');
        return;
      }
    }
    
    final currentSelection = _state.selection;
    final newAnchor = selection.baseOffset.clamp(0, _state.doc.length);
    final newHead = selection.extentOffset.clamp(0, _state.doc.length);
    
    // Only dispatch if selection actually changed
    if (currentSelection.main.anchor != newAnchor || 
        currentSelection.main.head != newHead) {
      debugPrint('[CM] Dispatching selection change: $newAnchor-$newHead');
      dispatch([
        TransactionSpec(
          selection: EditorSelection.create([
            EditorSelection.range(newAnchor, newHead),
          ]),
          userEvent: 'select',
        ),
      ]);
    } else {
      debugPrint('[CM] Selection unchanged, not dispatching');
    }
  }

  void _onFocusChanged() {
    // Update input state
    if (_focusNode.hasFocus) {
      _inputState.lastFocusTime = DateTime.now().millisecondsSinceEpoch;
    }
    _inputState.notifiedFocused = _focusNode.hasFocus;

    // Dispatch focus change transaction if needed
    final tr = focusChangeTransaction(_state, _focusNode.hasFocus);
    if (tr != null) {
      dispatchTransaction(tr);
    }
  }

  void _onScroll() {
    // Track scroll position in input state
    _inputState.lastScrollTop = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0;
    // Note: horizontal scroll would need a separate controller

    // Update viewport based on scroll position
    // In full impl, trigger viewport recalculation
  }

  // ============================================================================
  // TextInputClient implementation
  // ============================================================================

  @override
  TextEditingValue get currentTextEditingValue => _textController.value;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_updating) return;

    _textController.value = value;
  }

  @override
  void performAction(TextInputAction action) {
    // Handle enter, etc.
    if (action == TextInputAction.newline) {
      final spec = _state.replaceSelection('\n');
      dispatch([
        TransactionSpec(
          changes: spec.changes,
          selection: spec.selection,
          userEvent: 'input.type.compose',
        ),
      ]);
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // Not used
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // Not used
  }

  @override
  void connectionClosed() {
    _textInputConnection = null;
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // Not used
  }

  @override
  void insertTextPlaceholder(Size size) {
    // Not used
  }

  @override
  void removeTextPlaceholder() {
    // Not used
  }

  @override
  void showToolbar() {
    // Not used
  }

  @override
  void didChangeInputControl(
      TextInputControl? oldControl, TextInputControl? newControl) {
    // Not used
  }

  @override
  void performSelector(String selectorName) {
    // Handle macOS selectors
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // Handle rich content insertion
  }

  // ============================================================================
  // DeltaTextInputClient implementation
  // ============================================================================

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    if (_updating) return;

    for (final delta in textEditingDeltas) {
      if (delta is TextEditingDeltaInsertion) {
        final pos = delta.insertionOffset;
        final text = delta.textInserted;
        
        debugPrint('[CM] Delta insertion: pos=$pos text="${text.replaceAll('\n', '\\n')}" currentCursor=${_state.selection.main.head}');
        
        // Check input handlers first
        final handlers = _state.facet(input.inputHandler);
        var handled = false;
        for (final handler in handlers) {
          if (handler(this, pos, pos, text)) {
            handled = true;
            debugPrint('[CM] Handled by inputHandler');
            break;
          }
        }
        
        if (!handled) {
          debugPrint('[CM] Dispatching insert, new cursor will be ${pos + text.length}');
          dispatch([
            TransactionSpec(
              changes: ChangeSpec(from: pos, insert: text),
              selection: EditorSelection.single(pos + text.length),
              userEvent: 'input.type',
            ),
          ]);
          debugPrint('[CM] After dispatch, cursor is ${_state.selection.main.head}');
        }
      } else if (delta is TextEditingDeltaDeletion) {
        dispatch([
          TransactionSpec(
            changes: ChangeSpec(
              from: delta.deletedRange.start,
              to: delta.deletedRange.end,
            ),
            selection: EditorSelection.single(delta.deletedRange.start),
            userEvent: 'delete',
          ),
        ]);
      } else if (delta is TextEditingDeltaReplacement) {
        dispatch([
          TransactionSpec(
            changes: ChangeSpec(
              from: delta.replacedRange.start,
              to: delta.replacedRange.end,
              insert: delta.replacementText,
            ),
            selection: EditorSelection.single(
              delta.replacedRange.start + delta.replacementText.length,
            ),
            userEvent: 'input.type',
          ),
        ]);
      }
    }
  }

  // ============================================================================
  // Build
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = widget.style ??
        TextStyle(
          fontFamily: 'JetBrainsMono',
          fontFamilyFallback: const ['monospace'],
          package: 'codemirror',
          fontSize: 14,
          height: fixedLineHeight / 14, // Line height = 20px for consistent alignment
          color: theme.textTheme.bodyMedium?.color,
        );

    final isEditable =
        !widget.readOnly && _state.facet(EditorView.editable);

    // Check if we have any gutters configured
    final gutterConfigs = _state.facet(activeGutters);
    final hasGutters = gutterConfigs.isNotEmpty;

    // Build the main editor content
    Widget editorContent = LayoutBuilder(
      builder: (context, constraints) {
        // If gutters are configured, put gutter and content in same scroll view
        if (hasGutters) {
          final lineBlocks = _getLineBlocks();
          final contentHeight = lineBlocks.isEmpty 
              ? lineHeight 
              : lineBlocks.last.bottom;
          
          return Container(
            color: widget.backgroundColor ?? theme.scaffoldBackgroundColor,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: widget.padding,
                child: Stack(
                  children: [
                    // Active line background (behind everything including gutter)
                    Positioned.fill(
                      child: ActiveLineBackground(
                        state: _state,
                        lineHeight: lineHeight,
                        lineBlocks: lineBlocks,
                      ),
                    ),
                    // Row with gutter and content
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Before gutters (not in their own scroll view)
                        _buildGutterColumn(context, gutterConfigs, GutterSide.before, lineBlocks, contentHeight),
                        // Main content
                        Expanded(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth - widget.padding.horizontal,
                            ),
                            child: _buildContent(textStyle, isEditable),
                          ),
                        ),
                        // After gutters
                        _buildGutterColumn(context, gutterConfigs, GutterSide.after, lineBlocks, contentHeight),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        // No gutters - simple scroll view
        return Container(
          color: widget.backgroundColor ?? theme.scaffoldBackgroundColor,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: widget.padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth - widget.padding.horizontal,
              ),
              child: Stack(
                children: [
                  // Active line background (behind text)
                  Positioned.fill(
                    child: ActiveLineBackground(
                      state: _state,
                      lineHeight: lineHeight,
                      lineBlocks: _getLineBlocks(),
                    ),
                  ),
                  // Text content
                  _buildContent(textStyle, isEditable),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Determine panel theme based on highlight theme
    final panelTheme = widget.highlightTheme == HighlightTheme.defaultDark ||
            widget.highlightTheme == HighlightTheme.dark
        ? PanelTheme.dark
        : PanelTheme.light;

    // Wrap with PanelThemeProvider and PanelView to support search panel and other panels
    return PanelThemeProvider(
      theme: panelTheme,
      child: PanelView(
        state: _state,
        child: editorContent,
      ),
    );
  }

  /// Build a column of gutters for a specific side.
  Widget _buildGutterColumn(
    BuildContext context,
    List<ResolvedGutterConfig> allConfigs,
    GutterSide side,
    List<BlockInfo> lineBlocks,
    double contentHeight,
  ) {
    final configs = allConfigs.where((c) => c.side == side).toList();
    if (configs.isEmpty) return const SizedBox.shrink();
    
    // No separate scroll view - gutter is inside the same scroll view as content
    return Padding(
      // Add margin between gutter and content
      padding: EdgeInsets.only(
        right: side == GutterSide.before ? 12.0 : 0.0,
        left: side == GutterSide.after ? 12.0 : 0.0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final config in configs)
            GutterView(
              config: config,
              state: _state,
              lineBlocks: lineBlocks,
              contentHeight: contentHeight,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(TextStyle style, bool editable) {
    // Build text spans from document
    final text = _state.doc.toString();

    // For editable mode, use EditableText with gesture detection for mouse selection
    if (editable) {
      // Create strutStyle to force consistent line heights
      final strutStyle = StrutStyle(
        fontFamily: style.fontFamily,
        fontFamilyFallback: style.fontFamilyFallback,
        fontSize: style.fontSize,
        height: style.height,
        forceStrutHeight: true,
      );
      
      final editableText = EditableText(
        key: _editableTextKey,
        controller: _textController,
        focusNode: _focusNode,
        style: style,
        strutStyle: strutStyle,
        cursorColor: widget.cursorColor ??
            Theme.of(context).colorScheme.primary,
        backgroundCursorColor: Colors.grey,
        selectionColor: widget.selectionColor ??
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        // Use tight selection to only highlight actual text, not full line width
        selectionWidthStyle: BoxWidthStyle.tight,
        maxLines: null,
        expands: false,
        autofocus: widget.autofocus,
        readOnly: false,
        showCursor: true,
        enableInteractiveSelection: true,
        onSelectionChanged: _onSelectionChanged,
        // Tell EditableText to ignore pointer events - gesture detector handles them
        rendererIgnoresPointer: true,
        // Note: Flutter's built-in undo is not explicitly disabled here,
        // but CodeMirror's keymap intercepts Cmd-Z/Cmd-Shift-Z before Flutter can handle them.
      );
      
      // Wrap with gesture detector for mouse drag selection support
      // Then wrap with FocusScope to intercept keyboard events
      // And MouseRegion for hover tooltips
      return FocusScope(
        autofocus: widget.autofocus,
        skipTraversal: true,
        child: MouseRegion(
          cursor: _showingLinkCursor ? SystemMouseCursors.click : MouseCursor.defer,
          onHover: _onHover,
          onExit: _onHoverExit,
          child: _selectionGestureDetectorBuilder.buildGestureDetector(
            behavior: HitTestBehavior.translucent,
            child: editableText,
          ),
        ),
      );
    }

    // Read-only mode: use same EditableText but with readOnly: true
    final strutStyle = StrutStyle(
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      fontSize: style.fontSize,
      height: style.height,
      forceStrutHeight: true,
    );

    final editableText = EditableText(
      key: _editableTextKey,
      controller: _textController,
      focusNode: _focusNode,
      style: style,
      strutStyle: strutStyle,
      cursorColor: widget.cursorColor ?? Colors.transparent,
      backgroundCursorColor: Colors.grey,
      selectionColor: widget.selectionColor ??
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      selectionWidthStyle: BoxWidthStyle.tight,
      maxLines: null,
      expands: false,
      autofocus: widget.autofocus,
      readOnly: true,
      showCursor: false,
      enableInteractiveSelection: true,
      onSelectionChanged: _onSelectionChanged,
      rendererIgnoresPointer: true,
      // Note: Flutter's built-in undo is not explicitly disabled here,
      // but CodeMirror's keymap intercepts Cmd-Z/Cmd-Shift-Z before Flutter can handle them.
    );

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: _selectionGestureDetectorBuilder.buildGestureDetector(
        behavior: HitTestBehavior.translucent,
        child: editableText,
      ),
    );
  }
}

// ============================================================================
// Selection Painter
// ============================================================================

// ignore: unused_element - may be used for custom selection rendering later
class _SelectionPainter extends CustomPainter {
  final TextSelection selection;
  final String text;
  final TextStyle style;
  final Color color;

  _SelectionPainter({
    required this.selection,
    required this.text,
    required this.style,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.isCollapsed) return;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: size.width);

    final boxes = textPainter.getBoxesForSelection(selection);
    final paint = Paint()..color = color;

    for (final box in boxes) {
      canvas.drawRect(box.toRect(), paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) {
    return selection != oldDelegate.selection ||
        text != oldDelegate.text ||
        color != oldDelegate.color;
  }
}

// ============================================================================
// Signature Help Tooltip Widget
// ============================================================================

/// Widget that displays function signature help.
class _SignatureHelpTooltip extends StatelessWidget {
  final SignatureInfo signature;
  final double maxWidth;

  const _SignatureHelpTooltip({
    required this.signature,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      color: isDark ? const Color(0xFF2D2D30) : Colors.white,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? const Color(0xFF454545) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Signature label with highlighted active parameter
            _buildSignatureLabel(context, isDark),
            // Documentation if available
            if (signature.documentation != null) ...[
              const SizedBox(height: 4),
              const Divider(height: 8),
              MarkdownBody(
                data: signature.documentation!,
                styleSheet: _buildMarkdownStyle(isDark),
                shrinkWrap: true,
              ),
            ],
            // Active parameter documentation
            if (signature.activeParameter >= 0 &&
                signature.activeParameter < signature.parameters.length &&
                signature.parameters[signature.activeParameter].documentation != null) ...[
              const SizedBox(height: 4),
              MarkdownBody(
                data: '**${signature.parameters[signature.activeParameter].label}**: ${signature.parameters[signature.activeParameter].documentation}',
                styleSheet: _buildMarkdownStyle(isDark, smaller: true),
                shrinkWrap: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureLabel(BuildContext context, bool isDark) {
    // Parse the signature label and highlight the active parameter
    final label = signature.label;
    final activeIdx = signature.activeParameter;
    
    if (activeIdx < 0 || activeIdx >= signature.parameters.length) {
      // No active parameter, show plain label
      return Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontFamilyFallback: const ['monospace'],
          fontSize: 13,
          color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
        ),
      );
    }
    
    final activeParam = signature.parameters[activeIdx];
    final paramLabel = activeParam.label;
    
    // Find the parameter in the label
    final paramIndex = label.indexOf(paramLabel);
    if (paramIndex < 0) {
      // Parameter not found in label, show plain
      return Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontFamilyFallback: const ['monospace'],
          fontSize: 13,
          color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
        ),
      );
    }
    
    // Build rich text with highlighted parameter
    final before = label.substring(0, paramIndex);
    final param = label.substring(paramIndex, paramIndex + paramLabel.length);
    final after = label.substring(paramIndex + paramLabel.length);
    
    final baseStyle = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontFamilyFallback: const ['monospace'],
      fontSize: 13,
      color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
    );
    
    final highlightStyle = baseStyle.copyWith(
      fontWeight: FontWeight.bold,
      color: isDark ? const Color(0xFF569CD6) : const Color(0xFF0066CC),
      backgroundColor: isDark 
          ? const Color(0xFF264F78).withOpacity(0.3) 
          : const Color(0xFFD6EBFF),
    );
    
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: before),
          TextSpan(text: param, style: highlightStyle),
          TextSpan(text: after),
        ],
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyle(bool isDark, {bool smaller = false}) {
    final textColor = isDark ? const Color(0xFFCCCCCC) : const Color(0xFF666666);
    final codeBackground = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8);
    final fontSize = smaller ? 11.0 : 12.0;
    
    return MarkdownStyleSheet(
      p: TextStyle(
        fontFamily: 'system-ui',
        fontSize: fontSize,
        color: textColor,
        height: 1.4,
      ),
      code: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontSize: fontSize - 1,
        color: textColor,
        backgroundColor: codeBackground,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(3),
      ),
      codeblockPadding: const EdgeInsets.all(6),
      h1: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
      h2: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
      h3: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
      blockSpacing: 6,
      listBullet: TextStyle(color: textColor),
      a: TextStyle(
        color: isDark ? const Color(0xFF569CD6) : const Color(0xFF0066CC),
        decoration: TextDecoration.underline,
      ),
    );
  }
}

// ============================================================================
// Rename Input Widget
// ============================================================================

/// Widget that displays an inline input for renaming symbols.
class _RenameInputWidget extends StatefulWidget {
  final Offset anchor;
  final double lineHeight;
  final String initialValue;
  final TextEditingController controller;
  final void Function(String newName) onSubmit;
  final VoidCallback onCancel;

  const _RenameInputWidget({
    required this.anchor,
    required this.lineHeight,
    required this.initialValue,
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  State<_RenameInputWidget> createState() => _RenameInputWidgetState();
}

class _RenameInputWidgetState extends State<_RenameInputWidget> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus and select all text
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    widget.onSubmit(widget.controller.text);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _handleSubmit();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    const inputWidth = 200.0;
    const viewPadding = 8.0;
    
    // Position at anchor
    var left = widget.anchor.dx;
    var top = widget.anchor.dy;
    
    // Ensure it stays on screen
    final screenSize = MediaQuery.of(context).size;
    if (left + inputWidth > screenSize.width - viewPadding) {
      left = screenSize.width - inputWidth - viewPadding;
    }
    if (left < viewPadding) {
      left = viewPadding;
    }

    return Positioned(
      left: left,
      top: top,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: _handleKeyEvent,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(4),
          color: isDark ? const Color(0xFF2D2D30) : Colors.white,
          child: Container(
            width: inputWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isDark ? const Color(0xFF007ACC) : const Color(0xFF0066CC),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontFamilyFallback: const ['monospace'],
                      fontSize: 13,
                      color: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1E1E1E),
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _handleSubmit,
                  borderRadius: BorderRadius.circular(2),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.check,
                      size: 16,
                      color: isDark ? const Color(0xFF89D185) : const Color(0xFF388A34),
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onCancel,
                  borderRadius: BorderRadius.circular(2),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: isDark ? const Color(0xFFF48771) : const Color(0xFFE51400),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
