import 'package:flutter/material.dart';

/// Mission banner explaining ads support free coding for students, with a link to B Code Pro.
class MissionBanner extends StatelessWidget {
  final VoidCallback onGoAdFree;

  const MissionBanner({super.key, required this.onGoAdFree});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2232),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A364F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: Color(0xFFFF5252), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Advertising helps keep Kriya free 🥺',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              InkWell(
                onTap: onGoAdFree,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'GO AD FREE',
                    style: TextStyle(
                      color: Color(0xFF00E676),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '1 short sponsor break unlocks an extension or runtime permanently. Zero ads inside your editor.',
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
