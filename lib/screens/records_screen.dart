import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/page_header.dart';
import 'detail_screen.dart';

/// Mirrors `pages/records/records.vue` (insole-only).
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final insole = context.watch<InsoleProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageHeader(title: 'Test records'),
              Expanded(
                child: insole.list.isEmpty
                    ? const Center(
                        child: Text('No test data yet', style: TextStyle(color: AppColors.textSecondary)),
                      )
                    : ListView.separated(
                        itemCount: insole.list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final record = insole.list[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => DetailScreen(recordId: record.id)),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                        gradient: AppColors.gradBlue, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(record.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text(record.date,
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
