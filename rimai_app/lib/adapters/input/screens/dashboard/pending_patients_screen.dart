import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kP = Color(0xFFA43714);
const _kA = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurf = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSub = Color(0xFF58423B);
const _kBdr = Color(0xFFDFC0B7);

class PendingPatientsScreen extends ConsumerWidget {
  const PendingPatientsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendientesProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _kText, size: 18),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
        title: Text(
          'Solicitudes pendientes',
          style: GoogleFonts.plusJakartaSans(
              color: _kText, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _kSub),
            onPressed: () => ref.invalidate(pendientesProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kP)),
        error: (e, _) => _buildError(context, ref, e.toString()),
        data: (list) => list.isEmpty ? _buildEmpty() : _buildList(context, ref, list),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _kA.withOpacity(0.2), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_outline_rounded, size: 56, color: Color(0xFF4A624D)),
      ),
      const SizedBox(height: 20),
      Text('Sin solicitudes pendientes',
          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: _kText)),
      const SizedBox(height: 8),
      Text('Todas las solicitudes han sido atendidas.',
          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _kSub)),
    ]),
  );

  Widget _buildError(BuildContext context, WidgetRef ref, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_rounded, size: 56, color: _kSub),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(color: _kSub), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () => ref.invalidate(pendientesProvider),
        style: ElevatedButton.styleFrom(backgroundColor: _kA, foregroundColor: _kText),
        child: const Text('Reintentar'),
      ),
    ]),
  );

  Widget _buildList(BuildContext context, WidgetRef ref, List<NinoPendiente> list) {
    return RefreshIndicator(
      color: _kP,
      onRefresh: () async => ref.invalidate(pendientesProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Header informativo
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDE8E8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: _kP, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                '${list.length} ${list.length == 1 ? "niño espera" : "niños esperan"} ser vinculado${list.length == 1 ? "" : "s"} a un terapeuta.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kText, fontWeight: FontWeight.w600),
              )),
            ]),
          ),
          ...list.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PendingCard(
              paciente: p,
              onAceptar: () => _showDetailSheet(context, ref, p),
            ),
          )),
        ],
      ),
    );
  }

  void _showDetailSheet(BuildContext context, WidgetRef ref, NinoPendiente p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(paciente: p, ref: ref),
    );
  }
}

// ── Pending card ──────────────────────────────────────────────────────────────
class _PendingCard extends StatelessWidget {
  final NinoPendiente paciente;
  final VoidCallback onAceptar;

  const _PendingCard({required this.paciente, required this.onAceptar});

  @override
  Widget build(BuildContext context) {
    final diasEspera = DateTime.now().difference(paciente.fechaRegistro).inDays;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBdr.withOpacity(0.6)),
        boxShadow: [BoxShadow(color: _kBdr.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFFDE8E8),
              child: Text(paciente.nombre[0].toUpperCase(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kP)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(paciente.nombre,
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: _kText)),
              const SizedBox(height: 2),
              Text('${paciente.edad} años${paciente.diagnostico != null ? " · ${paciente.diagnostico}" : ""}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kSub)),
            ])),
            // Días esperando
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$diasEspera', style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w900, color: diasEspera > 3 ? _kP : _kSub)),
              Text('días', style: GoogleFonts.plusJakartaSans(fontSize: 10, color: _kSub)),
            ]),
          ]),
          const SizedBox(height: 14),
          // Info rápida
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (paciente.tutorNombre != null)
              _chip(Icons.person_outline, 'Familia: ${paciente.tutorNombre!}'),
            if (paciente.comunicacion != null)
              _chip(Icons.record_voice_over_outlined, paciente.comunicacion!),
            if (paciente.intereses.isNotEmpty)
              _chip(Icons.star_outline, paciente.intereses.take(2).join(', ')),
          ]),
          const SizedBox(height: 14),
          // Acciones
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: onAceptar,
              style: OutlinedButton.styleFrom(
                foregroundColor: _kP,
                side: const BorderSide(color: _kP),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text('Ver expediente',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: onAceptar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kP,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                elevation: 0,
              ),
              child: Text('Vincular',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13)),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _kSurf,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: _kBdr.withOpacity(0.5)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: _kSub),
      const SizedBox(width: 5),
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: _kSub, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────
class _DetailSheet extends ConsumerStatefulWidget {
  final NinoPendiente paciente;
  final WidgetRef ref;

  const _DetailSheet({required this.paciente, required this.ref});

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  bool _linking = false;

  Future<void> _vincular() async {
    setState(() => _linking = true);
    try {
      // 1. Vincular en backend → estado pasa a perfil_clinico_incompleto
      await widget.ref.read(dashboardServiceProvider).vincularPorId(widget.paciente.id);
      // 2. Refrescar bandeja de espera
      widget.ref.invalidate(pendientesProvider);
      // 3. Navegar a la pantalla de enriquecimiento clínico
      if (mounted) {
        Navigator.pop(context);
        context.go('/terapeuta/admision?ninoId=${widget.paciente.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paciente;
    final fechaFmt = DateFormat('dd MMM yyyy').format(p.fechaRegistro);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
              decoration: BoxDecoration(color: _kBdr, borderRadius: BorderRadius.circular(2))),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFFDE8E8),
                child: Text(p.nombre[0].toUpperCase(),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kP)),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.nombre, style: GoogleFonts.plusJakartaSans(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _kText)),
                Text('${p.edad} años · Registrado el $fechaFmt',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kSub)),
              ])),
            ]),
          ),
          const Divider(height: 28, indent: 24, endIndent: 24),
          // Content
          Expanded(child: ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
            _row('Familia / Tutor', p.tutorNombre ?? 'No registrado'),
            if (p.diagnostico != null) _row('Diagnóstico', p.diagnostico!),
            if (p.comunicacion != null) _row('Comunicación', p.comunicacion!),
            if (p.intereses.isNotEmpty) _row('Intereses', p.intereses.join(', ')),
            const SizedBox(height: 20),
            // Aviso
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kA.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: Color(0xFF4A624D), size: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Al vincular, podrás completar el perfil clínico y luego generar el plan terapéutico con IA.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kText),
                )),
              ]),
            ),
            const SizedBox(height: 24),
            // Acciones
            ElevatedButton.icon(
              onPressed: _linking ? null : _vincular,
              icon: _linking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.link_rounded),
              label: Text(_linking ? 'Vinculando...' : 'Aceptar y vincular paciente',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kP,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kSub,
                side: const BorderSide(color: _kBdr),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Cerrar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(label,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub))),
      Expanded(child: Text(value,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: _kText))),
    ]),
  );
}
