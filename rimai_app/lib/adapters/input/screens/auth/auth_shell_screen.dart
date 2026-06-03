import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/brand_header.dart';
import 'package:rimai_app/adapters/input/widgets/feature_panel.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_footer.dart';
import 'package:rimai_app/adapters/input/widgets/auth_tab_bar.dart';

class AuthShellScreen extends StatelessWidget {
  final Widget child;

  const AuthShellScreen({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Obtenemos la ruta actual para saber qué tab activar.
    final location = GoRouterState.of(context).uri.toString();
    final activeTab =
        location.contains('login') ? AuthTab.login : AuthTab.register;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const RimAIBrandHeader(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth >= 768;

                      if (isDesktop) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                flex: 5,
                                child: RimAIFeaturePanel(),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                flex: 6,
                                child: _buildFormCard(
                                    context, activeTab, location),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildFormCard(context, activeTab, location),
                        );
                      }
                    },
                  ),
                ),
              ),
              const RimAIFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(
      BuildContext context, AuthTab activeTab, String location) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D2A26).withValues(alpha: 0.04),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RimAIAuthTabBar(
            activeTab: activeTab,
            onLoginTap: () => context.go('/auth/login'),
            onRegisterTap: () => context.go('/auth/register'),
          ),
          // AnimatedSize + slide horizontal: la carta crece/encoge y el formulario
          // se desliza como un bloque al cambiar entre login y registro.
          AnimatedSize(
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: _AuthFormSwitcher(
              activeTab: activeTab,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Desliza el formulario activo horizontalmente, como una transición de página.
class _AuthFormSwitcher extends StatelessWidget {
  static const _duration = Duration(milliseconds: 480);

  final AuthTab activeTab;
  final Widget child;

  const _AuthFormSwitcher({
    required this.activeTab,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final tab = (child.key as ValueKey<AuthTab>).value;
        final fromRight = tab == AuthTab.register;
        final slideOffset = Tween<Offset>(
          begin: Offset(fromRight ? 0.18 : -0.18, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ));

        return ClipRect(
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slideOffset,
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(activeTab),
        child: child,
      ),
    );
  }
}
