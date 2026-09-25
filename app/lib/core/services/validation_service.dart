import '../models/survey.dart';

/// Implements the Radar validation appendix: 20 `vtype` regex families plus
/// mandatory / length / numeric-range rules. Returns `null` when valid, or a
/// human-readable error message when invalid.
class ValidationService {
  ValidationService._();

  /// vtype code -> regex pattern (from the Radar documentation appendix).
  static final Map<int, RegExp> _patterns = {
    1: RegExp(r'^[a-zA-Z][a-zA-Z ]+[a-zA-Z]$'), // Name
    2: RegExp(r'^[0-9]{1,2}(\.[0-9]{1,2})?$'), // Age
    3: RegExp(r'^[a-zA-Z0-9][\w\.\-]+@([0-9a-zA-Z][0-9a-zA-Z-]+\.)+[a-zA-Z]{2,8}$'), // Email
    4: RegExp(r'^(\+91|0)?[6789]\d{9}$'), // Mobile
    5: RegExp(r'^[\w\-\.,\r\n ]+$'), // Address
    6: RegExp(r'^[a-zA-Z0-9]{5,7}$'), // OTP
    7: RegExp(r'^(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$'), // Credit card
    8: RegExp(r'^[a-zA-Z0-9\.\@\#]+$'), // Password
    9: RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$'), // Web URL
    10: RegExp(r'^[0-9]{6}$'), // Pincode
    11: RegExp(r'^[0-9]+$'), // Number
    12: RegExp(r'^[1-9]+$'), // Non-zero number
    13: RegExp(r'^[0-9]+(\.[0-9]+)?$'), // Float
    14: RegExp(r'^[a-zA-Z0-9]+$'), // Alphanumeric
    15: RegExp(r'^[a-zA-Z]+$'), // Alphabets
    16: RegExp(r'^[a-zA-Z0-9 ]+$'), // Alphanumeric + space
    17: RegExp(r'^[a-zA-Z]+(\-[a-zA-Z]+)?$'), // Alphabets w/ hyphen
    18: RegExp(r'^[0-9]+(\-[0-9]+)?$'), // Number range
    19: RegExp(r'^[0-9]+(\.[0-9]+)?\%$'), // Percentage
    20: RegExp(r'''^[a-zA-Z0-9\_\.\,\/\?\!\@\#\$\%\^\&\*\-\(\)\=\+\;\'\"\[\]\{\} ]+$'''), // Any
  };

  static const Map<int, String> _defaultVtypeMsg = {
    1: 'Please enter a valid name',
    2: 'Please enter a valid age',
    3: 'Please enter a valid email',
    4: 'Please enter a valid mobile number',
    5: 'Please enter a valid address',
    6: 'Please enter a valid OTP',
    7: 'Please enter a valid card number',
    8: 'Please enter a valid password',
    9: 'Please enter a valid URL',
    10: 'Please enter a valid pincode',
    11: 'Please enter a valid number',
    12: 'Please enter a non-zero number',
    13: 'Please enter a valid decimal number',
    14: 'Only letters and numbers are allowed',
    15: 'Only letters are allowed',
    16: 'Only letters, numbers and spaces are allowed',
    17: 'Only letters and a hyphen are allowed',
    18: 'Please enter a valid range',
    19: 'Please enter a valid percentage',
    20: 'Please enter a valid value',
  };

  /// Validates a text value against a control's rules.
  static String? validateText(Control c, String? raw) {
    final value = (raw ?? '').trim();
    final v = c.validations;

    if (v.isMandatory && value.isEmpty) {
      return c.validationMsgs['mn'] ?? 'This field is required';
    }
    if (value.isEmpty) return null; // optional + empty => valid

    if (value.length < v.minLen || value.length > v.maxLen) {
      return c.validationMsgs['len'] ??
          'Length must be between ${v.minLen} and ${v.maxLen} characters';
    }
    if (v.vtype > 0) {
      final pattern = _patterns[v.vtype];
      if (pattern != null && !pattern.hasMatch(value)) {
        return c.validationMsgs['vtype'] ??
            _defaultVtypeMsg[v.vtype] ??
            'Please enter a valid value';
      }
    }
    return null;
  }

  /// Validates a selection / non-text answer (dropdown, radio, checkbox,
  /// rating, image list). [answer] may be a String, List, num, or null.
  static String? validateAnswer(Control c, dynamic answer) {
    final v = c.validations;
    final empty = answer == null ||
        (answer is String && answer.trim().isEmpty) ||
        (answer is List && answer.isEmpty);

    if (v.isMandatory && empty) {
      return c.validationMsgs['mn'] ?? 'This field is required';
    }
    if (empty) return null;

    if (answer is num) {
      if (v.minValue != null && answer < v.minValue!) {
        return c.validationMsgs['min'] ?? 'Minimum is ${v.minValue}';
      }
      if (v.maxValue != null && answer > v.maxValue!) {
        return c.validationMsgs['max'] ?? 'Maximum is ${v.maxValue}';
      }
    }
    if (c.opType == OpType.input) {
      return validateText(c, answer?.toString());
    }
    return null;
  }
}
