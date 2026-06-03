import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
const _kMinActivitySeconds = 30;
const _kEarlyFinishMessages = [
  'Esto fue demasiado rápido. ¿No crees?',
  'Esto me huele a trampa. ¡Vamos, inténtalo!',
  'Tienes que hacerlo. ¡Tú puedes!',
];

class FamilyActivitySessionScreen extends ConsumerStatefulWidget {
  final String actividadId;
  final String ninoId;
  final String planId;

  const FamilyActivitySessionScreen({
    super.key,
    required this.actividadId,
    required this.ninoId,
    required this.planId,
  });

  @override
  ConsumerState<FamilyActivitySessionScreen> createState() =>
      _FamilyActivitySessionScreenState();
}

class _FamilyActivitySessionScreenState
    extends ConsumerState<FamilyActivitySessionScreen> {
  final _obsController = TextEditingController();
  Timer? _timer;
  int _seconds = 0;
  int _step = 0;
  int _aciertos = 0;
  int _intentos = 0;
  String _nivelAyuda = 'Ninguna';
  bool _saving = false;
  int _earlyFinishMessageIndex = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _obsController.dispose();
    super.dispose();
  }

  String get _time {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(planActivoProvider(widget.ninoId));

    return Scaffold(
      backgroundColor: _kBg,
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Actividad familiar',
        leadingIcon: Icons.arrow_back,
        iconColor: _kPrimary,
        onLeadingPressed: () => context.go('/familia/plan/${widget.ninoId}'),
        trailingWidget: _TimerPill(time: _time),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 96 + MediaQuery.of(context).padding.top,
          left: 24,
          right: 24,
          bottom: 48,
        ),
        child: planAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: _kPrimary)),
          error: (err, _) => Text(
            'No se pudo cargar el plan: $err',
            style: const TextStyle(color: _kSubtext),
          ),
          data: (plan) {
            final actividad = plan.actividades.firstWhere(
              (item) => item.id == widget.actividadId,
              orElse: () => plan.actividades.first,
            );
            if (actividad.completada) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.ninoNombre,
                    style: const TextStyle(
                      color: _kSubtext,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    actividad.nombre,
                    style: const TextStyle(
                      color: _kText,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  BentoCard(
                    backgroundColor: const Color(0xFFE8F5E9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle, color: Color(0xFF2F6B45)),
                            SizedBox(width: 10),
                            Text(
                              'Actividad completada',
                              style: TextStyle(
                                color: _kText,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Esta actividad ya fue registrada para esta sesion. Continua con las actividades restantes.',
                          style: TextStyle(color: _kSubtext, height: 1.35),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                context.go('/familia/plan/${widget.ninoId}'),
                            icon: const Icon(Icons.arrow_back),
                            label:
                                Text('Volver a la sesion ${plan.sesionNumero}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAction,
                              foregroundColor: _kText,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            final steps = _stepsFor(actividad);
            final active = steps[_step];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.ninoNombre,
                  style: const TextStyle(
                    color: _kSubtext,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  actividad.nombre,
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                if (actividad.requiereAcompanamiento) ...[
                  const _WarningBox(
                    text:
                        'Esta actividad requiere acompanamiento del tutor junto al niño.',
                  ),
                  const SizedBox(height: 16),
                ],
                _buildActivityGuide(actividad),
                const SizedBox(height: 16),
                BentoCard(
                  backgroundColor: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paso ${_step + 1}/${steps.length}',
                        style: const TextStyle(
                          color: _kSubtext,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        active.title,
                        style: const TextStyle(
                          color: _kText,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        active.body,
                        style: const TextStyle(color: _kSubtext, height: 1.35),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _step == 0
                                ? null
                                : () => setState(() => _step--),
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Anterior'),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _step == steps.length - 1
                                ? null
                                : () => setState(() => _step++),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Siguiente'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kAction,
                              foregroundColor: _kText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ResultPanel(
                  aciertos: _aciertos,
                  intentos: _intentos,
                  nivelAyuda: _nivelAyuda,
                  onResult: (ok) => setState(() {
                    _intentos++;
                    if (ok) _aciertos++;
                  }),
                  onNivelAyuda: (value) => setState(() => _nivelAyuda = value),
                ),
                const SizedBox(height: 16),
                BentoCard(
                  backgroundColor: _kSurface,
                  child: TextField(
                    controller: _obsController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Observaciones del tutor',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : () => _finish(plan, actividad),
                    icon: const Icon(Icons.check_circle_outline),
                    label:
                        Text(_saving ? 'Guardando...' : 'Finalizar actividad'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_StepInfo> _stepsFor(ActividadPlan actividad) {
    final materiales = actividad.materiales.isEmpty
        ? 'Prepara un espacio tranquilo y evita distractores.'
        : 'Materiales: ${actividad.materiales.join(', ')}.';
    return [
      _StepInfo('Preparar', materiales),
      _StepInfo(
        'Explicar',
        actividad.instrucciones ?? 'Presenta la consigna de forma breve.',
      ),
      const _StepInfo(
        'Realizar',
        'Acompana al niño durante la actividad y registra cada intento.',
      ),
      const _StepInfo(
        'Cerrar',
        'Anota observaciones y finaliza para enviar el reporte al terapeuta.',
      ),
    ];
  }

  Widget _buildActivityGuide(ActividadPlan actividad) {
    final materiales = actividad.materiales;
    final recomendaciones = actividad.recomendacionesAdaptadas.isEmpty
        ? [
            actividad.requiereAcompanamiento
                ? 'Acompana al nino y ofrece ayuda gradual si la necesita.'
                : 'Supervisa de cerca y permite que el nino intente con autonomia.',
            'Mantente dentro del tiempo estimado y registra observaciones al finalizar.',
          ]
        : actividad.recomendacionesAdaptadas;

    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GUIA DE ACTIVIDAD',
            style: TextStyle(
              color: _kSubtext,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _GuideMetric(
                  icon: Icons.timer_outlined,
                  label: 'Duracion',
                  value: _durationLabel(actividad.duracionEstimada),
                ),
                _GuideMetric(
                  icon: Icons.tune,
                  label: 'Dificultad',
                  value: actividad.nivelDificultad,
                ),
                _GuideMetric(
                  icon: actividad.requiereAcompanamiento
                      ? Icons.supervisor_account_outlined
                      : Icons.person_outline,
                  label: 'Modo',
                  value: actividad.requiereAcompanamiento
                      ? 'Acompanada'
                      : 'Autonoma',
                ),
              ];
              if (constraints.maxWidth < 560) {
                return Column(
                  children: metrics
                      .map((metric) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: metric,
                          ))
                      .toList(),
                );
              }
              return Row(
                children: [
                  Expanded(child: metrics[0]),
                  const SizedBox(width: 10),
                  Expanded(child: metrics[1]),
                  const SizedBox(width: 10),
                  Expanded(child: metrics[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Materiales necesarios',
            style: TextStyle(color: _kText, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (materiales.isEmpty)
            const Text(
              'No se registraron materiales especificos. Prepara un espacio tranquilo antes de iniciar.',
              style: TextStyle(color: _kSubtext, height: 1.35),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: materiales
                  .map((item) => Chip(
                        label: Text(item),
                        backgroundColor: _kSurface,
                        side: BorderSide.none,
                      ))
                  .toList(),
            ),
          const SizedBox(height: 18),
          const Text(
            'Recomendaciones para este nino',
            style: TextStyle(color: _kText, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...recomendaciones.take(5).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: _kPrimary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style:
                              const TextStyle(color: _kSubtext, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _durationLabel(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Sin limite';
    final minutes = (seconds / 60).round();
    return '$minutes min';
  }

  Future<void> _finish(PlanData plan, ActividadPlan actividad) async {
    if (_intentos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registra al menos un intento.')),
      );
      return;
    }

    if (_seconds < _kMinActivitySeconds) {
      _showEarlyFinishSnack();
      return;
    }

    final duracionEstimada = actividad.duracionEstimada ?? 0;
    if (duracionEstimada > 0 && _seconds > duracionEstimada) {
      await _showTimeExpiredDialog();
      return;
    }

    setState(() => _saving = true);
    try {
      final result =
          await ref.read(sesionServiceProvider).guardarResultadoActividad(
                ninoId: plan.ninoId,
                planId: plan.id,
                actividadId: actividad.id,
                aciertos: _aciertos,
                intentos: _intentos,
                segundos: _seconds,
                nivelAyuda: _nivelAyuda,
                nivelDificultadUsado: actividad.nivelDificultad,
                observaciones: _obsController.text.trim(),
              );
      _timer?.cancel();
      if (!mounted) return;
      final pendienteSync = result['pendiente_sync'] == true;
      if (pendienteSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Actividad guardada sin conexion. Se sincronizara automaticamente.',
            ),
          ),
        );
      }
      context.go('/familia/sesion/resumen', extra: {
        'aciertos': _aciertos,
        'intentos': _intentos,
        'segundos': _seconds,
        'nivelAyuda': _nivelAyuda,
        'ninoNombre': plan.ninoNombre,
        'observaciones': _obsController.text.trim(),
        'ninoId': plan.ninoId,
        'planId': plan.id,
        'sesionId': result['sesion_id']?.toString(),
        'sesionNumero': plan.sesionNumero,
        'nivelRecomendado': result['nivel_dificultad_recomendado']?.toString(),
        'ajustesDificultad': result['ajustes_dificultad'],
        'pendienteSync': pendienteSync,
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ActivitySaveException && e.code == 'actividad_muy_rapida') {
        _showEarlyFinishSnack();
      } else if (e is ActivitySaveException && e.code == 'tiempo_agotado') {
        await _showTimeExpiredDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No se pudo guardar la actividad. Intenta nuevamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showEarlyFinishSnack() {
    final message = _kEarlyFinishMessages[
        _earlyFinishMessageIndex % _kEarlyFinishMessages.length];
    setState(() => _earlyFinishMessageIndex++);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _showTimeExpiredDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _kSurface,
        title: const Text(
          'Tiempo terminado',
          style: TextStyle(color: _kText, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'El tiempo de esta actividad ya acabo. Puedes volver a intentarlo si gustas.',
          style: TextStyle(color: _kSubtext, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _restartActivity();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAction,
              foregroundColor: _kText,
            ),
            child: const Text('Volver a intentar'),
          ),
        ],
      ),
    );
  }

  void _restartActivity() {
    setState(() {
      _seconds = 0;
      _step = 0;
      _aciertos = 0;
      _intentos = 0;
      _nivelAyuda = 'Ninguna';
      _obsController.clear();
    });
  }
}

class _StepInfo {
  final String title;
  final String body;
  const _StepInfo(this.title, this.body);
}

class _TimerPill extends StatelessWidget {
  final String time;

  const _TimerPill({required this.time});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E1D8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        time,
        style: const TextStyle(color: _kText, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _GuideMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _GuideMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _kSubtext,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  final String text;

  const _WarningBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2CC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2A300)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6B4300),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final int aciertos;
  final int intentos;
  final String nivelAyuda;
  final ValueChanged<bool> onResult;
  final ValueChanged<String> onNivelAyuda;

  const _ResultPanel({
    required this.aciertos,
    required this.intentos,
    required this.nivelAyuda,
    required this.onResult,
    required this.onNivelAyuda,
  });

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      backgroundColor: _kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registro: $aciertos / $intentos aciertos',
            style: const TextStyle(
              color: _kText,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onResult(true),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Correcto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAction,
                    foregroundColor: _kText,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onResult(false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Intentar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kText,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: nivelAyuda,
            decoration: InputDecoration(
              labelText: 'Nivel de ayuda requerido',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            items: const ['Ninguna', 'Verbal', 'Fisica']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (value) {
              if (value != null) onNivelAyuda(value);
            },
          ),
        ],
      ),
    );
  }
}
