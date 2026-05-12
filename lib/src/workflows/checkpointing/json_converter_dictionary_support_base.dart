import 'json_converter_base.dart';

/// Extends [JsonConverterBase] with support for using [T] values as JSON
/// dictionary keys via [stringify] / [parse], and provides [escape] /
/// [unescape] helpers that double `|` characters to avoid collision with
/// the `|`-based composite key format.
abstract class JsonConverterDictionarySupportBase<T>
    extends JsonConverterBase<T> {
  /// Converts [value] to a string suitable for use as a JSON map key.
  String stringify(T value);

  /// Parses a JSON map key back into [T].
  T parse(String key);

  /// Escapes [value] for inclusion in a `|`-delimited composite key.
  ///
  /// When [allowNullAndPad] is `false` (the default), [value] must be
  /// non-null and the result is the input with every `|` doubled.
  ///
  /// When [allowNullAndPad] is `true`, a `null` [value] produces an empty
  /// string and a non-null value is prefixed with `@` after escaping.
  static String escape(String? value, {bool allowNullAndPad = false}) {
    if (value == null) {
      if (!allowNullAndPad) {
        throw const FormatException(
          'Null value not allowed for non-padded escape.',
        );
      }
      return '';
    }
    final escaped = value.replaceAll('|', '||');
    return allowNullAndPad ? '@$escaped' : escaped;
  }

  /// Unescapes a component produced by [escape].
  ///
  /// When [allowNullAndPad] is `false` (the default), an empty [value]
  /// throws and the result is the doubled-pipes replaced with single ones.
  ///
  /// When [allowNullAndPad] is `true`, an empty [value] returns `null`,
  /// and a non-empty value must start with `@` (which is stripped).
  static String? unescape(String value, {bool allowNullAndPad = false}) {
    if (value.isEmpty) {
      if (!allowNullAndPad) {
        throw const FormatException(
          'Empty string not allowed for non-padded unescape.',
        );
      }
      return null;
    }
    if (allowNullAndPad) {
      if (value[0] != '@') {
        throw FormatException(
          "Expected '@' prefix for nullable component, got '$value'.",
        );
      }
      return value.substring(1).replaceAll('||', '|');
    }
    return value.replaceAll('||', '|');
  }
}
