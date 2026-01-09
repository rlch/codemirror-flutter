/// Decoding utilities for parser data.
///
/// This module provides functions to decode parser tables from
/// the compact string format used by lezer-generator.
library;

import 'dart:typed_data';

import 'constants.dart';

/// Decode a packed array from a string.
///
/// The encoding uses printable ASCII characters to represent values,
/// with special handling for large values and certain characters.
Uint16List decodeArray(Object /* String | Uint16List */ input) {
  if (input is Uint16List) return input;
  final str = input as String;

  Uint16List? array;
  var out = 0;
  var pos = 0;

  while (pos < str.length) {
    var value = 0;
    while (true) {
      var next = str.codeUnitAt(pos++);
      var stop = false;

      if (next == Encode.bigValCode) {
        value = Encode.bigVal;
        break;
      }
      if (next >= Encode.gap2) next--;
      if (next >= Encode.gap1) next--;

      var digit = next - Encode.start;
      if (digit >= Encode.base) {
        digit -= Encode.base;
        stop = true;
      }
      value += digit;
      if (stop) break;
      value *= Encode.base;
    }

    if (array != null) {
      array[out++] = value;
    } else {
      array = Uint16List(value);
    }
  }

  return array ?? Uint16List(0);
}

/// Decode a packed array to Uint32List.
Uint32List decodeArray32(Object /* String | Uint32List */ input) {
  if (input is Uint32List) return input;
  final str = input as String;

  Uint32List? array;
  var out = 0;
  var pos = 0;

  while (pos < str.length) {
    var value = 0;
    while (true) {
      var next = str.codeUnitAt(pos++);
      var stop = false;

      if (next == Encode.bigValCode) {
        value = Encode.bigVal;
        break;
      }
      if (next >= Encode.gap2) next--;
      if (next >= Encode.gap1) next--;

      var digit = next - Encode.start;
      if (digit >= Encode.base) {
        digit -= Encode.base;
        stop = true;
      }
      value += digit;
      if (stop) break;
      value *= Encode.base;
    }

    if (array != null) {
      array[out++] = value;
    } else {
      array = Uint32List(value);
    }
  }

  return array ?? Uint32List(0);
}
