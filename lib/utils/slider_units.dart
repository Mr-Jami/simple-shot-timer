/// Bundles row display, dialog prefill, parsing and range hint for one unit
/// family, so a slider's readout and its typed input can't drift apart.
abstract class SliderUnit<T extends num> {
  const SliderUnit();

  /// Value text shown next to the slider label.
  String format(T value);

  /// Bare number (no suffix) prefilled in the edit dialog.
  String editText(T value);

  /// Unit label appended in [format] and [rangeHint]; '' if none. Carries its
  /// own leading space where the display convention has one (e.g. ' Hz').
  String get suffix => '';

  /// Whether the dialog keyboard should offer a decimal point.
  bool get isDecimal => false;

  /// Converts a parsed number in edit units back to a native value.
  T fromNumber(double number);

  /// Parses dialog input back to a native value; null if not a number.
  /// Tolerates a trailing unit suffix and a comma decimal separator.
  T? parse(String text) {
    var t = text.trim();
    final s = suffix.trim();
    if (s.isNotEmpty && t.toLowerCase().endsWith(s.toLowerCase())) {
      t = t.substring(0, t.length - s.length).trim();
    }
    final number = double.tryParse(t.replaceAll(',', '.'));
    return number == null ? null : fromNumber(number);
  }

  /// Valid range shown as dialog helper text, e.g. '0.1s – 30.0s'.
  String rangeHint(T min, T max) =>
      '${editText(min)}$suffix – ${editText(max)}$suffix';
}

/// Int value stored in native units and edited as `value / divisor` with a
/// fixed number of decimals — covers seconds-from-ms, plain ms, percent and
/// bare counts.
class ScaledIntUnit extends SliderUnit<int> {
  const ScaledIntUnit({this.divisor = 1, this.decimals = 0, this.suffix = ''});

  final int divisor;
  final int decimals;
  @override
  final String suffix;

  @override
  String format(int value) => '${editText(value)}$suffix';

  @override
  String editText(int value) => (value / divisor).toStringAsFixed(decimals);

  @override
  bool get isDecimal => decimals > 0;

  @override
  int fromNumber(double number) => (number * divisor).round();
}

/// Frequency in Hz; the row compacts to kHz above 1000, input is plain Hz.
class HertzUnit extends SliderUnit<int> {
  const HertzUnit();

  @override
  String format(int value) => value >= 1000
      ? '${(value / 1000).toStringAsFixed(1)} kHz'
      : '$value Hz';

  @override
  String editText(int value) => '$value';

  @override
  String get suffix => ' Hz';

  @override
  int fromNumber(double number) => number.round();
}

/// 0..1 fraction displayed and edited as a percentage.
class FractionPercentUnit extends SliderUnit<double> {
  const FractionPercentUnit();

  @override
  String format(double value) => '${(value * 100).round()}%';

  @override
  String editText(double value) => '${(value * 100).round()}';

  @override
  String get suffix => '%';

  @override
  double fromNumber(double number) => number / 100;
}

const secondsFromMsUnit = ScaledIntUnit(divisor: 1000, decimals: 1, suffix: 's');
const wholeSecondsFromMsUnit = ScaledIntUnit(divisor: 1000, suffix: 's');
const millisecondsUnit = ScaledIntUnit(suffix: 'ms');
const percentUnit = ScaledIntUnit(suffix: '%');
const countUnit = ScaledIntUnit();
const hertzUnit = HertzUnit();
const fractionPercentUnit = FractionPercentUnit();
