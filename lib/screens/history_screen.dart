// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import '../providers/history_provider.dart';
import '../services/export_service.dart';
import '../widgets/string_tile.dart';
import '../widgets/tab_header.dart';
import 'review_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          TabHeader(
            title: context.tr('history.title'),
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
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  context
                      .tr('common.failedToLoad', args: {'error': e.toString()}),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Center(child: Text(context.tr('history.empty')));
                }
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
                      child: StringTile(
                        string: s,
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
          ),
        ],
      ),
    );
  }
}
