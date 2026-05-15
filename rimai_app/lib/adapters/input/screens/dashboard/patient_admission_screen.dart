import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kP = Color(0xFFA43714);
const _kA = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurf = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSub = Color(0xFF58423B);
const _kBdr = Color(0xFFDFC0B7);

/// Pantalla de admisión / enriquecimiento clínico.
///
/// Modo A — Enriquecimiento ([ninoId] != null):
///   El terapeuta ya vinculó al niño desde la bandeja de espera.
///   Aquí completa el perfil clínico (nivel cognitivo, objetivos, sensorial).
///
/// Modo B — Búsqueda ([ninoId] == null):
///   Flujo de búsqueda por nombre+fecha (fallback legacy).
class PatientAdmissionScreen extends ConsumerStatefulWidget {
  final String? ninoId;
  const PatientAdmissionScreen({Key? key, this.ninoId}) : super(key: key);

  @override
  ConsumerState<PatientAdmissionScreen> createState() =>
      _PatientAdmissionScreenState();
}

class _PatientAdmissionScreenState
    extends ConsumerState<PatientAdmissionScreen>
    with SingleTickerProviderStateMixin {
  // ── Modo B: búsqueda ───────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  DateTime? _selectedDate;
  late TabController _tabCtrl;

  // ── Compartido: datos clínicos ─────────────────────────────────────────────
  String _nivelCognitivo = 'Medio';
  final List<String> _objetivos = [];
  final _objCtrl = TextEditingController();
  final Set<String> _hiper = {};
  final Set<String> _hipo = {};
  final Set<String> _rep = {};
  final Set<String> _int = {};
  final _obsCtrl = TextEditingController();

  bool _saving = false;

  bool get _enrichMode => widget.ninoId != null;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dateCtrl.dispose();
    _tabCtrl.dispose();
    _objCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  void _tog(Set<String> s, String v) =>
      setState(() => s.contains(v) ? s.remove(v) : s.add(v));

  // ── Guardar perfil clínico (Modo A) ───────────────────────────────────────
  Future<void> _guardarPerfil() async {
    if (_objetivos.isEmpty) {
      _snack('Agrega al menos un objetivo de intervención.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(dashboardServiceProvider)
          .completarPerfilClinico(widget.ninoId!, {
        'nivel_cognitivo': _nivelCognitivo,
        'objetivos_intervencion': _objetivos,
        'perfil_sensorial': {
          'hipersensibilidad': _hiper.toList(),
          'hiposensibilidad': _hipo.toList(),
          'comportamientos_repetitivos': _rep.toList(),
          'intereses_obsesivos': _int.toList(),
        },
        if (_obsCtrl.text.trim().isNotEmpty)
          'observaciones_clinicas': _obsCtrl.text.trim(),
      });

      ref.invalidate(dashboardProvider);
      ref.invalidate(pendientesProvider);

      final estado = result['estado_clinico'] as String? ?? '';
      final msg = estado == 'listo_para_plan'
          ? '✅ Perfil completo. Paciente listo para generar plan.'
          : '💾 Perfil guardado. ${result['mensaje'] ?? ''}';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: estado == 'listo_para_plan'
                ? const Color(0xFF4A624D)
                : const Color(0xFF5C4A00),
            duration: const Duration(seconds: 4),
          ),
        );
        context.go('/terapeuta/nino/${widget.ninoId}');
      }
    } catch (e) {
      _snack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Vincular por nombre+fecha (Modo B — legacy) ────────────────────────────
  Future<void> _vincularLegacy() async {
    if (_nameCtrl.text.trim().isEmpty || _selectedDate == null) {
      _snack('Nombre y fecha son obligatorios.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(dashboardServiceProvider).vincularPaciente({
        'nombre': _nameCtrl.text.trim(),
        'fecha_nacimiento': _dateCtrl.text,
        'nivel_cognitivo': _nivelCognitivo,
        'objetivos_intervencion': _objetivos,
        'perfil_sensorial': {
          'hipersensibilidad': _hiper.toList(),
          'hiposensibilidad': _hipo.toList(),
          'comportamientos_repetitivos': _rep.toList(),
          'intereses_obsesivos': _int.toList(),
        },
      });
      ref.invalidate(dashboardProvider);
      if (mounted) {
        _snack('✓ Paciente vinculado exitosamente.');
        context.go('/terapeuta/dashboard');
      }
    } catch (e) {
      _snack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 365 * 6)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kP, onPrimary: Colors.white, onSurface: _kText),
        ),
        child: child!,
      ),
    );
    if (p != null) {
      setState(() {
        _selectedDate = p;
        _dateCtrl.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade800 : const Color(0xFF4A624D),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return _enrichMode ? _buildEnrichMode() : _buildSearchMode();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODO A — ENRIQUECIMIENTO CLÍNICO
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildEnrichMode() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _kText, size: 18),
          onPressed: () => context.go('/terapeuta/pendientes'),
        ),
        title: Text('Perfil clínico',
            style: GoogleFonts.plusJakartaSans(color: _kText, fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      body: SafeArea(
        child: Column(children: [
          // Info banner
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kA.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.link_rounded, color: Color(0xFF4A624D), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Paciente vinculado. Completa el perfil clínico para generar el plan.',
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kText),
              )),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(children: [
              _clinicalCard(),
              const SizedBox(height: 16),
              _sensorialCard(),
              const SizedBox(height: 16),
              _obsCard(),
            ]),
          )),
          // Bottom save button
          _saveBar(onPressed: _guardarPerfil, label: 'Guardar perfil clínico'),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MODO B — BÚSQUEDA (legacy)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildSearchMode() {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _kText, size: 18),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
        title: Text('Vincular paciente',
            style: GoogleFonts.plusJakartaSans(color: _kText, fontWeight: FontWeight.bold, fontSize: 17)),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _kP,
          unselectedLabelColor: _kSub,
          indicatorColor: _kP,
          tabs: const [Tab(text: 'Búsqueda'), Tab(text: 'Perfil clínico')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_searchTab(), _clinicalTab()],
      ),
    );
  }

  Widget _searchTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label('NOMBRE DEL PACIENTE'),
        _field('Nombre completo', _nameCtrl),
        const SizedBox(height: 16),
        _label('FECHA DE NACIMIENTO'),
        InkWell(
          onTap: _pickDate,
          child: IgnorePointer(child: TextFormField(
            controller: _dateCtrl,
            decoration: _dec('Seleccionar fecha', icon: Icons.calendar_today),
          )),
        ),
      ])),
      const SizedBox(height: 24),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: () => _tabCtrl.animateTo(1),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kA, foregroundColor: _kText,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Text('Continuar con perfil clínico →',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
      )),
    ]),
  );

  Widget _clinicalTab() => Column(children: [
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _clinicalCard(),
        const SizedBox(height: 16),
        _sensorialCard(),
        const SizedBox(height: 16),
        _obsCard(),
      ]),
    )),
    _saveBar(onPressed: _vincularLegacy, label: 'Vincular paciente'),
  ]);

  // ── Secciones del formulario clínico ─────────────────────────────────────
  Widget _clinicalCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Datos clínicos', style: GoogleFonts.plusJakartaSans(
        fontSize: 15, fontWeight: FontWeight.bold, color: _kText)),
    const SizedBox(height: 16),
    _label('NIVEL COGNITIVO'),
    Row(children: ['Bajo', 'Medio', 'Alto'].map((v) {
      final sel = v == _nivelCognitivo;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: ChoiceChip(
          label: Text(v),
          selected: sel,
          onSelected: (_) => setState(() => _nivelCognitivo = v),
          selectedColor: _kA,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(color: sel ? _kA : _kBdr)),
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13, color: _kText),
        ),
      );
    }).toList()),
    const SizedBox(height: 20),
    _label('OBJETIVOS DE INTERVENCIÓN'),
    Row(children: [
      Expanded(child: TextFormField(
        controller: _objCtrl,
        decoration: _dec('Agregar objetivo...'),
        style: GoogleFonts.plusJakartaSans(fontSize: 13),
        onFieldSubmitted: (_) => _addObjetivo(),
      )),
      const SizedBox(width: 8),
      IconButton(
        onPressed: _addObjetivo,
        icon: const Icon(Icons.add_circle_rounded, color: _kP),
      ),
    ]),
    if (_objetivos.isNotEmpty) ...[
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: _objetivos.map((o) => Chip(
        label: Text(o, style: GoogleFonts.plusJakartaSans(fontSize: 12)),
        backgroundColor: _kA.withOpacity(0.2),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: () => setState(() => _objetivos.remove(o)),
      )).toList()),
    ],
  ]));

  void _addObjetivo() {
    final v = _objCtrl.text.trim();
    if (v.isNotEmpty && !_objetivos.contains(v)) {
      setState(() { _objetivos.add(v); _objCtrl.clear(); });
    }
  }

  Widget _sensorialCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Perfil sensorial', style: GoogleFonts.plusJakartaSans(
        fontSize: 15, fontWeight: FontWeight.bold, color: _kText)),
    const SizedBox(height: 16),
    _multiChips('HIPERSENSIBILIDAD (evita)',
        ['Ruidos fuertes', 'Texturas ásperas', 'Luces brillantes', 'Multitudes'], _hiper),
    const SizedBox(height: 14),
    _multiChips('HIPOSENSIBILIDAD (busca)',
        ['Movimiento constante', 'Presión profunda', 'Morder objetos'], _hipo),
    const SizedBox(height: 14),
    _multiChips('COMPORTAMIENTOS REPETITIVOS',
        ['Aleteo', 'Balanceo', 'Ecolalia', 'Alinear objetos', 'Puntillas'], _rep),
    const SizedBox(height: 14),
    _multiChips('INTERESES PRINCIPALES',
        ['Dinosaurios', 'Trenes', 'Música', 'Números', 'Animales', 'Arte'], _int),
  ]));

  Widget _obsCard() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _label('OBSERVACIONES CLÍNICAS (opcional)'),
    TextFormField(
      controller: _obsCtrl,
      maxLines: 4,
      decoration: _dec('Notas clínicas relevantes para el plan...'),
      style: GoogleFonts.plusJakartaSans(fontSize: 13),
    ),
  ]));

  // ── Widget helpers ────────────────────────────────────────────────────────
  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: _kSurf, borderRadius: BorderRadius.circular(18)),
    child: child,
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.plusJakartaSans(
        fontSize: 11, fontWeight: FontWeight.bold, color: _kSub, letterSpacing: 0.5)),
  );

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    suffixIcon: icon != null ? Icon(icon, color: _kP, size: 18) : null,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kP, width: 1.5)),
    contentPadding: const EdgeInsets.all(14),
    hintStyle: TextStyle(color: _kSub.withOpacity(0.5), fontSize: 13),
  );

  Widget _field(String hint, TextEditingController ctrl) => TextFormField(
    controller: ctrl,
    decoration: _dec(hint),
    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
  );

  Widget _multiChips(String label, List<String> opts, Set<String> sel) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(label),
      Wrap(spacing: 8, runSpacing: 6, children: opts.map((o) {
        final s = sel.contains(o);
        return FilterChip(
          label: Text(o),
          selected: s,
          onSelected: (_) => _tog(sel, o),
          selectedColor: _kA,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(color: s ? _kA : _kBdr)),
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12, color: _kText),
          checkmarkColor: _kText,
        );
      }).toList()),
    ],
  );

  Widget _saveBar({required VoidCallback onPressed, required String label}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: _kBg,
          border: Border(top: BorderSide(color: _kBdr.withOpacity(0.5))),
        ),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kP, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(label, style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      );
}
