/// View plugin - extension mechanism for the editor view.
///
/// This module provides [ViewPlugin], which allows extensions to hook into
/// the view lifecycle and respond to updates.
library;

import 'package:meta/meta.dart';

import '../state/facet.dart' hide EditorState, Transaction;
import '../state/range_set.dart';
import '../state/state.dart';
import 'decoration.dart';
import 'editor_view.dart';
import 'view_update.dart';

// ============================================================================
// PluginValue - Base class for plugin values
// ============================================================================

/// Base class for view plugin values.
///
/// View plugins can optionally implement these methods to respond to
/// various view events.
abstract class PluginValue {
  /// Called when the view is updated.
  void update(ViewUpdate update) {}

  /// Called when the document view has been updated.
  void docViewUpdate(EditorViewState view) {}

  /// Called when the plugin is destroyed.
  void destroy(EditorViewState view) {}
}

// ============================================================================
// ViewPlugin - Plugin specification
// ============================================================================

/// A view plugin specification.
///
/// View plugins allow extensions to maintain state and respond to view
/// updates. They are created when the view is initialized and destroyed
/// when the view is disposed.
///
/// ## Example
///
/// ```dart
/// final lineHighlighter = ViewPlugin.define(
///   (view) => LineHighlighter(),
///   eventHandlers: {
///     'click': (event, view) {
///       // Handle click
///       return false;
///     },
///   },
/// );
/// ```
class ViewPlugin<V extends PluginValue> implements ViewOnlyExtension {
  /// The unique ID for this plugin.
  final int id = _nextId++;

  /// Factory function to create the plugin value.
  final V Function(EditorViewState view) create;

  /// Specification for the plugin.
  final ViewPluginSpec<V>? spec;
  
  /// Base extensions provided by this plugin (decorations, etc.).
  final List<Extension> _baseExtensions = [];

  static int _nextId = 0;

  ViewPlugin._(this.create, this.spec);

  /// Define a new view plugin.
  ///
  /// If the spec includes a `decorations` accessor, the plugin's decorations
  /// will be automatically contributed to the view's decoration set.
  static ViewPlugin<V> define<V extends PluginValue>(
    V Function(EditorViewState view) create, [
    ViewPluginSpec<V>? spec,
  ]) {
    // Create the plugin first
    final plugin = ViewPlugin<V>._(create, spec);
    
    // Now build extensions that reference the plugin
    if (spec?.decorations != null) {
      final decoFn = spec!.decorations!;
      plugin._baseExtensions.add(decorationsFacet.of((EditorViewState view) {
        final pluginValue = view.plugin(plugin);
        if (pluginValue == null) return Decoration.none;
        return decoFn(pluginValue);
      }));
    }
    
    return plugin;
  }
  
  /// Get the extension to install this plugin and its facet contributions.
  Extension get extension => ExtensionList([
    viewPlugin.of(this as ViewPlugin<PluginValue>),
    ..._baseExtensions,
  ]);

  /// Define a simple view plugin from a plain class.
  static ViewPlugin<SimplePluginValue> fromClass<T>(
    T Function(EditorViewState view) create, {
    void Function(T value, ViewUpdate update)? update,
    void Function(T value, EditorViewState view)? destroy,
    Map<String, bool Function(dynamic event, EditorViewState view)>? eventHandlers,
  }) {
    return ViewPlugin._(
      (view) {
        final value = create(view);
        return SimplePluginValue<T>(
          value,
          updateFn: update,
          destroyFn: destroy,
        );
      },
      eventHandlers != null ? ViewPluginSpec(eventHandlers: eventHandlers) : null,
    );
  }
}

// ============================================================================
// ViewPluginSpec - Plugin configuration
// ============================================================================

/// Configuration options for a view plugin.
class ViewPluginSpec<V> {
  /// Event handlers for this plugin.
  ///
  /// Keys are event names, values are handler functions that return
  /// true if the event was handled.
  final Map<String, bool Function(dynamic event, EditorViewState view)>? eventHandlers;

  /// Event observers for this plugin.
  ///
  /// Like handlers but cannot prevent further handling.
  final Map<String, void Function(dynamic event, EditorViewState view)>? eventObservers;

  /// A function to extract decorations from the plugin value.
  ///
  /// If provided, the plugin's decorations will be contributed to the
  /// view's decoration set.
  final RangeSet<Decoration> Function(V)? decorations;

  const ViewPluginSpec({
    this.eventHandlers,
    this.eventObservers,
    this.decorations,
  });
}

// ============================================================================
// SimplePluginValue - Wrapper for simple plugin values
// ============================================================================

/// A simple plugin value wrapper.
class SimplePluginValue<T> extends PluginValue {
  /// The wrapped value.
  final T value;

  /// Optional update function.
  final void Function(T value, ViewUpdate update)? updateFn;

  /// Optional destroy function.
  final void Function(T value, EditorViewState view)? destroyFn;

  SimplePluginValue(
    this.value, {
    this.updateFn,
    this.destroyFn,
  });

  @override
  void update(ViewUpdate update) {
    updateFn?.call(value, update);
  }

  @override
  void destroy(EditorViewState view) {
    destroyFn?.call(value, view);
  }
}

// ============================================================================
// PluginInstance - Runtime instance of a plugin
// ============================================================================

/// A runtime instance of a view plugin.
@internal
class PluginInstance {
  /// The plugin specification.
  final ViewPlugin<PluginValue> spec;

  /// The plugin value (created lazily).
  PluginValue? _value;

  /// Whether the plugin is being updated.
  ViewUpdate? mustUpdate;

  PluginInstance(this.spec);

  /// Get the plugin value, creating it if necessary.
  PluginValue? get value => _value;

  /// Update the plugin.
  void update(EditorViewState view) {
    if (_value == null) {
      // Create the plugin
      try {
        _value = spec.create(view);
      } catch (e) {
        _logException(view.state, e, 'plugin create');
      }
    } else if (mustUpdate != null) {
      // Update the plugin
      try {
        _value!.update(mustUpdate!);
      } catch (e) {
        _logException(view.state, e, 'plugin update');
      }
    }
    mustUpdate = null;
  }

  /// Destroy the plugin.
  void destroy(EditorViewState view) {
    if (_value != null) {
      try {
        _value!.destroy(view);
      } catch (e) {
        _logException(view.state, e, 'plugin destroy');
      }
    }
    _value = null;
  }
}

// ============================================================================
// Facets for view plugins
// ============================================================================

/// Facet for registering view plugins.
final viewPlugin = Facet.define<ViewPlugin<PluginValue>, List<ViewPlugin<PluginValue>>>();

// ============================================================================
// Decorations Facet
// ============================================================================

/// A decoration set or a function that returns one.
typedef DecorationSource = Object; // RangeSet<Decoration> | RangeSet<Decoration> Function(EditorViewState)

/// Facet for providing decorations to the editor view.
///
/// Extensions can use this to add syntax highlighting, search highlights,
/// error underlines, and other visual markers.
///
/// Values can be either:
/// - A [RangeSet<Decoration>] for static decorations
/// - A function `RangeSet<Decoration> Function(EditorViewState)` for dynamic decorations
final Facet<DecorationSource, List<DecorationSource>> decorationsFacet = Facet.define();

/// Facet for outer decorations (higher precedence, for things like lint markers).
final Facet<DecorationSource, List<DecorationSource>> outerDecorationsFacet = Facet.define();

// ============================================================================
// Exception logging
// ============================================================================

/// Facet for exception handlers.
final exceptionSink = Facet.define<void Function(Object error), List<void Function(Object error)>>();

/// Log an exception from the view.
void _logException(EditorState state, Object error, String context) {
  final sinks = state.facet(exceptionSink);
  if (sinks.isEmpty) {
    // ignore: avoid_print
    print('CodeMirror error ($context): $error');
  } else {
    for (final sink in sinks) {
      sink(error);
    }
  }
}

/// Log an exception (public API).
void logException(EditorState state, Object error, [String? context]) {
  _logException(state, error, context ?? 'extension');
}
