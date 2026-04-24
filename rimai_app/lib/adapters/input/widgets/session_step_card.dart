import 'package:flutter/material.dart';
import 'bento_card.dart';

class SessionStepCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String description;
  final String duration;
  final bool hasScanning;

  const SessionStepCard({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.description,
    required this.duration,
    this.hasScanning = false,
  });

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE9E1D8),
            child: Text(
              '$stepNumber',
              style: const TextStyle(
                color: Color(0xFF4A624D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1E1B16),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF58423B),
              height: 1.5, // leading relaxed
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A624D).withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.timer,
                  size: 14,
                  color: Color(0xFF4A624D),
                ),
                const SizedBox(width: 6),
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A624D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
