import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import 'package:rimai_app/adapters/input/widgets/rimai_top_bar.dart';
import 'package:rimai_app/adapters/input/widgets/rimai_bottom_nav.dart';
import 'package:rimai_app/adapters/input/widgets/bento_card.dart';
import 'package:rimai_app/adapters/input/widgets/tag_chip.dart';
import 'package:rimai_app/adapters/input/widgets/interest_card.dart';
import 'package:rimai_app/core/providers/pmv2_providers.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';

class TherapeuticProfileScreen extends ConsumerStatefulWidget {
  final String ninoId;
  const TherapeuticProfileScreen({super.key, required this.ninoId});

  @override
  ConsumerState<TherapeuticProfileScreen> createState() =>
      _TherapeuticProfileScreenState();
}

class _TherapeuticProfileScreenState
    extends ConsumerState<TherapeuticProfileScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  List<String> _selectedInterests = [];
  Map<String, List<String>> _aversiveStimuli = {
    'RUIDO': [],
    'COLORES': [],
    'LUGARES': []
  };
  String? _uploadedFileName;
  bool _dataInitialized = false;
  bool _isGeneratingPlan = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png'],
    );

    if (result != null && result.files.single.path != null) {
      // Simular subida
      final fileName = await ref
          .read(perfilServiceProvider)
          .cargarDiagnostico(result.files.single.path);
      setState(() {
        _uploadedFileName = fileName;
      });
    }
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
        trailingWidget: const CircleAvatar(
          radius: 20,
          backgroundColor: Color(0xFFFAF2E9),
          child: Icon(Icons.person, color: Color(0xFF58423B)),
        ),
      ),
      bottomNavigationBar: RimAIBottomNav(
        currentIndex: 0,
        onTap: (index) {
          if (index == 1) context.go('/terapeuta/ia');
          // if (index == 2) context.go('/terapeuta/calendario');
        },
        items: [
          BottomNavItem(icon: Icons.person, label: "Perfil"),
          BottomNavItem(icon: Icons.psychology, label: "Terapia"),
          BottomNavItem(icon: Icons.calendar_today, label: "Calendario"),
        ],
      ),
      body: perfilAsync.when(
        data: (perfil) {
          if (!_dataInitialized) {
            _nameController.text = perfil.nombre;
            _ageController.text = perfil.edad.toString();
            _selectedInterests = List.from(perfil.intereses);
            _aversiveStimuli = perfil.estimulosAversivos
                .map((key, value) => MapEntry(key, List<String>.from(value)));
            _dataInitialized = true;
          }

          return SingleChildScrollView(
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
                  _buildHeader(),
                  const SizedBox(height: 32),
                  _buildBentoGrid(),
                  const SizedBox(height: 32),
                  _buildEstadoBadge(perfil.estadoClinico),
                  const SizedBox(height: 16),
                  _buildPlanButton(perfil),
                  const SizedBox(height: 16),
                  _buildAIFeatureButton(perfil),
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
            color: const Color(0xFF58423B).withOpacity(0.8),
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
                    const SizedBox(height: 24),
                    _buildUploadDiagnosisCard(),
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
              const SizedBox(height: 24),
              _buildUploadDiagnosisCard(),
            ],
          );
        }
      },
    );
  }

  Widget _buildPatientInfoCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFFAF2E9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge, color: Color(0xFFB8D6B2)),
              const SizedBox(width: 8),
              const Text(
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
            color: const Color(0xFF58423B).withOpacity(0.6),
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
            children: [
              Row(
                children: [
                  const Icon(Icons.star_border, color: Color(0xFFB8D6B2)),
                  const SizedBox(width: 8),
                  const Text(
                    "Intereses y Preferencias",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF1E1B16),
                    ),
                  ),
                ],
              ),
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
        Icon(icon, size: 18, color: const Color(0xFF58423B).withOpacity(0.6)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF58423B).withOpacity(0.6),
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
          Row(
            children: [
              const Icon(Icons.warning, color: Color(0xFFA43714)),
              const SizedBox(width: 8),
              const Text(
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
            color: const Color(0xFF58423B).withOpacity(0.6),
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

  Widget _buildUploadDiagnosisCard() {
    return BentoCard(
      backgroundColor: const Color(0xFFB8D6B2).withOpacity(0.1),
      border:
          Border.all(color: const Color(0xFFB8D6B2).withOpacity(0.3), width: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file, color: Color(0xFF4A624D)),
              const SizedBox(width: 8),
              const Text(
                "Cargar Diagnóstico",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Color(0xFF1E1B16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Adjunta archivos de diagnóstico médico o historial previo.",
            style: TextStyle(
              fontSize: 14,
              color: const Color(0xFF58423B).withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          if (_uploadedFileName != null)
            Row(
              children: [
                const Icon(Icons.description, color: Color(0xFFB8D6B2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _uploadedFileName!,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text("Subido hoy",
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => setState(() => _uploadedFileName = null),
                )
              ],
            )
          else
            InkWell(
              onTap: _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  // Dashed effect can be simulated or handled with a package, standard border for now
                  border: Border.all(
                      color: const Color(0xFFB8D6B2), style: BorderStyle.solid),
                  color: Colors.white.withOpacity(0.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload,
                        size: 36, color: Color(0xFFB8D6B2)),
                    const SizedBox(height: 12),
                    const Text(
                      "Seleccionar archivo",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A624D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "PDF, JPG o PNG (Max 10MB)",
                      style: TextStyle(
                          fontSize: 11,
                          color: const Color(0xFF58423B).withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
            )
        ],
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  static Color _estadoColor(String e) => switch (e) {
    'plan_activo' => const Color(0xFF22C55E),
    'listo_para_plan' => const Color(0xFF3B82F6),
    'vinculado_terapeuta' || 'perfil_clinico_incompleto' => const Color(0xFFF59E0B),
    _ => const Color(0xFF94A3B8),
  };

  static String _estadoLabel(String e) => switch (e) {
    'plan_activo' => 'Plan activo',
    'listo_para_plan' => 'Listo para generar plan',
    'vinculado_terapeuta' => 'Terapeuta asignado',
    'perfil_clinico_incompleto' => 'Perfil incompleto',
    _ => 'Pendiente de asignación',
  };

  // ── Botón de Plan ─────────────────────────────────────────────────────────────────
  Widget _buildPlanButton(PacientePerfil perfil) {
    final hasPlan = perfil.planActivoId != null;
    if (!hasPlan) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => context.go('/terapeuta/plan/${widget.ninoId}'),
        icon: const Icon(Icons.assignment_outlined),
        label: const Text('Ver plan terapeutico'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFB8D6B2),
          foregroundColor: const Color(0xFF1E1B16),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
      ),
    );
  }

  // ── Botón IA (condicional por estado) ──────────────────────────────────────────
  Widget _buildAIFeatureButton(PacientePerfil perfil) {
    final estado = perfil.estadoClinico;
    final isIncomplete = estado == 'perfil_clinico_incompleto' || estado == 'vinculado_terapeuta';
    final isPending = estado == 'pendiente_asignacion';

    // Estado pendiente de asignación
    if (isPending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDFC0B7).withOpacity(0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_empty, color: Color(0xFF94A3B8), size: 28),
          const SizedBox(width: 16),
          const Expanded(child: Text(
            'Esperando asignación a terapeuta',
            style: TextStyle(color: Color(0xFF58423B), fontWeight: FontWeight.bold),
          )),
        ]),
      );
    }

    // Estado incompleto: mostrar botón deshabilitado con acción de completar perfil
    if (isIncomplete) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Completa el perfil clínico antes de generar el plan:',
              style: TextStyle(color: Color(0xFF58423B), fontSize: 13)),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/terapeuta/admision?ninoId=${widget.ninoId}'),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Completar perfil clínico'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
          ),
        ),
      ]);
    }

    // Estado listo o plan activo: botón IA activo
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B16),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB8D6B2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isGeneratingPlan ? null : _generarPlanIA,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFB8D6B2).withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: _isGeneratingPlan
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(color: Color(0xFFB8D6B2), strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, color: Color(0xFFB8D6B2), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _isGeneratingPlan ? 'Analizando con IA...' :
                      (estado == 'plan_activo' ? 'Regenerar Plan con IA' : 'Generar Plan Terapeutico (IA)'),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Predicción de dificultad mediante Random Forest',
                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                ),
              ])),
              const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
            ]),
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
            title: Row(
              children: const [
                Icon(Icons.auto_awesome, color: Color(0xFFA43714)),
                SizedBox(width: 8),
                Text("Plan Generado",
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
                _buildInfoRow("Confianza IA:",
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF58423B).withOpacity(0.7))),
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
