import 'package:flutter/material.dart';
import 'package:yomu_ui/yomu_ui.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(YomuTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: YomuTokens.space3),
          Text(
            message,
            style: const TextStyle(color: YomuTokens.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
