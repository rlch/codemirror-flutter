/// The default set of highlighting tags.
///
/// This collection is heavily biased towards programming languages,
/// and necessarily incomplete.
library;

import 'tag.dart';

/// Helper for defining tags.
Tag _t([Tag? parent]) => Tag.define(parent);

// Base categories
final Tag _comment = _t();
final Tag _name = _t();
final Tag _typeName = _t(_name);
final Tag _propertyName = _t(_name);
final Tag _literal = _t();
final Tag _string = _t(_literal);
final Tag _number = _t(_literal);
final Tag _content = _t();
final Tag _heading = _t(_content);
final Tag _keyword = _t();
final Tag _operator = _t();
final Tag _punctuation = _t();
final Tag _bracket = _t(_punctuation);
final Tag _meta = _t();

/// The default set of highlighting tags.
///
/// This collection is heavily biased towards programming languages,
/// and necessarily incomplete. A full ontology of syntactic constructs
/// would fill a stack of books, and be impractical to write themes for.
///
/// Note that it is not obligatory to always attach the most specific
/// tag possible to an element—if your grammar can't easily distinguish
/// a certain type of element (such as a local variable), it is okay to
/// style it as its more general variant (a variable).
class Tags {
  Tags._();

  // ============================================================
  // Comments
  // ============================================================

  /// A comment.
  static final Tag comment = _comment;

  /// A line comment.
  static final Tag lineComment = _t(comment);

  /// A block comment.
  static final Tag blockComment = _t(comment);

  /// A documentation comment.
  static final Tag docComment = _t(comment);

  // ============================================================
  // Names
  // ============================================================

  /// Any kind of identifier.
  static final Tag name = _name;

  /// The name of a variable.
  static final Tag variableName = _t(name);

  /// A type name.
  static final Tag typeName = _typeName;

  /// A tag name (subtag of typeName).
  static final Tag tagName = _t(typeName);

  /// A property or field name.
  static final Tag propertyName = _propertyName;

  /// An attribute name (subtag of propertyName).
  static final Tag attributeName = _t(propertyName);

  /// The name of a class.
  static final Tag className = _t(name);

  /// A label name.
  static final Tag labelName = _t(name);

  /// A namespace name.
  static final Tag namespace = _t(name);

  /// The name of a macro.
  static final Tag macroName = _t(name);

  // ============================================================
  // Literals
  // ============================================================

  /// A literal value.
  static final Tag literal = _literal;

  /// A string literal.
  static final Tag string = _string;

  /// A documentation string.
  static final Tag docString = _t(string);

  /// A character literal (subtag of string).
  static final Tag character = _t(string);

  /// An attribute value (subtag of string).
  static final Tag attributeValue = _t(string);

  /// A number literal.
  static final Tag number = _number;

  /// An integer number literal.
  static final Tag integer = _t(number);

  /// A floating-point number literal.
  static final Tag float = _t(number);

  /// A boolean literal.
  static final Tag bool_ = _t(literal);

  /// Regular expression literal.
  static final Tag regexp = _t(literal);

  /// An escape literal, for example a backslash escape in a string.
  static final Tag escape = _t(literal);

  /// A color literal.
  static final Tag color = _t(literal);

  /// A URL literal.
  static final Tag url = _t(literal);

  // ============================================================
  // Keywords
  // ============================================================

  /// A language keyword.
  static final Tag keyword = _keyword;

  /// The keyword for the self or this object.
  static final Tag self = _t(keyword);

  /// The keyword for null.
  static final Tag null_ = _t(keyword);

  /// A keyword denoting some atomic value.
  static final Tag atom = _t(keyword);

  /// A keyword that represents a unit.
  static final Tag unit = _t(keyword);

  /// A modifier keyword.
  static final Tag modifier = _t(keyword);

  /// A keyword that acts as an operator.
  static final Tag operatorKeyword = _t(keyword);

  /// A control-flow related keyword.
  static final Tag controlKeyword = _t(keyword);

  /// A keyword that defines something.
  static final Tag definitionKeyword = _t(keyword);

  /// A keyword related to defining or interfacing with modules.
  static final Tag moduleKeyword = _t(keyword);

  // ============================================================
  // Operators
  // ============================================================

  /// An operator.
  static final Tag operator = _operator;

  /// An operator that dereferences something.
  static final Tag derefOperator = _t(operator);

  /// Arithmetic-related operator.
  static final Tag arithmeticOperator = _t(operator);

  /// Logical operator.
  static final Tag logicOperator = _t(operator);

  /// Bit operator.
  static final Tag bitwiseOperator = _t(operator);

  /// Comparison operator.
  static final Tag compareOperator = _t(operator);

  /// Operator that updates its operand.
  static final Tag updateOperator = _t(operator);

  /// Operator that defines something.
  static final Tag definitionOperator = _t(operator);

  /// Type-related operator.
  static final Tag typeOperator = _t(operator);

  /// Control-flow operator.
  static final Tag controlOperator = _t(operator);

  // ============================================================
  // Punctuation
  // ============================================================

  /// Program or markup punctuation.
  static final Tag punctuation = _punctuation;

  /// Punctuation that separates things.
  static final Tag separator = _t(punctuation);

  /// Bracket-style punctuation.
  static final Tag bracket = _bracket;

  /// Angle brackets (usually `<` and `>` tokens).
  static final Tag angleBracket = _t(bracket);

  /// Square brackets (usually `[` and `]` tokens).
  static final Tag squareBracket = _t(bracket);

  /// Parentheses (usually `(` and `)` tokens).
  static final Tag paren = _t(bracket);

  /// Braces (usually `{` and `}` tokens).
  static final Tag brace = _t(bracket);

  // ============================================================
  // Content
  // ============================================================

  /// Content, for example plain text in XML or markup documents.
  static final Tag content = _content;

  /// Content that represents a heading.
  static final Tag heading = _heading;

  /// A level 1 heading.
  static final Tag heading1 = _t(heading);

  /// A level 2 heading.
  static final Tag heading2 = _t(heading);

  /// A level 3 heading.
  static final Tag heading3 = _t(heading);

  /// A level 4 heading.
  static final Tag heading4 = _t(heading);

  /// A level 5 heading.
  static final Tag heading5 = _t(heading);

  /// A level 6 heading.
  static final Tag heading6 = _t(heading);

  /// A prose content separator (such as a horizontal rule).
  static final Tag contentSeparator = _t(content);

  /// Content that represents a list.
  static final Tag list = _t(content);

  /// Content that represents a quote.
  static final Tag quote = _t(content);

  /// Content that is emphasized.
  static final Tag emphasis = _t(content);

  /// Content that is styled strong.
  static final Tag strong = _t(content);

  /// Content that is part of a link.
  static final Tag link = _t(content);

  /// Content that is styled as code or monospace.
  static final Tag monospace = _t(content);

  /// Content that has a strike-through style.
  static final Tag strikethrough = _t(content);

  // ============================================================
  // Change tracking
  // ============================================================

  /// Inserted text in a change-tracking format.
  static final Tag inserted = _t();

  /// Deleted text.
  static final Tag deleted = _t();

  /// Changed text.
  static final Tag changed = _t();

  // ============================================================
  // Special
  // ============================================================

  /// An invalid or unsyntactic element.
  static final Tag invalid = _t();

  /// Metadata or meta-instruction.
  static final Tag meta = _meta;

  /// Metadata that applies to the entire document.
  static final Tag documentMeta = _t(meta);

  /// Metadata that annotates or adds attributes to a given syntactic element.
  static final Tag annotation = _t(meta);

  /// Processing instruction or preprocessor directive.
  static final Tag processingInstruction = _t(meta);

  // ============================================================
  // Modifiers
  // ============================================================

  /// Modifier that indicates that a given element is being defined.
  ///
  /// Expected to be used with the various name tags.
  static final Tag Function(Tag) definition = Tag.defineModifier('definition');

  /// Modifier that indicates that something is constant.
  ///
  /// Mostly expected to be used with variable names.
  static final Tag Function(Tag) constant = Tag.defineModifier('constant');

  /// Modifier used to indicate that a variable or property name is being
  /// called or defined as a function.
  static final Tag Function(Tag) function = Tag.defineModifier('function');

  /// Modifier that can be applied to names to indicate that they belong
  /// to the language's standard environment.
  static final Tag Function(Tag) standard = Tag.defineModifier('standard');

  /// Modifier that indicates a given name is local to some scope.
  static final Tag Function(Tag) local = Tag.defineModifier('local');

  /// A generic variant modifier that can be used to tag language-specific
  /// alternative variants of some common tag.
  ///
  /// It is recommended for themes to define special forms of at least
  /// the string and variable name tags, since those come up a lot.
  static final Tag Function(Tag) special = Tag.defineModifier('special');
}

/// Convenience alias for [Tags].
final tags = Tags;
