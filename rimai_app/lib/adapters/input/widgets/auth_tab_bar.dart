import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Constantes de la paleta
const Color _kBrand = Color(0xFFB8D6B2);
const Color _kTabBg = Color(0xFFF2EBE1);
const Color _kTextPrimary = Color(0xFF63524E);
const Color _kBorder = Color(0xFFD9C5BF);
const Color _kSurface = Color(0xFFFFFFFF);

/// Enum para indicar cuál tab está activo
enum AuthTab { login, register }

/// Barra de tabs animada compartida entre LoginScreen y RegisterScreen.
/// La píldora activa se desliza suavemente al cambiar de tab.
class RimAIAuthTabBar extends StatefulWidget {
  /// Tab que está actualmente activo (viene del padre)
  final AuthTab activeTab;

  /// Callback al presionar "Iniciar Sesión"
  final VoidCallback onLoginTap;

  /// Callback al presionar "Registrarse"
  final VoidCallback onRegisterTap;

  const RimAIAuthTabBar({
    super.key,
    required this.activeTab,
    required this.onLoginTap,
    required this.onRegisterTap,
  });

  @override
  State<RimAIAuthTabBar> createState() => _RimAIAuthTabBarState();
}

class _RimAIAuthTabBarState extends State<RimAIAuthTabBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // La píldora va de izquierda (0.0) a derecha (1.0)
    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    // Posición inicial según el tab activo
    if (widget.activeTab == AuthTab.register) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(RimAIAuthTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      if (widget.activeTab == AuthTab.login) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _kTabBg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              children: [
                // ── Píldora blanca deslizante ──────────────────────────────
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final halfWidth = constraints.maxWidth / 2;
                      return Transform.translate(
                        offset: Offset(
                          _slideAnimation.value * halfWidth,
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 0.5,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _kSurface,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _kBorder.withValues(alpha: 0.3),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // ── Textos de cada tab ─────────────────────────────────────
                Row(
                  children: [
                    // Tab: Iniciar Sesión
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.activeTab != AuthTab.login
                            ? widget.onLoginTap
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: widget.activeTab == AuthTab.login
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: widget.activeTab == AuthTab.login
                                  ? _kBrand
                                  : _kTextPrimary.withValues(alpha: 0.6),
                            ),
                            child: Text(
                              'Iniciar Sesión',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Tab: Registrarse
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.activeTab != AuthTab.register
                            ? widget.onRegisterTap
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: widget.activeTab == AuthTab.register
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: widget.activeTab == AuthTab.register
                                  ? _kBrand
                                  : _kTextPrimary.withValues(alpha: 0.6),
                            ),
                            child: Text(
                              'Registrarse',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
