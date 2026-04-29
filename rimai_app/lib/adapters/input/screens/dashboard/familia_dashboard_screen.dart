import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

class FamiliaDashboardScreen extends ConsumerStatefulWidget {
  const FamiliaDashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<FamiliaDashboardScreen> createState() => _FamiliaDashboardScreenState();
}

class _FamiliaDashboardScreenState extends ConsumerState<FamiliaDashboardScreen> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _dateController = TextEditingController(); // Controlador visual para la fecha
  DateTime? _selectedDate; // Fecha real seleccionada
  late TabController _tabController;
  bool _isDataLoaded = false;
  bool _isSaving = false;

  // ML Features: Desarrollo
  String _comunicacion = 'Palabras sueltas';
  String _contactoVisual = 'Intermitente';
  String _juegoSocial = 'Paralelo';
  final Set<String> _motricidad = {};

  // ML Features: Sensorial e Intereses
  final Set<String> _hipersensibilidad = {};
  final Set<String> _hiposensibilidad = {};
  final Set<String> _comportamientosRepetitivos = {};
  final Set<String> _interesesObsesivos = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSet(Set<String> set, String item) {
    setState(() {
      if (set.contains(item)) set.remove(item);
      else set.add(item);
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 6)), // 6 años por defecto
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFB8D6B2),
              onPrimary: Color(0xFF1E1B16),
              onSurface: Color(0xFF1E1B16),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(familiaDashboardProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      body: dashboardState.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFB8D6B2))),
        error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
        data: (data) {
          if (data.pacientes.isNotEmpty && !_isDataLoaded) {
            final paciente = data.pacientes.first;
            _nameController.text = paciente.nombre;
            // Solo para mostrar visualmente, el backend no mandó la fecha en el MVP, pero si la tuviera se asignaría aquí.
            _dateController.text = 'Registrado (${paciente.edad} años)'; 
            _isDataLoaded = true;
          }

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildTabBar(),
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildBasicoTab(),
                        _buildDesarrolloTab(),
                        _buildSensorialTab(),
                      ],
                    ),
                  ),
                ],
              ),
              _buildBottomNav(context),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 100.0),
        child: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _guardarPerfilML,
          backgroundColor: const Color(0xFFB8D6B2),
          icon: _isSaving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF1E1B16), strokeWidth: 2))
            : const Icon(Icons.psychology, color: Color(0xFF1E1B16)),
          label: Text(
            _isSaving ? 'Analizando...' : 'Guardar y Analizar',
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF1E1B16), fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Future<void> _guardarPerfilML() async {
    final nombre = _nameController.text.trim();
    
    if (nombre.isEmpty || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor ingresa el nombre y selecciona la fecha de nacimiento.')));
      return;
    }

    final fechaStr = _dateController.text;

    setState(() => _isSaving = true);

    try {
      final datos = {
        "nombre": nombre,
        "fecha_nacimiento": fechaStr,
        "hitos": {
          "comunicacion": _comunicacion,
          "contacto_visual": _contactoVisual,
          "juego_social": _juegoSocial,
          "motricidad": _motricidad.toList(),
        },
        "sensorial": {
          "hipersensibilidad": _hipersensibilidad.toList(),
          "hiposensibilidad": _hiposensibilidad.toList(),
          "comportamientos_repetitivos": _comportamientosRepetitivos.toList(),
          "intereses_obsesivos": _interesesObsesivos.toList(),
        }
      };

      await ref.read(dashboardServiceProvider).guardarPerfilNino(datos);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos guardados exitosamente para el modelo ML.'), backgroundColor: Color(0xFF4A624D)),
        );
        ref.invalidate(familiaDashboardProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- UI Components ---

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5EDE4),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        labelColor: const Color(0xFFA43714),
        unselectedLabelColor: const Color(0xFF58423B).withOpacity(0.6),
        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
        tabs: const [
          Tab(text: "Básico"),
          Tab(text: "Desarrollo"),
          Tab(text: "Sensorial"),
        ],
      ),
    );
  }

  Widget _buildBasicoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 200),
      child: Column(
        children: [
          _buildCard(
            backgroundColor: const Color(0xFFFAF2E9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.badge, color: Color(0xFFB8D6B2), size: 32),
                    const SizedBox(width: 12),
                    Text('Datos del Paciente', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16))),
                  ],
                ),
                const SizedBox(height: 32),
                _buildTextField('NOMBRE DEL PACIENTE', 'Ej: Mateo García', _nameController),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text('FECHA DE NACIMIENTO', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16).withOpacity(0.5))),
                    ),
                    InkWell(
                      onTap: () => _selectDate(context),
                      child: IgnorePointer(
                        child: TextFormField(
                          controller: _dateController,
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'Seleccionar fecha',
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFFA43714)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesarrolloTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 200),
      child: Column(
        children: [
          _buildCard(
            backgroundColor: const Color(0xFFFAF2E9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.escalator_warning, color: Color(0xFFB8D6B2), size: 32),
                    const SizedBox(width: 12),
                    Text('Hitos del Desarrollo', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16))),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSingleChoiceSection('NIVEL DE COMUNICACIÓN', ['No verbal', 'Palabras sueltas', 'Frases cortas', 'Fluido'], _comunicacion, (v) => setState(() => _comunicacion = v)),
                const SizedBox(height: 24),
                _buildSingleChoiceSection('CONTACTO VISUAL', ['Nulo', 'Intermitente', 'Sostenido'], _contactoVisual, (v) => setState(() => _contactoVisual = v)),
                const SizedBox(height: 24),
                _buildSingleChoiceSection('JUEGO SOCIAL', ['Aislado', 'Paralelo', 'Interactúa'], _juegoSocial, (v) => setState(() => _juegoSocial = v)),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('MOTRICIDAD', ['Camina solo', 'Sube escaleras', 'Pinza fina', 'Corre'], _motricidad),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorialTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 200),
      child: Column(
        children: [
          _buildCard(
            backgroundColor: const Color(0xFFF5EDE4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.visibility, color: Color(0xFFA43714), size: 32),
                    const SizedBox(width: 12),
                    Text('Perfil Clínico (IA)', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16))),
                  ],
                ),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('HIPERSENSIBILIDAD (EVITA)', ['Ruidos fuertes', 'Texturas ásperas', 'Luces brillantes', 'Multitudes', 'Etiquetas'], _hipersensibilidad),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('HIPOSENSIBILIDAD (BUSCA)', ['Dolor', 'Movimiento constante', 'Presión profunda', 'Morder objetos'], _hiposensibilidad),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('COMPORTAMIENTOS REPETITIVOS', ['Aleteo de manos', 'Balanceo', 'Ecolalia', 'Alinear juguetes', 'Caminar de puntillas'], _comportamientosRepetitivos),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('INTERESES OBSESIVOS', ['Dinosaurios', 'Trenes', 'Espacio', 'Formas geométricas', 'Números', 'Ninguno'], _interesesObsesivos),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Helpers ---

  Widget _buildSingleChoiceSection(String title, List<String> options, String currentValue, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF58423B).withOpacity(0.6))),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected = opt == currentValue;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: (val) { if (val) onChanged(opt); },
              selectedColor: const Color(0xFFB8D6B2),
              backgroundColor: Colors.white,
              labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF1E1B16) : const Color(0xFF58423B)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: Colors.transparent)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMultiChoiceSection(String title, List<String> options, Set<String> currentSet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF58423B).withOpacity(0.6))),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected = currentSet.contains(opt);
            return FilterChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: (_) => _toggleSet(currentSet, opt),
              selectedColor: const Color(0xFFB8D6B2),
              backgroundColor: Colors.white,
              labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFF1E1B16) : const Color(0xFF58423B)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: Colors.transparent)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child, required Color backgroundColor}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(24)),
      child: child,
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16).withOpacity(0.5))),
        ),
        TextFormField(
          controller: controller,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFB8D6B2), width: 2)),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      floating: false,
      expandedHeight: 80.0,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFFFF8F2).withOpacity(0.7)),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.all_inclusive, color: Color(0xFFA43714), size: 28),
                        const SizedBox(width: 12),
                        Text('RimAI', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFA43714), fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Perfil Clínico (IA)', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: const Color(0xFF1E1B16))),
        const SizedBox(height: 8),
        Text('Ingresa los datos para alimentar el motor de IA terapéutica.', style: GoogleFonts.plusJakartaSans(fontSize: 16, color: const Color(0xFF58423B).withOpacity(0.8))),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F2),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(48), topRight: Radius.circular(48)),
          boxShadow: [BoxShadow(color: const Color(0xFF58423B).withOpacity(0.06), blurRadius: 30, offset: const Offset(0, -8))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(Icons.person, 'Perfil', true, () {}),
            _buildNavItem(Icons.psychology, 'Terapia', false, () {}),
            IconButton(
              icon: const Icon(Icons.logout, color: Color(0xFF58423B)),
              onPressed: () async {
                await ref.read(authStorageProvider).clearSession();
                if (context.mounted) context.go('/auth/login');
              },
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(color: isActive ? const Color(0xFFB8D6B2) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? const Color(0xFF1E1B16) : const Color(0xFF1E1B16).withOpacity(0.5)),
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? const Color(0xFF1E1B16) : const Color(0xFF1E1B16).withOpacity(0.5))),
          ],
        ),
      ),
    );
  }
}
