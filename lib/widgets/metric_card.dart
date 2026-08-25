import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Gradient stat tile used on the home dashboard + trends screen, mirroring
/// the `.metric-card` / `.summary-stat` cards in the Vue app.
class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Gradient gradient;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.gradient = AppColors.gradBlue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
