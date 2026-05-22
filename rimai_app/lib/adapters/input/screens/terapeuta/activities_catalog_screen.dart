import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);
const _kBorder = Color(0xFFDFC0B7);

class ActivitiesCatalogScreen extends ConsumerStatefulWidget {
  const ActivitiesCatalogScreen({super.key});

  @override
  ConsumerState<ActivitiesCatalogScreen> createState() =>
      _ActivitiesCatalogScreenState();
}

class _ActivitiesCatalogScreenState
    extends ConsumerState<ActivitiesCatalogScreen> {
  final _nombreCtrl = TextEditingController();
  final _materialesCtrl = TextEditingController();
  final _instruccionesCtrl = TextEditingController();
  String _categoria = 'Regulacion sensorial';
  String _dificultad = 'Medio';
  int _duracionMin = 10;
  String? _planId;
  bool _saving = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _materialesCtrl.dispose();
    _instruccionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_nombreCtrl.text.trim().isEmpty ||
        _instruccionesCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nombre e instrucciones son obligatorios.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(dashboardServiceProvider).crearActividad({
        'nombre': _nombreCtrl.text.trim(),
        'categoria': _categoria,
        'nivel_dificultad': _dificultad,
        'duracion_estimada': _duracionMin * 60,
        'materiales': _materialesCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'instrucciones': _instruccionesCtrl.text.trim(),
        if (_planId != null) 'plan_id': _planId,
      });
      ref.invalidate(actividadesCatalogoProvider(_planId));
      if (_planId != null) {
        ref.invalidate(planActivoProvider);
      }
      setState(() {
        _nombreCtrl.clear();
        _materialesCtrl.clear();
        _instruccionesCtrl.clear();
        _duracionMin = 10;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_planId == null
                ? 'Actividad registrada en el catalogo.'
                : 'Actividad registrada y asociada al plan.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _asociar(ActividadCatalogo actividad) async {
    if (_planId == null || actividad.asociado) return;
    try {
      await ref.read(dashboardServiceProvider).asociarActividadAPlan(
            planId: _planId!,
            actividadId: actividad.id,
          );
      ref.invalidate(actividadesCatalogoProvider(_planId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actividad asociada al plan activo.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    final actividades = ref.watch(actividadesCatalogoProvider(_planId));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: RimAITopBar(
        title: 'Actividades ocupacionales',
        leadingIcon: Icons.arrow_back_ios_new,
        onLeadingPressed: () => context.go('/terapeuta/dashboard'),
        iconColor: _kPrimary,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: _kPrimary,
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(actividadesCatalogoProvider(_planId));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurar actividades',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Registra intervenciones ocupacionales y asocialas a un plan activo.',
                  style: GoogleFonts.plusJakartaSans(
                    color: _kSubtext,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                _formCard(dashboard),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Text(
                      'Catalogo',
                      style: GoogleFonts.plusJakartaSans(
                        color: _kText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_planId != null)
                      Text(
                        'Plan seleccionado',
                        style: GoogleFonts.plusJakartaSans(
                          color: _kPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                actividades.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: _kPrimary),
                    ),
                  ),
                  error: (e, _) => _messageCard('No se pudieron cargar: $e'),
                  data: (items) {
                    if (items.isEmpty) {
                      return _messageCard(
                          'Aun no hay actividades registradas.');
                    }
                    return Column(
                      children: items
                          .map((a) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _activityCard(a),
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _formCard(AsyncValue<DashboardData> dashboard) {
    final planes = dashboard.valueOrNull?.pacientes
            .where((p) => p.planActivoId != null)
            .toList() ??
        [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nueva actividad',
            style: GoogleFonts.plusJakartaSans(
              color: _kText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nombreCtrl,
            decoration: _dec('Nombre de la actividad'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _categoria,
            items: const [
              'Regulacion sensorial',
              'Atencion conjunta',
              'Comunicacion social',
              'Motricidad fina',
              'Autonomia diaria',
              'Regulacion emocional',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _categoria = v ?? _categoria),
            decoration: _dec('Categoria'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _dificultad,
                  items: const ['Bajo', 'Medio', 'Alto']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _dificultad = v ?? _dificultad),
                  decoration: _dec('Dificultad'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: _duracionMin.toString(),
                  keyboardType: TextInputType.number,
                  decoration: _dec('Duracion (min)'),
                  onChanged: (v) =>
                      _duracionMin = int.tryParse(v) ?? _duracionMin,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _materialesCtrl,
            decoration: _dec('Materiales separados por coma'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instruccionesCtrl,
            minLines: 3,
            maxLines: 5,
            decoration: _dec('Instrucciones para la intervencion'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _planId,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Solo guardar en catalogo'),
              ),
              ...planes.map(
                (p) => DropdownMenuItem<String?>(
                  value: p.planActivoId,
                  child: Text('${p.nombre} - ${p.planActivo}'),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _planId = v),
            decoration: _dec('Asociacion a plan activo'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _guardar,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar actividad'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityCard(ActividadCatalogo a) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder.withOpacity(0.55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Expanded(
              child: Text(
                a.nombre,
                style: GoogleFonts.plusJakartaSans(
                  color: _kText,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            _pill(a.nivelDificultad),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${a.categoria} - ${(a.duracionEstimada / 60).round()} min',
          style: GoogleFonts.plusJakartaSans(
            color: _kSubtext,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (a.materiales.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Materiales: ${a.materiales.join(', ')}',
            style: GoogleFonts.plusJakartaSans(color: _kSubtext, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          a.instrucciones,
          style: GoogleFonts.plusJakartaSans(
            color: _kText,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (_planId != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: a.asociado ? null : () => _asociar(a),
              icon: Icon(a.asociado
                  ? Icons.check_circle_outline
                  : Icons.add_circle_outline),
              label: Text(a.asociado ? 'Asociada' : 'Asociar al plan'),
              style: OutlinedButton.styleFrom(
                foregroundColor: a.asociado ? _kSubtext : _kPrimary,
                side: BorderSide(color: a.asociado ? _kBorder : _kPrimary),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _messageCard(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: GoogleFonts.plusJakartaSans(color: _kSubtext)),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kAction,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            color: _kText,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.4),
        ),
      );
}
