import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/auth_providers.dart';
import '../../../../domain/entities/registro_usuario_request.dart';

// ─── Paleta de colores ───────────────────────────────────────────────────────
const Color _kBrand = Color(0xFFB8D6B2);
const Color _kBrandDark = Color(0xFF6B8E6D);
const Color _kBackground = Color(0xFFFDFBF8);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kPanel = Color(0xFFF7F3EF);
const Color _kBorder = Color(0xFFD9C5BF);
const Color _kTabBg = Color(0xFFF2EBE1);
const Color _kFieldBg = Color(0xFFE5DED5);
const Color _kTextPrimary = Color(0xFF63524E);
const Color _kIconMuted = Color(0xFF9E8A84);
const Color _kError = Color(0xFFB3261E);
const Color _kCircle1Bg = Color(0xFFDCEFDD);
const Color _kCircle2Bg = Color(0xFFEDE4D9);

/// Pantalla de Registro — adaptador de entrada (hexagonal)
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _contrasenaController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  // ── Validaciones ──────────────────────────────────────────────────────────

  String? _validateNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre completo es requerido';
    }
    return null;
  }

  String? _validateCorreo(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El correo electrónico es requerido';
    }
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validateContrasena(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es requerida';
    }
    if (value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    return null;
  }

  // ── Acción de registro ────────────────────────────────────────────────────

  Future<void> _onCrearCuenta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final useCase = ref.read(registrarUsuarioUseCaseProvider);
      final request = RegistroUsuarioRequest(
        nombreCompleto: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      await useCase.ejecutar(request);

      if (!mounted) return;

      // Navegar según el rol retornado por el backend
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _kError,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;

    return Scaffold(
      backgroundColor: _kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              _buildBody(isDesktop),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sección 1: Encabezado de marca ────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 32),
      child: Column(
        children: [
          // Logo + nombre
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.all_inclusive,
                size: 52,
                color: _kBrand,
              ),
              const SizedBox(width: 10),
              Text(
                'RimAI',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: _kBrand,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Subtítulo
          Text(
            'Bienvenido a tu mundo virtual',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: _kTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sección 2: Cuerpo central ─────────────────────────────────────────────

  Widget _buildBody(bool isDesktop) {
    final horizontalPadding = isDesktop ? 48.0 : 20.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _buildInfoPanel()),
                const SizedBox(width: 32),
                Expanded(flex: 6, child: _buildFormCard()),
              ],
            )
          : _buildFormCard(),
    );
  }

  // ── Panel izquierdo (solo desktop) ────────────────────────────────────────

  Widget _buildInfoPanel() {
    return Container(
      constraints: const BoxConstraints(minHeight: 460),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _kBorder.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Círculo decorativo inferior-derecha
          Positioned(
            bottom: -40,
            right: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Círculo decorativo superior-derecha
          Positioned(
            top: -30,
            right: 20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kBrand.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Contenido
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu espacio,\ntu IA',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: _kBrand,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 36),
                _buildFeatureRow(
                  circleBg: _kCircle1Bg,
                  icon: Icons.psychology,
                  iconColor: _kBrandDark,
                  label: 'IA diseñada para\nel bienestar',
                ),
                const SizedBox(height: 24),
                _buildFeatureRow(
                  circleBg: _kCircle2Bg,
                  icon: Icons.child_care,
                  iconColor: _kIconMuted,
                  label: 'Entornos sensoriales\nadaptativos',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required Color circleBg,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: circleBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: _kTextPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ── Tarjeta de formulario ─────────────────────────────────────────────────

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTabBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 36),
            child: _buildForm(),
          ),
        ],
      ),
    );
  }

  // ── Tab de navegación ─────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _kTabBg,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            // Tab: Iniciar Sesión (inactivo)
            Expanded(
              child: GestureDetector(
                onTap: () => context.go('/login'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    'Iniciar Sesión',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _kTextPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
            // Tab: Registrarse (activo)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: _kBorder.withValues(alpha: 0.4),
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
                child: Text(
                  'Registrarse',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kBrand,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Formulario ────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          _buildFieldLabel('Nombre Completo'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _nombreController,
            hint: 'Ej. Ana García',
            icon: Icons.person_outline,
            keyboardType: TextInputType.name,
            validator: _validateNombre,
          ),
          const SizedBox(height: 24),
          _buildFieldLabel('Correo Electrónico'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _correoController,
            hint: 'tu@email.com',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            validator: _validateCorreo,
          ),
          const SizedBox(height: 24),
          _buildFieldLabel('Contraseña'),
          const SizedBox(height: 6),
          _buildPasswordField(),
          const SizedBox(height: 32),
          _buildSubmitButton(),
          const SizedBox(height: 20),
          _buildTermsText(),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _kTextPrimary,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: _kTextPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          color: _kIconMuted.withValues(alpha: 0.7),
        ),
        prefixIcon: Icon(icon, color: _kIconMuted, size: 20),
        filled: true,
        fillColor: _kFieldBg.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kBrand.withValues(alpha: 0.6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kError, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kError, width: 1.5),
        ),
        errorStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: _kError,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _contrasenaController,
      obscureText: !_isPasswordVisible,
      validator: _validateContrasena,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: _kTextPrimary,
      ),
      decoration: InputDecoration(
        hintText: '••••••••',
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          color: _kIconMuted.withValues(alpha: 0.7),
        ),
        prefixIcon: const Icon(Icons.lock_outline, color: _kIconMuted, size: 20),
        suffixIcon: GestureDetector(
          onTap: () =>
              setState(() => _isPasswordVisible = !_isPasswordVisible),
          child: Icon(
            _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
            color: _isPasswordVisible ? _kBrand : _kIconMuted,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: _kFieldBg.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _kBrand.withValues(alpha: 0.6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kError, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _kError, width: 1.5),
        ),
        errorStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: _kError,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  // ── Botón principal ───────────────────────────────────────────────────────

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _onCrearCuenta,
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
          _isLoading ? 'Creando cuenta...' : 'Crear Cuenta',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        iconAlignment: IconAlignment.end,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBrand,
          disabledBackgroundColor: _kBrand.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
          shadowColor: _kBrand.withValues(alpha: 0.3),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) return 8;
            return 4;
          }),
          shadowColor: WidgetStateProperty.all(_kBrand.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  // ── Texto de términos ─────────────────────────────────────────────────────

  Widget _buildTermsText() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          color: _kTextPrimary,
        ),
        children: [
          const TextSpan(text: 'Al registrarte aceptas los '),
          TextSpan(
            text: 'Términos de Servicio',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kBrand,
            ),
          ),
          const TextSpan(text: ' y la '),
          TextSpan(
            text: 'Política de Privacidad',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kBrand,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sección 3: Footer ─────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildDot(opacity: 1.0),
              const SizedBox(width: 6),
              _buildDot(opacity: 0.6),
              const SizedBox(width: 6),
              _buildDot(opacity: 0.3),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'RIMAI © 2026',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kIconMuted.withValues(alpha: 0.6),
              letterSpacing: 2.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot({required double opacity}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kBrand.withValues(alpha: opacity),
      ),
    );
  }
}
