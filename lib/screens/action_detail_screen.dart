import 'package:flutter/material.dart';

class ActionDetailScreen extends StatelessWidget {
  const ActionDetailScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
    this.actions = const [],
  });

  final String title;
  final IconData icon;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Icon(icon, size: 56, color: const Color(0xFF2D95E5)),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF68778A)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (actions.isEmpty)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            )
          else
            ...actions,
        ],
      ),
    );
  }
}
