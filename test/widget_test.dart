// Aggregate test entry point.
import 'delay_test.dart' as delay;
import 'shot_detector_test.dart' as detector;
import 'split_test.dart' as split;

void main() {
  delay.main();
  split.main();
  detector.main();
}
