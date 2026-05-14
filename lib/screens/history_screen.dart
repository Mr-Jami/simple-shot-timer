import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../i18n/app_localizations.dart';
import '../models/enums.dart';
import '../providers/history_provider.dart';
import '../services/export_service.dart';
import '../utils/time_format.dart';
import 'review_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('history.title')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'export') {
                final items = history.value ?? const [];
                if (items.isEmpty) return;
                final subject = context.tr('history.exportSubject');
                final exporter = ExportService();
                final file = await exporter.writeAllStringsCsv(items);
                await exporter.share(file, subject: subject);
              } else if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(context.tr('history.clearConfirmTitle')),
                    content: Text(context.tr('history.clearConfirmBody')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(context.tr('common.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(context.tr('common.deleteAll')),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(historyProvider.notifier).deleteAll();
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'export',
                child: Text(context.tr('history.exportAll')),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(context.tr('history.clearAll')),
              ),
            ],
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            context.tr('common.failedToLoad', args: {'error': e.toString()}),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(context.tr('history.empty')));
          }
          final dateFmt = DateFormat.yMMMd().add_jm();
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = items[index];
              return Dismissible(
                key: ValueKey('string-${s.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Icon(Icons.delete),
                ),
                onDismissed: (_) =>
                    ref.read(historyProvider.notifier).delete(s.id!),
                child: ListTile(
                  title: Text(
                    s.label?.isNotEmpty == true
                        ? s.label!
                        : context.tr('history.itemFallback', args: {
                            'seconds': formatSeconds(s.totalTimeMs),
                            'count': s.shotCount,
                          }),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${dateFmt.format(s.createdAt.toLocal())} · '
                    '${s.drillMode.labelFor(context)}',
                  ),
                  trailing: Text(
                    '${formatSeconds(s.totalTimeMs)}s',
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewScreen(stringId: s.id!),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
