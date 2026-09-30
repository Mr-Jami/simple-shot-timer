import 'package:flutter/widgets.dart';

/// The app's two motion durations. Both are critically damped ease-outs in
/// practice: no overshoot, nothing decorative. A state change is drawn
/// continuously from wherever the previous one left off; it is never delayed.
const Duration kMotionShort = Duration(milliseconds: 150);
const Duration kMotionMedium = Duration(milliseconds: 200);

/// Scale tick played on the big number when a shot is detected.
const Duration kMotionTick = Duration(milliseconds: 120);

/// True when the platform asks for reduced motion (Android "Remove
/// animations", iOS "Reduce Motion").
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [base], or zero when the platform asks for reduced motion so every
/// implicit animation collapses to an instant swap.
Duration motion(BuildContext context, Duration base) =>
    reducedMotionOf(context) ? Duration.zero : base;
