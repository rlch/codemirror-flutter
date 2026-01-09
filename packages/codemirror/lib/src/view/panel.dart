/// Panel system for displaying content above/below the editor.
///
/// This module provides infrastructure for showing panels (like search bars,
/// status lines, or other UI) at the top or bottom of the editor.
library;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/state.dart';
import 'view_update.dart';

// ============================================================================
// Panel Configuration
// ============================================================================

/// Configuration for the panel system.
class PanelConfig {
  /// By default, panels will be placed inside the editor's widget tree.
  /// You can use this option to specify an external container widget key
  /// for panels with `top: true`.
  final GlobalKey? topContainerKey;

  /// External container key for panels with `top: false`.
  final GlobalKey? bottomContainerKey;

  const PanelConfig({
    this.topContainerKey,
    this.bottomContainerKey,
  });
}

/// Facet for panel configuration.
final Facet<PanelConfig, PanelConfig> _panelConfig = Facet.define(
  FacetConfig(
    combine: (configs) {
      GlobalKey? topContainer;
      GlobalKey? bottomContainer;
      for (final c in configs) {
        topContainer ??= c.topContainerKey;
        bottomContainer ??= c.bottomContainerKey;
      }
      return PanelConfig(
        topContainerKey: topContainer,
        bottomContainerKey: bottomContainer,
      );
    },
  ),
);

/// Configures the panel-managing extension.
Extension panels([PanelConfig? config]) {
  return config != null ? _panelConfig.of(config) : const _PanelsMarker();
}

/// Marker extension indicating panels are enabled.
class _PanelsMarker implements Extension {
  const _PanelsMarker();
}

// ============================================================================
// Panel Interface
// ============================================================================

/// Object that describes an active panel.
///
/// In Flutter, panels are represented as widgets, but this class provides
/// the interface for panel lifecycle management.
abstract class Panel {
  /// Build the widget for this panel.
  Widget build(BuildContext context);

  /// Called after the panel has been added to the editor.
  void mount() {}

  /// Update the panel for a given view update.
  void update(ViewUpdate update) {}

  /// Called when the panel is removed from the editor or the editor
  /// is destroyed.
  void destroy() {}

  /// Whether the panel should be at the top or bottom of the editor.
  ///
  /// Defaults to false (bottom).
  bool get top => false;
}

/// A simple panel implementation using a builder function.
class SimplePanel extends Panel {
  final Widget Function(BuildContext context) _builder;
  final bool _top;
  final void Function()? _onMount;
  final void Function(ViewUpdate update)? _onUpdate;
  final void Function()? _onDestroy;

  SimplePanel({
    required Widget Function(BuildContext context) builder,
    bool top = false,
    void Function()? onMount,
    void Function(ViewUpdate update)? onUpdate,
    void Function()? onDestroy,
  })  : _builder = builder,
        _top = top,
        _onMount = onMount,
        _onUpdate = onUpdate,
        _onDestroy = onDestroy;

  @override
  Widget build(BuildContext context) => _builder(context);

  @override
  bool get top => _top;

  @override
  void mount() => _onMount?.call();

  @override
  void update(ViewUpdate update) => _onUpdate?.call(update);

  @override
  void destroy() => _onDestroy?.call();
}

// ============================================================================
// Panel Facet
// ============================================================================

/// A function that creates a panel.
///
/// Used in [showPanel] to lazily create panels.
/// Note: Takes EditorState for compatibility, but panels that need view access
/// should use context.findAncestorStateOfType<EditorViewState>() in build().
typedef PanelConstructor = Panel Function(EditorState state);

/// Opening a panel is done by providing a constructor function for the panel
/// through this facet. (The panel is closed again when its constructor is
/// no longer provided.) Values of `null` are ignored.
final Facet<PanelConstructor?, List<PanelConstructor?>> showPanel =
    Facet.define();

/// Get the active panel created by the given constructor, if any.
///
/// This can be useful when you need access to your panels' state.
Panel? getPanel(EditorState state, PanelConstructor constructor) {
  // Note: In the full implementation, this would look up the panel
  // in the view plugin state. For now, return null.
  return null;
}

// ============================================================================
// Panel Container Widget
// ============================================================================

/// Widget that manages and displays panels.
class PanelContainer extends StatefulWidget {
  /// The editor state.
  final EditorState state;

  /// The child widget (editor content).
  final Widget child;

  /// Whether this container is for top panels.
  final bool top;

  /// Optional theme classes for styling.
  final String? themeClasses;

  const PanelContainer({
    super.key,
    required this.state,
    required this.child,
    required this.top,
    this.themeClasses,
  });

  @override
  State<PanelContainer> createState() => _PanelContainerState();
}

class _PanelContainerState extends State<PanelContainer> {
  late List<PanelConstructor> _specs;
  late List<Panel> _panels;

  @override
  void initState() {
    super.initState();
    _initializePanels();
  }

  void _initializePanels() {
    final input = widget.state.facet(showPanel);
    _specs = input.whereType<PanelConstructor>().toList();
    _panels = _specs.map((spec) => spec(widget.state)).toList();

    // Filter by position
    _panels =
        _panels.where((p) => p.top == widget.top).toList();

    // Mount panels
    for (final panel in _panels) {
      panel.mount();
    }
  }

  @override
  void didUpdateWidget(PanelContainer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final input = widget.state.facet(showPanel);
    final newSpecs = input.whereType<PanelConstructor>().toList();

    if (!_specsEqual(newSpecs, _specs)) {
      // Destroy old panels
      for (final panel in _panels) {
        panel.destroy();
      }

      // Create new panels
      _specs = newSpecs;
      _panels = _specs.map((spec) => spec(widget.state)).toList();
      _panels = _panels.where((p) => p.top == widget.top).toList();

      // Mount new panels
      for (final panel in _panels) {
        panel.mount();
      }
    }
  }

  bool _specsEqual(List<PanelConstructor> a, List<PanelConstructor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    for (final panel in _panels) {
      panel.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_panels.isEmpty) {
      return widget.child;
    }

    final panelWidgets = _panels
        .map((p) => Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: widget.top
                      ? const BorderSide(color: Color(0xFFDDDDDD))
                      : BorderSide.none,
                  top: !widget.top
                      ? const BorderSide(color: Color(0xFFDDDDDD))
                      : BorderSide.none,
                ),
              ),
              child: p.build(context),
            ))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.top
          ? [...panelWidgets, Expanded(child: widget.child)]
          : [Expanded(child: widget.child), ...panelWidgets],
    );
  }
}

// ============================================================================
// PanelView - Combined panel management
// ============================================================================

/// Widget that wraps editor content with top and bottom panel containers.
class PanelView extends StatefulWidget {
  /// The editor state.
  final EditorState state;

  /// The editor content widget.
  final Widget child;

  const PanelView({
    super.key,
    required this.state,
    required this.child,
  });

  @override
  State<PanelView> createState() => _PanelViewState();
}

class _PanelViewState extends State<PanelView> {
  List<PanelConstructor> _specs = [];
  List<Panel> _panels = [];
  
  @override
  void initState() {
    super.initState();
    _updatePanels();
  }
  
  @override
  void didUpdateWidget(PanelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Check if panel specs have changed
    final newSpecs = widget.state.facet(showPanel).whereType<PanelConstructor>().toList();
    if (!_specsEqual(newSpecs, _specs)) {
      // Destroy old panels
      for (final panel in _panels) {
        panel.destroy();
      }
      _updatePanels();
    }
  }
  
  void _updatePanels() {
    final input = widget.state.facet(showPanel);
    _specs = input.whereType<PanelConstructor>().toList();
    _panels = _specs.map((spec) => spec(widget.state)).toList();
    
    // Mount panels
    for (final panel in _panels) {
      panel.mount();
    }
  }
  
  bool _specsEqual(List<PanelConstructor> a, List<PanelConstructor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  
  @override
  void dispose() {
    for (final panel in _panels) {
      panel.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.state.facet(_panelConfig);

    if (_panels.isEmpty) {
      return widget.child;
    }

    // Separate by position
    final topPanels = _panels.where((p) => p.top).toList();
    final bottomPanels = _panels.where((p) => !p.top).toList();

    // Build the layout
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top panels
        if (topPanels.isNotEmpty)
          _PanelGroup(
            panels: topPanels,
            top: true,
            containerKey: config.topContainerKey,
          ),

        // Editor content
        Expanded(child: widget.child),

        // Bottom panels
        if (bottomPanels.isNotEmpty)
          _PanelGroup(
            panels: bottomPanels,
            top: false,
            containerKey: config.bottomContainerKey,
          ),
      ],
    );
  }
}

/// Theme configuration for panels.
class PanelTheme {
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color inputBackgroundColor;
  final Color inputBorderColor;
  final Color buttonBackgroundColor;
  final Color buttonTextColor;
  final Color toggleActiveColor;
  final Color toggleInactiveColor;

  const PanelTheme({
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.inputBackgroundColor,
    required this.inputBorderColor,
    required this.buttonBackgroundColor,
    required this.buttonTextColor,
    required this.toggleActiveColor,
    required this.toggleInactiveColor,
  });

  /// Light theme panel colors (GitHub Light style).
  static const light = PanelTheme(
    backgroundColor: Color(0xFFF6F8FA),
    borderColor: Color(0xFFD0D7DE),
    textColor: Color(0xFF24292F),
    inputBackgroundColor: Color(0xFFFFFFFF),
    inputBorderColor: Color(0xFFD0D7DE),
    buttonBackgroundColor: Color(0xFFF6F8FA),
    buttonTextColor: Color(0xFF24292F),
    toggleActiveColor: Color(0xFF0969DA),
    toggleInactiveColor: Color(0xFF57606A),
  );

  /// Dark theme panel colors (GitHub Dark style).
  static const dark = PanelTheme(
    backgroundColor: Color(0xFF161B22),
    borderColor: Color(0xFF30363D),
    textColor: Color(0xFFC9D1D9),
    inputBackgroundColor: Color(0xFF0D1117),
    inputBorderColor: Color(0xFF30363D),
    buttonBackgroundColor: Color(0xFF21262D),
    buttonTextColor: Color(0xFFC9D1D9),
    toggleActiveColor: Color(0xFF58A6FF),
    toggleInactiveColor: Color(0xFF8B949E),
  );
}

/// InheritedWidget to provide panel theme down the tree.
class PanelThemeProvider extends InheritedWidget {
  final PanelTheme theme;

  const PanelThemeProvider({
    super.key,
    required this.theme,
    required super.child,
  });

  static PanelTheme of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<PanelThemeProvider>();
    return provider?.theme ?? PanelTheme.light;
  }

  @override
  bool updateShouldNotify(PanelThemeProvider oldWidget) => theme != oldWidget.theme;
}

/// A group of panels at the top or bottom.
class _PanelGroup extends StatefulWidget {
  final List<Panel> panels;
  final bool top;
  final GlobalKey? containerKey;

  const _PanelGroup({
    required this.panels,
    required this.top,
    this.containerKey,
  });

  @override
  State<_PanelGroup> createState() => _PanelGroupState();
}

class _PanelGroupState extends State<_PanelGroup> {
  @override
  void initState() {
    super.initState();
    for (final panel in widget.panels) {
      panel.mount();
    }
  }

  @override
  void dispose() {
    for (final panel in widget.panels) {
      panel.destroy();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = PanelThemeProvider.of(context);
    return Container(
      key: widget.containerKey,
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        border: Border(
          bottom: widget.top
              ? BorderSide(color: theme.borderColor)
              : BorderSide.none,
          top: !widget.top
              ? BorderSide(color: theme.borderColor)
              : BorderSide.none,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.panels.map((p) => p.build(context)).toList(),
      ),
    );
  }
}

// ============================================================================
// Scroll Margins
// ============================================================================

/// Internal: Calculate scroll margins for panels.
@internal
({double top, double bottom}) panelScrollMargins(EditorState state) {
  // In full implementation, this would measure actual panel heights
  return (top: 0, bottom: 0);
}
