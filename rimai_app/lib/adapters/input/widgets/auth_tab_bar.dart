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

class _RimAIAuthTabBarState extends State<RimAIAuthTabBar> {
  late AuthTab _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.activeTab;
  }

  @override
  void didUpdateWidget(RimAIAuthTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab) {
      _currentTab = widget.activeTab;
    }
  }

  void _handleTabTap(AuthTab targetTab) {
    if (_currentTab == targetTab) return;

    // Al usar ShellRoute no necesitamos delay artificial, Router se encarga.
    if (targetTab == AuthTab.login) {
      widget.onLoginTap();
    } else {
      widget.onRegisterTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _kTabBg,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16), bottom: Radius.circular(12)),
        ),
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            // ── Píldora blanca deslizante ──────────────────────────────
            AnimatedAlign(
              duration: const Duration(milliseconds: 480),
              curve: Curves.easeOutCubic,
              alignment: _currentTab == AuthTab.login
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
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
            ),
            // ── Textos de cada tab ─────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleTabTap(AuthTab.login),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: _currentTab == AuthTab.login
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _currentTab == AuthTab.login
                              ? _kBrand
                              : _kTextPrimary.withValues(alpha: 0.6),
                        ),
                        child: const Text('Iniciar Sesión'),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleTabTap(AuthTab.register),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: _currentTab == AuthTab.register
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _currentTab == AuthTab.register
                              ? _kBrand
                              : _kTextPrimary.withValues(alpha: 0.6),
                        ),
                        child: const Text('Registrarse'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
