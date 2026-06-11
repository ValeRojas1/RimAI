import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/tag_chip.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class ActiveSessionScreen extends ConsumerStatefulWidget {
  final String sesionId;
  final String? ninoId;
  final String? planId;
  final String? actividadId;
  final bool previewOnly;

  const ActiveSessionScreen({
    super.key,
    required this.sesionId,
    this.ninoId,
    this.planId,
    this.actividadId,
    this.previewOnly = false,
  });

  @override
  ConsumerState<ActiveSessionScreen> createState() =>
      _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  final _observacionController = TextEditingController();
  Timer? _timer;
  int _secondsElapsed = 0;
  int _aciertos = 0;
  int _intentos = 0;
  String _currentAssistLevel = 'Ninguna';
  String _nivelUsado = 'Medio';
  int _currentStep = 0;
  bool _nivelInicialAplicado = false;

  @override
  void initState() {
    super.initState();
    if (widget.previewOnly) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _observacionController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final m = (_secondsElapsed / 60).floor().toString().padLeft(2, '0');
    final s = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handleResult(bool acierto) {
    setState(() {
      _intentos++;
      if (acierto) _aciertos++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ninoId = widget.ninoId;
    final actividadId = widget.actividadId;
    final planAsync =
        ninoId == null ? null : ref.watch(planActivoProvider(ninoId));
    final nivelAsync = ninoId != null && actividadId != null
        ? ref.watch(
            nivelInicialProvider((ninoId: ninoId, actividadId: actividadId)))
        : null;
    final plan = planAsync?.valueOrNull;
    ActividadPlan? actividad;
    if (plan != null && actividadId != null) {
      for (final item in plan.actividades) {
        if (item.id == actividadId) {
          actividad = item;
          break;
        }
      }
    }
    if (actividad != null && !_nivelInicialAplicado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _nivelInicialAplicado || _intentos > 0) return;
        setState(() {
          _nivelUsado = actividad!.nivelDificultad;
          _nivelInicialAplicado = true;
        });
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Actividad',
        leadingIcon: Icons.arrow_back,
        iconColor: const Color(0xFF4A624D),
        onLeadingPressed: () {
          if (context.canPop()) {
            context.pop();
          } else if (ninoId != null) {
            context.go('/terapeuta/plan/$ninoId');
          } else {
            context.go('/terapeuta/dashboard');
          }
        },
        trailingWidget: widget.previewOnly
            ? IconButton(
                tooltip: 'Inicio',
                icon: const Icon(Icons.home_rounded, color: Color(0xFF58423B)),
                onPressed: () => context.go('/terapeuta/dashboard'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _timerPill(),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Inicio',
                    icon: const Icon(Icons.home_rounded,
                        color: Color(0xFF58423B)),
                    onPressed: () => context.go('/terapeuta/dashboard'),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 2) {
            context
                .go(ninoId != null ? '/terapeuta/ia/$ninoId' : '/terapeuta/ia');
          }
          if (index == 3) {
            context.go(ninoId != null
                ? '/terapeuta/progreso/$ninoId'
                : '/terapeuta/progreso');
          }
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'Apoyo'),
          BottomNavItem(icon: Icons.insights, label: 'Progreso'),
        ],
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
            Text(plan?.ninoNombre ?? 'Paciente',
                style: const TextStyle(
                    color: Color(0xFF58423B), fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              actividad?.nombre ?? 'Actividad terapeutica',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E1B16)),
            ),
            const SizedBox(height: 8),
            Text(
              actividad?.instrucciones ??
                  'Carga el plan activo para iniciar el registro clinico.',
              style: const TextStyle(color: Color(0xFF58423B), height: 1.4),
            ),
            const SizedBox(height: 24),
            if (widget.previewOnly && actividad != null) ...[
              _buildPreviewOverview(actividad),
              const SizedBox(height: 24),
            ],
            if (!widget.previewOnly && nivelAsync != null) ...[
              _buildNivelInicial(nivelAsync),
              const SizedBox(height: 24),
            ],
            _buildGuidedPanel(actividad),
            if (!widget.previewOnly) ...[
              const SizedBox(height: 24),
              _buildExecutionPanel(),
              const SizedBox(height: 24),
              _buildObservationPanel(),
            ],
            const SizedBox(height: 24),
            _buildActions(plan, actividad),
          ],
        ),
      ),
    );
  }

  Widget _timerPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFE9E1D8),
          borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 16, color: Color(0xFF58423B)),
          const SizedBox(width: 8),
          Text(_formattedTime,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF1E1B16))),
        ],
      ),
    );
  }

  Widget _buildPreviewOverview(ActividadPlan actividad) {
    final minutos = ((actividad.duracionEstimada ?? 0) / 60).round();
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tiles = [
            _previewMetric(
              Icons.tune,
              'Dificultad',
              actividad.nivelDificultad,
            ),
            _previewMetric(
              Icons.timer_outlined,
              'Duracion',
              minutos > 0 ? '$minutos min' : 'Sin tiempo',
            ),
            _previewMetric(
              actividad.requiereAcompanamiento
                  ? Icons.supervisor_account_outlined
                  : Icons.person_outline,
              'Modo',
              actividad.requiereAcompanamiento ? 'Acompanada' : 'Autonoma',
            ),
          ];
          if (constraints.maxWidth < 620) {
            return Column(
              children: tiles
                  .map(
                    (tile) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: tile,
                    ),
                  )
                  .toList(),
            );
          }
          return Row(
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 12),
              Expanded(child: tiles[1]),
              const SizedBox(width: 12),
              Expanded(child: tiles[2]),
            ],
          );
        },
      ),
    );
  }

  Widget _previewMetric(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9E1D8)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4A624D)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF8B716A),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1E1B16),
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

  Widget _buildNivelInicial(AsyncValue<NivelInicialData> nivelAsync) {
    return nivelAsync.when(
      loading: () => const LinearProgressIndicator(color: Color(0xFF4A624D)),
      error: (_, __) => _nivelBadge('Medio', 0, fallback: true),
      data: (data) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _intentos == 0 && !_nivelInicialAplicado) {
            setState(() {
              _nivelUsado = data.nivelRecomendado;
              _nivelInicialAplicado = true;
            });
          }
        });
        return _nivelBadge(data.nivelRecomendado, data.confianza,
            fallback: data.fallback);
      },
    );
  }

  Widget _nivelBadge(String nivel, double confianza, {required bool fallback}) {
    return BentoCard(
      backgroundColor: const Color(0xFF4A624D),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Color(0xFFB8D6B2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              fallback
                  ? 'IA-01 no disponible. Nivel por defecto: Medio'
                  : 'IA-01 recomienda nivel $nivel (${(confianza * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _nivelUsado,
              dropdownColor: const Color(0xFF4A624D),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              items: ['Bajo', 'Medio', 'Alto']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _nivelUsado = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidedPanel(ActividadPlan? actividad) {
    final materiales = actividad?.materiales ?? const <String>[];
    final instrucciones = actividad?.instrucciones?.trim();
    final steps = [
      (
        icon: Icons.inventory_2_outlined,
        title: 'Preparar',
        body: materiales.isEmpty
            ? 'Prepara el espacio y confirma que el paciente este listo.'
            : 'Materiales: ${materiales.join(', ')}.'
      ),
      (
        icon: Icons.record_voice_over_outlined,
        title: 'Guiar',
        body: instrucciones?.isNotEmpty == true
            ? instrucciones!
            : 'Presenta la consigna y modela la actividad antes de iniciar.'
      ),
      (
        icon: Icons.touch_app_outlined,
        title: 'Registrar',
        body:
            'Marca cada intento como correcto o por intentar, y ajusta el nivel de ayuda usado.'
      ),
      (
        icon: Icons.fact_check_outlined,
        title: 'Cerrar',
        body:
            'Valida observaciones y finaliza para ver la sugerencia de dificultad.'
      ),
    ];
    final active = steps[_currentStep];

    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: Color(0xFF4A624D)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Guia paso a paso',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E1B16),
                      ),
                ),
              ),
              Text(
                '${_currentStep + 1}/${steps.length}',
                style: const TextStyle(
                  color: Color(0xFF58423B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length, (index) {
              final selected = index == _currentStep;
              return Expanded(
                child: Container(
                  height: 6,
                  margin:
                      EdgeInsets.only(right: index == steps.length - 1 ? 0 : 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF4A624D)
                        : const Color(0xFFE9E1D8),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFB8D6B2),
                foregroundColor: const Color(0xFF1E1B16),
                child: Icon(active.icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active.title,
                      style: const TextStyle(
                        color: Color(0xFF1E1B16),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      active.body,
                      style: const TextStyle(
                        color: Color(0xFF58423B),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _currentStep == 0
                    ? null
                    : () => setState(() => _currentStep--),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Anterior'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _currentStep == steps.length - 1
                    ? null
                    : () => setState(() => _currentStep++),
                icon: const Icon(Icons.chevron_right),
                label: const Text('Siguiente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A624D),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutionPanel() {
    final tasa = _intentos > 0 ? ((_aciertos / _intentos) * 100).toInt() : 0;
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('METRICAS CLINICAS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A624D))),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _metric('Aciertos', '$_aciertos / $_intentos')),
              Expanded(child: _metric('Logro', '$tasa%')),
              Expanded(child: _metric('Tiempo', _formattedTime)),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: _resultButton(true)),
              const SizedBox(width: 16),
              Expanded(child: _resultButton(false)),
            ],
          ),
          const SizedBox(height: 28),
          const Text('NIVEL DE AYUDA',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A624D))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ['Ninguna', 'Verbal', 'Fisica'].map((level) {
              return TagChip(
                label: level,
                isSelected: _currentAssistLevel == level,
                onTap: () => setState(() => _currentAssistLevel = level),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF58423B))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E1B16))),
        ),
      ],
    );
  }

  Widget _resultButton(bool acierto) {
    return GestureDetector(
      onTap: () => _handleResult(acierto),
      child: Container(
        height: 118,
        decoration: BoxDecoration(
          color: acierto ? const Color(0xFFB8D6B2) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: acierto
              ? null
              : Border.all(color: const Color(0xFFDFC0B7), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(acierto ? Icons.check_circle : Icons.refresh,
                size: 38, color: const Color(0xFF1E1B16)),
            const SizedBox(height: 8),
            Text(acierto ? 'CORRECTO' : 'INTENTAR',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _buildObservationPanel() {
    return BentoCard(
      backgroundColor: const Color(0xFFF5EDE4),
      child: TextField(
        controller: _observacionController,
        maxLines: 4,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: '¿Algún comentario o recomendación?',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildActions(PlanData? plan, ActividadPlan? actividad) {
    final ninoId = plan?.ninoId ?? widget.ninoId;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          if (ninoId != null) {
            context.go('/terapeuta/plan/$ninoId');
          } else {
            context.go('/terapeuta/dashboard');
          }
        },
        icon: const Icon(Icons.arrow_back),
        label: Text(widget.previewOnly
            ? 'Volver al plan terapeutico'
            : 'Volver a la lista de actividades'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          backgroundColor: const Color(0xFF4A624D),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
