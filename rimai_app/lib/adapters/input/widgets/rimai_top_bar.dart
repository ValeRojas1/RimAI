import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RimAITopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData leadingIcon;
  final Color iconColor;
  final Widget? trailingWidget;
  final VoidCallback? onLeadingPressed;

  const RimAITopBar({
    super.key,
    required this.title,
    required this.leadingIcon,
    this.iconColor = const Color(0xFF4A624D),
    this.trailingWidget,
    this.onLeadingPressed,
  });

  @override
  Widget build(BuildContext context) {
    void defaultBack() {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    void goHome() {
      final path = GoRouterState.of(context).uri.path;
      if (path.startsWith('/familia')) {
        context.go('/familia/dashboard');
      } else if (path.startsWith('/admin')) {
        context.go('/admin/dashboard');
      } else {
        context.go('/terapeuta/dashboard');
      }
    }

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
            color: const Color(0xFFFFF8F2).withValues(alpha: 0.7),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF58423B).withValues(alpha: 0.08),
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
                  IconButton(
                    icon: Icon(leadingIcon, color: iconColor),
                    tooltip: title,
                    onPressed: onLeadingPressed ?? defaultBack,
                  ),
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
                IconButton(
                  tooltip: 'Inicio',
                  icon: const Icon(
                    Icons.home_rounded,
                    color: Color(0xFF58423B),
                  ),
                  onPressed: goHome,
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
