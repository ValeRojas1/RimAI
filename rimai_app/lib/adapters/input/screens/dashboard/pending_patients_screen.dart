import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<bool?> _showVinculacionDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _kBg,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _kA.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.assignment_ind_outlined,
                  size: 40,
                  color: Color(0xFF4A624D),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Perfil Clínico Opcional',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '¿Deseas completar el perfil clínico detallado en este momento o prefieres utilizar directamente la información cargada por la familia?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: _kSub,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false), // No, omitir
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kSub,
                        side: const BorderSide(color: _kBdr),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Omitir / Usar del Padre',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true), // Sí, completar
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kP,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Completar Ahora',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _vincular() async {
    final p = widget.paciente;
    bool shouldEdit = true;

    if (!p.requiereScq) {
      final res = await _showVinculacionDialog(context);
      if (res == null) return; // canceló
      shouldEdit = res;
    }

    setState(() => _linking = true);
    try {
      if (shouldEdit) {
        // Vinculación normal y navegar a admisión
        await widget.ref.read(dashboardServiceProvider).vincularPorId(p.id, omitirPerfil: false);
        widget.ref.invalidate(pendientesProvider);
        if (mounted) {
          Navigator.pop(context);
          context.go('/terapeuta/admision?ninoId=${p.id}');
        }
      } else {
        // Vinculación omitiendo el perfil (se auto-infiere en backend)
        await widget.ref.read(dashboardServiceProvider).vincularPorId(p.id, omitirPerfil: true);
        widget.ref.invalidate(pendientesProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Paciente vinculado con éxito usando datos familiares.'),
              backgroundColor: Color(0xFF4A624D),
            ),
          );
          Navigator.pop(context);
        }
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

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBdr.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: _kBdr.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: _kP, size: 20),
          title: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              color: _kText,
              fontSize: 14,
            ),
          ),
          iconColor: _kP,
          collapsedIconColor: _kSub,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paciente;
    final fechaFmt = DateFormat('dd MMM yyyy').format(p.fechaRegistro);

    // 1. Hitos y Comunicación
    final hitos = p.hitos;
    final hWidgets = <Widget>[];
    if (hitos.isEmpty) {
      hWidgets.add(Text('No se registraron hitos del desarrollo.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)));
    } else {
      hitos.forEach((k, v) {
        hWidgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kText),
              children: [
                TextSpan(
                    text: '${k.toUpperCase().replaceAll('_', ' ')}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: '$v', style: GoogleFonts.plusJakartaSans(color: _kSub)),
              ],
            ),
          ),
        ));
      });
    }

    // 2. Perfil Sensorial Familiar
    final sens = p.sensorialFamilia;
    final aversivos = p.estimulosAversivos;
    final rutinas = p.rutinasRegulacion;
    final sWidgets = <Widget>[];
    if (sens.isNotEmpty) {
      sWidgets.add(Text('Comportamientos Sensoriales:',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)));
      sens.forEach((k, v) {
        sWidgets.add(Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 8.0),
          child: Text('• ${k.toUpperCase().replaceAll('_', ' ')}: $v',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)),
        ));
      });
    }
    if (aversivos.isNotEmpty) {
      if (sWidgets.isNotEmpty) sWidgets.add(const SizedBox(height: 12));
      sWidgets.add(Text('Estímulos Aversivos:',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)));
      aversivos.forEach((k, v) {
        sWidgets.add(Padding(
          padding: const EdgeInsets.only(left: 8.0, top: 4.0, bottom: 8.0),
          child: Text('• ${k.toUpperCase().replaceAll('_', ' ')}: $v',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)),
        ));
      });
    }
    if (rutinas.isNotEmpty) {
      if (sWidgets.isNotEmpty) sWidgets.add(const SizedBox(height: 12));
      sWidgets.add(Text('Rutinas de Regulación:',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)));
      sWidgets.add(Padding(
        padding: const EdgeInsets.only(left: 8.0, top: 4.0),
        child: Text(rutinas.join(', '), style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)),
      ));
    }
    if (sens.isEmpty && aversivos.isEmpty && rutinas.isEmpty) {
      sWidgets.add(Text('No se registraron datos sensoriales.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)));
    }

    // 3. Documentos Adjuntos
    final docs = p.documentosClinicos;
    final dWidgets = <Widget>[];
    if (docs.isEmpty || docs.values.every((v) => v == null || v.toString().isEmpty)) {
      dWidgets.add(Text('No se adjuntaron documentos clínicos.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)));
    } else {
      docs.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty) {
          final docUrl = v.toString();
          dWidgets.add(Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kSurf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBdr.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: _kP, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        k.replaceAll('_', ' ').toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _kText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Documento PDF',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: _kSub,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final uri = Uri.parse(docUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('No se pudo abrir el enlace: $docUrl'),
                            backgroundColor: Colors.red.shade800,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kP,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(
                    'Ver',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ));
        }
      });
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: _kBdr, borderRadius: BorderRadius.circular(2)),
          ),
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
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                // 1. Datos Generales y Tutor
                _sectionCard(
                  title: 'Datos Generales y Tutor',
                  icon: Icons.person_outline,
                  initiallyExpanded: true,
                  children: [
                    _row('Familia / Tutor', p.tutorNombre ?? 'No registrado'),
                    if (p.diagnostico != null) _row('Diagnóstico', p.diagnostico!),
                    _row('Medicación Actual', p.medicacionActual ?? 'Ninguna reportada'),
                    if (p.requiereScq) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0EC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kP.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.assignment_outlined, color: _kP, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Caso SCQ obligatorio · Puntaje: ${p.scqPuntaje ?? "Sin datos"} (${p.scqNivel ?? "Sin datos"})',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: _kP, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // 2. Hitos y Comunicación
                _sectionCard(
                  title: 'Hitos del Desarrollo y Comunicación',
                  icon: Icons.emoji_events_outlined,
                  children: hWidgets,
                ),

                // 3. Perfil Sensorial Familiar
                _sectionCard(
                  title: 'Perfil Sensorial Familiar',
                  icon: Icons.favorite_border_rounded,
                  children: sWidgets,
                ),

                // 4. Documentos del Expediente
                _sectionCard(
                  title: 'Documentos del Expediente',
                  icon: Icons.folder_open_outlined,
                  children: dWidgets,
                ),

                const SizedBox(height: 10),
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
                      p.requiereScq
                          ? 'Al vincular, deberás completar obligatoriamente el perfil clínico antes de generar el plan terapéutico.'
                          : 'Al vincular, podrás rellenar el perfil clínico ahora o utilizar el expediente familiar para generar el plan terapéutico con IA.',
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
              ],
            ),
          ),
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
