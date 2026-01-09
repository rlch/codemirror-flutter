/// Syntax highlighting definitions for CEL (Common Expression Language).
///
/// This module provides the highlight prop source for CEL syntax.
library;

import 'package:lezer/lezer.dart';

/// CEL highlighting style tags.
///
/// Maps node names to highlighting tags.
final NodePropSource celHighlight = styleTags({
  // Literals
  'Number': Tags.number,
  'String': Tags.string,
  'Bytes': Tags.string,
  'BooleanLiteral': Tags.bool_,
  'NullLiteral': Tags.null_,

  // Identifiers
  'Identifier': Tags.variableName,
  'PropertyName': Tags.propertyName,

  // Operators
  'LogicalOr LogicalAnd': Tags.logicOperator,
  'Equals NotEquals LessThan LessThanEq GreaterThan GreaterThanEq':
      Tags.compareOperator,
  'Plus Minus Star Slash Percent': Tags.arithmeticOperator,
  'Not': Tags.logicOperator,
  'in': Tags.operatorKeyword,

  // Keywords
  'true false': Tags.bool_,
  'null': Tags.null_,

  // Punctuation
  '( )': Tags.paren,
  '[ ]': Tags.squareBracket,
  '{ }': Tags.brace,
  '. , : ?': Tags.punctuation,

  // Conditional (ternary)
  'ConditionalExpr/? ConditionalExpr/:': Tags.controlKeyword,

  // Comments
  'LineComment': Tags.lineComment,

  // Function calls
  'GlobalCallExpr/Identifier': Tags.function(Tags.variableName),
  'CallExpr/PropertyName': Tags.function(Tags.propertyName),
});
