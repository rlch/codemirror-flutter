/// Node sets for managing collections of node types.
///
/// This module provides [NodeSet] which holds a collection of [NodeType]s.
library;

import 'node_prop.dart';
import 'node_type.dart';

/// A node set holds a collection of node types.
///
/// It is used to compactly represent trees by storing their type ids,
/// rather than a full pointer to the type object, in a numeric array.
/// Each parser has a node set, and tree buffers can only store
/// collections of nodes from the same set.
///
/// A set can have a maximum of 2^16 (65536) node types in it, so that
/// the ids fit into 16-bit typed array slots.
class NodeSet {
  /// The node types in this set, by id.
  final List<NodeType> types;

  /// Create a set with the given types.
  ///
  /// The [id] property of each type should correspond to its position
  /// within the array.
  NodeSet(this.types) {
    for (var i = 0; i < types.length; i++) {
      if (types[i].id != i) {
        throw RangeError(
            'Node type ids should correspond to array positions '
            'when creating a node set');
      }
    }
  }

  /// Create a copy of this set with some node properties added.
  ///
  /// The arguments to this method can be created with [NodeProp.add].
  NodeSet extend(List<NodePropSource> props) {
    final newTypes = <NodeType>[];
    for (final type in types) {
      Map<int, Object?>? newProps;
      for (final source in props) {
        final add = source(type);
        if (add != null) {
          // Use dynamic to handle covariance issues with NodeProp<T>.combine
          final dynamic propDynamic = add.$1;
          final value = add.$2;
          final int propId = propDynamic.id;
          final dynamic combineFunc = propDynamic.combine;
          newProps ??= Map.of(type.props);
          final effectiveValue = combineFunc != null && newProps.containsKey(propId)
              ? combineFunc(newProps[propId], value)
              : value;
          newProps[propId] = effectiveValue;
        }
      }
      newTypes.add(newProps != null
          ? NodeType(type.name, newProps, type.id, type.flags)
          : type);
    }
    return NodeSet(newTypes);
  }
}
