import 'package:flutter/material.dart';

class InterestCard extends StatefulWidget {
  final String label;
  final String? imageUrl;
  final bool isSelected;
  final VoidCallback onTap;

  const InterestCard({
    super.key,
    required this.label,
    this.imageUrl,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<InterestCard> createState() => _InterestCardState();
}

class _InterestCardState extends State<InterestCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 128,
          decoration: BoxDecoration(
            color: const Color(0xFFFAF2E9),
            borderRadius: BorderRadius.circular(12),
            border: widget.isSelected
                ? Border.all(color: const Color(0xFFB8D6B2), width: 2)
                : null,
            boxShadow: [
              if (_isHovered)
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
            ],
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              if (widget.imageUrl != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(10), // Account for border width
                    child: AnimatedScale(
                      scale: _isHovered ? 1.1 : 1.0,
                      duration: const Duration(milliseconds: 500),
                      child: Opacity(
                        opacity: 0.4,
                        child: Image.network(
                          widget.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Color(0xFFB8D6B2),
                      size: 20,
                    ),
                  ),
                ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF1E1B16),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
