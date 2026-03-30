import 'package:flutter/material.dart';
import '../models/daily_reading.dart';

class FocusChip extends StatelessWidget {
  final FocusArea focusArea;

  const FocusChip({super.key, required this.focusArea});

  Color get _levelColor {
    switch (focusArea.level) {
      case 'positive':
        return const Color(0xFF4CAF50);
      case 'caution':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF78909C);
    }
  }

  IconData get _iconData {
    switch (focusArea.icon) {
      case 'chat':
        return Icons.chat_bubble_outline;
      case 'work':
        return Icons.work_outline;
      case 'heart':
        return Icons.favorite_outline;
      case 'health':
        return Icons.spa_outlined;
      case 'money':
        return Icons.attach_money;
      case 'star':
        return Icons.star_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _levelColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _levelColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconData, size: 16, color: _levelColor),
          const SizedBox(width: 6),
          Text(
            focusArea.label,
            style: TextStyle(
              color: _levelColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
