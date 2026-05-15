import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/tag_chip.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class ClinicalValidationScreen extends ConsumerStatefulWidget {
  final String ninoId;
  const ClinicalValidationScreen({super.key, required this.ninoId});

  @override
  ConsumerState<ClinicalValidationScreen> createState() =>
      _ClinicalValidationScreenState();
}

class _ClinicalValidationScreenState
    extends ConsumerState<ClinicalValidationScreen> {
  String _selectedFilter = 'PENDIENTE';

  @override
  Widget build(BuildContext context) {
    final recomendaciones = ref.watch(recomendacionesProvider);
    final countPendientes =
        recomendaciones.where((r) => r.estado == 'PENDIENTE').length;
    final countAceptadas = recomendaciones
        .where((r) => r.estado == 'ACEPTADA' || r.estado == 'MODIFICADA')
        .length;
    final countRechazadas =
        recomendaciones.where((r) => r.estado == 'RECHAZADA').length;

    final itemsMostrar = _selectedFilter == 'TODAS'
        ? recomendaciones
        : recomendaciones
            .where((r) =>
                r.estado == _selectedFilter ||
                (_selectedFilter == 'ACEPTADA' && r.estado == 'MODIFICADA'))
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: "Validación Clínica (IA-07)",
        leadingIcon: Icons.verified,
        iconColor: const Color(0xFF4A624D),
        trailingWidget: IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF58423B)),
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            top: 96 + MediaQuery.of(context).padding.top,
            left: 24,
            right: 24,
            bottom: 120,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Toda recomendación generada por el motor adaptativo debe ser supervisada y justificada para aplicarse al plan del paciente. Tasa de revisión objetivo: >80%",
                style: TextStyle(color: Color(0xFF58423B), height: 1.5),
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                        'TODAS', "Todas (${recomendaciones.length})"),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                        'PENDIENTE', "Pendientes ($countPendientes)"),
                    const SizedBox(width: 8),
                    _buildFilterChip('ACEPTADA', "Aceptadas ($countAceptadas)"),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                        'RECHAZADA', "Rechazadas ($countRechazadas)"),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (itemsMostrar.isEmpty)
                const Center(
                    child: Text("No hay recomendaciones en este filtro.",
                        style: TextStyle(
                            color: Color(0xFF8B716A),
                            fontStyle: FontStyle.italic)))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: itemsMostrar.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 24),
                  itemBuilder: (context, idx) {
                    return _RecomendacionItemCard(
                        recomendacion: itemsMostrar[idx]);
                  },
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    return TagChip(
      label: label,
      isSelected: _selectedFilter == value,
      onTap: () => setState(() => _selectedFilter = value),
    );
  }
}

class _RecomendacionItemCard extends ConsumerStatefulWidget {
  final RecomendacionClinica recomendacion;
  const _RecomendacionItemCard({required this.recomendacion});

  @override
  ConsumerState<_RecomendacionItemCard> createState() =>
      _RecomendacionItemCardState();
}

class _RecomendacionItemCardState
    extends ConsumerState<_RecomendacionItemCard> {
  final _obsController = TextEditingController();

  Color _getStatusColor(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return const Color(0xFFD97706);
      case 'ACEPTADA':
        return const Color(0xFF22C55E);
      case 'MODIFICADA':
        return const Color(0xFF4A624D);
      case 'RECHAZADA':
        return const Color(0xFFBA1A1A);
      default:
        return Colors.grey;
    }
  }

  Future<void> _procesarDecision(String accion, String observacion) async {
    await ref
        .read(registrarDecisionProvider)
        .ejecutar(widget.recomendacion.id, accion, observacion);
    ref
        .read(recomendacionesProvider.notifier)
        .updateEstado(widget.recomendacion.id, accion, observacion);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Decisión $accion registrada exitosamente.")));
  }

  void _abrirModalModificacion() {
    String nuevaAct = widget.recomendacion.actividad;
    String motivo = "";

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Modificar Parámetro Clínico",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextFormField(
                  initialValue: widget.recomendacion.actividad,
                  decoration: const InputDecoration(
                      labelText: "Ajuste propuesto",
                      border: OutlineInputBorder()),
                  onChanged: (v) => nuevaAct = v,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: "Motivo Clínico de Modificación *",
                      border: OutlineInputBorder()),
                  onChanged: (v) => motivo = v,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (motivo.isEmpty) return;
                      Navigator.of(ctx).pop();
                      _procesarDecision(
                          'MODIFICADA', 'AJUSTE: $nuevaAct => $motivo');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A624D),
                      padding: const EdgeInsets.all(16),
                    ),
                    child: const Text("Registrar Modificación",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recomendacion;
    final isPendiente = r.estado == 'PENDIENTE';

    return BentoCard(
        backgroundColor: Colors.white,
        border: Border.all(color: const Color(0xFFDFC0B7)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(r.estado).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(r.estado,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(r.estado))),
                      ),
                      const SizedBox(height: 12),
                      Text(r.actividad,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E1B16),
                              height: 1.2)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Color(0xFFF5EDE4), shape: BoxShape.circle),
                      child: Text("${(r.confianza * 100).toInt()}%",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF4A624D))),
                    ),
                    const SizedBox(height: 4),
                    const Text("Confianza IA",
                        style:
                            TextStyle(fontSize: 10, color: Color(0xFF8B716A))),
                  ],
                )
              ],
            ),
            const SizedBox(height: 16),
            const Text("JUSTIFICACIÓN DEL MOTOR (IA-03)",
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B716A))),
            const SizedBox(height: 8),
            Text(r.justificacion,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF58423B), height: 1.5)),
            const SizedBox(height: 24),
            if (isPendiente) ...[
              const Divider(),
              const SizedBox(height: 16),
              TextField(
                controller: _obsController,
                decoration: InputDecoration(
                  hintText: "Observación o matiz clínico (opcional)...",
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE9E1D8))),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        _procesarDecision('RECHAZADA', _obsController.text),
                    child: const Text("Rechazar",
                        style: TextStyle(
                            color: Color(0xFFBA1A1A),
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _abrirModalModificacion,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF4A624D)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100)),
                    ),
                    child: const Text("Modificar",
                        style: TextStyle(
                            color: Color(0xFF4A624D),
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        _procesarDecision('ACEPTADA', _obsController.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A624D),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100)),
                    ),
                    child: const Text("Aceptar",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFF5EDE4),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 14, color: Color(0xFF58423B)),
                        const SizedBox(width: 6),
                        Text(
                            "Decisión registrada el ${DateFormat('dd MMM yyyy, HH:mm').format(r.fechaRespuesta)}",
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF58423B))),
                      ],
                    ),
                    if (r.observacion != null && r.observacion!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('“${r.observacion}”',
                          style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF58423B))),
                    ]
                  ],
                ),
              )
            ]
          ],
        ));
  }
}
