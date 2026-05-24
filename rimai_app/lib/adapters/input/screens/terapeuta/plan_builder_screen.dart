import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kAction = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class PlanBuilderScreen extends ConsumerStatefulWidget {
  final String ninoId;
  final String patientName;

  const PlanBuilderScreen({
    super.key,
    required this.ninoId,
    required this.patientName,
  });

  @override
  ConsumerState<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

class _PlanBuilderScreenState extends ConsumerState<PlanBuilderScreen> {
  final Set<String> _selectedActivityIds = {};
  bool _isInitialized = false;
  bool _isProcessing = false;

  void _initializeSelection(List<RecomendacionClinica> recomendaciones) {
    if (_isInitialized) return;
    _isInitialized = true;
    for (final rec in recomendaciones) {
      _selectedActivityIds.add(rec.id);
    }
  }

  Future<void> _generarYAsignarPlan(List<RecomendacionClinica> recomendaciones) async {
    final seleccionadas = recomendaciones.where((r) => _selectedActivityIds.contains(r.id)).toList();
    
    if (seleccionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona al menos una actividad para la nueva sesión.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final service = ref.read(dashboardServiceProvider);

      // 1. Invocar el generador de plan de la IA en el backend (crea un nuevo borrador)
      final result = await service.generarPlanIA(widget.ninoId);
      final newPlanId = result['plan_id']?.toString() ?? '';

      if (newPlanId.isEmpty) {
        throw Exception('No se pudo obtener el ID del plan generado.');
      }

      // 2. Identificar cuáles actividades fueron deseleccionadas por el terapeuta
      final deseleccionadas = recomendaciones.where((r) => !_selectedActivityIds.contains(r.id)).toList();

      // 3. Remover del backend las actividades deseleccionadas
      for (final rec in deseleccionadas) {
        await service.desasociarActividadDePlan(
          planId: newPlanId,
          actividadId: rec.id,
        );
      }

      // 4. Invalidar estados de Riverpod para refrescar la información
      ref.invalidate(planActivoProvider(widget.ninoId));
      ref.invalidate(perfilPacienteProvider(widget.ninoId));
      ref.invalidate(dashboardProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Sesión ${result['sesion_numero'] ?? ''} generada exitosamente con las actividades elegidas.'),
            backgroundColor: const Color(0xFF4A624D),
            duration: const Duration(seconds: 4),
          ),
        );
        // Regresar al plan terapéutico del niño para que el terapeuta pueda aprobarlo y publicarlo
        context.go('/terapeuta/plan/${widget.ninoId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar la sesión: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Obtener las sugerencias de la IA cargadas desde el asistente clínico
    final iaDataAsync = ref.watch(iaAssistantProvider(widget.ninoId));

    return Scaffold(
      backgroundColor: _kBg,
      appBar: RimAITopBar(
        title: "Constructor de Sesión",
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () => context.pop(),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 120,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner informativo superior
            BentoCard(
              backgroundColor: const Color(0xFFFFF2CC),
              border: Border.all(color: const Color(0xFFE2A300)),
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF8A5A00)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Recomendaciones adaptativas de RimAI para **${widget.patientName}** basadas en los resultados y desempeño de su sesión previa. Revisa la justificación y elige las actividades que conformarán la nueva sesión.',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF6B4300),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            Text(
              "Actividades recomendadas por IA",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            const SizedBox(height: 16),

            iaDataAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(color: _kPrimary),
                ),
              ),
              error: (err, _) => BentoCard(
                backgroundColor: _kSurface,
                child: Text(
                  'No se pudieron cargar recomendaciones personalizadas. Posiblemente este paciente aún no tenga resultados clínicos previos.\n\nDetalle: $err',
                  style: const TextStyle(color: _kSubtext, height: 1.35),
                ),
              ),
              data: (iaData) {
                final recomendaciones = iaData.recomendaciones;

                if (recomendaciones.isEmpty) {
                  return BentoCard(
                    backgroundColor: _kSurface,
                    child: const Text(
                      'La IA no tiene recomendaciones pendientes de actividades en este momento.',
                      style: TextStyle(color: _kSubtext),
                    ),
                  );
                }

                _initializeSelection(recomendaciones);

                return Column(
                  children: [
                    ...recomendaciones.map((rec) {
                      final isSelected = _selectedActivityIds.contains(rec.id);
                      final pctConfianza = (rec.confianza * 100).round();
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _isProcessing
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedActivityIds.remove(rec.id);
                                      } else {
                                        _selectedActivityIds.add(rec.id);
                                      }
                                    });
                                  },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected 
                                      ? _kPrimary.withValues(alpha: 0.3) 
                                      : const Color(0xFFE9E1D8),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    activeColor: _kPrimary,
                                    value: isSelected,
                                    onChanged: _isProcessing
                                        ? null
                                        : (val) {
                                            setState(() {
                                              if (val == true) {
                                                _selectedActivityIds.add(rec.id);
                                              } else {
                                                _selectedActivityIds.remove(rec.id);
                                              }
                                            });
                                          },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                rec.actividad,
                                                style: GoogleFonts.plusJakartaSans(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: _kText,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _kAction.withValues(alpha: 0.25),
                                                borderRadius: BorderRadius.circular(100),
                                              ),
                                              child: Text(
                                                '$pctConfianza% IA',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF2F6B45),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Justificación Clínica de la IA:',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _kPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          rec.justificacion,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            color: _kSubtext,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    
                    const SizedBox(height: 24),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing 
                            ? null 
                            : () => _generarYAsignarPlan(recomendaciones),
                        icon: _isProcessing 
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _isProcessing 
                              ? 'Procesando sesión...' 
                              : 'Confirmar y Asignar Sesión (${_selectedActivityIds.length} act.)',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
