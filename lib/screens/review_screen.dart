import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../i18n/app_localizations.dart';
import '../models/enums.dart';
import '../models/shot.dart';
import '../models/timer_string.dart';
import '../providers/history_provider.dart';
import '../providers/providers.dart';
import '../providers/string_provider.dart';
import '../services/export_service.dart';
import '../utils/time_format.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key, required this.stringId});
  final int stringId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stringAsync = ref.watch(stringByIdProvider(stringId));
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('review.title')),
        actions: [
          IconButton(
            tooltip: context.tr('review.shareCsv'),
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              final s = stringAsync.value;
              if (s == null) return;
              final subject =
                  context.tr('review.exportSubject', args: {'id': s.id ?? ''});
              final exporter = ExportService();
              final file = await exporter.writeStringCsv(s);
              await exporter.share(file, subject: subject);
            },
          ),
        ],
      ),
      body: stringAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child:
              Text(context.tr('common.failed', args: {'error': e.toString()})),
        ),
        data: (s) {
          if (s == null) {
            return Center(child: Text(context.tr('review.notFound')));
          }
          return _ReviewBody(string: s);
        },
      ),
    );
  }
}

class _ReviewBody extends ConsumerStatefulWidget {
  const _ReviewBody({required this.string});
  final TimerString string;

  @override
  ConsumerState<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends ConsumerState<_ReviewBody> {
  late final TextEditingController _labelCtrl =
      TextEditingController(text: widget.string.label ?? '');
  late final TextEditingController _notesCtrl =
      TextEditingController(text: widget.string.notes ?? '');
  late int _penaltyMs = widget.string.penaltyMs;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<Widget> _buildShotRows(
    BuildContext context,
    ThemeData theme,
    TimerString s,
  ) {
    final multiCycle = s.cyclesWithShots.length > 1;
    final rows = <Widget>[];
    int? currentCycle;
    for (var i = 0; i < s.shots.length; i++) {
      final shot = s.shots[i];
      if (multiCycle && shot.cycleIndex != currentCycle) {
        currentCycle = shot.cycleIndex;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            context.tr('review.cycleHeader',
                args: {'cycle': shot.cycleIndex}),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 1,
            ),
          ),
        ));
      }
      // Position within the same cycle for the leading badge + split calc.
      final prev = i == 0 ? null : s.shots[i - 1];
      final sameCycle = prev != null && prev.cycleIndex == shot.cycleIndex;
      final split = sameCycle ? shot.timeMs - prev.timeMs : null;
      final cycleOrdinal = sameCycle ? _cycleOrdinal(s, i) : 1;
      rows.add(Dismissible(
        key: ValueKey('shot-${shot.id ?? i}-$i'),
        direction: DismissDirection.endToStart,
        background: Container(
          color: theme.colorScheme.errorContainer,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const Icon(Icons.delete),
        ),
        onDismissed: (_) => _deleteShot(i),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: shot.manual
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.primaryContainer,
            child: Text(
              '$cycleOrdinal',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          title: Text(
            '${formatSeconds(shot.timeMs)}s',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            split == null
                ? context.tr('review.splitFirst')
                : context.tr('review.splitOther', args: {
                    'seconds': (split / 1000).toStringAsFixed(2),
                  }),
          ),
          trailing: shot.manual ? const Icon(Icons.edit, size: 16) : null,
        ),
      ));
    }
    return rows;
  }

  int _cycleOrdinal(TimerString s, int globalIdx) {
    final cycle = s.shots[globalIdx].cycleIndex;
    var n = 0;
    for (var j = 0; j <= globalIdx; j++) {
      if (s.shots[j].cycleIndex == cycle) n++;
    }
    return n;
  }

  Future<void> _persistMeta() async {
    final db = ref.read(databaseProvider);
    await db.updateStringMeta(
      widget.string.id!,
      label: _labelCtrl.text,
      notes: _notesCtrl.text,
      penaltyMs: _penaltyMs,
    );
    ref.invalidate(stringByIdProvider(widget.string.id!));
    ref.invalidate(historyProvider);
  }

  Future<void> _deleteShot(int index) async {
    final remaining = [
      for (var i = 0; i < widget.string.shots.length; i++)
        if (i != index) widget.string.shots[i],
    ];
    final reindexed = [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].copyWith(index: i),
    ];
    await ref.read(databaseProvider).replaceShots(widget.string.id!, reindexed);
    ref.invalidate(stringByIdProvider(widget.string.id!));
    ref.invalidate(historyProvider);
  }

  Future<void> _addShot() async {
    final lastMs =
        widget.string.shots.isEmpty ? 0 : widget.string.shots.last.timeMs;
    final controller = TextEditingController(
      text: ((lastMs + 200) / 1000).toStringAsFixed(2),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('review.addShotTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              InputDecoration(labelText: context.tr('review.timeSecondsLabel')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text)),
            child: Text(context.tr('common.add')),
          ),
        ],
      ),
    );
    if (result == null) return;
    final newMs = (result * 1000).round();
    // Inherit the cycle of the existing tail so an "add shot" extends the
    // last captured cycle instead of silently dropping into a new one.
    final inheritedCycle = widget.string.shots.isEmpty
        ? 1
        : widget.string.shots.last.cycleIndex;
    final shots = [
      ...widget.string.shots,
      Shot(
        stringId: widget.string.id,
        index: widget.string.shots.length,
        timeMs: newMs,
        manual: true,
        cycleIndex: inheritedCycle,
      )
    ]..sort((a, b) {
        if (a.cycleIndex != b.cycleIndex) {
          return a.cycleIndex.compareTo(b.cycleIndex);
        }
        return a.timeMs.compareTo(b.timeMs);
      });
    final reindexed = [
      for (var i = 0; i < shots.length; i++) shots[i].copyWith(index: i),
    ];
    await ref.read(databaseProvider).replaceShots(widget.string.id!, reindexed);
    ref.invalidate(stringByIdProvider(widget.string.id!));
    ref.invalidate(historyProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.string;
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd().add_jm();
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            dateFmt.format(s.createdAt.toLocal()),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('review.headerLine', args: {
              'drill': s.drillMode.labelFor(context),
              'delay': s.delayMode.labelFor(context),
              'seconds': (s.delayUsedMs / 1000).toStringAsFixed(2),
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (s.cyclesWithShots.length > 1)
            _PerCycleSummary(string: s)
          else
            _SummaryGrid(string: s),
          const SizedBox(height: 16),
          TextField(
            controller: _labelCtrl,
            decoration: InputDecoration(
              labelText: context.tr('review.label'),
              border: const OutlineInputBorder(),
            ),
            onEditingComplete: _persistMeta,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: context.tr('review.notes'),
              border: const OutlineInputBorder(),
            ),
            onEditingComplete: _persistMeta,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('review.penalty', args: {
                    'seconds': (_penaltyMs / 1000).toStringAsFixed(2),
                  }),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _penaltyMs = (_penaltyMs - 1000).clamp(0, 1 << 30);
                  });
                  _persistMeta();
                },
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _penaltyMs += 1000);
                  _persistMeta();
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Text(
                context
                    .tr('review.shotsHeader', args: {'count': s.shots.length}),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addShot,
                icon: const Icon(Icons.add),
                label: Text(context.tr('common.add')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (s.shots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(context.tr('review.noShots'))),
            )
          else
            ..._buildShotRows(context, theme, s),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.string});
  final TimerString string;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <_SummaryItem>[
      _SummaryItem(
        context.tr('review.summary.total'),
        '${formatSeconds(string.totalTimeMs)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.first'),
        string.firstShotMs == null
            ? '--'
            : '${formatSeconds(string.firstShotMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.fastest'),
        string.fastestSplitMs == null
            ? '--'
            : '${formatSeconds(string.fastestSplitMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.slowest'),
        string.slowestSplitMs == null
            ? '--'
            : '${formatSeconds(string.slowestSplitMs!)}s',
      ),
      _SummaryItem(
        context.tr('review.summary.average'),
        string.averageSplitMs == null
            ? '--'
            : '${formatSeconds(string.averageSplitMs!)}s',
      ),
      _SummaryItem(context.tr('review.summary.shots'), '${string.shotCount}'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        for (final i in items)
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  i.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  i.value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value);
  final String label;
  final String value;
}

/// Per-cycle aggregate panel shown for par-repeat strings, replacing the flat
/// summary grid. Each row is one cycle: total time, first-shot time, average
/// split, and shot count, all relative to that cycle's beep.
class _PerCycleSummary extends StatelessWidget {
  const _PerCycleSummary({required this.string});
  final TimerString string;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final cycle in string.cyclesWithShots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: _CycleSummaryRow(string: string, cycle: cycle),
            ),
          ),
      ],
    );
  }
}

class _CycleSummaryRow extends StatelessWidget {
  const _CycleSummaryRow({required this.string, required this.cycle});
  final TimerString string;
  final int cycle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final splits = string.splitsForCycle(cycle);
    final avgSplit = splits.isEmpty
        ? null
        : splits.reduce((a, b) => a + b) ~/ splits.length;
    String fmt(int? ms) => ms == null ? '--' : '${formatSeconds(ms)}s';
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            context.tr('review.cycleHeader', args: {'cycle': cycle}),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Expanded(
          child: _CycleStat(
            label: context.tr('review.summary.total'),
            value: fmt(string.totalForCycle(cycle)),
          ),
        ),
        Expanded(
          child: _CycleStat(
            label: context.tr('review.summary.first'),
            value: fmt(string.firstShotForCycle(cycle)),
          ),
        ),
        Expanded(
          child: _CycleStat(
            label: context.tr('review.summary.average'),
            value: fmt(avgSplit),
          ),
        ),
        Expanded(
          child: _CycleStat(
            label: context.tr('review.summary.shots'),
            value: '${string.shotsForCycle(cycle).length}',
          ),
        ),
      ],
    );
  }
}

class _CycleStat extends StatelessWidget {
  const _CycleStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
