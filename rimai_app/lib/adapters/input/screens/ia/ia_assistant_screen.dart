import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/session_step_card.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

class IAAssistantScreen extends ConsumerStatefulWidget {
  const IAAssistantScreen({super.key});

  @override
  ConsumerState<IAAssistantScreen> createState() => _IAAssistantScreenState();
}

class _IAAssistantScreenState extends ConsumerState<IAAssistantScreen> with SingleTickerProviderStateMixin {
  final _observationController = TextEditingController();
  bool _isProcessing = true;
  late AnimationController _scanController;
  final String _ninoId = '123'; // mock id

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
       vsync: this,
       duration: const Duration(seconds: 3),
    )..repeat();
    
    // Simulate processing phase
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  @override
  void dispose() {
    _observationController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: "Asistente IA",
        leadingIcon: Icons.psychology,
        iconColor: const Color(0xFF4A624D),
        trailingWidget: const CircleAvatar(
          radius: 20,
          backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=32'),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 2,
        onTap: (index) {
          if (index == 0) context.go('/terapeuta/dashboard');
          if (index == 1) context.go('/terapeuta/sesion');
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
              _buildProcessingStatus(),
              const SizedBox(height: 24),
              _buildHeader(),
              const SizedBox(height: 32),
              _buildBentoGrid(),
              const SizedBox(height: 32),
              _buildSystemLog(),
              const SizedBox(height: 32),
              _buildObservationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingStatus() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: _isProcessing ? 1.0 : 0.0,
      child: _isProcessing ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A624D).withOpacity(0.1),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: List.generate(3, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4A624D),
                    shape: BoxShape.circle,
                  ),
                ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(
                     duration: 400.ms,
                     delay: (index * 200).ms, 
                     begin: const Offset(0.5, 0.5), 
                     end: const Offset(1.2, 1.2),
                   );
              }),
            ),
            const SizedBox(width: 8),
            const Text(
              "PROCESANDO PERFIL...",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A624D),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ) : const SizedBox.shrink(),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: Color(0xFF1E1B16),
              fontFamily: 'PlusJakartaSans',
            ),
            children: [
              TextSpan(text: "Análisis Cognitivo en\n"),
              TextSpan(text: "Tiempo Real", style: TextStyle(color: Color(0xFF4A624D))),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "El asistente IA analiza indicadores biométricos y genera un plan adaptativo instantáneo.",
          style: TextStyle(
            fontSize: 16,
            color: const Color(0xFF58423B),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGrid() {
    final resumenAsync = ref.watch(resumenSesionProvider(_ninoId));
    final planSesionAsync = ref.watch(planSesionProvider(_ninoId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;
        
        return Column(
          children: [
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: _buildSensorySummaryCard(resumenAsync)),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: _buildPredictiveMetricsCard(resumenAsync)),
                ],
              )
            else
              Column(
                children: [
                  _buildSensorySummaryCard(resumenAsync),
                  const SizedBox(height: 24),
                  _buildPredictiveMetricsCard(resumenAsync),
                ],
              ),
            const SizedBox(height: 24),
            _buildSessionPlanCard(planSesionAsync),
          ],
        );
      },
    );
  }

  Widget _buildSensorySummaryCard(AsyncValue<ResumenSesionData> asyncData) {
    return BentoCard(
      backgroundColor: const Color(0xFFF5EDE4),
      backgroundWidget: AnimatedBuilder(
        animation: _scanController,
        builder: (context, child) {
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [
                  _scanController.value - 0.2, 
                  _scanController.value, 
                  _scanController.value + 0.2
                ],
                colors: [
                  Colors.transparent,
                  const Color(0xFFB8D6B2).withOpacity(0.2),
                  Colors.transparent,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcOver,
            child: Container(color: Colors.transparent),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("MÓDULO 01", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  SizedBox(height: 4),
                  Text("Resumen Sensorial", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.graphic_eq, color: Color(0xFF4A624D)),
              )
            ],
          ),
          const SizedBox(height: 24),
          _buildSensoryItem(Icons.visibility, "Hipersensibilidad Visual", "Luz blanca causa evitación."),
          const SizedBox(height: 12),
          _buildSensoryItem(Icons.volume_up, "Umbral Auditivo", "Sensible a frecuencias agudas.", highlightColor: const Color(0xFF4A624D)),
          const SizedBox(height: 24),
          
          asyncData.when(
            data: (data) => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Carga Cognitiva Actual", style: TextStyle(fontWeight: FontWeight.w500)),
                    Text("${(data.cargaCognitiva * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: data.cargaCognitiva,
                    backgroundColor: const Color(0xFFEEDDC8),
                    color: const Color(0xFF4A624D),
                    minHeight: 12,
                  ),
                ),
              ],
            ),
            loading: () => const LinearProgressIndicator(color: Color(0xFFB8D6B2)),
            error: (e, st) => const Text("Error al cargar"),
          )
        ],
      ),
    );
  }

  Widget _buildSensoryItem(IconData icon, String title, String subtitle, {Color? highlightColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF2E9),
        borderRadius: BorderRadius.circular(12),
        border: highlightColor != null ? Border(left: BorderSide(color: highlightColor, width: 4)) : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4A624D)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: Color(0xFF58423B))),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPredictiveMetricsCard(AsyncValue<ResumenSesionData> asyncData) {
    return BentoCard(
      backgroundColor: const Color(0xFF4A624D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("MÓDULO 02", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Color(0xFFCFE9CF))),
          const SizedBox(height: 4),
          const Text("Métricas Predictivas", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
            "Análisis basado en historial del menor.",
            style: TextStyle(fontSize: 14, color: Color(0xFFB3CDB4), height: 1.5),
          ),
          const SizedBox(height: 24),
          
          asyncData.when(
            data: (data) => Column(
               children: [
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     const Text("Foco Estimado", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                     Text(data.focoEstimado, style: const TextStyle(fontSize: 28, color: Colors.black, fontWeight: FontWeight.bold)),
                   ],
                 ),
                 Divider(color: Colors.white.withOpacity(0.1), height: 32),
                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     const Text("Nivel de Calma", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                     Text("${data.nivelCalma}/10", style: const TextStyle(fontSize: 28, color: Colors.black, fontWeight: FontWeight.bold)),
                   ],
                 ),
               ],
             ),
             loading: () => const CircularProgressIndicator(color: Colors.white),
             error: (e, st) => const Text("Error al cargar", style: TextStyle(color: Colors.red)),
          ),
          
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.bolt, color: Color(0xFFCFE9CF)),
                SizedBox(width: 8),
                Expanded(
                  child: Text("ALERTA: Posible pico de estrés si la duración supera 25 min.", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSessionPlanCard(AsyncValue<List<SessionStep>> planAsync) {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      backgroundWidget: Positioned(
         bottom: -50,
         right: -50,
         child: Icon(Icons.psychology_alt, size: 200, color: const Color(0xFF58423B).withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("MÓDULO 03", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  SizedBox(height: 4),
                  Text("Plan de Sesión Recomendado", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text("Ejecutar Sesión", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A624D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          planAsync.when(
            data: (steps) => GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width < 768 ? 1 : (MediaQuery.of(context).size.width < 1024 ? 2 : 3),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: steps.asMap().entries.map((entry) {
                return SessionStepCard(
                  stepNumber: entry.key + 1,
                  title: entry.value.title,
                  description: entry.value.description,
                  duration: entry.value.duration,
                  hasScanning: entry.value.hasScanning,
                );
              }).toList(),
            ),
            loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF4A624D))),
            error: (e, st) => Text("Error: $e"),
          )
        ],
      ),
    );
  }

  Widget _buildSystemLog() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E1D8).withOpacity(0.3),
        border: Border.all(color: const Color(0xFF4A624D).withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text("LOG DEL SISTEMA IA", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 16),
          DefaultTextStyle(
            style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF58423B), height: 1.8),
            child: AnimatedTextKit(
              animatedTexts: [
                TypewriterAnimatedText('> Analizando flujos de datos biométricos... OK\n> Calibrando respuesta emocional predictiva... 88% Precisión\n> Sincronizando con dispositivo sensorial... Conectado\n> Generando interfaz adaptativa... Listo para iniciar.',
                  speed: const Duration(milliseconds: 50),
                ),
              ],
              isRepeatingAnimation: false,
              displayFullTextOnTap: true,
            ),
          )
        ],
      )
    );
  }

  Widget _buildObservationSection() {
    return Container(
       padding: const EdgeInsets.all(24),
       decoration: BoxDecoration(
         color: const Color(0xFFB8D6B2).withOpacity(0.2),
         border: Border.all(color: const Color(0xFF4A624D).withOpacity(0.2)),
         borderRadius: BorderRadius.circular(16),
       ),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: const [
               Icon(Icons.edit_note, color: Color(0xFF4A624D)),
               SizedBox(width: 8),
               Text("OBSERVACIONES EN TIEMPO REAL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4A624D))),
             ],
           ),
           const SizedBox(height: 16),
           Stack(
             children: [
               TextFormField(
                 controller: _observationController,
                 minLines: 4,
                 maxLines: null,
                 decoration: InputDecoration(
                   filled: true,
                   fillColor: Colors.white,
                   hintText: "Escribe algo que está sucediendo...",
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12),
                     borderSide: BorderSide(color: const Color(0xFF4A624D).withOpacity(0.2)),
                   ),
                   focusedBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12),
                     borderSide: const BorderSide(color: Color(0xFF4A624D)),
                   ),
                   contentPadding: const EdgeInsets.all(16),
                 ),
                 onChanged: (val) => setState((){}),
               ),
               Positioned(
                 bottom: 12,
                 right: 12,
                 child: AnimatedOpacity(
                   duration: const Duration(milliseconds: 200),
                   opacity: _observationController.text.isNotEmpty ? 1.0 : 0.0,
                   child: FloatingActionButton.small(
                     onPressed: _observationController.text.isNotEmpty ? () async {
                       await ref.read(sesionServiceProvider).guardarObservacion('sesion123', _observationController.text);
                       _observationController.clear();
                       if(mounted) setState((){});
                       // Show a snackbar or something
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Observación guardada.")));
                     } : null,
                     backgroundColor: const Color(0xFF4A624D),
                     child: const Icon(Icons.check, color: Colors.white),
                   ),
                 )
               )
             ],
           ),
           const SizedBox(height: 8),
           Text("Las notas se guardarán automáticamente en el perfil.", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: const Color(0xFF58423B).withOpacity(0.7))),
         ],
       ),
    );
  }
}
