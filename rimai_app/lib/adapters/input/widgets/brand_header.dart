import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RimAIBrandHeader extends StatelessWidget {
  const RimAIBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.all_inclusive,
                size: 52,
                color: Color(0xFFB8D6B2),
              ),
              const SizedBox(width: 10),
              Text(
                'RimAI',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFB8D6B2),
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bienvenido a tu mundo virtual',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF63524E),
            ),
          ),
        ],
      ),
    );
  }
}
