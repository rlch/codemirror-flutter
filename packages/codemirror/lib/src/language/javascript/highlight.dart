/// Syntax highlighting definitions for JavaScript.
///
/// This module provides the highlight prop source for JavaScript syntax.
library;

import 'package:lezer/lezer.dart';

/// JavaScript highlighting style tags.
///
/// Maps node names to highlighting tags.
final NodePropSource jsHighlight = styleTags({
  'get set async static': Tags.modifier,
  'for while do if else switch try catch finally return throw break continue default case defer':
      Tags.controlKeyword,
  'in of await yield void typeof delete instanceof as satisfies':
      Tags.operatorKeyword,
  'let var const using function class extends': Tags.definitionKeyword,
  'import export from': Tags.moduleKeyword,
  'with debugger new': Tags.keyword,
  'TemplateString': Tags.special(Tags.string),
  'super': Tags.atom,
  'BooleanLiteral': Tags.bool_,
  'this': Tags.self,
  'null': Tags.null_,
  'Star': Tags.modifier,
  'VariableName': Tags.variableName,
  'CallExpression/VariableName TaggedTemplateExpression/VariableName':
      Tags.function(Tags.variableName),
  'VariableDefinition': Tags.definition(Tags.variableName),
  'Label': Tags.labelName,
  'PropertyName': Tags.propertyName,
  'PrivatePropertyName': Tags.special(Tags.propertyName),
  'CallExpression/MemberExpression/PropertyName':
      Tags.function(Tags.propertyName),
  'FunctionDeclaration/VariableDefinition':
      Tags.function(Tags.definition(Tags.variableName)),
  'ClassDeclaration/VariableDefinition': Tags.definition(Tags.className),
  'NewExpression/VariableName': Tags.className,
  'PropertyDefinition': Tags.definition(Tags.propertyName),
  'PrivatePropertyDefinition': Tags.definition(Tags.special(Tags.propertyName)),
  'UpdateOp': Tags.updateOperator,
  'LineComment Hashbang': Tags.lineComment,
  'BlockComment': Tags.blockComment,
  'Number': Tags.number,
  'String': Tags.string,
  'Escape': Tags.escape,
  'ArithOp': Tags.arithmeticOperator,
  'LogicOp': Tags.logicOperator,
  'BitOp': Tags.bitwiseOperator,
  'CompareOp': Tags.compareOperator,
  'RegExp': Tags.regexp,
  'Equals': Tags.definitionOperator,
  'Arrow': Tags.function(Tags.punctuation),
  ': Spread': Tags.punctuation,
  '( )': Tags.paren,
  '[ ]': Tags.squareBracket,
  '{ }': Tags.brace,
  'InterpolationStart InterpolationEnd': Tags.special(Tags.brace),
  '.': Tags.derefOperator,
  ', ;': Tags.separator,
  '@': Tags.meta,
  // TypeScript-specific
  'TypeName': Tags.typeName,
  'TypeDefinition': Tags.definition(Tags.typeName),
  'type enum interface implements namespace module declare':
      Tags.definitionKeyword,
  'abstract global Privacy readonly override': Tags.modifier,
  'is keyof unique infer asserts': Tags.operatorKeyword,
  // JSX-specific
  'JSXAttributeValue': Tags.attributeValue,
  'JSXText': Tags.content,
  'JSXStartTag JSXStartCloseTag JSXSelfCloseEndTag JSXEndTag': Tags.angleBracket,
  'JSXIdentifier JSXNameSpacedName': Tags.tagName,
  'JSXAttribute/JSXIdentifier JSXAttribute/JSXNameSpacedName':
      Tags.attributeName,
  'JSXBuiltin/JSXIdentifier': Tags.standard(Tags.tagName),
});
