import 'dart:ui';
import 'package:flutter/material.dart';

class RimAITopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData leadingIcon;
  final Color iconColor;
  final Widget? trailingWidget;

  const RimAITopBar({
    super.key,
    required this.title,
    required this.leadingIcon,
    this.iconColor = const Color(0xFF4A624D),
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          height: preferredSize.height + MediaQuery.of(context).padding.top,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F2).withOpacity(0.7),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF58423B).withOpacity(0.08),
                blurRadius: 40,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(leadingIcon, color: iconColor),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
              if (trailingWidget != null) 
                trailingWidget! 
              else 
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Color(0xFFE9E1D8),
                  child: Icon(Icons.person, color: Color(0xFF58423B)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64.0);
}
