import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/scq_providers.dart';
import 'package:rimai_app/domain/entities/scq_result.dart';

const _kP = Color(0xFFA43714);
const _kBg = Color(0xFFFFF8F2);
const _kSurf = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSub = Color(0xFF58423B);
const _kBdr = Color(0xFFDFC0B7);

class SCQResultScreen extends ConsumerStatefulWidget {
  final SCQResult result;

  const SCQResultScreen({super.key, required this.result});

  @override
  ConsumerState<SCQResultScreen> createState() => _SCQResultScreenState();
}

class _SCQResultScreenState extends ConsumerState<SCQResultScreen> {
  bool _sending = false;

  Future<void> _sendToTherapist() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(submitSCQUsecaseProvider)
          .enviarCasoATerapeuta(widget.result.patientId);
      ref.invalidate(familiaDashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud enviada al terapeuta.')),
        );
        context.go('/familia/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String description;

    if (widget.result.nivelIndicio == 'Alto') {
      statusColor = const Color(0xFFDC2626);
      statusIcon = Icons.warning_amber_rounded;
      description =
          'Se ha identificado un alto indicio de dificultades en la comunicacion social. Se recomienda priorizar una evaluacion clinica presencial.';
    } else if (widget.result.nivelIndicio == 'Moderado') {
      statusColor = const Color(0xFFD97706);
      statusIcon = Icons.info_outline;
      description =
          'Se observa un nivel moderado de indicadores. Un terapeuta debe revisar el perfil y confirmar clinicamente la situacion.';
    } else {
      statusColor = const Color(0xFF15803D);
      statusIcon = Icons.check_circle_outline;
      description =
          'Los indicadores se encuentran dentro del rango esperado. Si aun existe preocupacion, puede solicitar revision profesional.';
    }

    return Scaffold(
      backgroundColor: _kBg,
      appBar: RimAITopBar(
        title: 'Resultados SCQ',
        leadingIcon: Icons.home,
        onLeadingPressed: () => context.go('/familia/dashboard'),
        iconColor: _kP,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.08),
                shape: BoxShape.circle,
                border:
                    Border.all(color: statusColor.withOpacity(0.2), width: 2),
              ),
              child: Icon(statusIcon, size: 84, color: statusColor),
            ),
            const SizedBox(height: 28),
            Text(
              'Nivel de Indicio SCQ',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _kSub,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.result.nivelIndicio,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _kSurf,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: _kBdr.withOpacity(0.4)),
              ),
              child: Text(
                'Puntaje total: ${widget.result.puntajeTotal} puntos',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kBdr.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: _kText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: _kBdr),
                  const SizedBox(height: 12),
                  Text(
                    'Uso no diagnostico: este resultado es solo una orientacion preliminar. No reemplaza una evaluacion medica o clinica profesional.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: _kSub,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
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
                onPressed: _sending ? null : _sendToTherapist,
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Enviar solicitud al terapeuta',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed:
                  _sending ? null : () => context.go('/familia/dashboard'),
              child: Text(
                'Volver sin enviar por ahora',
                style: GoogleFonts.plusJakartaSans(
                  color: _kSub,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
