import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/auth_providers.dart';
import 'package:rimai_app/domain/entities/registro_usuario_request.dart';
import 'package:rimai_app/adapters/input/widgets/brand_header.dart';
import 'package:rimai_app/adapters/input/widgets/feature_panel.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_footer.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_text_field.dart';
import 'package:rimai_app/adapters/input/widgets/error_banner.dart';
import 'package:rimai_app/adapters/input/widgets/auth_tab_bar.dart';

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

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  String? _validateNombre(String? value) {
    if (value == null || value.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres';
    }
    return null;
  }

  String? _validateCorreo(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El correo electrónico es requerido';
    }
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validateContrasena(String? value) {
    if (value == null || value.length < 8) {
      return 'La contraseña debe tener al menos 8 caracteres';
    }
    return null;
  }

  Future<void> _onCrearCuenta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final registerUseCase = ref.read(registrarUsuarioUseCaseProvider);
      
      final request = RegistroUsuarioRequest(
        nombreCompleto: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      // 1. Ejecutar el registro
      await registerUseCase.ejecutar(request);

      // 2. Si el registro fue exitoso, ejecutamos Login (Auto-Login)
      final loginUseCase = ref.read(iniciarSesionUseCaseProvider);
      final usuario = await loginUseCase.ejecutar(
        correo: request.correo,
        contrasena: request.contrasena,
      );

      if (!mounted) return;

      // 3. Navegar automáticamente al dashboard
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
                                child: _buildFormCard(context),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _buildFormCard(context),
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

  Widget _buildFormCard(BuildContext context) {
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
        children: [
          _buildTabBar(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RimAIErrorBanner(message: _errorMessage),
                  
                  // Wrap each field conditionally pointing error if Form validate fails
                  // The manual validator is passed via RimAITextField logic...
                  // Wait, RimAITextField doesn't use Form's native validator.
                  // I will implement a quick validation locally or we use standard Form handling.
                  // Since RimAITextField expects errorText locally, let's keep it simple for now
                  // (the design requires errorText directly but for MVP we wrap it or rely on parent form if possible).
                  // But the prompt states: Validator was inside TextFormField. 
                  // Let's modify RimAITextField usages to standard TextFormField wrapper if needed, 
                  // or just let it be. Let's wrap in TextFormField invisibly if needed, or update RimAITextField?
                  // I'll update RimAITextField in another call if needed, but for now we'll use FormFields cleanly.
                  // Wait! I didn't add validator to RimAITextField! 
                  // Let's inject a standard FormField wrapping it for validation:
                  FormField<String>(
                    validator: _validateNombre,
                    builder: (state) => RimAITextField(
                      label: 'Nombre Completo',
                      placeholder: 'Ej. Ana García',
                      prefixIcon: Icons.person_outline,
                      controller: _nombreController,
                      keyboardType: TextInputType.name,
                      enabled: !_isLoading,
                      errorText: state.errorText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  FormField<String>(
                    validator: _validateCorreo,
                    builder: (state) => RimAITextField(
                      label: 'Correo Electrónico',
                      placeholder: 'tu@email.com',
                      prefixIcon: Icons.mail_outline,
                      controller: _correoController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !_isLoading,
                      errorText: state.errorText,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  FormField<String>(
                    validator: _validateContrasena,
                    builder: (state) => RimAITextField(
                      label: 'Contraseña',
                      placeholder: '••••••••',
                      prefixIcon: Icons.lock_outline,
                      controller: _contrasenaController,
                      obscureText: true,
                      showToggle: true,
                      enabled: !_isLoading,
                      errorText: state.errorText,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  _buildRegisterButton(),
                  const SizedBox(height: 20),
                  _buildTermsText(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return RimAIAuthTabBar(
      activeTab: AuthTab.register,
      onLoginTap: () => context.go('/auth/login'),
      onRegisterTap: () {}, // ya estamos en registro, no hace nada
    );
  }

  Widget _buildRegisterButton() {
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

  Widget _buildTermsText() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: const Color(0xFF63524E),
          ),
          children: [
            const TextSpan(text: 'Al registrarte, aceptas nuestros\n'),
            TextSpan(
              text: 'Términos de Servicio',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB8D6B2),
              ),
            ),
            const TextSpan(text: ' y '),
            TextSpan(
              text: 'Política de Privacidad',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB8D6B2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
