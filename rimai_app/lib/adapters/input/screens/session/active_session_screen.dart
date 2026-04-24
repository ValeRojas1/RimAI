import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/tag_chip.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class ActiveSessionScreen extends ConsumerStatefulWidget {
  final String sesionId;
  const ActiveSessionScreen({super.key, required this.sesionId});

  @override
  ConsumerState<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends ConsumerState<ActiveSessionScreen> {
  final _observacionController = TextEditingController();
  
  bool _cameraConsent = false;
  String _currentAssistLevel = 'Ninguna';
  
  // Timer state
  int _secondsElapsed = 0;
  Timer? _timer;

  // Session state
  int _aciertos = 0;
  int _intentos = 0;
  int _dificultad = 1;

  @override
  void initState() {
    super.initState();
    startTimer();
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    _observacionController.dispose();
    super.dispose();
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  String get _formattedTime {
    final m = (_secondsElapsed / 60).floor().toString().padLeft(2, '0');
    final s = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _requestCameraConsent() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Consentimiento Requerido"),
        content: const Text(
          "¿El tutor legal autoriza el uso temporal de la cámara para la detección de emociones en tiempo real?\n\nLos datos no se graban ni constituyen diagnóstico."
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _cameraConsent = false);
            },
            child: const Text("Rechazar"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _cameraConsent = true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A624D)),
            child: const Text("Autorizar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleResult(bool acierto) async {
    setState(() {
      _intentos++;
      if (acierto) _aciertos++;
    });
    final newDiff = await ref.read(ajustarDificultadProvider).ejecutar(acierto);
    if (mounted) {
      setState(() => _dificultad = newDiff);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: "RimAI",
        leadingIcon: Icons.all_inclusive,
        iconColor: const Color(0xFF4A624D),
        trailingWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE9E1D8),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer, size: 16, color: Color(0xFF58423B)),
              const SizedBox(width: 8),
              Text(
                _formattedTime,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E1B16)),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1, // Sesión
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 2) context.go('/terapeuta/ia');
          if (index == 3) context.go('/terapeuta/progreso');
        },
        items: [
          BottomNavItem(icon: Icons.home, label: "Inicio"),
          BottomNavItem(icon: Icons.spatial_audio_off, label: "Sesión"),
          BottomNavItem(icon: Icons.auto_awesome, label: "IA"),
          BottomNavItem(icon: Icons.insights, label: "Progreso"),
        ],
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
               _buildActivityHeader(),
               const SizedBox(height: 24),
               _buildMainGrid(),
             ],
           ),
         ),
      ),
    );
  }

  Widget _buildActivityHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: const [
                 Text("Lucas · 7 Años", style: TextStyle(color: Color(0xFF58423B), fontWeight: FontWeight.bold)),
                 SizedBox(height: 4),
                 Text("Atención Conjunta con Dinosaurios", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
               ],
             ),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
               decoration: BoxDecoration(
                 color: const Color(0xFFB8D6B2),
                 borderRadius: BorderRadius.circular(8),
               ),
               child: const Text("PASO 2 DE 3", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E1B16))),
             )
           ],
         ),
         const SizedBox(height: 12),
         const Text(
           "Integrar intereses principales para fomentar el seguimiento visual de objetos que se desplazan de izquierda a derecha.",
           style: TextStyle(fontSize: 16, color: Color(0xFF58423B), height: 1.5),
         )
      ],
    );
  }

  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        
        return Column(
          children: [
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: _buildExecutionPanel()),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: _buildRightPanel()),
                ],
              )
            else
              Column(
                children: [
                  _buildExecutionPanel(),
                  const SizedBox(height: 24),
                  _buildRightPanel(),
                ],
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      side: const BorderSide(color: Color(0xFF58423B), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Pausar Sesión", style: TextStyle(color: Color(0xFF58423B), fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      _timer?.cancel();
                      context.go(
                        '/terapeuta/sesion/resumen',
                        extra: {
                          'aciertos': _aciertos,
                          'intentos': _intentos,
                          'segundos': _secondsElapsed,
                          'nivelAyuda': _currentAssistLevel,
                          'ninoNombre': 'Lucas Mendoza',
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: const Color(0xFF4A624D),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Finalizar Actividad", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          ],
        );
      },
    );
  }

  Widget _buildExecutionPanel() {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("MÉTRICAS CLÍNICA", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4A624D), letterSpacing: 1)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMetric("Aciertos / Intentos", "$_aciertos / $_intentos"),
              _buildMetric("Tiempo", _formattedTime),
              _buildMetric("Nivel IA", "Dif. $_dificultad"),
            ],
          ),
          const SizedBox(height: 32),
          
          Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   const Text("Registro de intento:", style: TextStyle(fontWeight: FontWeight.bold)),
                   Text("${_intentos > 0 ? ((_aciertos/_intentos)*100).toInt() : 0}% de precisión", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4A624D))),
                 ],
               ),
               const SizedBox(height: 16),
               Row(
                 children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _handleResult(true),
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFB8D6B2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check_circle, size: 40, color: Color(0xFF1E1B16)),
                              SizedBox(height: 8),
                              Text("CORRECTO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E1B16)))
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _handleResult(false),
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFDFC0B7), width: 2),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.refresh, size: 40, color: Color(0xFF58423B)),
                              SizedBox(height: 8),
                              Text("INTENTAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF58423B)))
                            ],
                          ),
                        ),
                      ),
                    ),
                 ],
               )
             ],
          ),
          const SizedBox(height: 32),
          const Text("NIVEL DE AYUDA (PROMPTING)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4A624D))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ['Ninguna', 'Verbal', 'Física'].map((level) {
              return TagChip(
                label: level,
                isSelected: _currentAssistLevel == level,
                onTap: () => setState(() => _currentAssistLevel = level),
              );
            }).toList(),
          )
        ],
      ),
    );
  }
  
  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF58423B))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E1B16))),
      ],
    );
  }

  Widget _buildRightPanel() {
    return Column(
      children: [
        BentoCard(
          backgroundColor: const Color(0xFF4A624D),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("MÓDULO IA-04", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFFCFE9CF))),
                  Switch(
                    value: _cameraConsent,
                    activeColor: const Color(0xFFB8D6B2),
                    onChanged: (val) {
                      if (val) {
                        _requestCameraConsent();
                      } else {
                        setState(() => _cameraConsent = false);
                      }
                    },
                  )
                ],
              ),
              const SizedBox(height: 8),
              const Text("Detección Emocional", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 24),
              
              if (_cameraConsent)
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                     alignment: Alignment.center,
                     children: [
                       const Icon(Icons.camera_alt, size: 64, color: Colors.white24),
                       // Mock Emotion readout
                       Positioned(
                         bottom: 16,
                         child: Container(
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                           decoration: BoxDecoration(
                             color: const Color(0xFFB8D6B2).withOpacity(0.9),
                             borderRadius: BorderRadius.circular(100)
                           ),
                           child: const Text("NEUTRAL - 88%", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A2010))),
                         ),
                       )
                     ],
                  ),
                )
              else
                Container(
                   padding: const EdgeInsets.all(24),
                   decoration: BoxDecoration(
                     color: Colors.white.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(12),
                   ),
                   child: const Center(
                     child: Text(
                       "Módulo inactivo. \nRequiere confirmación del tutor.",
                       textAlign: TextAlign.center,
                       style: TextStyle(color: Color(0xFFCFE9CF), height: 1.5),
                     ),
                   ),
                ),
              const SizedBox(height: 24),
              Row(
                 children: const [
                   Icon(Icons.info_outline, size: 16, color: Color(0xFFB3CDB4)),
                   SizedBox(width: 8),
                   Expanded(child: Text("Este dato no constituye diagnóstico clínico.", style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFFB3CDB4)))),
                 ],
              )
            ],
          ),
        ),
        const SizedBox(height: 24),
        BentoCard(
          backgroundColor: const Color(0xFFF5EDE4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                 children: const [
                   Icon(Icons.edit_note, color: Color(0xFF4A624D)),
                   SizedBox(width: 8),
                   Text("BITÁCORA", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4A624D))),
                 ],
               ),
               const SizedBox(height: 16),
               TextField(
                 controller: _observacionController,
                 maxLines: 3,
                 decoration: InputDecoration(
                   filled: true,
                   fillColor: Colors.white,
                   hintText: "Observación rápida...",
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12),
                     borderSide: BorderSide(color: const Color(0xFF4A624D).withOpacity(0.2)),
                   ),
                 ),
               ),
            ],
          ),
        ),
      ],
    );
  }
}
