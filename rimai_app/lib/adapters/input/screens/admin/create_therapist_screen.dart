import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/admin_providers.dart';

class CreateTherapistScreen extends ConsumerStatefulWidget {
  const CreateTherapistScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CreateTherapistScreen> createState() => _CreateTherapistScreenState();
}

class _CreateTherapistScreenState extends ConsumerState<CreateTherapistScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Datos Generales
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  
  // Datos Profesionales
  final _especialidadCtrl = TextEditingController();
  final _colegiaturaCtrl = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _especialidadCtrl.dispose();
    _colegiaturaCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarTerapeuta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(adminServiceProvider).crearUsuario(
        _nombreCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
        'terapeuta',
        especialidad: _especialidadCtrl.text.trim(),
        colegiatura: _colegiaturaCtrl.text.trim(),
      );

      ref.invalidate(listaUsuariosProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terapeuta creado exitosamente'), backgroundColor: Color(0xFF4A624D)),
        );
        context.pop(); // Volver al dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E1B16)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Alta de Terapeuta',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF1E1B16),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Datos Generales',
                style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFA43714)),
              ),
              const SizedBox(height: 16),
              _buildTextField('Nombre Completo', 'Ej. Dra. Ana López', _nombreCtrl, icon: Icons.person, isRequired: true),
              const SizedBox(height: 16),
              _buildTextField('Correo Electrónico', 'ana@rimai.com', _emailCtrl, icon: Icons.email, isRequired: true, keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),
              _buildTextField('Contraseña Temporal', 'Mínimo 6 caracteres', _passwordCtrl, icon: Icons.lock, isRequired: true, obscureText: true),
              
              const SizedBox(height: 32),
              
              Text(
                'Datos Profesionales',
                style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFFA43714)),
              ),
              const SizedBox(height: 16),
              _buildTextField('Especialidad', 'Ej. Terapia Ocupacional, Fonoaudiología', _especialidadCtrl, icon: Icons.medical_services, isRequired: true),
              const SizedBox(height: 16),
              _buildTextField('Número de Colegiatura / Licencia', 'Ej. CBP-12345', _colegiaturaCtrl, icon: Icons.badge, isRequired: true),

              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _guardarTerapeuta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB8D6B2),
                    foregroundColor: const Color(0xFF1E1B16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator(color: Color(0xFF1E1B16))
                      : Text('Crear Terapeuta', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, {required IconData icon, bool isRequired = false, bool obscureText = false, TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF58423B))),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFFA43714).withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFA43714), width: 2)),
            contentPadding: const EdgeInsets.all(16),
          ),
          validator: (value) {
            if (isRequired && (value == null || value.trim().isEmpty)) {
              return 'Este campo es obligatorio';
            }
            return null;
          },
        ),
      ],
    );
  }
}
