import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/tag_chip.dart';
import 'package:rimai_app/adapters/input/widgets/interest_card.dart';
import 'package:rimai_app/core/constants/api_constants.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

class TherapeuticProfileScreen extends ConsumerStatefulWidget {
  final String ninoId;
  final bool editMode;
  const TherapeuticProfileScreen({
    super.key,
    required this.ninoId,
    this.editMode = false,
  });

  @override
  ConsumerState<TherapeuticProfileScreen> createState() =>
      _TherapeuticProfileScreenState();
}

class _TherapeuticProfileScreenState
    extends ConsumerState<TherapeuticProfileScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _objectivesController = TextEditingController();
  final _clinicalNotesController = TextEditingController();
  List<String> _selectedInterests = [];
  Map<String, List<String>> _aversiveStimuli = {
    'RUIDO': [],
    'COLORES': [],
    'LUGARES': []
  };
  bool _dataInitialized = false;
  bool _isGeneratingPlan = false;
  bool _isSavingValidation = false;
  int _nivelTea = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _objectivesController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  void _toggleAversive(String category, String item) {
    setState(() {
      if (_aversiveStimuli[category]?.contains(item) ?? false) {
        _aversiveStimuli[category]?.remove(item);
      } else {
        _aversiveStimuli[category]?.add(item);
        // Guardar cambios vía el provider si es necesario.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final perfilAsync = ref.watch(perfilPacienteProvider(widget.ninoId));

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      extendBodyBehindAppBar: true,
      appBar: RimAITopBar(
        title: "RimAI",
        leadingIcon: Icons.all_inclusive,
        iconColor: const Color(0xFFA43714),
        trailingWidget: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF58423B)),
          tooltip: 'Volver al dashboard',
          onPressed: () => context.go('/terapeuta/dashboard'),
        ),
      ),
      body: perfilAsync.when(
        data: (perfil) {
          if (!_dataInitialized) {
            _nameController.text = perfil.nombre;
            _ageController.text = perfil.edad.toString();
            _selectedInterests = List.from(perfil.intereses);
            _aversiveStimuli = perfil.estimulosAversivos
                .map((key, value) => MapEntry(key, List<String>.from(value)));
            _nivelTea = perfil.nivelTeaValidado ??
                _nivelTeaFromDiagnosis(perfil.diagnostico);
            _objectivesController.text = perfil.objetivosIntervencion.isEmpty
                ? 'Mejorar comunicacion funcional\nIncrementar tolerancia a rutinas guiadas\nFortalecer autonomia en actividades diarias'
                : perfil.objetivosIntervencion.join('\n');
            _dataInitialized = true;
          }

          final hasPlan = perfil.planActivoId != null;
          final showActionsOnly = hasPlan && !widget.editMode;
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                top: 96 + MediaQuery.of(context).padding.top,
                left: 24,
                right: 24,
                bottom: 48,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: showActionsOnly
                    ? [
                        _buildActionsHeader(perfil),
                        const SizedBox(height: 20),
                        _buildEstadoBadge(perfil.estadoClinico),
                        const SizedBox(height: 24),
                        _buildQuickNav(perfil, compact: true),
                      ]
                    : [
                        _buildHeader(),
                        const SizedBox(height: 32),
                        _buildBentoGrid(),
                        const SizedBox(height: 32),
                        _buildEstadoBadge(perfil.estadoClinico),
                        const SizedBox(height: 24),
                        _buildFamilyDataCard(perfil),
                        const SizedBox(height: 24),
                        _buildClinicalValidationCard(perfil),
                        const SizedBox(height: 24),
                        _buildQuickNav(perfil),
                      ],
              ),
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFB8D6B2)),
        ),
        error: (err, stack) => Center(
          child: Text("Error: $err", style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Perfil Terapéutico",
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Color(0xFF1E1B16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Documentación detallada para el plan de intervención personalizado.",
          style: TextStyle(
            fontSize: 16,
            color: const Color(0xFF58423B).withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsHeader(PacientePerfil perfil) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          perfil.nombre,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1E1B16),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Plan activo listo. Accede a las acciones principales sin revisar todo el perfil clinico.',
          style: TextStyle(
            fontSize: 16,
            color: const Color(0xFF58423B).withValues(alpha: 0.8),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1024) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    _buildPatientInfoCard(),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildInterestsCard(),
                    const SizedBox(height: 24),
                    _buildAversiveStimuliCard(),
                  ],
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildPatientInfoCard(),
              const SizedBox(height: 24),
              _buildInterestsCard(),
              const SizedBox(height: 24),
              _buildAversiveStimuliCard(),
            ],
          );
        }
      },
    );
  }

  int _nivelTeaFromDiagnosis(String? diagnostico) {
    final text = (diagnostico ?? '').toLowerCase();
    if (text.contains('nivel 3') || text.contains('nivel iii')) return 3;
    if (text.contains('nivel 2') || text.contains('nivel ii')) return 2;
    return 1;
  }

  Widget _buildPatientInfoCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge, color: Color(0xFFB8D6B2)),
              SizedBox(width: 8),
              Text(
                "Información del Paciente",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF1E1B16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFFB8D6B2), width: 4),
                        color: const Color(0xFFB8D6B2),
                      ),
                      child: Center(
                        child: Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text
                                  .substring(0, 1)
                                  .toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E1B16)),
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFB8D6B2),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.edit,
                            size: 16, color: Color(0xFF1E1B16)),
                        onPressed: () {},
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                _buildTextField("Nombre del Paciente", _nameController),
                const SizedBox(height: 16),
                _buildTextField("Edad", _ageController,
                    keyboardType: TextInputType.number),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF58423B).withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildInterestsCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.star_border, color: Color(0xFFB8D6B2)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Intereses y Preferencias",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF1E1B16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 16, color: Color(0xFF1E1B16)),
                label: const Text("Añadir",
                    style: TextStyle(color: Color(0xFF1E1B16))),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB8D6B2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                  elevation: 0,
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          _buildSubSectionLabel("TEMAS Y FORMAS", Icons.category),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width < 768 ? 2 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio:
                1, // To make them square-ish based on height spec 128
            children: [
              InterestCard(
                label: "Dinosaurios",
                imageUrl:
                    "https://images.unsplash.com/photo-1596489370607-bb1b590e82aa?q=80&w=300",
                isSelected: _selectedInterests.contains("Dinosaurios"),
                onTap: () {
                  setState(() => _selectedInterests.contains("Dinosaurios")
                      ? _selectedInterests.remove("Dinosaurios")
                      : _selectedInterests.add("Dinosaurios"));
                },
              ),
              InterestCard(
                label: "Trenes",
                imageUrl:
                    "https://images.unsplash.com/photo-1517524285303-d6fc683dddf8?q=80&w=300",
                isSelected: _selectedInterests.contains("Trenes"),
                onTap: () {
                  setState(() => _selectedInterests.contains("Trenes")
                      ? _selectedInterests.remove("Trenes")
                      : _selectedInterests.add("Trenes"));
                },
              ),
              InterestCard(
                label: "Lego",
                imageUrl:
                    "https://images.unsplash.com/photo-1585366119957-e9730b6d0f60?q=80&w=300",
                isSelected: _selectedInterests.contains("Lego"),
                onTap: () {
                  setState(() => _selectedInterests.contains("Lego")
                      ? _selectedInterests.remove("Lego")
                      : _selectedInterests.add("Lego"));
                },
              )
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width < 768
                    ? double.infinity
                    : (MediaQuery.of(context).size.width / 2 - 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubSectionLabel("COMIDAS", Icons.restaurant),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TagChip(
                            label: "Manzana",
                            isSelected: _selectedInterests.contains("Manzana"),
                            onTap: () => setState(() =>
                                _selectedInterests.contains("Manzana")
                                    ? _selectedInterests.remove("Manzana")
                                    : _selectedInterests.add("Manzana"))),
                        TagChip(
                            label: "Galletas",
                            isSelected: _selectedInterests.contains("Galletas"),
                            onTap: () => setState(() =>
                                _selectedInterests.contains("Galletas")
                                    ? _selectedInterests.remove("Galletas")
                                    : _selectedInterests.add("Galletas"))),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width < 768
                    ? double.infinity
                    : (MediaQuery.of(context).size.width / 2 - 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubSectionLabel("JUGUETES", Icons.toys),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TagChip(
                            label: "Pelota ahulada",
                            isSelected:
                                _selectedInterests.contains("Pelota ahulada"),
                            onTap: () => setState(() => _selectedInterests
                                    .contains("Pelota ahulada")
                                ? _selectedInterests.remove("Pelota ahulada")
                                : _selectedInterests.add("Pelota ahulada"))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSubSectionLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon,
            size: 18, color: const Color(0xFF58423B).withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF58423B).withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildAversiveStimuliCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFF5EDE4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning, color: Color(0xFFA43714)),
              SizedBox(width: 8),
              Text(
                "Estímulos Aversivos",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF1E1B16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildAversiveCategory(
              "RUIDO", ["Licuadora", "Gritos", "Aspiradora", "Música alta"]),
          const SizedBox(height: 20),
          _buildAversiveCategory(
              "COLORES", ["Rojo chillón", "Amarillo brillante", "Neón"]),
          const SizedBox(height: 20),
          _buildAversiveCategory("LUGARES",
              ["Multitudes", "Cuartos blancos", "Espacios reducidos"]),
        ],
      ),
    );
  }

  Widget _buildAversiveCategory(String categoryName, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          categoryName,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF58423B).withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final isSelected =
                _aversiveStimuli[categoryName]?.contains(opt) ?? false;
            return TagChip(
              label: opt,
              isSelected: isSelected,
              onTap: () => _toggleAversive(categoryName, opt),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFamilyDataCard(PacientePerfil perfil) {
    final docs = perfil.documentosClinicos.entries.toList();
    return BentoCard(
      backgroundColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Informacion registrada por la familia',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E1B16),
            ),
          ),
          const SizedBox(height: 14),
          _dataSection(
            'Rutinas de regulacion',
            perfil.rutinasRegulacion.isEmpty
                ? ['Sin rutinas registradas']
                : perfil.rutinasRegulacion,
          ),
          const SizedBox(height: 14),
          _documentsSection(docs),
          const SizedBox(height: 14),
          _dataSection(
            'Medicacion actual',
            (perfil.medicacionActual == null ||
                    perfil.medicacionActual!.isEmpty)
                ? ['Sin medicacion registrada']
                : perfil.medicacionActual!
                    .split(RegExp(r'[\n;]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList(),
          ),
        ],
      ),
    );
  }

  String _documentLabel(dynamic value) {
    if (value is Map) {
      return value['nombre']?.toString() ?? value.toString();
    }
    return value?.toString() ?? 'archivo';
  }

  String? _documentUrl(dynamic value) {
    if (value is Map) {
      final raw = value['url'] ?? value['download_url'] ?? value['path'];
      final url = raw?.toString();
      return url == null || url.isEmpty ? null : url;
    }
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  String _absoluteDocumentUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiConstants.baseUrl.replaceAll(RegExp(r'/$'), '');
    final path = url.startsWith('/') ? url : '/$url';
    return '$base$path';
  }

  String _safeFileName(String label, String url) {
    final uriName = Uri.tryParse(url)?.pathSegments.last;
    final raw = (uriName?.isNotEmpty == true ? uriName : label)
        ?.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_');
    return raw == null || raw.isEmpty ? 'documento_clinico' : raw;
  }

  String _documentType(String key) => switch (key) {
        'evaluacion_profesional' => 'Evaluacion profesional',
        'plan_terapeutico_previo' => 'Plan terapeutico previo',
        'medicacion' => 'Documento de medicacion',
        _ => key.replaceAll('_', ' '),
      };

  Future<void> _openDocument(String url, String label) async {
    final absoluteUrl = _absoluteDocumentUrl(url);
    final uri = Uri.tryParse(absoluteUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El enlace del documento no es valido.')),
      );
      return;
    }
    try {
      final filename = _safeFileName(label, absoluteUrl);
      final target = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}$filename');
      await ref.read(dioProvider).download(absoluteUrl, target.path);
      final opened = await launchUrl(
        Uri.file(target.path),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el documento.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descargar el documento: $e')),
      );
    }
  }

  Widget _documentsSection(List<MapEntry<String, dynamic>> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DOCUMENTOS ENVIADOS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF58423B),
          ),
        ),
        const SizedBox(height: 8),
        if (docs.isEmpty)
          const Text(
            'Sin documentos adjuntos',
            style: TextStyle(color: Color(0xFF58423B)),
          )
        else
          ...docs.map((entry) {
            final label = _documentLabel(entry.value);
            final url = _documentUrl(entry.value);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF2E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDFC0B7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.picture_as_pdf_outlined,
                      color: Color(0xFFA43714)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _documentType(entry.key),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF58423B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E1B16),
                          ),
                        ),
                        if (url == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Archivo registrado sin enlace disponible.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8B716A),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Abrir documento',
                    onPressed:
                        url == null ? null : () => _openDocument(url, label),
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _dataSection(String title, List<String> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF58423B),
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Color(0xFF4A624D)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row,
                    style: const TextStyle(
                      color: Color(0xFF58423B),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClinicalValidationCard(PacientePerfil perfil) {
    final obligatoria = perfil.requiereScq && !perfil.tieneEvidenciaClinica;
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: Color(0xFF4A624D)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  perfil.perfilValidado
                      ? 'Perfil validado por terapeuta'
                      : obligatoria
                          ? 'Validacion clinica obligatoria'
                          : 'Validacion clinica opcional',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E1B16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            obligatoria
                ? 'Este caso viene de SCQ sin evidencia clinica previa. Confirma el nivel TEA y los objetivos antes de generar el plan.'
                : 'La familia adjunto evidencia clinica o datos suficientes. Puedes confirmar o ajustar estos objetivos antes de generar el plan.',
            style: const TextStyle(color: Color(0xFF58423B), height: 1.4),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _nivelTea,
            decoration: _inputDecoration('Nivel TEA validado'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Nivel 1')),
              DropdownMenuItem(value: 2, child: Text('Nivel 2')),
              DropdownMenuItem(value: 3, child: Text('Nivel 3')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _nivelTea = value);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _objectivesController,
            minLines: 3,
            maxLines: 5,
            decoration: _inputDecoration('Objetivos terapeuticos'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _clinicalNotesController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration('Observaciones del terapeuta'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingValidation
                  ? null
                  : () => _guardarValidacionClinica(perfil),
              icon: const Icon(Icons.save_outlined),
              label: Text(_isSavingValidation
                  ? 'Guardando...'
                  : 'Guardar validacion clinica'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A624D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  // ── Badge de estado clínico ─────────────────────────────────────────────────────────────
  Widget _buildEstadoBadge(String estado) {
    final color = _estadoColor(estado);
    final label = _estadoLabel(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  static Color _estadoColor(String e) => switch (e) {
        'plan_activo' => const Color(0xFF22C55E),
        'listo_para_plan' => const Color(0xFF3B82F6),
        'vinculado_terapeuta' ||
        'perfil_clinico_incompleto' =>
          const Color(0xFFF59E0B),
        _ => const Color(0xFF94A3B8),
      };

  static String _estadoLabel(String e) => switch (e) {
        'plan_activo' => 'Plan activo',
        'listo_para_plan' => 'Listo para generar plan',
        'vinculado_terapeuta' => 'Terapeuta asignado',
        'perfil_clinico_incompleto' => 'Perfil incompleto',
        _ => 'Pendiente de asignación',
      };

  // ── Panel de Navegación Rápida ────────────────────────────────────────────────
  Widget _buildQuickNav(PacientePerfil perfil, {bool compact = false}) {
    final estado = perfil.estadoClinico;
    final hasPlan = perfil.planActivoId != null;
    final isActive = estado == 'plan_activo' || estado == 'listo_para_plan';
    final isPending = estado == 'pendiente_asignacion';
    final perfilObligatorio =
        perfil.requiereScq && !perfil.tieneEvidenciaClinica;
    final isIncomplete =
        estado == 'perfil_clinico_incompleto' && perfilObligatorio;
    final canGenerate = perfil.perfilValidado ||
        (!perfilObligatorio && perfil.tieneEvidenciaClinica);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ACCIONES RÁPIDAS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Color(0xFF58423B),
          ),
        ),
        const SizedBox(height: 12),

        // ── Botón: Ver / Generar Plan ──────────────────────────────────────────
        if (hasPlan)
          _quickNavTile(
            icon: Icons.assignment_outlined,
            iconColor: const Color(0xFF4A624D),
            bgColor: const Color(0xFFB8D6B2).withValues(alpha: 0.25),
            label: 'Plan Terapéutico',
            subtitle: 'Ver actividades del plan activo',
            onTap: () => context.push('/terapeuta/plan/${widget.ninoId}'),
          )
        else if (isIncomplete)
          _quickNavTile(
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFFD97706),
            bgColor: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            label: 'Completar Perfil Clínico',
            subtitle: 'Requerido para generar el plan',
            onTap: () =>
                context.push('/terapeuta/admision?ninoId=${widget.ninoId}'),
          )
        else if (!perfil.perfilValidado)
          _quickNavTile(
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFF4A624D),
            bgColor: const Color(0xFFB8D6B2).withValues(alpha: 0.18),
            label: 'Perfil clinico opcional',
            subtitle: 'Puedes enriquecerlo si necesitas mas precision',
            onTap: () =>
                context.push('/terapeuta/admision?ninoId=${widget.ninoId}'),
          )
        else if (isPending)
          _quickNavTile(
            icon: Icons.hourglass_empty,
            iconColor: const Color(0xFF94A3B8),
            bgColor: const Color(0xFFF1F5F9),
            label: 'Sin plan asignado',
            subtitle: 'Esperando asignación a terapeuta',
            onTap: null,
          ),

        const SizedBox(height: 12),

        // ── Boton: Apoyo clinico ──────────────────────────────────────────────
        _quickNavTile(
          icon: Icons.auto_awesome,
          iconColor: const Color(0xFFA43714),
          bgColor: const Color(0xFFFFF3F0),
          label: 'Apoyo clinico',
          subtitle: 'Recomendaciones y plan de sesion',
          onTap: (isActive || hasPlan)
              ? () => context.push('/terapeuta/ia/${widget.ninoId}')
              : null,
          disabledReason: isPending
              ? 'Disponible tras asignación'
              : isIncomplete
                  ? 'Completa el perfil primero'
                  : null,
        ),

        const SizedBox(height: 12),

        // ── Botón: Progreso Clínico ──────────────────────────────────────────
        _quickNavTile(
          icon: Icons.insights,
          iconColor: const Color(0xFF1A365D),
          bgColor: const Color(0xFFEBF4FF),
          label: 'Progreso Clínico',
          subtitle: 'Métricas y evolución de sesiones',
          onTap: hasPlan
              ? () => context.push('/terapeuta/progreso/${widget.ninoId}')
              : null,
          disabledReason: !hasPlan ? 'Disponible con plan activo' : null,
        ),

        const SizedBox(height: 12),

        // Boton: Generar plan o nueva sesion
        if (isActive || canGenerate) ...[
          if (hasPlan) ...[
            // Banner premium de sugerencias de IA
            GestureDetector(
              onTap: () {
                context.push(
                  '/terapeuta/plan_builder?ninoId=${widget.ninoId}&nombre=${Uri.encodeComponent(perfil.nombre)}',
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF2CC), Color(0xFFFFF8E1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2A300).withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE2A300).withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFD97706), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💡 Sugerencias de IA disponibles',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: const Color(0xFF8A5A00),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'El motor clínico de RimAI ha preparado actividades personalizadas basadas en el progreso de la sesión anterior.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: const Color(0xFF6B4300),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                'Ver sugerencias en el constructor',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: const Color(0xFFA43714),
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_forward,
                                size: 12,
                                color: Color(0xFFA43714),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          _buildGeneratePlanTile(estado, enabled: canGenerate, hasPlan: hasPlan, perfil: perfil),
        ],

        if (hasPlan) ...[
          const SizedBox(height: 12),
          _quickNavTile(
            icon: compact ? Icons.edit_note_rounded : Icons.manage_accounts,
            iconColor: const Color(0xFF58423B),
            bgColor: const Color(0xFFF5EDE4),
            label: compact
                ? 'Editar perfil terapeutico'
                : 'Volver a modo de acciones',
            subtitle: compact
                ? 'Abrir datos clinicos, preferencias y validacion'
                : 'Ocultar el perfil clinico y ver solo accesos directos',
            onTap: () => context.go(compact
                ? '/terapeuta/nino/${widget.ninoId}?editarPerfil=true'
                : '/terapeuta/nino/${widget.ninoId}'),
          ),
        ],
      ],
    );
  }

  Widget _quickNavTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
    String? disabledReason,
  }) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.55,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: enabled ? bgColor : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled
                    ? iconColor.withValues(alpha: 0.18)
                    : const Color(0xFFE0E0E0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: enabled
                        ? iconColor.withValues(alpha: 0.12)
                        : const Color(0xFFEEEEEE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      color: enabled ? iconColor : const Color(0xFFBDBDBD),
                      size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: enabled
                              ? const Color(0xFF1E1B16)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        disabledReason ?? subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: disabledReason != null
                              ? const Color(0xFFD97706)
                              : const Color(0xFF8B716A),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.chevron_right : Icons.lock_outline,
                  color: enabled
                      ? iconColor.withValues(alpha: 0.5)
                      : const Color(0xFFBDBDBD),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratePlanTile(
    String estado, {
    required bool enabled,
    required bool hasPlan,
    required PacientePerfil perfil,
  }) {
    final title = _isGeneratingPlan
        ? 'Generando plan...'
        : !enabled
            ? 'Valida el perfil antes de generar'
            : (hasPlan ? 'Nueva sesión' : 'Generar plan terapéutico');

    final subtitle = enabled
        ? (hasPlan
            ? 'Personaliza y planifica la siguiente sesión'
            : 'Usa datos familiares y validacion del terapeuta')
        : 'Confirma nivel TEA y objetivos primero';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isGeneratingPlan || !enabled
            ? null
            : () {
                if (hasPlan) {
                  context.push(
                    '/terapeuta/plan_builder?ninoId=${widget.ninoId}&nombre=${Uri.encodeComponent(perfil.nombre)}',
                  );
                } else {
                  _generarPlanIA();
                }
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B16),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB8D6B2).withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB8D6B2).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: _isGeneratingPlan
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Color(0xFFB8D6B2), strokeWidth: 2))
                    : const Icon(Icons.auto_awesome,
                        color: Color(0xFFB8D6B2), size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generarPlanIA() async {
    setState(() => _isGeneratingPlan = true);
    try {
      final result =
          await ref.read(dashboardServiceProvider).generarPlanIA(widget.ninoId);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFFFAF2E9),
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFFA43714)),
                SizedBox(width: 8),
                Text("Sesion generada",
                    style: TextStyle(
                        color: Color(0xFF1E1B16), fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result['mensaje'] ?? 'Plan generado exitosamente.',
                    style: const TextStyle(color: Color(0xFF58423B))),
                const SizedBox(height: 16),
                _buildInfoRow(
                    "Dificultad:", result['dificultad_inicial'] ?? 'N/A'),
                const SizedBox(height: 8),
                _buildInfoRow("Confianza de sugerencia:",
                    "${((result['confianza_ia'] ?? 0) * 100).toStringAsFixed(1)}%"),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  context.pop();
                  ref.invalidate(perfilPacienteProvider(widget.ninoId));
                },
                child: const Text("Cerrar",
                    style: TextStyle(
                        color: Color(0xFFA43714), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPlan = false);
    }
  }

  Future<void> _guardarValidacionClinica(PacientePerfil perfil) async {
    final objetivos = _objectivesController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (objetivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registra al menos un objetivo.')),
      );
      return;
    }

    setState(() => _isSavingValidation = true);
    try {
      final perfilSensorial = Map<String, dynamic>.from(perfil.perfilSensorial);
      perfilSensorial['intereses'] = _selectedInterests;
      perfilSensorial['estimulosAversivos'] = _aversiveStimuli;
      await ref.read(perfilServiceProvider).actualizarPerfilClinico(
        widget.ninoId,
        {
          'nivel_cognitivo': perfil.nivelCognitivo,
          'diagnostico': perfil.diagnostico,
          'perfil_sensorial': perfilSensorial,
          'objetivos_intervencion': objetivos,
          'observaciones_clinicas': _clinicalNotesController.text.trim(),
        },
      );
      await ref.read(dashboardServiceProvider).validarNivelTea(
            ninoId: widget.ninoId,
            nivelTea: _nivelTea,
            observacion: _clinicalNotesController.text.trim(),
          );
      ref.invalidate(perfilPacienteProvider(widget.ninoId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Validacion clinica guardada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la validacion: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingValidation = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF58423B).withValues(alpha: 0.7))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFB8D6B2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFF1E1B16))),
        ),
      ],
    );
  }
}
