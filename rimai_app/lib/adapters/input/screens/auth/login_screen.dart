import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/auth_providers.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_text_field.dart';
import 'package:rimai_app/adapters/input/widgets/error_banner.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _onIniciarSesion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final useCase = ref.read(iniciarSesionUseCaseProvider);
      
      final usuario = await useCase.ejecutar(
        correo: _emailController.text.trim(),
        contrasena: _passController.text,
      );

      if (!mounted) return;
      
      // La navegación automática debe ser gestionada por el enrutador
      // dependiendo del rol depositado en AuthStorageService.
      // Pero forzamos a GoRouter a refrescar evaluando nuevamente la ruta.
      if (usuario.rol == 'terapeuta') {
        context.go('/terapeuta/dashboard');
      } else if (usuario.rol == 'admin') {
        context.go('/admin/dashboard');
      } else {
        context.go('/familia/dashboard');
      }
      
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RimAIErrorBanner(message: _errorMessage),
            RimAITextField(
              label: 'Correo Electrónico',
              placeholder: 'tu@email.com',
              prefixIcon: Icons.mail_outline,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 24),
            RimAITextField(
              label: 'Contraseña',
              placeholder: '••••••••',
              prefixIcon: Icons.lock_outline,
              controller: _passController,
              obscureText: true,
              showToggle: true,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 8),
            _buildForgotPassword(),
            const SizedBox(height: 16),
            _buildLoginButton(),
            const SizedBox(height: 24),
            _buildDivider(),
            const SizedBox(height: 24),
            _buildSocialButtons(context),
            const SizedBox(height: 32),
            _buildRegisterLink(context),
          ],
        ),
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recuperar contraseña - próximamente')),
          );
        },
        child: Text(
          '¿Olvidaste tu contraseña?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFB8D6B2),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _onIniciarSesion,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
        label: Text(
          _isLoading ? 'Iniciando sesión...' : 'Iniciar Sesión',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        iconAlignment: IconAlignment.end,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB8D6B2),
          disabledBackgroundColor: const Color(0xFFB8D6B2).withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return 8;
            return 4;
          }),
          shadowColor: WidgetStateProperty.all(const Color(0xFFB8D6B2).withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: const Color(0xFFEAE4DC).withValues(alpha: 0.5), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'O CONTINÚA CON',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF63524E).withValues(alpha: 0.6),
              letterSpacing: 1.0,
            ),
          ),
        ),
        Expanded(child: Divider(color: const Color(0xFFEAE4DC).withValues(alpha: 0.5), thickness: 1)),
      ],
    );
  }

  Widget _buildSocialButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _socialButton(
          context: context,
          iconData: Icons.g_mobiledata, // Fallback icon instead of pure SVG to avoid adding flutter_svg
          color: const Color(0xFF4285F4),
        ),
        const SizedBox(width: 16),
        _socialButton(
          context: context,
          iconData: Icons.apple,
          color: Colors.black,
        ),
      ],
    );
  }

  Widget _socialButton({required BuildContext context, required IconData iconData, required Color color}) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login social - próximamente')),
        );
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFD9C5BF).withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Icon(iconData, size: 28, color: color),
        ),
      ),
    );
  }

  Widget _buildRegisterLink(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => context.go('/auth/register'),
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: const Color(0xFF63524E),
            ),
            children: [
              const TextSpan(text: '¿No tienes cuenta? '),
              TextSpan(
                text: 'Crea una ahora',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFB8D6B2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
