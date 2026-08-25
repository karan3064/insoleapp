import 'package:flutter/material.dart';

/// Mirrors `components/PageHeader/PageHeader.vue`: a simple bold title used
/// on screens with a custom (non-native) app bar.
class PageHeader extends StatelessWidget {
  final String title;

  const PageHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
    );
  }
}
