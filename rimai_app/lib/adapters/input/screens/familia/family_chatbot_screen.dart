import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';

const _kPrimary = Color(0xFFA43714);
const _kBg = Color(0xFFFFF8F2);
const _kSurface = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSubtext = Color(0xFF58423B);

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class FamilyChatbotScreen extends ConsumerStatefulWidget {
  const FamilyChatbotScreen({super.key});

  @override
  ConsumerState<FamilyChatbotScreen> createState() =>
      _FamilyChatbotScreenState();
}

class _FamilyChatbotScreenState extends ConsumerState<FamilyChatbotScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _selectedNinoId;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Mensaje de bienvenida inicial
    _messages.add(
      ChatMessage(
        text:
            '¡Hola! Soy tu asistente de IA especializado de RimAI. Estoy aquí para ayudarte a comprender mejor el desarrollo de tu hijo, resolver dudas sobre el autismo (TEA), consultar sus rutinas de regulación o ver qué actividades tenemos preparadas para su sesión de hoy. ¿De quién te gustaría conversar hoy?',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend(String text, {PacientePerfil? perfil, PlanData? plan}) {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
      _isTyping = true;
    });
    _scrollToBottom();

    // Simular retraso del chatbot local (< 1.5s)
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final reply = _generateResponse(text, perfil: perfil, plan: plan);
      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(
            text: reply,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
    });
  }

  String _generateResponse(String text,
      {PacientePerfil? perfil, PlanData? plan}) {
    final query = text.toLowerCase().trim();
    final nombre = perfil?.nombre ?? 'tu niño';

    // 1. Preguntas sobre actividades del plan / sesión actual
    if (query.contains('actividad') ||
        query.contains('actividades') ||
        query.contains('sesion') ||
        query.contains('sesión') ||
        query.contains('plan') ||
        query.contains('hoy')) {
      if (plan == null || plan.actividades.isEmpty) {
        return 'Actualmente no veo un plan de actividades activo o publicado para $nombre. Te sugiero consultar con su terapeuta para que diseñe y apruebe la sesión correspondiente.';
      }

      final buffer = StringBuffer();
      buffer.writeln(
          'Para la sesión de hoy de **$nombre** (Sesión ${plan.sesionNumero}), tenemos programadas las siguientes actividades:');
      buffer.writeln();
      for (var i = 0; i < plan.actividades.length; i++) {
        final act = plan.actividades[i];
        final tipo = act.requiereAcompanamiento
            ? 'Acompañada (requiere tu apoyo)'
            : 'Autónoma (el niño puede hacerla solo)';
        buffer.writeln('${i + 1}. **${act.nombre}** (${act.nivelDificultad}):');
        buffer.writeln('   - *Tipo:* $tipo');
        buffer.writeln(
            '   - *Instrucciones:* ${act.instrucciones ?? "Sin instrucciones específicas."}');
        if (i < plan.actividades.length - 1) buffer.writeln();
      }
      buffer.writeln();
      buffer.writeln(
          '¿Tienes alguna duda sobre cómo ejecutar alguna de ellas en casa?');
      return buffer.toString();
    }

    // 2. Preguntas sobre rutinas de regulación
    if (query.contains('regular') ||
        query.contains('regulacion') ||
        query.contains('regulación') ||
        query.contains('crisis') ||
        query.contains('calmar') ||
        query.contains('rutina') ||
        query.contains('rutinas')) {
      if (perfil == null || perfil.rutinasRegulacion.isEmpty) {
        return 'No tienes registradas rutinas de regulación específicas para $nombre en su perfil familiar.\n\n**Consejo general de regulación sensorial:**\nSi notas que $nombre se encuentra sobreestimulado o desregulado:\n1. **Espacio seguro:** Llévalo a un ambiente con baja estimulación visual y auditiva.\n2. **Presión profunda:** Muchos niños con TEA responden positivamente a abrazos contenedores o mantas con peso.\n3. **Anticipación:** Háblale con voz suave explicando pausadamente lo que va a ocurrir para mitigar la ansiedad.\n\nTe recomiendo registrar sus rutinas preferidas en el botón "Editar registro" de su tarjeta en el Inicio para que el terapeuta también las considere.';
      }

      final buffer = StringBuffer();
      buffer.writeln(
          'Aquí tienes las rutinas de regulación que has registrado para **$nombre**:');
      for (final r in perfil.rutinasRegulacion) {
        buffer.writeln('• $r');
      }
      buffer.writeln();
      buffer.writeln(
          'Estas rutinas son esenciales para el terapeuta al planificar las actividades. ¿Te gustaría saber más sobre cómo aplicarlas durante las crisis sensoriales?');
      return buffer.toString();
    }

    // 3. Preguntas sobre medicación
    if (query.contains('medicacion') ||
        query.contains('medicación') ||
        query.contains('medicamento') ||
        query.contains('medicamentos') ||
        query.contains('remedio')) {
      if (perfil == null ||
          perfil.medicacionActual == null ||
          perfil.medicacionActual!.trim().isEmpty) {
        return 'No tienes registrada ninguna medicación actual para $nombre.\n\n*Nota:* Recuerda que cualquier administración de medicamentos debe estar siempre supervisada y recetada por su neuropediatra o pediatra de cabecera.';
      }
      return 'De acuerdo al perfil clínico registrado para **$nombre**, su medicación actual consiste en:\n\n${perfil.medicacionActual}\n\n*Recuerda:* Si hay algún cambio en su dosis o tratamiento, asegúrate de actualizar el registro en la aplicación familiar y notificar a su terapeuta.';
    }

    // 4. Preguntas sobre objetivos de intervención
    if (query.contains('objetivo') ||
        query.contains('objetivos') ||
        query.contains('meta') ||
        query.contains('metas')) {
      if (perfil == null || perfil.objetivosIntervencion.isEmpty) {
        return 'Aún no se han configurado objetivos terapéuticos específicos para $nombre en su perfil clínico. El terapeuta los establecerá tan pronto valide clínicamente el caso.';
      }
      final buffer = StringBuffer();
      buffer.writeln(
          'Los objetivos terapéuticos actuales establecidos para **$nombre** son:');
      for (var i = 0; i < perfil.objetivosIntervencion.length; i++) {
        buffer.writeln('${i + 1}. ${perfil.objetivosIntervencion[i]}');
      }
      return buffer.toString();
    }

    // 5. Preguntas generales sobre TEA
    if (query.contains('que es') ||
        query.contains('qué es') ||
        query.contains('tea') ||
        query.contains('autismo')) {
      return 'El **Trastorno del Espectro Autista (TEA)** es una condición del neurodesarrollo que influye en cómo las personas perciben el mundo e interactúan con los demás. Se caracteriza principalmente por:\n\n'
          '• **Diferencias en la comunicación y el juego social:** Van desde la ausencia del habla o ecolalia, hasta dificultades en interpretar expresiones faciales u metáforas.\n'
          '• **Intereses enfocados y conductas repetitivas:** Gusto por mantener rutinas fijas, movimientos como el aleteo (stimming) que les ayudan a autorregularse, e intereses profundos en temas específicos (como trenes o dinosaurios).\n'
          '• **Procesamiento sensorial atípico:** Mayor sensibilidad (hipersensibilidad) o menor sensibilidad (hiposensibilidad) a ruidos, luces, texturas o movimientos.\n\n'
          'Cada niño es único y progresa a su propio ritmo. ¡El apoyo oportuno y el trabajo conjunto en casa y terapia marcan una gran diferencia!';
    }

    if (query.contains('aleteo') ||
        query.contains('stimming') ||
        query.contains('repetitivo') ||
        query.contains('balanceo')) {
      return 'Los comportamientos repetitivos, como el **aleteo de manos (stimming)** o el balanceo, son herramientas naturales de **autorregulación**. Los niños con TEA los utilizan para calmarse ante la sobrecarga sensorial o emocional, o para expresar emoción extrema.\n\n'
          '**¿Qué hacer?**\n'
          '• No reprimas el stimming a menos que sea autolesivo.\n'
          '• Trata de identificar el detonante: ¿es por entusiasmo, aburrimiento o ansiedad por ruido?\n'
          '• Si es por estrés, acompáñalo a un lugar tranquilo y utiliza sus objetos reguladores o presiones profundas.';
    }

    if (query.contains('ruido') ||
        query.contains('ruidos') ||
        query.contains('hiper') ||
        query.contains('sensorial')) {
      final tieneHipersensibilidad =
          perfil?.perfilSensorial['hipersensibilidad'] != null &&
              (perfil!.perfilSensorial['hipersensibilidad'] as List).isNotEmpty;

      final evitaciones = tieneHipersensibilidad
          ? '\n\nPara **$nombre**, tienes registrado que suele evitar: ' +
              (perfil.perfilSensorial['hipersensibilidad'] as List)
                  .join(', ')
                  .toLowerCase() +
              '.'
          : '';

      return 'La **hipersensibilidad sensorial** es muy común. Estímulos cotidianos como la licuadora, el secador de pelo o centros comerciales concurridos pueden ser percibidos como dolorosos o abrumadores.$evitaciones\n\n'
          '**Consejos prácticos para manejarlo:**\n'
          '1. **Uso de audífonos de cancelación de ruido:** Excelentes para salidas o ruidos imprevistos en casa.\n'
          '2. **Anticipación visual o verbal:** "Hijo, voy a encender la licuadora, ponte tus audífonos".\n'
          '3. **Zonas de calma:** Tener una pequeña carpa o rincón en casa con luces tenues y cojines suaves donde pueda refugiarse.';
    }

    // 6. Fallback amigable
    return 'Entiendo tu consulta. Como asistente de IA especializado en TEA y en la evolución de **$nombre**, te comento que es ideal reforzar siempre la estimulación positiva en casa. \n\nPuedes preguntarme sobre:\n'
        '• Las actividades de la sesión de hoy (ej. "*¿Qué actividades tiene hoy?*").\n'
        '• Sus rutinas de regulación sensorial (ej. "*¿Cómo puedo ayudarlo a regularse?*").\n'
        '• Sus objetivos terapéuticos o medicación registrada.\n'
        '• Consultas generales de TEA (ej. "*¿Qué es el aleteo?*", "*Manejo de hipersensibilidad*").\n\n'
        '¿En qué más te gustaría profundizar para acompañar a $nombre hoy?';
  }

  @override
  Widget build(BuildContext context) {
    final familyDataAsync = ref.watch(familiaDashboardProvider);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: const RimAITopBar(
        title: 'Asistente IA Familiar',
        leadingIcon: Icons.forum_rounded,
        iconColor: _kPrimary,
      ),
      body: familyDataAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _kPrimary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudo cargar la información familiar: $err',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) {
          final pacientes = data.pacientes;

          // Seleccionar automáticamente el primer niño si no hay selección
          if (_selectedNinoId == null && pacientes.isNotEmpty) {
            _selectedNinoId = pacientes.first.id;
          }

          final selectedNino = pacientes.isEmpty
              ? null
              : pacientes.firstWhere((p) => p.id == _selectedNinoId,
                  orElse: () => pacientes.first);

          return Consumer(
            builder: (context, ref, child) {
              // Cargar dinámicamente el perfil del paciente y su plan
              final perfilAsync = _selectedNinoId != null
                  ? ref.watch(perfilPacienteProvider(_selectedNinoId!))
                  : null;
              final planAsync = _selectedNinoId != null
                  ? ref.watch(planActivoProvider(_selectedNinoId!))
                  : null;

              final PacientePerfil? perfil = perfilAsync?.valueOrNull;
              final PlanData? plan = planAsync?.valueOrNull;

              return Column(
                children: [
                  // Banner de Selector de Niño
                  if (pacientes.isNotEmpty)
                    Container(
                      color: _kSurface,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.child_care_rounded,
                              color: _kPrimary, size: 20),
                          const SizedBox(width: 10),
                          const Text(
                            'Consultando sobre:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: _kSubtext),
                          ),
                          const Spacer(),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedNinoId,
                              dropdownColor: _kSurface,
                              icon: const Icon(Icons.arrow_drop_down,
                                  color: _kPrimary),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _kPrimary,
                                fontSize: 15,
                              ),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedNinoId = val;
                                    // Agregar mensaje informando el cambio de contexto
                                    final pName = pacientes
                                        .firstWhere((p) => p.id == val)
                                        .nombre;
                                    _messages.add(
                                      ChatMessage(
                                        text:
                                            'Cambiando el asistente al contexto de **$pName**. Ahora mis respuestas considerarán sus datos particulares de regulación y actividades de sesión.',
                                        isUser: false,
                                        timestamp: DateTime.now(),
                                      ),
                                    );
                                  });
                                  _scrollToBottom();
                                }
                              },
                              items: pacientes.map((p) {
                                return DropdownMenuItem<String>(
                                  value: p.id,
                                  child: Text(p.nombre),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Caja de Mensajes
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(24),
                      itemCount: _messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isTyping) {
                          return _buildTypingIndicator();
                        }
                        final message = _messages[index];
                        return _buildMessageBubble(message);
                      },
                    ),
                  ),

                  // Fichas de Sugerencia rápidas
                  if (_messages.length <= 2 && selectedNino != null)
                    _buildSuggestionChips(selectedNino.nombre, perfil, plan),

                  // Campo de Entrada de Texto
                  _buildInputArea(perfil, plan),
                ],
              );
            },
          );
        },
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 1, // Chatbot IA
        onTap: (index) {
          if (index == 0) {
            context.go('/familia/dashboard');
          }
        },
        items: [
          BottomNavItem(icon: Icons.home_rounded, label: 'Inicio'),
          BottomNavItem(icon: Icons.forum_rounded, label: 'Asistente IA'),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: msg.isUser ? _kPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: msg.isUser ? const Radius.circular(20) : Radius.zero,
            bottomRight: msg.isUser ? Radius.zero : const Radius.circular(20),
          ),
          border: msg.isUser
              ? null
              : Border.all(color: _kSubtext.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Procesa texto simple con soporte de negritas básicas **
            _buildMarkdownText(msg.text, msg.isUser),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 10,
                  color: msg.isUser
                      ? Colors.white.withValues(alpha: 0.6)
                      : _kSubtext.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkdownText(String rawText, bool isUser) {
    final style = GoogleFonts.plusJakartaSans(
      fontSize: 14.5,
      height: 1.45,
      color: isUser ? Colors.white : _kText,
    );

    final List<InlineSpan> spans = [];
    final reg = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final match in reg.allMatches(rawText)) {
      if (match.start > start) {
        spans.add(TextSpan(text: rawText.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      start = match.end;
    }

    if (start < rawText.length) {
      spans.add(TextSpan(text: rawText.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: spans,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.zero,
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: _kSubtext.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(0),
            const SizedBox(width: 5),
            _buildDot(1),
            const SizedBox(width: 5),
            _buildDot(2),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int delayIndex) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: _kPrimary,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildSuggestionChips(
      String ninoNombre, PacientePerfil? perfil, PlanData? plan) {
    final chips = [
      (
        '📊 ¿Qué actividades tiene hoy?',
        '¿Qué actividades tiene programadas $ninoNombre hoy?'
      ),
      (
        '🧘‍♂️ ¿Cómo puedo ayudarlo a regularse?',
        '¿Cómo puedo ayudar a regularse a $ninoNombre?'
      ),
      (
        '📘 ¿Qué es el TEA y cómo influye?',
        '¿Qué es el TEA y cuáles son sus características principales?'
      ),
      (
        '💡 Manejo de hipersensibilidad sensorial',
        '¿Cómo manejar la hipersensibilidad sensorial y ruidos fuertes?'
      ),
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final item = chips[index];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ActionChip(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              side: const BorderSide(color: _kPrimary, width: 1.0),
              label: Text(
                item.$1,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: _kPrimary,
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
              onPressed: () => _handleSend(item.$2, perfil: perfil, plan: plan),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea(PacientePerfil? perfil, PlanData? plan) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      decoration: BoxDecoration(
        color: _kBg,
        border: Border(
          top: BorderSide(
            color: _kSubtext.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                style: GoogleFonts.plusJakartaSans(color: _kText, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Pregúntame sobre rutinas, actividades o TEA...',
                  hintStyle: TextStyle(
                    color: _kSubtext.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  border: InputBorder.none,
                ),
                onSubmitted: (val) =>
                    _handleSend(val, perfil: perfil, plan: plan),
              ),
            ),
          ),
          const SizedBox(width: 14),
          IconButton.filled(
            onPressed: () =>
                _handleSend(_controller.text, perfil: perfil, plan: plan),
            icon: const Icon(Icons.send_rounded),
            style: IconButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}
