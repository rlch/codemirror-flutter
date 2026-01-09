/// Facets and state fields for extensible editor state.
///
/// This module provides [Facet] for typed extension aggregation and
/// [StateField] for persistent state slots. These form the core
/// extensibility mechanism of the editor.
library;

import 'package:meta/meta.dart';

// Forward references - these will be properly imported when available
// ignore: unused_import
import 'change.dart';
import 'selection.dart';

// Import StateEffect and StateEffectType from transaction.dart
// We only need a subset of transaction.dart to avoid circular dependencies
export 'transaction.dart' show StateEffect, StateEffectType;
import 'transaction.dart' show StateEffect, StateEffectType;

// ============================================================================
// Abstract base types - implemented by state.dart
// ============================================================================

/// Abstract interface for EditorState used by facet resolution.
///
/// The concrete implementation is in state.dart.
abstract class EditorState {
  /// Get the value of a facet.
  T facet<T>(FacetReader<T> facet);

  /// Get the value of a state field.
  T? field<T>(StateField<T> field, [bool require = true]);

  /// The configuration for this state.
  Configuration get config;

  /// Internal status array for slot resolution.
  @internal
  List<int> get status;

  /// Internal values array.
  @internal
  List<dynamic> get values;

  /// Internal slot computation function.
  @internal
  int Function(EditorState, DynamicSlot)? get computeSlot;
}

/// Abstract interface for Transaction used by facet resolution.
///
/// The concrete implementation is in transaction.dart.
abstract class Transaction {
  /// Whether the document was changed.
  bool get docChanged;

  /// The new selection, if any.
  EditorSelection? get selection;

  /// The effects added to the transaction.
  List<StateEffect<dynamic>> get effects;
}

// ============================================================================
// Global ID counter for unique identification of facets, fields, and providers
// ============================================================================

int _nextId = 0;

// ============================================================================
// Slot - A type that can be used as a dependency for computed values
// ============================================================================

/// A slot that can provide values to the state.
///
/// This is a sealed type that can be a [FacetReader], [StateField],
/// or a special string marker for document or selection dependencies.
sealed class Slot<T> {
  const Slot();
}

/// Represents a dependency on the document content.
class DocSlot extends Slot<void> {
  const DocSlot._();

  /// The singleton instance.
  static const DocSlot instance = DocSlot._();
}

/// Represents a dependency on the selection.
class SelectionSlot extends Slot<void> {
  const SelectionSlot._();

  /// The singleton instance.
  static const SelectionSlot instance = SelectionSlot._();
}

/// Document dependency marker for use in [Facet.compute].
const Slot<void> docSlot = DocSlot.instance;

/// Selection dependency marker for use in [Facet.compute].
const Slot<void> selectionSlot = SelectionSlot.instance;

// ============================================================================
// Provider type enumeration
// ============================================================================

/// The type of a facet provider.
///
/// Internal enum used by [FacetProvider].
@internal
enum ProviderType {
  /// A static value.
  static_,

  /// A single computed value.
  single,

  /// Multiple computed values.
  multi,
}

// ============================================================================
// SlotStatus - Status flags for slot resolution
// ============================================================================

/// Status of a slot during resolution.
class SlotStatus {
  SlotStatus._();

  /// Slot has not been resolved yet.
  static const int unresolved = 0;

  /// Slot value has changed.
  static const int changed = 1;

  /// Slot has been computed.
  static const int computed = 2;

  /// Slot is currently being computed (for cycle detection).
  static const int computing = 4;
}

// ============================================================================
// FacetReader - Read-only view of a facet
// ============================================================================

/// A facet reader can be used to fetch the value of a facet, through
/// [EditorState.facet] or as a dependency in [Facet.compute], but not
/// to define new values for the facet.
abstract class FacetReader<Output> extends Slot<Output> {
  /// Unique identifier for this facet.
  int get id;

  /// The default value when no inputs are present.
  Output get defaultValue;
}

// ============================================================================
// Facet - Typed extension aggregation point
// ============================================================================

/// Configuration options for defining a facet.
class FacetConfig<Input, Output> {
  /// How to combine the input values into a single output value.
  ///
  /// When not given, the list of input values becomes the output.
  /// This function will immediately be called on creating the facet,
  /// with an empty list, to compute the facet's default value when no
  /// inputs are present.
  final Output Function(List<Input> values)? combine;

  /// How to compare output values to determine whether the value of
  /// the facet changed.
  ///
  /// Defaults to comparing by `==` or, if no [combine] function was given,
  /// comparing each element of the list with `==`.
  final bool Function(Output a, Output b)? compare;

  /// How to compare input values to avoid recomputing the output
  /// value when no inputs changed.
  ///
  /// Defaults to comparing with `==`.
  final bool Function(Input a, Input b)? compareInput;

  /// Forbids dynamic inputs to this facet.
  final bool isStatic;

  /// If given, these extension(s) (or the result of calling the given
  /// function with the facet) will be added to any state where this
  /// facet is provided.
  final Object? enables;

  const FacetConfig({
    this.combine,
    this.compare,
    this.compareInput,
    this.isStatic = false,
    this.enables,
  });
}

/// A facet is a labeled value that is associated with an editor state.
///
/// It takes inputs from any number of extensions, and combines those into
/// a single output value.
///
/// Examples of uses of facets are the tab size, editor attributes, and
/// update listeners.
///
/// Note that [Facet] instances can be used anywhere where [FacetReader]
/// is expected.
class Facet<Input, Output> implements FacetReader<Output> {
  @override
  final int id;

  @override
  final Output defaultValue;

  /// Extensions enabled by this facet.
  @internal
  final Extension? extensions;

  /// How to combine the input values into a single output value.
  @internal
  final Output Function(List<Input> values) combine;

  /// Untyped version of combine for dynamic dispatch.
  /// This avoids Dart's runtime type checking when called with List<dynamic>.
  @internal
  late final Function combineUntyped = (List<dynamic> values) =>
      combine(values.cast<Input>());

  /// How to compare input values.
  @internal
  final bool Function(Input a, Input b) compareInput;

  /// How to compare output values.
  @internal
  final bool Function(Output a, Output b) compare;

  /// Untyped version of compare for dynamic dispatch.
  @internal
  late final bool Function(dynamic, dynamic) compareUntyped = (a, b) =>
      compare(a as Output, b as Output);

  final bool _isStatic;

  Facet._({
    required this.id,
    required this.combine,
    required this.compareInput,
    required this.compare,
    required bool isStatic,
    required this.extensions,
  })  : _isStatic = isStatic,
        defaultValue = combine([]);

  /// Returns a facet reader for this facet, which can be used to
  /// read it but not to define values for it.
  FacetReader<Output> get reader => this;

  /// Define a new facet.
  static Facet<Input, Output> define<Input, Output>([
    FacetConfig<Input, Output>? config,
  ]) {
    config ??= FacetConfig<Input, Output>();

    final combiner = config.combine ?? ((List<Input> a) => a as Output);
    final inputComparer = config.compareInput ?? ((a, b) => a == b);
    final outputComparer = config.compare ??
        (config.combine == null
            ? ((a, b) => _sameArray(a as List, b as List))
            : ((a, b) => a == b));

    final id = _nextId++;

    // Handle enables - can be Extension or Function
    Extension? extensions;
    if (config.enables != null) {
      if (config.enables is Extension Function(Facet<Input, Output>)) {
        // We need to create the facet first, then call the function
        // This is a bit tricky - we'll create a temporary and replace
        final facet = Facet<Input, Output>._(
          id: id,
          combine: combiner,
          compareInput: inputComparer,
          compare: outputComparer,
          isStatic: config.isStatic,
          extensions: null,
        );
        extensions =
            (config.enables as Extension Function(Facet<Input, Output>))(facet);
        // Return a new facet with the extensions set
        return Facet<Input, Output>._(
          id: id,
          combine: combiner,
          compareInput: inputComparer,
          compare: outputComparer,
          isStatic: config.isStatic,
          extensions: extensions,
        );
      } else {
        extensions = config.enables as Extension;
      }
    }

    return Facet<Input, Output>._(
      id: id,
      combine: combiner,
      compareInput: inputComparer,
      compare: outputComparer,
      isStatic: config.isStatic,
      extensions: extensions,
    );
  }

  /// Returns an extension that adds the given value to this facet.
  Extension of(Input value) {
    return FacetProvider<Input>._(
      dependencies: const [],
      facet: this,
      type: ProviderType.static_,
      value: value,
    );
  }

  /// Create an extension that computes a value for the facet from a state.
  ///
  /// You must take care to declare the parts of the state that this value
  /// depends on, since your function is only called again for a new state
  /// when one of those parts changed.
  ///
  /// In cases where your value depends only on a single field, you'll want
  /// to use the [from] method instead.
  Extension compute(
    List<Slot<dynamic>> deps,
    Input Function(EditorState state) get,
  ) {
    if (_isStatic) {
      throw StateError("Can't compute a static facet");
    }
    return FacetProvider<Input>._(
      dependencies: deps,
      facet: this,
      type: ProviderType.single,
      value: get,
    );
  }

  /// Create an extension that computes zero or more values for this
  /// facet from a state.
  Extension computeN(
    List<Slot<dynamic>> deps,
    List<Input> Function(EditorState state) get,
  ) {
    if (_isStatic) {
      throw StateError("Can't compute a static facet");
    }
    return FacetProvider<Input>._(
      dependencies: deps,
      facet: this,
      type: ProviderType.multi,
      value: get,
    );
  }

  /// Shorthand method for registering a facet source with a state field
  /// as input.
  ///
  /// If the field's type corresponds to this facet's input type, the getter
  /// function can be omitted. If given, it will be used to retrieve the
  /// input from the field value.
  Extension from<T>(StateField<T> field, [Input Function(T value)? get]) {
    get ??= (x) => x as Input;
    return compute([field], (state) => get!(state.field(field) as T));
  }
}

/// Helper to compare two lists for equality.
bool _sameArray<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Helper to compare arrays element by element with a custom comparator.
bool _compareArrayWith<T>(
    List<T> a, List<T> b, bool Function(dynamic, dynamic) compare) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!compare(a[i], b[i])) return false;
  }
  return true;
}

// ============================================================================
// FacetProvider - Internal class for providing facet values
// ============================================================================

/// A provider of values for a facet.
///
/// This is an internal implementation class.
@internal
class FacetProvider<Input> implements Extension {
  /// Unique identifier.
  final int id = _nextId++;

  /// Dependencies that this provider depends on.
  final List<Slot<dynamic>> dependencies;

  /// The facet this provider contributes to.
  final Facet<Input, dynamic> facet;

  /// The type of this provider.
  final ProviderType type;

  /// The value or getter function.
  final Object? value;

  FacetProvider._({
    required this.dependencies,
    required this.facet,
    required this.type,
    required this.value,
  });

  /// Create a dynamic slot for this provider.
  @internal
  DynamicSlot dynamicSlot(Map<int, int> addresses) {
    final getter = value as Function;
    // Wrap the compareInput function to avoid runtime type cast issues
    // Dart doesn't allow casting (Input, Input) => bool to (dynamic, dynamic) => bool
    bool compare(dynamic a, dynamic b) => facet.compareInput(a, b);
    final idx = addresses[id]! >> 1;
    final multi = type == ProviderType.multi;

    var depDoc = false;
    var depSel = false;
    final depAddrs = <int>[];

    for (final dep in dependencies) {
      if (dep is DocSlot) {
        depDoc = true;
      } else if (dep is SelectionSlot) {
        depSel = true;
      } else if (dep is FacetReader) {
        final addr = addresses[dep.id];
        if (addr != null && (addr & 1) == 0) {
          depAddrs.add(addr);
        }
      } else if (dep is StateField) {
        final addr = addresses[dep.id];
        if (addr != null && (addr & 1) == 0) {
          depAddrs.add(addr);
        }
      }
    }

    return DynamicSlot(
      create: (state) {
        state.values[idx] = getter(state);
        return SlotStatus.changed;
      },
      update: (state, tr) {
        if ((depDoc && tr.docChanged) ||
            (depSel && (tr.docChanged || tr.selection != null)) ||
            _ensureAll(state, depAddrs)) {
          final newVal = getter(state);
          final bool matches;
          if (multi) {
            matches = _compareArrayWith(
                newVal as List, state.values[idx] as List, compare);
          } else {
            matches = compare(newVal as Input, state.values[idx] as Input);
          }
          if (!matches) {
            state.values[idx] = newVal;
            return SlotStatus.changed;
          }
        }
        return 0;
      },
      reconfigure: (state, oldState) {
        dynamic newVal;
        final oldAddr = oldState.config.address[id];
        if (oldAddr != null) {
          final oldVal = getAddr(oldState, oldAddr);
          var allMatch = true;
          for (final dep in dependencies) {
            if (dep is Facet) {
              if (oldState.facet(dep) != state.facet(dep)) {
                allMatch = false;
                break;
              }
            } else if (dep is StateField) {
              if (oldState.field(dep, false) != state.field(dep, false)) {
                allMatch = false;
                break;
              }
            }
          }
          if (allMatch) {
            state.values[idx] = oldVal;
            return 0;
          }
          newVal = getter(state);
          final bool matches;
          if (multi) {
            matches =
                _compareArrayWith(newVal as List, oldVal as List, compare);
          } else {
            matches = compare(newVal as Input, oldVal as Input);
          }
          if (matches) {
            state.values[idx] = oldVal;
            return 0;
          }
        } else {
          newVal = getter(state);
        }
        state.values[idx] = newVal;
        return SlotStatus.changed;
      },
    );
  }
}

// ============================================================================
// StateField - Persistent state slot
// ============================================================================

/// Configuration for defining a state field.
class StateFieldConfig<Value> {
  /// Creates the initial value for the field when a state is created.
  final Value Function(EditorState state) create;

  /// Compute a new value from the field's previous value and a transaction.
  final Value Function(Value value, Transaction transaction) update;

  /// Compare two values of the field, returning true when they are the same.
  ///
  /// This is used to avoid recomputing facets that depend on the field when
  /// its value did not change. Defaults to using `==`.
  final bool Function(Value a, Value b)? compare;

  /// Provide extensions based on this field.
  ///
  /// The given function will be called once with the initialized field.
  /// It will usually want to call some facet's [Facet.from] method to
  /// create facet inputs from this field, but can also return other
  /// extensions that should be enabled when the field is present in a
  /// configuration.
  final Extension Function(StateField<Value> field)? provide;

  /// A function used to serialize this field's content to JSON.
  ///
  /// Only necessary when this field is included in the argument to
  /// `EditorState.toJSON`.
  /// 
  /// Type is `dynamic Function(Value value, EditorState state)` but stored
  /// as Function to allow access through `StateField<dynamic>`.
  final Function? toJson;

  /// A function that deserializes the JSON representation of this
  /// field's content.
  /// 
  /// Type is `Value Function(dynamic json, EditorState state)` but stored
  /// as Function to allow access through `StateField<dynamic>`.
  final Function? fromJson;

  const StateFieldConfig({
    required this.create,
    required this.update,
    this.compare,
    this.provide,
    this.toJson,
    this.fromJson,
  });
}

/// A late-initialized facet for field initialization overrides.
late final Facet<FieldInit, List<FieldInit>> initField;

/// Internal class for field initialization info.
///
/// Used by [StateField.init] to override initial values.
@internal
class FieldInit {
  /// The field being initialized.
  final StateField<dynamic> field;

  /// The create function override.
  final dynamic Function(EditorState state) create;

  /// Create a field initialization.
  const FieldInit(this.field, this.create);
}

/// Initialize the initField facet.
///
/// This is called during module initialization.
void _initFieldFacet() {
  initField = Facet.define<FieldInit, List<FieldInit>>(
    FacetConfig(isStatic: true),
  );
}

// Module initialization
bool _initialized = false;
void _ensureInitialized() {
  if (!_initialized) {
    _initialized = true;
    _initFieldFacet();
  }
}

/// Fields can store additional information in an editor state, and keep
/// it in sync with the rest of the state.
class StateField<Value> extends Slot<Value> implements Extension {
  /// Unique identifier.
  @internal
  final int id;

  final Value Function(EditorState state) _createF;
  final Value Function(Value value, Transaction tr) _updateF;
  final bool Function(Value a, Value b) _compareF;

  /// The spec used to create this field.
  @internal
  final StateFieldConfig<Value> spec;

  /// Extensions provided by this field.
  @internal
  Extension? provides;

  StateField._({
    required this.id,
    required Value Function(EditorState state) createF,
    required Value Function(Value value, Transaction tr) updateF,
    required bool Function(Value a, Value b) compareF,
    required this.spec,
  })  : _createF = createF,
        _updateF = updateF,
        _compareF = compareF;

  /// Define a state field.
  static StateField<Value> define<Value>(StateFieldConfig<Value> config) {
    _ensureInitialized();

    final field = StateField<Value>._(
      id: _nextId++,
      createF: config.create,
      updateF: config.update,
      compareF: config.compare ?? ((a, b) => a == b),
      spec: config,
    );
    if (config.provide != null) {
      field.provides = config.provide!(field);
    }
    return field;
  }

  Value _create(EditorState state) {
    final init = state.facet(initField).where((i) => i.field == this).firstOrNull;
    if (init != null) {
      return init.create(state) as Value;
    }
    return _createF(state);
  }

  /// Create a dynamic slot for this field.
  @internal
  DynamicSlot slot(Map<int, int> addresses) {
    final idx = addresses[id]! >> 1;
    return DynamicSlot(
      create: (state) {
        state.values[idx] = _create(state);
        return SlotStatus.changed;
      },
      update: (state, tr) {
        final oldVal = state.values[idx] as Value;
        final value = _updateF(oldVal, tr);
        if (_compareF(oldVal, value)) return 0;
        state.values[idx] = value;
        return SlotStatus.changed;
      },
      reconfigure: (state, oldState) {
        final init = state.facet(initField);
        final oldInit = oldState.facet(initField);
        final reInit = init.where((i) => i.field == this).firstOrNull;
        if (reInit != null &&
            reInit != oldInit.where((i) => i.field == this).firstOrNull) {
          state.values[idx] = reInit.create(state);
          return SlotStatus.changed;
        }
        if (oldState.config.address[id] != null) {
          state.values[idx] = oldState.field(this);
          return 0;
        }
        state.values[idx] = _create(state);
        return SlotStatus.changed;
      },
    );
  }

  /// Returns an extension that enables this field and overrides the way
  /// it is initialized.
  ///
  /// Can be useful when you need to provide a non-default starting value
  /// for the field.
  Extension init(dynamic Function(EditorState state) create) {
    _ensureInitialized();
    return ExtensionList([this, initField.of(FieldInit(this, create))]);
  }

  /// State field instances can be used as [Extension] values to enable
  /// the field in a given state.
  Extension get extension => this;
}

// ============================================================================
// Extension - The base type for all extensions
// ============================================================================

/// Extension values can be provided when creating a state to attach various
/// kinds of configuration and behavior information.
///
/// They can either be built-in extension-providing objects, such as
/// [StateField] or facet providers ([Facet.of]), or objects with an
/// extension in their `extension` property. Extensions can be nested in
/// lists arbitrarily deep—they will be flattened when processed.
abstract class Extension {
  const Extension();
}

/// A list of extensions.
class ExtensionList implements Extension {
  /// The list of extensions.
  final List<Extension> extensions;

  const ExtensionList(this.extensions);
}

/// Mixin for objects that provide an extension.
mixin ExtensionProvider implements Extension {
  /// The extension provided by this object.
  Extension get extension;
}

/// Marker interface for extensions that are view-only.
///
/// These extensions are recognized by the state configuration system
/// but don't contribute any state-level functionality. They are only
/// used when a full view is available.
abstract interface class ViewOnlyExtension implements Extension {}

// ============================================================================
// Prec - Precedence levels
// ============================================================================

/// Precedence level values.
class _PrecLevel {
  _PrecLevel._();

  static const int lowest = 4;
  static const int low = 3;
  static const int defaultLevel = 2;
  static const int high = 1;
  static const int highest = 0;
}

/// By default extensions are registered in the order they are found in the
/// flattened form of nested array that was provided.
///
/// Individual extension values can be assigned a precedence to override this.
/// Extensions that do not have a precedence set get the precedence of the
/// nearest parent with a precedence, or [Prec.defaultLevel] if there is no
/// such parent.
///
/// The final ordering of extensions is determined by first sorting by
/// precedence and then by order within each precedence.
class Prec {
  Prec._();

  /// The highest precedence level, for extensions that should end up
  /// near the start of the precedence ordering.
  static Extension highest(Extension ext) =>
      PrecExtension._(ext, _PrecLevel.highest);

  /// A higher-than-default precedence, for extensions that should
  /// come before those with default precedence.
  static Extension high(Extension ext) => PrecExtension._(ext, _PrecLevel.high);

  /// The default precedence, which is also used for extensions
  /// without an explicit precedence.
  static Extension defaultLevel(Extension ext) =>
      PrecExtension._(ext, _PrecLevel.defaultLevel);

  /// A lower-than-default precedence.
  static Extension low(Extension ext) => PrecExtension._(ext, _PrecLevel.low);

  /// The lowest precedence level. Meant for things that should end up
  /// near the end of the extension order.
  static Extension lowest(Extension ext) =>
      PrecExtension._(ext, _PrecLevel.lowest);
}

/// An extension with an assigned precedence.
@internal
class PrecExtension implements Extension {
  /// The wrapped extension.
  final Extension inner;

  /// The precedence level.
  final int prec;

  const PrecExtension._(this.inner, this.prec);
}

// ============================================================================
// Compartment - Dynamic configuration
// ============================================================================

/// Extension compartments can be used to make a configuration dynamic.
///
/// By wrapping part of your configuration in a compartment, you can later
/// replace that part through a transaction.
class Compartment {
  /// Create an instance of this compartment to add to your state
  /// configuration.
  Extension of(Extension ext) => CompartmentInstance._(this, ext);

  /// Create an effect that reconfigures this compartment.
  StateEffect<CompartmentReconfigure> reconfigure(Extension content) {
    if (_reconfigure == null) {
      throw StateError('Compartment.reconfigure called before initialization. '
          'Call ensureStateInitialized() first.');
    }
    return _reconfigure!.of(CompartmentReconfigure(this, content));
  }

  /// Get the current content of the compartment in the state, or
  /// null if it isn't present.
  Extension? get(EditorState state) {
    return state.config.compartments[this];
  }

  /// This is initialized in state.dart to avoid a cyclic dependency.
  static StateEffectType<CompartmentReconfigure>? _reconfigure;

  /// Get the reconfigure effect type.
  ///
  /// Returns null if not yet initialized.
  static StateEffectType<CompartmentReconfigure>? get reconfigureEffect => _reconfigure;

  /// Initialize the reconfigure effect type.
  ///
  /// This is called from state.dart to set up the circular dependency.
  static void initReconfigure(StateEffectType<CompartmentReconfigure> effect) {
    _reconfigure = effect;
  }
}

/// Internal class for compartment reconfiguration.
///
/// Used by [Compartment.reconfigure] to create reconfiguration effects.
@internal
class CompartmentReconfigure {
  /// The compartment to reconfigure.
  final Compartment compartment;

  /// The new extension for the compartment.
  final Extension extension;

  /// Create a compartment reconfiguration.
  const CompartmentReconfigure(this.compartment, this.extension);
}

/// An instance of a compartment with its content.
@internal
class CompartmentInstance implements Extension {
  /// The compartment.
  final Compartment compartment;

  /// The content of the compartment.
  final Extension inner;

  const CompartmentInstance._(this.compartment, this.inner);
}

// ============================================================================
// DynamicSlot - Interface for slots that need dynamic resolution
// ============================================================================

/// A dynamic slot that can create, update, and reconfigure values.
@internal
class DynamicSlot {
  /// Create the initial value.
  final int Function(EditorState state) create;

  /// Update the value for a transaction.
  final int Function(EditorState state, Transaction tr) update;

  /// Reconfigure the value when the configuration changes.
  final int Function(EditorState state, EditorState oldState) reconfigure;

  const DynamicSlot({
    required this.create,
    required this.update,
    required this.reconfigure,
  });
}

// ============================================================================
// Configuration - Resolved extension state
// ============================================================================

/// Holds the resolved configuration for an editor state.
@internal
class Configuration {
  /// The base extension.
  final Extension base;

  /// Map of compartments to their current content.
  final Map<Compartment, Extension> compartments;

  /// The dynamic slots.
  final List<DynamicSlot> dynamicSlots;

  /// Map of slot IDs to their addresses.
  final Map<int, int> address;

  /// Static values (for static facets).
  final List<dynamic> staticValues;

  /// Facet providers by facet ID.
  final Map<int, List<FacetProvider<dynamic>>> facets;

  /// Template for slot status array.
  final List<int> statusTemplate;

  Configuration._({
    required this.base,
    required this.compartments,
    required this.dynamicSlots,
    required this.address,
    required this.staticValues,
    required this.facets,
  }) : statusTemplate = List.filled(dynamicSlots.length, SlotStatus.unresolved);

  /// Get the static value of a facet.
  Output staticFacet<Output>(Facet<dynamic, Output> facet) {
    final addr = address[facet.id];
    if (addr == null) return facet.defaultValue;
    return staticValues[addr >> 1] as Output;
  }

  /// Resolve a configuration from a base extension.
  static Configuration resolve(
    Extension base,
    Map<Compartment, Extension> compartments, [
    EditorState? oldState,
  ]) {
    _ensureInitialized();

    final fields = <StateField<dynamic>>[];
    final facets = <int, List<FacetProvider<dynamic>>>{};
    final newCompartments = <Compartment, Extension>{};

    for (final ext in _flatten(base, compartments, newCompartments)) {
      if (ext is StateField) {
        fields.add(ext);
      } else if (ext is FacetProvider) {
        (facets[ext.facet.id] ??= []).add(ext);
      }
    }

    final address = <int, int>{};
    final staticValues = <dynamic>[];
    final dynamicSlotBuilders =
        <DynamicSlot Function(Map<int, int> address)>[];

    for (final field in fields) {
      address[field.id] = dynamicSlotBuilders.length << 1;
      dynamicSlotBuilders.add((a) => field.slot(a));
    }

    final oldFacets = oldState?.config.facets;
    for (final entry in facets.entries) {
      final id = entry.key;
      final providers = entry.value;
      final facet = providers[0].facet;
      final oldProviders = oldFacets?[id] ?? [];

      if (providers.every((p) => p.type == ProviderType.static_)) {
        address[facet.id] = (staticValues.length << 1) | 1;
        if (_sameArray(oldProviders, providers)) {
          staticValues.add(oldState!.facet(facet));
        } else {
          // Use combineUntyped to avoid type issues with List<dynamic>
          final value = facet.combineUntyped(
              providers.map((p) => p.value).toList());
          if (oldState != null && facet.compareUntyped(value, oldState.facet(facet))) {
            staticValues.add(oldState.facet(facet));
          } else {
            staticValues.add(value);
          }
        }
      } else {
        for (final p in providers) {
          if (p.type == ProviderType.static_) {
            address[p.id] = (staticValues.length << 1) | 1;
            staticValues.add(p.value);
          } else {
            address[p.id] = dynamicSlotBuilders.length << 1;
            dynamicSlotBuilders.add((a) => p.dynamicSlot(a));
          }
        }
        address[facet.id] = dynamicSlotBuilders.length << 1;
        dynamicSlotBuilders
            .add((a) => _dynamicFacetSlot(a, facet, providers));
      }
    }

    final dynamic_ = dynamicSlotBuilders.map((f) => f(address)).toList();

    return Configuration._(
      base: base,
      compartments: newCompartments,
      dynamicSlots: dynamic_,
      address: address,
      staticValues: staticValues,
      facets: facets,
    );
  }
}

/// Flatten an extension tree into a sorted list.
List<Object> _flatten(
  Extension extension,
  Map<Compartment, Extension> compartments,
  Map<Compartment, Extension> newCompartments,
) {
  final result = <List<Object>>[[], [], [], [], []];
  final seen = <Object, int>{};

  void inner(Extension ext, int prec) {
    final known = seen[ext];
    if (known != null) {
      if (known <= prec) return;
      final found = result[known].indexOf(ext);
      if (found > -1) result[known].removeAt(found);
      if (ext is CompartmentInstance) {
        newCompartments.remove(ext.compartment);
      }
    }
    seen[ext] = prec;

    if (ext is ExtensionList) {
      for (final e in ext.extensions) {
        inner(e, prec);
      }
    } else if (ext is CompartmentInstance) {
      if (newCompartments.containsKey(ext.compartment)) {
        throw RangeError('Duplicate use of compartment in extensions');
      }
      final content = compartments[ext.compartment] ?? ext.inner;
      newCompartments[ext.compartment] = content;
      inner(content, prec);
    } else if (ext is PrecExtension) {
      inner(ext.inner, ext.prec);
    } else if (ext is StateField) {
      result[prec].add(ext);
      if (ext.provides != null) inner(ext.provides!, prec);
    } else if (ext is FacetProvider) {
      result[prec].add(ext);
      if (ext.facet.extensions != null) {
        inner(ext.facet.extensions!, _PrecLevel.defaultLevel);
      }
    } else if (ext is ExtensionProvider) {
      inner(ext.extension, prec);
    } else if (ext is ViewOnlyExtension) {
      // View-only extensions are stored but don't contribute providers
      // They will be handled by the view system
      result[prec].add(ext);
    } else {
      throw StateError(
        'Unrecognized extension value in extension set ($ext). '
        'This sometimes happens because multiple instances of the state '
        'package are loaded, breaking instanceof checks.',
      );
    }
  }

  inner(extension, _PrecLevel.defaultLevel);
  return result.expand((x) => x).toList();
}

/// Create a dynamic slot for a facet with multiple providers.
DynamicSlot _dynamicFacetSlot<Input, Output>(
  Map<int, int> addresses,
  Facet<Input, Output> facet,
  List<FacetProvider<Input>> providers,
) {
  final providerAddrs = providers.map((p) => addresses[p.id]!).toList();
  final providerTypes = providers.map((p) => p.type).toList();
  final dynamic_ = providerAddrs.where((p) => (p & 1) == 0).toList();
  final idx = addresses[facet.id]! >> 1;

  Output get(EditorState state) {
    final values = <dynamic>[];
    for (var i = 0; i < providerAddrs.length; i++) {
      final value = getAddr(state, providerAddrs[i]);
      if (providerTypes[i] == ProviderType.multi) {
        for (final val in value as List) {
          values.add(val);
        }
      } else {
        values.add(value);
      }
    }
    // Use combineUntyped to avoid type issues with List<dynamic>
    return facet.combineUntyped(values) as Output;
  }

  return DynamicSlot(
    create: (state) {
      for (final addr in providerAddrs) {
        ensureAddr(state, addr);
      }
      state.values[idx] = get(state);
      return SlotStatus.changed;
    },
    update: (state, tr) {
      if (!_ensureAll(state, dynamic_)) return 0;
      final value = get(state);
      if (facet.compareUntyped(value, state.values[idx])) return 0;
      state.values[idx] = value;
      return SlotStatus.changed;
    },
    reconfigure: (state, oldState) {
      final depChanged = _ensureAll(state, providerAddrs);
      final oldProviders = oldState.config.facets[facet.id];
      final oldValue = oldState.facet(facet);
      if (oldProviders != null &&
          !depChanged &&
          _sameArray(providers, oldProviders)) {
        state.values[idx] = oldValue;
        return 0;
      }
      final value = get(state);
      if (facet.compareUntyped(value, oldValue)) {
        state.values[idx] = oldValue;
        return 0;
      }
      state.values[idx] = value;
      return SlotStatus.changed;
    },
  );
}

/// Ensure all addresses are resolved, returning true if any changed.
bool _ensureAll(EditorState state, List<int> addrs) {
  var changed = false;
  for (final addr in addrs) {
    if ((ensureAddr(state, addr) & SlotStatus.changed) != 0) {
      changed = true;
    }
  }
  return changed;
}

/// Ensure a slot is resolved.
@internal
int ensureAddr(EditorState state, int addr) {
  if ((addr & 1) != 0) return SlotStatus.computed;
  final idx = addr >> 1;
  final status = state.status[idx];
  if (status == SlotStatus.computing) {
    throw StateError('Cyclic dependency between fields and/or facets');
  }
  if ((status & SlotStatus.computed) != 0) return status;
  state.status[idx] = SlotStatus.computing;
  final changed = state.computeSlot!(state, state.config.dynamicSlots[idx]);
  state.status[idx] = SlotStatus.computed | changed;
  return state.status[idx];
}

/// Get a value from an address.
@internal
dynamic getAddr(EditorState state, int addr) {
  if ((addr & 1) != 0) {
    return state.config.staticValues[addr >> 1];
  }
  return state.values[addr >> 1];
}
