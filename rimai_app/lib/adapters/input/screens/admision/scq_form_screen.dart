import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/scq_providers.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';

// ── Design tokens matching the family dashboard ──────────────────────────────
const _kP = Color(0xFFB8D6B2);     // Family action green
const _kA = Color(0xFFB8D6B2);     // Soft green accent
const _kGreenStrong = Color(0xFF4A624D);
const _kBg = Color(0xFFFAF9F6);
const _kSurf = Color(0xFFF5F3EC);
const _kText = Color(0xFF2A2825);
const _kSub = Color(0xFF6B6661);
const _kBdr = Color(0xFFE2E0D9);

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
  // Lista oficial de 40 preguntas del cuestionario SCQ en Español
  final List<String> _preguntas = [
    "¿Es capaz de hablar usando frases u oraciones cortas?",
    "¿Puede usted tener una conversación con él o ella, en la que participen ambos y se vayan turnando o vayan construyendo sobre lo ya dicho?",
    "¿Ha usado alguna vez frases raras o ha dicho la misma cosa una y otra vez y casi exactamente de la misma manera ya fueran frases que ha oído a otras personas o frases que ha inventado?",
    "¿Ha hecho alguna vez preguntas o afirmaciones socialmente inconvenientes, tales como preguntas indiscretas o comentarios personales en momentos inoportunos?",
    "¿Ha confundido alguna vez los pronombres diciendo, por ejemplo tu o ella en lugar de yo?",
    "¿Ha usado alguna vez palabras que ha inventado, ha expresado algunas cosas de manera rara o indirecta o ha usado formas metafóricas para referirse a las cosas, por ejemplo, decir “lluvia caliente” en lugar de “vapor”?",
    "¿Ha dicho en ocasiones la misma cosa una y otra vez y exactamente de la misma manera o ha insistido para que usted diga las mismas cosas una y otra vez?",
    "¿Ha insistido alguna vez en vez de hacer ciertas cosas de una manera o en un orden muy particular o ha habido determinados “rituales” que pretendía que usted respetase?",
    "¿Piensa usted que por lo general su expresión facial se ha podido considerar adecuada a la situación del momento?",
    "¿Ha usado alguna vez la mano de usted como una herramienta o como si fuera parte de su propio cuerpo, por ejemplo, apuntando con su dedo o poniendo la mano de usted en el tirador de la puerta para lograr que la abriese?",
    "¿Ha mostrado alguna vez intereses por cosas que le preocuparan mucho y que a otras personas les parecieran extrañas, por ejemplo, semáforos, tuberías de desagüe u horarios de transporte?",
    "¿Ha estado alguna vez más interesado en las piezas de un juguete o de un objeto, por ejemplo, dar vueltas a las ruedas de un coche, que en usar el objeto de acuerdo a su finalidad?",
    "¿Ha mostrado alguna vez un interés especial por algún tema, por ejemplo trenes o dinosaurios, que aun siendo normal a su edad y en su ambiente, parecía fuera de lo normal por su intensidad?",
    "¿Ha mostrado alguna vez un interés excepcional por la vista, el tacto, el sonido, el sabor o el olor de las cosas?",
    "¿Ha realizado en ocasiones gestos o movimientos extraños con las manos, como agitar o mover sus dedos delante de sus ojos?",
    "¿Ha realizado en ocasiones movimientos complicados de su cuerpo, como dar vueltas, retorcerse o dar saltos repetidos en el sitio?",
    "¿Se ha hecho daño a propósito alguna vez, por ejemplo, mordiéndose un brazo o golpeándose la cabeza?",
    "¿Ha tenido alguna vez objetos que necesitaba llevar consigo, aparte de un muñeco o una manta?",
    "¿Tiene un amigo íntimo o alguna amistad en particular?",
    "Cuando tenía entre 4 y 5 años, ¿habló con usted alguna vez solo para ser simpático y amable y no para conseguir algo?",
    "Cuando tenía entre 4 y 5 años, ¿imitaba alguna vez espontáneamente a otras personas o lo que hacían, como pasar la aspiradora, cocinar o arreglar cosas?",
    "Cuando tenía entre 4 y 5 años, ¿señalaba alguna vez espontáneamente las cosas que veía solo para mostrárselas a usted y no porque quisiese obtenerlas?",
    "Cuando tenía entre 4 y 5 años, ¿hacía alguna vez gestos para indicarle lo que quería, aparte de señalar el objeto o tirarle a usted de la mano?",
    "Cuando tenía entre 4 y 5 años, ¿asentía con la cabeza para decir que sí?",
    "Cuando tenía entre 4 y 5 años, ¿negaba con la cabeza para decir que no?",
    "Cuando tenía entre 4 y 5 años, ¿solía mirarle directamente a la cara?",
    "Cuando tenía entre 4 y 5 años, ¿devolvía la sonrisa si alguien le sonreía?",
    "Cuando tenía entre 4 y 5 años, ¿le mostraba a usted alguna vez que le interesaba a fin de captar su atención?",
    "Cuando tenía entre 4 y 5 años, ¿se ofrecía alguna vez a compartir cosas con usted, aparte de alimentos?",
    "Cuando tenía entre 4 y 5 años, ¿quiso alguna vez que usted participara en sus juegos?",
    "Cuando tenía entre 4 y 5 años, ¿intentó alguna vez consolarle si vio que usted estaba triste o se había hecho daño?",
    "Cuando tenía entre 4 y 5 años y quería algo o buscaba ayuda, ¿le miraba y hacía gestos con sonidos o palabras para captar su atención?",
    "Cuando tenía entre 4 y 5 años, ¿mostraba una variedad normal de expresiones faciales?",
    "Cuando tenía entre 4 y 5 años, ¿tomó parte espontáneamente alguna vez en juegos de grupo o trató de imitar las acciones de los juegos sociales?",
    "Cuando tenía entre 4 y 5 años, ¿jugaba a disfrazarse, a simular que era otra persona o a juegos de ficción en general?",
    "Cuando tenía entre 4 y 5 años, ¿mostraba intereses por niños de su edad a los que no conocía?",
    "Cuando tenía entre 4 y 5 años, ¿respondía positivamente al acercársele otro niño?",
    "Cuando tenía entre 4 y 5 años, si usted entraba en un cuarto y empezaba a hablarle sin decir su nombre, ¿por lo general levantaba la vista prestándole atención?",
    "Cuando tenía entre 4 y 5 años, ¿participó alguna vez con otros niños en juegos de ficción, de tal manera que fuese claro que unos y otros comprendían en qué consistía el juego?",
    "Cuando tenía entre 4 y 5 años, ¿participaba activamente en juegos que requerían colaborar con otros niños en grupo, como jugar al escondite o a la pelota?"
  ];

  late final List<int> _respuestas;
  bool _aceptoDisclaimer = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Las respuestas se inicializan en -1 (sin responder) para obligar a completar todo.
    _respuestas = List.filled(40, -1);
  }

  // Comprueba si una pregunta suma un punto clínico según el valor seleccionado
  bool _scoresPoint(int index, int val) {
    if (index == 0) return false;

    // Si Q1 = No, las preguntas 2 a 7 están omitidas
    final hablaFrases = _respuestas[0] == 1;
    if (!hablaFrases && 1 <= index && index <= 6) return false;

    // Preguntas donde 'No' (0) suma 1 punto
    final Set<int> noScores1 = {1, 8, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39};
    // Preguntas donde 'Sí' (1) suma 1 punto
    final Set<int> yesScores1 = {2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17};

    if (noScores1.contains(index)) {
      return val == 0;
    }
    if (yesScores1.contains(index)) {
      return val == 1;
    }
    return false;
  }

  // Calcula el puntaje en tiempo real en la pantalla
  int _calculateLiveScore() {
    int score = 0;
    final hablaFrases = _respuestas[0] == 1;
    for (int i = 1; i < 40; i++) {
      if (!hablaFrases && 1 <= i && i <= 6) continue;
      final val = _respuestas[i];
      if (val != -1 && _scoresPoint(i, val)) {
        score++;
      }
    }
    return score;
  }

  // Retorna el nivel de indicio estimado en base al puntaje actual
  String _getLiveIndicationLevel() {
    final score = _calculateLiveScore();
    if (score >= 15) return "Alto";
    if (score >= 11) return "Moderado";
    return "Bajo";
  }

  // Devuelve la cantidad de preguntas que faltan responder
  int _getPendingCount() {
    int pending = 0;
    final hablaFrases = _respuestas[0] == 1;

    if (_respuestas[0] == -1) return 40;

    for (int i = 0; i < 40; i++) {
      if (!hablaFrases && 1 <= i && i <= 6) {
        continue;
      }
      if (_respuestas[i] == -1) {
        pending++;
      }
    }
    return pending;
  }

  int _getTotalActiveCount() {
    final hablaFrases = _respuestas[0] == 1;
    return hablaFrases ? 40 : 34;
  }

  int _getAnsweredCount() {
    int answered = 0;
    final hablaFrases = _respuestas[0] == 1;
    for (int i = 0; i < 40; i++) {
      if (!hablaFrases && 1 <= i && i <= 6) {
        continue;
      }
      if (_respuestas[i] != -1) {
        answered++;
      }
    }
    return answered;
  }

  void _onQ1Changed(int val) {
    setState(() {
      _respuestas[0] = val;
      if (val == 0) {
        // Si responde No a Q1, las preguntas 2 a 7 se marcan automáticamente como 0 (No) para el backend
        for (int i = 1; i <= 6; i++) {
          _respuestas[i] = 0;
        }
      } else {
        // Si cambia a Sí, reseteamos las preguntas 2 a 7 a -1 (sin responder) si estaban automáticas
        for (int i = 1; i <= 6; i++) {
          _respuestas[i] = -1;
        }
      }
    });
  }

  void _submit() async {
    final pending = _getPendingCount();
    if (pending > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Por favor, responda todas las preguntas. Faltan $pending por responder.',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _kGreenStrong,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

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
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: _kGreenStrong,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final useCase = ref.read(submitSCQUsecaseProvider);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // Botón Sí / No Premium con animación táctil
  Widget _buildChoiceButton(String text, {required bool isSelected, required bool enabled, required VoidCallback onTap}) {
    final themeColor = text == "Sí" ? _kGreenStrong : _kSub;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.grey.shade100
              : (isSelected ? themeColor.withOpacity(0.12) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !enabled
                ? Colors.grey.shade200
                : (isSelected ? themeColor : _kBdr.withOpacity(0.6)),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: !enabled
                ? Colors.grey.shade400
                : (isSelected ? themeColor : _kSub),
          ),
        ),
      ),
    );
  }

  // Tarjeta de pregunta con soporte para desactivado/skipped
  Widget _buildQuestionCard(int index) {
    final hablaFrases = _respuestas[0] == 1;
    final isSkipped = !hablaFrases && 1 <= index && index <= 6;
    final val = _respuestas[index];
    final isSelectedYes = val == 1;
    final isSelectedNo = val == 0;

    String subtitleText = "Seleccione una respuesta";
    Color subtitleColor = _kSub;

    if (isSkipped) {
      subtitleText = "Pregunta omitida (no habla con frases cortas)";
      subtitleColor = Colors.grey.shade500;
    } else if (val != -1) {
      final pointsPoint = _scoresPoint(index, val);
      if (pointsPoint) {
        subtitleText = "Representa un indicador de riesgo de comunicación (+1 punto)";
        subtitleColor = _kGreenStrong;
      } else {
        subtitleText = "Representa un desarrollo típico esperado (0 puntos)";
        subtitleColor = const Color(0xFF15803D); // Forest Green
      }
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSkipped ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSkipped
              ? Colors.grey.shade50
              : (val != -1 ? Colors.white : _kSurf.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSkipped
                ? Colors.grey.shade200
                : (val != -1
                    ? (_scoresPoint(index, val) ? _kP.withOpacity(0.4) : _kA.withOpacity(0.5))
                    : _kBdr.withOpacity(0.4)),
            width: val != -1 ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (val != -1 && !isSkipped)
              BoxShadow(
                color: _scoresPoint(index, val) ? _kP.withOpacity(0.02) : _kA.withOpacity(0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
          ]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSkipped ? Colors.grey.shade200 : _kP.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${index + 1}",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSkipped ? Colors.grey.shade500 : _kGreenStrong,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _preguntas[index],
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSkipped ? Colors.grey.shade500 : _kText,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subtitleText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: val != -1 && !isSkipped ? FontWeight.bold : FontWeight.normal,
                      color: subtitleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    _buildChoiceButton(
                      "Sí",
                      isSelected: isSelectedYes,
                      enabled: !isSkipped,
                      onTap: () {
                        setState(() {
                          _respuestas[index] = 1;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildChoiceButton(
                      "No",
                      isSelected: isSelectedNo,
                      enabled: !isSkipped,
                      onTap: () {
                        setState(() {
                          _respuestas[index] = 0;
                        });
                      },
                    ),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientDisplayName = widget.patientName ?? "el Paciente";
    final totalActive = _getTotalActiveCount();
    final answered = _getAnsweredCount();
    final progressVal = totalActive > 0 ? answered / totalActive : 0.0;
    final liveScore = _calculateLiveScore();
    final indicationLevel = _getLiveIndicationLevel();

    return Scaffold(
      backgroundColor: _kBg,
      appBar: RimAITopBar(
        title: "Cuestionario SCQ",
        leadingIcon: Icons.arrow_back_ios_new,
        onLeadingPressed: () => context.pop(),
        iconColor: _kGreenStrong,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: _kGreenStrong),
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
          : Stack(
              children: [
                Column(
                  children: [
                    // Sticky Header con Progreso y Puntaje Preliminar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: _kBdr.withOpacity(0.4))),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Progreso del Cuestionario",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _kSub,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "$answered de $totalActive respondidas",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: _kText,
                                    ),
                                  ),
                                ],
                              ),
                              if (_respuestas[0] != -1)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _kP.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "Puntaje: ",
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: _kSub,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        "$liveScore pts",
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          color: _kGreenStrong,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          color: _kSub,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Indicio: $indicationLevel",
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: _kGreenStrong,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(100),
                            child: LinearProgressIndicator(
                              value: progressVal,
                              backgroundColor: Colors.grey.shade200,
                              color: progressVal == 1.0 ? _kA : _kP,
                              minHeight: 6,
                            ),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Evaluación Preliminar de Indicadores TEA",
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: _kText,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Basado en el Cuestionario de Comunicación Social (SCQ) oficial de 40 ítems para $patientDisplayName.",
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: _kSub,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Caja de instrucciones oficial (padre, madre o tutor)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _kA.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _kA.withOpacity(0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.description_outlined, color: _kSub, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Instrucciones de Respuesta",
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.bold,
                                          color: _kText,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Este cuestionario debe ser respondido por el padre, madre o tutor, pensando en el comportamiento que el niño o niña ha mostrado a lo largo de su vida. Cada pregunta se responde con Sí o No. En algunos casos, si la conducta ocurrió al menos una vez o de alguna forma parecida, se debe marcar Sí. Si existe duda, responda según la opción que parezca más correcta.",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12.5,
                                      color: _kSub,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Pregunta 1: Pregunta filtro (prominente e independiente)
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _respuestas[0] != -1 ? _kP : _kBdr.withOpacity(0.6),
                                  width: _respuestas[0] != -1 ? 2.0 : 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kP.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _kP,
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        child: Text(
                                          "Pregunta Filtro",
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _preguntas[0],
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _kText,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _respuestas[0] == -1
                                              ? "Respuesta requerida para habilitar el cuestionario"
                                              : (_respuestas[0] == 1
                                                  ? "Se habilitan todas las preguntas (2 a 40)"
                                                  : "Se omitirán preguntas de habla (2 a 7)"),
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _respuestas[0] == -1 ? _kGreenStrong : _kSub,
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          _buildChoiceButton(
                                            "Sí",
                                            isSelected: _respuestas[0] == 1,
                                            enabled: true,
                                            onTap: () => _onQ1Changed(1),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildChoiceButton(
                                            "No",
                                            isSelected: _respuestas[0] == 0,
                                            enabled: true,
                                            onTap: () => _onQ1Changed(0),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Panel Desplegable 1: Comportamiento General (Q2 a Q19)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _kBdr.withOpacity(0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kP.withOpacity(0.01),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  initiallyExpanded: true,
                                  iconColor: _kGreenStrong,
                                  collapsedIconColor: _kSub,
                                  title: Text(
                                    "Comportamiento General",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _kText,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "Preguntas 2 a 19 · Hábitos y patrones a lo largo de su vida",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: _kSub,
                                    ),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                      child: Column(
                                        children: List.generate(18, (i) {
                                          final qIndex = i + 1; // Preguntas 2 a 19 (índices 1 a 18)
                                          return _buildQuestionCard(qIndex);
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Panel Desplegable 2: Comportamiento Infancia (Q20 a Q40)
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _kBdr.withOpacity(0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kP.withOpacity(0.01),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  initiallyExpanded: false,
                                  iconColor: _kGreenStrong,
                                  collapsedIconColor: _kSub,
                                  title: Text(
                                    "Comportamiento entre 4 y 5 años",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _kText,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "Preguntas 20 a 40 · Desarrollo y relaciones retrospectivas",
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: _kSub,
                                    ),
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                      child: Column(
                                        children: List.generate(21, (i) {
                                          final qIndex = i + 19; // Preguntas 20 a 40 (índices 19 a 39)
                                          return _buildQuestionCard(qIndex);
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Advertencia Legal obligatoria (RNF-10)
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _kP.withOpacity(0.5), width: 1.5),
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
                                      const Icon(Icons.gavel_rounded, color: _kGreenStrong, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        "Advertencia Legal Obligatoria (RNF-10)",
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.bold,
                                          color: _kGreenStrong,
                                          fontSize: 13.5,
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
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
