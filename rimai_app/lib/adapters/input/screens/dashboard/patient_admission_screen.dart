import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/dashboard_providers.dart';

class PatientAdmissionScreen extends ConsumerStatefulWidget {
  const PatientAdmissionScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PatientAdmissionScreen> createState() => _PatientAdmissionScreenState();
}

class _PatientAdmissionScreenState extends ConsumerState<PatientAdmissionScreen> with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _dateController = TextEditingController();
  DateTime? _selectedDate;
  late TabController _tabController;
  bool _isSaving = false;

  // Datos Clínicos
  String _nivelCognitivo = 'Medio';
  final List<String> _objetivos = [];
  final _objetivoController = TextEditingController();

  // Perfil Sensorial (IA)
  final Set<String> _hipersensibilidad = {};
  final Set<String> _hiposensibilidad = {};
  final Set<String> _comportamientosRepetitivos = {};
  final Set<String> _interesesObsesivos = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _tabController.dispose();
    _objetivoController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 6)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFA43714),
              onPrimary: Colors.white,
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

  void _addObjetivo() {
    if (_objetivoController.text.trim().isNotEmpty) {
      setState(() {
        _objetivos.add(_objetivoController.text.trim());
        _objetivoController.clear();
      });
    }
  }

  void _removeObjetivo(String obj) {
    setState(() => _objetivos.remove(obj));
  }

  void _toggleSet(Set<String> set, String item) {
    setState(() {
      if (set.contains(item)) set.remove(item);
      else set.add(item);
    });
  }

  Future<void> _vincularPaciente() async {
    final nombre = _nameController.text.trim();
    if (nombre.isEmpty || _selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor ingresa el nombre exacto y la fecha de nacimiento para buscar.')));
      return;
    }

    if (_objetivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor agrega al menos un objetivo de intervención.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final datos = {
        "nombre": nombre,
        "fecha_nacimiento": _dateController.text,
        "nivel_cognitivo": _nivelCognitivo,
        "objetivos_intervencion": _objetivos,
        "perfil_sensorial": {
          "hipersensibilidad": _hipersensibilidad.toList(),
          "hiposensibilidad": _hiposensibilidad.toList(),
          "comportamientos_repetitivos": _comportamientosRepetitivos.toList(),
          "intereses_obsesivos": _interesesObsesivos.toList(),
        }
      };

      await ref.read(dashboardServiceProvider).vincularPaciente(datos);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paciente vinculado y enriquecido exitosamente.'), backgroundColor: Color(0xFF4A624D)),
        );
        ref.invalidate(dashboardProvider);
        context.go('/terapeuta/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')), 
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E1B16)),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 80 + MediaQuery.of(context).padding.top, left: 24, right: 24, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Admisión Clínica', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, color: const Color(0xFF1E1B16))),
                      const SizedBox(height: 8),
                      Text('Encuentra el expediente creado por el familiar y añade tus parámetros clínicos.', style: GoogleFonts.plusJakartaSans(fontSize: 16, color: const Color(0xFF58423B).withOpacity(0.8))),
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
                    _buildBusquedaTab(),
                    _buildClinicoTab(),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 24, left: 24, right: 24,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _vincularPaciente,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA43714),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              icon: _isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.person_add_alt_1),
              label: Text(
                _isSaving ? 'Buscando y Vinculando...' : 'Vincular Paciente',
                style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
          Tab(text: "1. Búsqueda"),
          Tab(text: "2. Clínica IA"),
        ],
      ),
    );
  }

  Widget _buildBusquedaTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 100),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFFFAF2E9), borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.search, color: Color(0xFFA43714), size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text('Identificación Exacta', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16)))),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFA43714), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('El niño debe estar previamente registrado por un familiar en la aplicación.', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF58423B))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildTextField('NOMBRE EXACTO DEL PACIENTE', 'Ej: Mateo García', _nameController),
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
    );
  }

  Widget _buildClinicoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 100),
      child: Column(
        children: [
          // Nivel Cognitivo y Objetivos
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFFE5DCC4).withOpacity(0.3), borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parámetros de Intervención', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16))),
                const SizedBox(height: 24),
                _buildSingleChoiceSection('NIVEL COGNITIVO', ['Bajo', 'Medio', 'Alto'], _nivelCognitivo, (v) => setState(() => _nivelCognitivo = v)),
                const SizedBox(height: 24),
                Text('OBJETIVOS DE TERAPIA', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF58423B).withOpacity(0.6))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _objetivos.map((obj) => Chip(
                    label: Text(obj, style: const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.white,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _removeObjetivo(obj),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: const BorderSide(color: Color(0xFFDFC0B7))),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _objetivoController,
                        decoration: InputDecoration(
                          hintText: 'Añadir objetivo...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _addObjetivo(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _addObjetivo,
                      icon: const Icon(Icons.add_circle, color: Color(0xFFA43714), size: 36),
                    )
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Perfil Sensorial (IA)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: const Color(0xFFF5EDE4), borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.visibility, color: Color(0xFFA43714), size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Perfil Sensorial Clínico (Ajuste IA)', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E1B16)))),
                  ],
                ),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('HIPERSENSIBILIDAD (EVITA)', ['Ruidos fuertes', 'Texturas ásperas', 'Luces brillantes', 'Multitudes', 'Etiquetas'], _hipersensibilidad),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('HIPOSENSIBILIDAD (BUSCA)', ['Dolor', 'Movimiento constante', 'Presión profunda', 'Morder objetos'], _hiposensibilidad),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('COMPORTAMIENTOS REPETITIVOS', ['Aleteo de manos', 'Balanceo', 'Ecolalia', 'Alinear juguetes', 'Caminar de puntillas'], _comportamientosRepetitivos),
                const SizedBox(height: 24),
                _buildMultiChoiceSection('INTERESES OBSESIVOS', ['Dinosaurios', 'Trenes', 'Espacio', 'Geometría', 'Números', 'Ninguno'], _interesesObsesivos),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
}
