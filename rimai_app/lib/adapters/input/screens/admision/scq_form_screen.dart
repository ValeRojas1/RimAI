import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/scq_providers.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

// ── Design tokens matching the family dashboard ──────────────────────────────
const _kP = Color(0xFFA43714);
const _kA = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurf = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSub = Color(0xFF58423B);
const _kBdr = Color(0xFFDFC0B7);

class SCQFormScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String? patientName;

  const SCQFormScreen({
    super.key,
    required this.patientId,
    this.patientName,
  });

  @override
  ConsumerState<SCQFormScreen> createState() => _SCQFormScreenState();
}

class _SCQFormScreenState extends ConsumerState<SCQFormScreen> {
  // Lista de 15 preguntas de comunicación social altamente representativas del SCQ
  final List<String> _preguntas = [
    "¿Puede mantener una conversación bidireccional adecuada?",
    "¿Utiliza gestos espontáneos para comunicarse y expresarse?",
    "¿Tiene intereses intensos u obsesivos que parecen poco comunes?",
    "¿Realiza movimientos repetitivos con manos o dedos (como aleteo)?",
    "¿Muestra hipersensibilidad inusual a ruidos cotidianos o texturas?",
    "¿Tiene dificultades para integrarse en juegos grupales con otros niños?",
    "¿Presenta ecolalia (repetir palabras o frases que escucha)?",
    "¿Usa juguetes de manera inusual (alinear, girar ruedas obsesivamente)?",
    "¿Evita o desvía el contacto visual directo durante las interacciones?",
    "¿Parece no responder o ignorar cuando se le llama por su nombre?",
    "¿Muestra poco interés por compartir logros, juguetes o emociones con usted?",
    "¿Tiene rutinas muy rígidas y se altera significativamente ante cambios?",
    "¿Expresa sus emociones de manera poco comprensible o inusual?",
    "¿Busca sensaciones físicas intensas (dar vueltas, oler objetos, etc.)?",
    "¿Tiene problemas para comprender las expresiones faciales o el lenguaje no verbal?",
  ];

  late final List<int> _respuestas;
  bool _aceptoDisclaimer = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Las respuestas se inicializan en 0 (No).
    // Nota: Para la puntuación SCQ, la presencia del comportamiento de riesgo de TEA (ej. Evita contacto visual) suma 1 punto.
    // Para preguntas positivas (ej. ¿Puede mantener conversación?), un "No" suma 1 punto.
    // Para mantenerlo intuitivo en esta interfaz simplificada, activado (Sí) representará el indicio de TEA (suma 1 punto).
    _respuestas = List.filled(_preguntas.length, 0);
  }

  void _submit() async {
    if (!_aceptoDisclaimer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Debe aceptar la advertencia legal RNF-10 para continuar',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _kP,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final useCase = ref.read(submitSCQUsecaseProvider);
      // Enviamos el cuestionario al backend real
      final result = await useCase.execute(
        widget.patientId,
        _respuestas,
        _aceptoDisclaimer,
      );

      if (mounted) {
        ref.invalidate(familiaDashboardProvider);
        context.go('/padre/scq/resultados', extra: result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al enviar el cuestionario SCQ: $e',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientDisplayName = widget.patientName ?? "el Paciente";

    return Scaffold(
      backgroundColor: _kBg,
      appBar: RimAITopBar(
        title: "Cuestionario SCQ",
        leadingIcon: Icons.arrow_back_ios_new,
        onLeadingPressed: () => context.pop(),
        iconColor: _kP,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: _kP),
                  const SizedBox(height: 16),
                  Text(
                    "Procesando evaluación preliminar...",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _kSub,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Evaluación Preliminar de Indicadores TEA",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _kText,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Basado en el Cuestionario de Comunicación Social (SCQ) para $patientDisplayName.",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _kSub,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kA.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kA.withOpacity(0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: _kSub, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Por favor, responda con honestidad. Marque la opción correspondiente si observa el comportamiento indicado de manera persistente.",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: _kText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Render de las preguntas como hermosas tarjetas interactivas
                  ...List.generate(_preguntas.length, (index) {
                    final isChecked = _respuestas[index] == 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isChecked ? _kA.withOpacity(0.1) : _kSurf,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isChecked ? _kA : _kBdr.withOpacity(0.4),
                          width: isChecked ? 1.5 : 1.0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SwitchListTile(
                          activeColor: _kP,
                          activeTrackColor: _kA,
                          inactiveThumbColor: _kSub,
                          inactiveTrackColor: Colors.grey.shade300,
                          title: Text(
                            _preguntas[index],
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kText,
                            ),
                          ),
                          subtitle: Text(
                            isChecked
                                ? "Comportamiento presente (1 punto)"
                                : "No observado (0 puntos)",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: isChecked ? _kP : _kSub,
                              fontWeight: isChecked
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          value: isChecked,
                          onChanged: (val) {
                            setState(() {
                              _respuestas[index] = val ? 1 : 0;
                            });
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                  // Disclaimer Legal obligatorio (RNF-10)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border:
                          Border.all(color: _kP.withOpacity(0.5), width: 1.5),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _kP.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.gavel_rounded,
                                color: _kP, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Advertencia Legal Obligatoria (RNF-10)",
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                color: _kP,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Los resultados de este cuestionario y las evaluaciones automatizadas generadas por RimAI constituyen únicamente indicadores de orientación preliminar. No constituyen de ninguna manera un diagnóstico clínico médico definitivo, el cual debe ser determinado exclusivamente por profesionales médicos calificados.",
                          style: GoogleFonts.plusJakartaSans(
                            color: _kSub,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Checkbox(
                              value: _aceptoDisclaimer,
                              activeColor: _kP,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              onChanged: (val) => setState(
                                  () => _aceptoDisclaimer = val ?? false),
                            ),
                            Expanded(
                              child: Text(
                                "He leído, entiendo y acepto los términos de esta advertencia legal.",
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: _kText,
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kP,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _submit,
                      child: Text(
                        "Enviar Evaluación SCQ",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
