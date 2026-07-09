import 'package:flutter/material.dart';

import '../theme/yomu_tokens.dart';

class YomuNavItem {
  const YomuNavItem({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

/// Provisional desktop app shell — swap visual layer later without touching core.
class YomuAppShell extends StatelessWidget {
  const YomuAppShell({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
    required this.body,
    this.statusBar,
    this.title = 'Yomu',
  });

  final List<YomuNavItem> items;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Widget body;
  final Widget? statusBar;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 220,
                  color: YomuTokens.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(YomuTokens.space4),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          children: [
                            for (final item in items)
                              ListTile(
                                leading: Icon(item.icon),
                                title: Text(item.label),
                                selected: item.id == selectedId,
                                selectedTileColor: YomuTokens.surfaceHover,
                                onTap: () => onSelect(item.id),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          ),
          if (statusBar != null) ...[
            const Divider(height: 1),
            Material(
              color: YomuTokens.surface,
              child: SizedBox(
                height: 36,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: YomuTokens.space3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: statusBar,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
