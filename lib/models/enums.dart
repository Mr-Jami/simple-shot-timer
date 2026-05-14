import 'package:flutter/widgets.dart';

import '../i18n/app_localizations.dart';

enum DelayMode {
  instant,
  fixed,
  random,
}

enum DrillMode {
  standard,
  par,
  stage,
}

enum AppThemeMode {
  system,
  light,
  dark,
  highContrast,
}

enum TimerPhase {
  idle,
  countdown,
  running,
  finished,
}

extension DelayModeX on DelayMode {
  String labelFor(BuildContext context) {
    final t = AppLocalizations.of(context);
    switch (this) {
      case DelayMode.instant:
        return t.t('enums.delayMode.instant');
      case DelayMode.fixed:
        return t.t('enums.delayMode.fixed');
      case DelayMode.random:
        return t.t('enums.delayMode.random');
    }
  }
}

extension DrillModeX on DrillMode {
  String labelFor(BuildContext context) {
    final t = AppLocalizations.of(context);
    switch (this) {
      case DrillMode.standard:
        return t.t('enums.drillMode.standard');
      case DrillMode.par:
        return t.t('enums.drillMode.par');
      case DrillMode.stage:
        return t.t('enums.drillMode.stage');
    }
  }
}

extension AppThemeModeX on AppThemeMode {
  String labelFor(BuildContext context) {
    final t = AppLocalizations.of(context);
    switch (this) {
      case AppThemeMode.system:
        return t.t('enums.theme.system');
      case AppThemeMode.light:
        return t.t('enums.theme.light');
      case AppThemeMode.dark:
        return t.t('enums.theme.dark');
      case AppThemeMode.highContrast:
        return t.t('enums.theme.highContrast');
    }
  }
}
