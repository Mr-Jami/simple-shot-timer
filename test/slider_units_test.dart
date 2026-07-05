import 'package:flutter_test/flutter_test.dart';
import 'package:simple_shot_timer/utils/slider_units.dart';

void main() {
  group('SecondsFromMsUnit', () {
    test('formats ms as one-decimal seconds', () {
      expect(secondsFromMsUnit.format(2500), '2.5s');
      expect(secondsFromMsUnit.format(0), '0.0s');
    });

    test('edit round-trip', () {
      expect(secondsFromMsUnit.editText(2500), '2.5');
      expect(secondsFromMsUnit.parse('2.5'), 2500);
      expect(secondsFromMsUnit.parse(secondsFromMsUnit.editText(1234)), 1200);
    });

    test('accepts comma decimals and a typed suffix', () {
      expect(secondsFromMsUnit.parse('2,5'), 2500);
      expect(secondsFromMsUnit.parse(' 2.5s '), 2500);
      expect(secondsFromMsUnit.parse('2,5 S'), 2500);
    });

    test('rejects garbage', () {
      expect(secondsFromMsUnit.parse(''), isNull);
      expect(secondsFromMsUnit.parse('abc'), isNull);
      expect(secondsFromMsUnit.parse('2..5'), isNull);
    });

    test('range hint carries the unit', () {
      expect(secondsFromMsUnit.rangeHint(100, 30000), '0.1s – 30.0s');
    });
  });

  group('WholeSecondsFromMsUnit', () {
    test('formats and parses whole seconds', () {
      expect(wholeSecondsFromMsUnit.format(60000), '60s');
      expect(wholeSecondsFromMsUnit.parse('90'), 90000);
      expect(wholeSecondsFromMsUnit.parse('90.5'), 90500);
    });
  });

  group('MillisecondsUnit', () {
    test('formats and parses plain ms', () {
      expect(millisecondsUnit.format(80), '80ms');
      expect(millisecondsUnit.parse('80'), 80);
      expect(millisecondsUnit.parse('80ms'), 80);
      expect(millisecondsUnit.parse('80.4'), 80);
    });
  });

  group('HertzUnit', () {
    test('row display compacts to kHz above 1000', () {
      expect(hertzUnit.format(300), '300 Hz');
      expect(hertzUnit.format(6000), '6.0 kHz');
    });

    test('edit text and parse stay in plain Hz', () {
      expect(hertzUnit.editText(6000), '6000');
      expect(hertzUnit.parse('6000'), 6000);
      expect(hertzUnit.parse('6000 Hz'), 6000);
    });

    test('range hint uses plain Hz', () {
      expect(hertzUnit.rangeHint(50, 2000), '50 Hz – 2000 Hz');
    });
  });

  group('PercentUnit', () {
    test('formats and parses', () {
      expect(percentUnit.format(15), '15%');
      expect(percentUnit.parse('15'), 15);
      expect(percentUnit.parse('15%'), 15);
    });
  });

  group('FractionPercentUnit', () {
    test('displays a 0..1 fraction as percent', () {
      expect(fractionPercentUnit.format(0.9), '90%');
      expect(fractionPercentUnit.editText(0.9), '90');
    });

    test('parses percent back to a fraction', () {
      expect(fractionPercentUnit.parse('90'), closeTo(0.9, 1e-9));
      expect(fractionPercentUnit.parse('90%'), closeTo(0.9, 1e-9));
    });
  });

  group('CountUnit', () {
    test('plain integer round-trip', () {
      expect(countUnit.format(500), '500');
      expect(countUnit.parse('500'), 500);
      expect(countUnit.parse('bogus'), isNull);
    });
  });
}
