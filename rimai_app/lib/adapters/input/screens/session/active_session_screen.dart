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

  const ActiveSessionScreen({
    super.key,
    required this.sesionId,
    this.ninoId,
    this.planId,
    this.actividadId,
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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: 'Actividad',
        leadingIcon: Icons.spatial_audio_off,
        iconColor: const Color(0xFF4A624D),
        trailingWidget: _timerPill(),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 2 && ninoId != null) context.go('/terapeuta/ia/$ninoId');
          if (index == 3 && ninoId != null)
            context.go('/terapeuta/progreso/$ninoId');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: 'Inicio'),
          BottomNavItem(icon: Icons.spatial_audio_off, label: 'Sesion'),
          BottomNavItem(icon: Icons.auto_awesome, label: 'IA'),
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
            if (nivelAsync != null) ...[
              _buildNivelInicial(nivelAsync),
              const SizedBox(height: 24),
            ],
            _buildExecutionPanel(),
            const SizedBox(height: 24),
            _buildObservationPanel(),
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

  Widget _buildNivelInicial(AsyncValue<NivelInicialData> nivelAsync) {
    return nivelAsync.when(
      loading: () => const LinearProgressIndicator(color: Color(0xFF4A624D)),
      error: (_, __) => _nivelBadge('Medio', 0, fallback: true),
      data: (data) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _intentos == 0 && _nivelUsado == 'Medio') {
            setState(() => _nivelUsado = data.nivelRecomendado);
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
          hintText: 'Observaciones del terapeuta',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildActions(PlanData? plan, ActividadPlan? actividad) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: plan == null
                ? null
                : () => context.go('/terapeuta/plan/${plan.ninoId}'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18)),
            child: const Text('Volver al plan'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _saving || plan == null || actividad == null
                ? null
                : () => _finalizar(plan, actividad),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: const Color(0xFF4A624D),
              foregroundColor: Colors.white,
            ),
            child: Text(_saving ? 'Guardando...' : 'Finalizar actividad'),
          ),
        ),
      ],
    );
  }

  Future<void> _finalizar(PlanData plan, ActividadPlan actividad) async {
    setState(() => _saving = true);
    try {
      await ref.read(sesionServiceProvider).guardarResultadoActividad(
            ninoId: plan.ninoId,
            planId: plan.id,
            actividadId: actividad.id,
            aciertos: _aciertos,
            intentos: _intentos,
            segundos: _secondsElapsed,
            nivelAyuda: _currentAssistLevel,
            nivelDificultadUsado: _nivelUsado,
            observaciones: _observacionController.text.trim(),
          );
      _timer?.cancel();
      if (!mounted) return;
      context.go('/terapeuta/sesion/resumen', extra: {
        'aciertos': _aciertos,
        'intentos': _intentos,
        'segundos': _secondsElapsed,
        'nivelAyuda': _currentAssistLevel,
        'ninoNombre': plan.ninoNombre,
        'observaciones': _observacionController.text.trim(),
        'ninoId': plan.ninoId,
        'planId': plan.id,
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
