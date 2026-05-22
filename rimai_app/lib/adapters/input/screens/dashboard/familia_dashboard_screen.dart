import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rimai_app/core/providers/dashboard_providers.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kP = Color(0xFFA43714);
const _kA = Color(0xFFB8D6B2);
const _kBg = Color(0xFFFFF8F2);
const _kSurf = Color(0xFFFAF2E9);
const _kText = Color(0xFF1E1B16);
const _kSub = Color(0xFF58423B);
const _kBdr = Color(0xFFDFC0B7);

// ── Estado badge helpers ──────────────────────────────────────────────────────
Color _estadoColor(String e) => switch (e) {
      'plan_activo' => const Color(0xFF22C55E),
      'listo_para_plan' => const Color(0xFF3B82F6),
      'vinculado_terapeuta' ||
      'perfil_clinico_incompleto' =>
        const Color(0xFFF59E0B),
      _ => const Color(0xFF94A3B8),
    };

String _estadoLabel(String e) => switch (e) {
      'plan_activo' => '🚀 Plan activo',
      'listo_para_plan' => '✅ Listo para plan',
      'vinculado_terapeuta' => '👨‍⚕️ Terapeuta asignado',
      'perfil_clinico_incompleto' => '⚠️ Completando perfil',
      _ => '🕐 Esperando terapeuta',
    };

// ── Screen ────────────────────────────────────────────────────────────────────
class FamiliaDashboardScreen extends ConsumerStatefulWidget {
  const FamiliaDashboardScreen({Key? key}) : super(key: key);
  @override
  ConsumerState<FamiliaDashboardScreen> createState() => _State();
}

class _State extends ConsumerState<FamiliaDashboardScreen> {
  // Wizard control
  bool _wizardMode = false;
  int _step = 0;
  final _pc = PageController();
  bool _saving = false;
  String? _editingNinoId;

  // Step 1
  final _nameCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _diagCtrl = TextEditingController();
  DateTime? _date;
  String _nivelCognitivo = 'Bajo';

  // Step 2
  String _com = 'Palabras sueltas';
  String _cv = 'Intermitente';
  String _js = 'Paralelo';
  final Set<String> _mot = {};

  // Step 3
  final Set<String> _hiper = {};
  final Set<String> _hipo = {};
  final Set<String> _rep = {};
  final _rutinaCtrl = TextEditingController();

  // Step 4
  String? _docDiagnosticoName;
  String? _docDiagnosticoPath;
  String? _planTerapeuticoName;
  String? _planTerapeuticoPath;
  String? _medicacionFileName;
  String? _medicacionFilePath;
  final _medicacionCtrl = TextEditingController();

  // Step 5
  final Set<String> _int = {};

  @override
  void dispose() {
    _pc.dispose();
    _nameCtrl.dispose();
    _dateCtrl.dispose();
    _diagCtrl.dispose();
    _rutinaCtrl.dispose();
    _medicacionCtrl.dispose();
    super.dispose();
  }

  void _tog(Set<String> s, String v) =>
      setState(() => s.contains(v) ? s.remove(v) : s.add(v));

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate:
          _date ?? DateTime.now().subtract(const Duration(days: 365 * 5)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: _kP, onPrimary: Colors.white, onSurface: _kText),
        ),
        child: child!,
      ),
    );
    if (p != null) {
      setState(() {
        _date = p;
        _dateCtrl.text =
            '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _next() {
    if (_step == 0 && (_nameCtrl.text.trim().isEmpty || _date == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nombre y fecha de nacimiento son obligatorios.')),
      );
      return;
    }
    if (_step < 4) {
      setState(() => _step++);
      _pc.animateToPage(_step,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _guardar();
    }
  }

  void _prev() {
    if (_step > 0) {
      setState(() => _step--);
      _pc.animateToPage(_step,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      setState(() {
        _reset();
        _wizardMode = false;
        _step = 0;
      });
    }
  }

  Map<String, dynamic> _perfilPayload() {
    return {
      'nombre': _nameCtrl.text.trim(),
      'fecha_nacimiento': _dateCtrl.text,
      'nivel_cognitivo': _nivelCognitivo,
      if (_diagCtrl.text.trim().isNotEmpty)
        'diagnostico': _diagCtrl.text.trim(),
      'hitos': {
        'comunicacion': _com,
        'contacto_visual': _cv,
        'juego_social': _js,
        'motricidad': _mot.toList(),
      },
      'sensorial': {
        'hipersensibilidad': _hiper.toList(),
        'hiposensibilidad': _hipo.toList(),
        'comportamientos_repetitivos': _rep.toList(),
        'intereses_obsesivos': _int.toList(),
      },
      'rutinas_regulacion': _rutinaCtrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'documentos_clinicos': {
        if (_docDiagnosticoName != null)
          'evaluacion_profesional': _docDiagnosticoName,
        if (_planTerapeuticoName != null)
          'plan_terapeutico_previo': _planTerapeuticoName,
        if (_medicacionFileName != null) 'medicacion': _medicacionFileName,
      },
      if (_medicacionCtrl.text.trim().isNotEmpty)
        'medicacion_actual': _medicacionCtrl.text.trim(),
      'intereses': _int.toList(),
    };
  }

  Future<void> _guardar() async {
    setState(() => _saving = true);
    try {
      final nombreRegistrado = _nameCtrl.text.trim();
      final debeSugerirScqLocal = _debeSugerirScq();
      final editingId = _editingNinoId;
      final service = ref.read(dashboardServiceProvider);
      final result = editingId == null
          ? await service.guardarPerfilNino(_perfilPayload())
          : await service.actualizarPerfilNino(editingId, _perfilPayload());
      final ninoId = result['id']?.toString() ?? '';
      final requiereScq = editingId == null &&
          (result['requiere_scq'] == true || debeSugerirScqLocal);
      if (ninoId.isNotEmpty) {
        await _uploadClinicalFiles(ninoId);
      }
      ref.invalidate(familiaDashboardProvider);
      setState(() {
        _wizardMode = false;
        _step = 0;
        _reset();
      });
      if (mounted) {
        if (requiereScq && ninoId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showScqPrompt(ninoId, nombreRegistrado);
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(editingId == null
                ? 'Paciente registrado. Un terapeuta lo vinculara pronto.'
                : 'Registro actualizado correctamente.'),
            backgroundColor: const Color(0xFF4A624D),
            duration: const Duration(seconds: 4),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _debeSugerirScq() {
    final tieneDiagnostico = _diagCtrl.text.trim().isNotEmpty;
    final tieneMedicacion = _medicacionCtrl.text.trim().isNotEmpty;
    final tieneDocumento = _docDiagnosticoName != null ||
        _planTerapeuticoName != null ||
        _medicacionFileName != null;
    return !tieneDiagnostico && !tieneMedicacion && !tieneDocumento;
  }

  void _reset() {
    _editingNinoId = null;
    _nameCtrl.clear();
    _dateCtrl.clear();
    _diagCtrl.clear();
    _date = null;
    _nivelCognitivo = 'Bajo';
    _mot.clear();
    _hiper.clear();
    _hipo.clear();
    _rep.clear();
    _int.clear();
    _rutinaCtrl.clear();
    _medicacionCtrl.clear();
    _docDiagnosticoName = null;
    _docDiagnosticoPath = null;
    _planTerapeuticoName = null;
    _planTerapeuticoPath = null;
    _medicacionFileName = null;
    _medicacionFilePath = null;
    _com = 'Palabras sueltas';
    _cv = 'Intermitente';
    _js = 'Paralelo';
  }

  Future<void> _pickClinicalFile(String tipo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    final file = result?.files.single;
    if (file == null) return;
    setState(() {
      if (tipo == 'diagnostico') {
        _docDiagnosticoName = file.name;
        _docDiagnosticoPath = file.path;
      }
      if (tipo == 'plan') {
        _planTerapeuticoName = file.name;
        _planTerapeuticoPath = file.path;
      }
      if (tipo == 'medicacion') {
        _medicacionFileName = file.name;
        _medicacionFilePath = file.path;
      }
    });
  }

  Future<void> _uploadClinicalFiles(String ninoId) async {
    final service = ref.read(dashboardServiceProvider);
    final files = [
      ('evaluacion_profesional', _docDiagnosticoPath, _docDiagnosticoName),
      ('plan_terapeutico_previo', _planTerapeuticoPath, _planTerapeuticoName),
      ('medicacion', _medicacionFilePath, _medicacionFileName),
    ];

    for (final item in files) {
      final path = item.$2;
      final name = item.$3;
      if (path == null || name == null) continue;
      await service.subirDocumentoClinico(
        ninoId: ninoId,
        tipo: item.$1,
        path: path,
        fileName: name,
      );
    }
  }

  List<String> _listFrom(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  String? _documentName(Map<String, dynamic> docs, String key) {
    final value = docs[key];
    if (value is Map) return value['nombre']?.toString();
    return value?.toString();
  }

  void _editarPaciente(PacienteDashboard p) {
    final fecha = p.fechaNacimiento;
    setState(() {
      _reset();
      _editingNinoId = p.id;
      _wizardMode = true;
      _step = 0;
      _nameCtrl.text = p.nombre;
      _dateCtrl.text = fecha ?? '';
      _date = fecha != null ? DateTime.tryParse(fecha) : null;
      _diagCtrl.text = p.diagnostico ?? '';
      _nivelCognitivo = p.nivelCognitivo.isNotEmpty ? p.nivelCognitivo : 'Bajo';
      _com = p.hitos['comunicacion']?.toString() ?? 'Palabras sueltas';
      _cv = p.hitos['contacto_visual']?.toString() ?? 'Intermitente';
      _js = p.hitos['juego_social']?.toString() ?? 'Paralelo';
      _mot.addAll(_listFrom(p.hitos['motricidad']));
      _hiper.addAll(_listFrom(p.sensorial['hipersensibilidad']));
      _hipo.addAll(_listFrom(p.sensorial['hiposensibilidad']));
      _rep.addAll(_listFrom(p.sensorial['comportamientos_repetitivos']));
      _int.addAll(p.intereses.isNotEmpty
          ? p.intereses
          : _listFrom(p.sensorial['intereses_obsesivos']));
      _rutinaCtrl.text = p.rutinasRegulacion.join('\n');
      _medicacionCtrl.text = p.medicacionActual ?? '';
      _docDiagnosticoName =
          _documentName(p.documentosClinicos, 'evaluacion_profesional');
      _planTerapeuticoName =
          _documentName(p.documentosClinicos, 'plan_terapeutico_previo');
      _medicacionFileName = _documentName(p.documentosClinicos, 'medicacion');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pc.hasClients) _pc.jumpToPage(0);
    });
  }

  Future<void> _confirmarEliminar(PacienteDashboard p) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: Text(
          'Se ocultara el registro de ${p.nombre} del panel familiar y de la bandeja del terapeuta. Esta accion no elimina tu cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await ref.read(dashboardServiceProvider).eliminarPerfilNino(p.id);
      ref.invalidate(familiaDashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro eliminado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  void _showScqPrompt(String ninoId, String nombre) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cuestionario SCQ sugerido'),
        content: Text(
          'No registraste informes, plan previo ni medicacion para $nombre. Puedes responder el SCQ como orientacion preliminar antes de enviar el caso al terapeuta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Luego'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(
                  '/padre/scq/$ninoId?nombre=${Uri.encodeComponent(nombre)}');
            },
            child: const Text('Responder SCQ'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(familiaDashboardProvider);
    return Scaffold(
      backgroundColor: _kBg,
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: _kP)),
        error: (e, _) => _buildError(e.toString()),
        data: (data) {
          final show = _wizardMode || data.pacientes.isEmpty;
          return show
              ? _buildWizard(data.pacientes.isNotEmpty)
              : _buildStatus(data);
        },
      ),
    );
  }

  Widget _buildError(String msg) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_rounded, size: 64, color: _kSub),
        const SizedBox(height: 12),
        Text(msg,
            style: const TextStyle(color: _kSub), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => ref.invalidate(familiaDashboardProvider),
          style: ElevatedButton.styleFrom(
              backgroundColor: _kA, foregroundColor: _kText),
          child: const Text('Reintentar'),
        ),
      ]));

  // ══════════════════════════════════════════════════════════════════════════
  // STATUS VIEW
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildStatus(DashboardData data) {
    return SafeArea(
        child: Column(children: [
      _topBar(showAdd: true),
      Expanded(
          child: RefreshIndicator(
        color: _kP,
        onRefresh: () async => ref.invalidate(familiaDashboardProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Seguimiento\nfamiliar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                  height: 1.2,
                )),
            const SizedBox(height: 6),
            Text(
                '${data.totalPacientes} paciente${data.totalPacientes != 1 ? 's' : ''} registrado${data.totalPacientes != 1 ? 's' : ''}',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _kSub)),
            const SizedBox(height: 24),
            ...data.pacientes.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _PatientCard(
                    p: p,
                    onEdit: () => _editarPaciente(p),
                    onDelete: () => _confirmarEliminar(p),
                  ),
                )),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Registrar otro niño'),
                  onPressed: () => setState(() {
                    _reset();
                    _wizardMode = true;
                    _step = 0;
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kP,
                    side: const BorderSide(color: _kP),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                )),
          ]),
        ),
      )),
    ]));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WIZARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildWizard(bool canGoBack) {
    const titles = [
      'Datos básicos',
      'Hitos del desarrollo',
      'Perfil sensorial',
      'Antecedentes',
      'Intereses'
    ];
    const subs = [
      'Información general del niño.',
      'Describe el nivel de desarrollo observado.',
      'Características sensoriales del niño.',
      'Informes, planes previos y medicación actual.',
      'Intereses principales y resumen.',
    ];
    return SafeArea(
        child: Column(children: [
      _topBar(
          showAdd: false,
          canBack: canGoBack,
          onBack: () => setState(() {
                _reset();
                _wizardMode = false;
                _step = 0;
              })),
      // Progress
      Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Paso ${_step + 1}/5',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: _kSub,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${((_step + 1) / 5 * 100).toInt()}%',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _kP, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_step + 1) / 5,
                  backgroundColor: _kBdr.withOpacity(0.4),
                  valueColor: const AlwaysStoppedAnimation<Color>(_kP),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 14),
              Text(titles[_step],
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _kText)),
              Text(subs[_step],
                  style:
                      GoogleFonts.plusJakartaSans(fontSize: 13, color: _kSub)),
            ],
          )),
      const SizedBox(height: 8),
      // Pages
      Expanded(
          child: PageView(
        controller: _pc,
        physics: const NeverScrollableScrollPhysics(),
        children: [_page1(), _page2(), _page3(), _page4(), _page5()],
      )),
      // Nav
      _navBar(),
    ]));
  }

  Widget _navBar() => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        decoration: BoxDecoration(
            color: _kBg,
            border: Border(top: BorderSide(color: _kBdr.withOpacity(0.5)))),
        child: Row(children: [
          if (_step > 0) ...[
            Expanded(
                child: OutlinedButton(
              onPressed: _prev,
              style: OutlinedButton.styleFrom(
                  foregroundColor: _kSub,
                  side: const BorderSide(color: _kBdr),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: Text('Atrás',
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 12),
          ],
          Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _saving ? null : _next,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kP,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _step == 4
                            ? (_editingNinoId == null
                                ? 'Registrar paciente'
                                : 'Guardar cambios')
                            : 'Siguiente',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              )),
        ]),
      );

  Widget _topBar(
      {required bool showAdd, bool canBack = false, VoidCallback? onBack}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        if (canBack && onBack != null)
          IconButton(
              icon:
                  const Icon(Icons.arrow_back_ios_new, size: 18, color: _kSub),
              onPressed: onBack)
        else ...[
          const Icon(Icons.all_inclusive, color: _kP, size: 22),
          const SizedBox(width: 6),
          Text('RimAI',
              style: GoogleFonts.plusJakartaSans(
                  color: _kP, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
        const Spacer(),
        if (showAdd)
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: _kP, size: 26),
            tooltip: 'Registrar otro niño',
            onPressed: () => setState(() {
              _reset();
              _wizardMode = true;
              _step = 0;
            }),
          ),
        IconButton(
          icon: const Icon(Icons.logout, color: _kSub, size: 20),
          onPressed: () async {
            await ref.read(authStorageProvider).clearSession();
            if (mounted) context.go('/auth/login');
          },
        ),
      ]),
    );
  }

  // ── Page 1: Datos básicos ─────────────────────────────────────────────────
  Widget _page1() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _field('NOMBRE DEL NIÑO', 'Ej: Mateo García', _nameCtrl),
                const SizedBox(height: 16),
                _label('FECHA DE NACIMIENTO'),
                InkWell(
                  onTap: _pickDate,
                  child: IgnorePointer(
                      child: TextFormField(
                    controller: _dateCtrl,
                    decoration:
                        _dec('Seleccionar fecha', icon: Icons.calendar_today),
                  )),
                ),
                const SizedBox(height: 16),
                _field('DIAGNÓSTICO (opcional)', 'Ej: TEA nivel 1', _diagCtrl),
              ])),
        ]),
      );

  // ── Page 2: Hitos del desarrollo ──────────────────────────────────────────
  Widget _page2() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _choice(
                    'NIVEL DE COMUNICACIÓN',
                    [
                      'No verbal',
                      'Palabras sueltas',
                      'Frases cortas',
                      'Fluido'
                    ],
                    _com,
                    (v) => setState(() => _com = v)),
                const SizedBox(height: 20),
                _choice(
                    'CONTACTO VISUAL',
                    ['Nulo', 'Intermitente', 'Sostenido'],
                    _cv,
                    (v) => setState(() => _cv = v)),
                const SizedBox(height: 20),
                _choice('JUEGO SOCIAL', ['Aislado', 'Paralelo', 'Interactúa'],
                    _js, (v) => setState(() => _js = v)),
                const SizedBox(height: 20),
                _multi(
                    'MOTRICIDAD',
                    ['Camina solo', 'Sube escaleras', 'Pinza fina', 'Corre'],
                    _mot),
              ])),
        ]),
      );

  // ── Page 3: Perfil sensorial ──────────────────────────────────────────────
  Widget _page3() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _multi(
                    'HIPERSENSIBILIDAD (evita)',
                    [
                      'Ruidos fuertes',
                      'Texturas ásperas',
                      'Luces brillantes',
                      'Multitudes',
                      'Etiquetas'
                    ],
                    _hiper),
                const SizedBox(height: 20),
                _multi(
                    'HIPOSENSIBILIDAD (busca)',
                    [
                      'Dolor',
                      'Movimiento constante',
                      'Presión profunda',
                      'Morder objetos'
                    ],
                    _hipo),
                const SizedBox(height: 20),
                _multi(
                    'COMPORTAMIENTOS REPETITIVOS',
                    [
                      'Aleteo de manos',
                      'Balanceo',
                      'Ecolalia',
                      'Alinear juguetes',
                      'Puntillas'
                    ],
                    _rep),
                const SizedBox(height: 20),
                _label('RUTINAS DE REGULACION'),
                TextFormField(
                  controller: _rutinaCtrl,
                  maxLines: 4,
                  decoration: _dec(
                      'Ej: presion profunda, balanceo, objeto preferido...'),
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ])),
        ]),
      );

  // ── Page 4: Antecedentes clinicos ─────────────────────────────────────────
  Widget _page4() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Evidencia clinica previa',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold,
                        color: _kText,
                        fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                  'Estos archivos son opcionales. Si no cuentas con evaluaciones, plan previo ni medicacion, se sugerira responder el SCQ antes de enviar la solicitud al terapeuta.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: _kSub, height: 1.4),
                ),
                const SizedBox(height: 16),
                _fileButton(
                    'Evaluacion de neurologo/psiquiatra',
                    _docDiagnosticoName,
                    () => _pickClinicalFile('diagnostico')),
                const SizedBox(height: 10),
                _fileButton('Plan terapeutico previo', _planTerapeuticoName,
                    () => _pickClinicalFile('plan')),
                const SizedBox(height: 10),
                _fileButton('Documento de medicacion', _medicacionFileName,
                    () => _pickClinicalFile('medicacion')),
                const SizedBox(height: 16),
                _label('MEDICACION ACTUAL (opcional)'),
                TextFormField(
                  controller: _medicacionCtrl,
                  maxLines: 2,
                  decoration: _dec('Nombre, dosis o indicaciones si aplica'),
                  style:
                      GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                ),
              ])),
        ]),
      );

  // ── Page 5: Intereses + resumen ───────────────────────────────────────────
  Widget _page5() => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: Column(children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _multi(
                    'INTERESES PRINCIPALES',
                    [
                      'Dinosaurios',
                      'Trenes',
                      'Espacio',
                      'Geometría',
                      'Números',
                      'Música',
                      'Animales'
                    ],
                    _int),
              ])),
          const SizedBox(height: 16),
          // Resumen
          _card(
              backgroundColor: const Color(0xFFE8F5E9),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.summarize_outlined,
                          color: Color(0xFF4A624D), size: 20),
                      const SizedBox(width: 8),
                      Text('Resumen de registro',
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.bold,
                              color: _kText,
                              fontSize: 15)),
                    ]),
                    const SizedBox(height: 12),
                    _summaryRow(
                        'Nombre',
                        _nameCtrl.text.trim().isEmpty
                            ? '—'
                            : _nameCtrl.text.trim()),
                    _summaryRow('Fecha nac.',
                        _dateCtrl.text.isEmpty ? '—' : _dateCtrl.text),
                    _summaryRow(
                        'Diagnóstico',
                        _diagCtrl.text.trim().isEmpty
                            ? 'No especificado'
                            : _diagCtrl.text.trim()),
                    _summaryRow('Comunicación', _com),
                    _summaryRow(
                        'Antecedentes',
                        [
                          _docDiagnosticoName,
                          _planTerapeuticoName,
                          _medicacionFileName
                        ].whereType<String>().isEmpty
                            ? 'Sin archivos adjuntos'
                            : 'Archivos adjuntos'),
                    _summaryRow('Intereses',
                        _int.isEmpty ? 'No seleccionados' : _int.join(', ')),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _kA.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFF4A624D), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(
                          [
                            _docDiagnosticoName,
                            _planTerapeuticoName,
                            _medicacionFileName,
                            _diagCtrl.text.trim(),
                            _medicacionCtrl.text.trim()
                          ]
                                  .where((v) =>
                                      v != null && v.toString().isNotEmpty)
                                  .isEmpty
                              ? 'Al registrar, se sugerira completar el SCQ antes de enviar el caso al terapeuta.'
                              : 'Al registrar, el paciente quedara en espera de asignacion a un terapeuta.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: _kText),
                        )),
                      ]),
                    ),
                  ])),
        ]),
      );

  // ── Widget helpers ────────────────────────────────────────────────────────
  Widget _card({required Widget child, Color? backgroundColor}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor ?? _kSurf,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _kSub,
                letterSpacing: 0.5)),
      );

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: icon != null ? Icon(icon, color: _kP, size: 18) : null,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kP, width: 1.5)),
        contentPadding: const EdgeInsets.all(14),
        hintStyle: TextStyle(color: _kSub.withOpacity(0.5), fontSize: 14),
      );

  Widget _field(String label, String hint, TextEditingController ctrl) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          TextFormField(
              controller: ctrl,
              decoration: _dec(hint),
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _fileButton(String label, String? fileName, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
          fileName == null ? Icons.attach_file : Icons.check_circle_outline,
          size: 18),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          fileName ?? label,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: fileName == null ? _kSub : _kP,
        side: BorderSide(color: fileName == null ? _kBdr : _kP),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _choice(String label, List<String> opts, String current,
          ValueChanged<String> onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: opts.map((o) {
                final sel = o == current;
                return ChoiceChip(
                  label: Text(o),
                  selected: sel,
                  onSelected: (v) {
                    if (v) onChanged(o);
                  },
                  selectedColor: _kA,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(color: sel ? _kA : _kBdr)),
                  labelStyle: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 13, color: _kText),
                );
              }).toList()),
        ],
      );

  Widget _multi(String label, List<String> opts, Set<String> current) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              children: opts.map((o) {
                final sel = current.contains(o);
                return FilterChip(
                  label: Text(o),
                  selected: sel,
                  onSelected: (_) => _tog(current, o),
                  selectedColor: _kA,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(color: sel ? _kA : _kBdr)),
                  labelStyle: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 13, color: _kText),
                  checkmarkColor: _kText,
                );
              }).toList()),
        ],
      );

  Widget _summaryRow(String key, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 90,
              child: Text(key,
                  style:
                      GoogleFonts.plusJakartaSans(fontSize: 12, color: _kSub))),
          Expanded(
              child: Text(val,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _kText))),
        ]),
      );
}

// ── Patient status card ───────────────────────────────────────────────────────
class _PatientCard extends ConsumerWidget {
  final PacienteDashboard p;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PatientCard({
    required this.p,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _estadoColor(p.estadoClinico);
    final label = _estadoLabel(p.estadoClinico);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kSurf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBdr.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _kA.withOpacity(0.4),
            child: Text((p.nombre.isNotEmpty ? p.nombre[0] : '?').toUpperCase(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _kText)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(p.nombre,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _kText)),
                Text('${p.edad} años · ${p.nivelCognitivo}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _kSub)),
              ])),
          IconButton(
            tooltip: 'Editar registro',
            icon: const Icon(Icons.edit_outlined, color: _kSub, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Eliminar registro',
            icon: Icon(Icons.delete_outline,
                color: Colors.red.shade700, size: 20),
            onPressed: onDelete,
          ),
        ]),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text(label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  )),
            ),
            const Spacer(),
            if (p.requiereScq && !p.scqCompletado)
              ElevatedButton.icon(
                icon: const Icon(Icons.quiz_outlined, size: 16),
                label: Text("Responder SCQ",
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () {
                  context.push(
                      '/padre/scq/${p.id}?nombre=${Uri.encodeComponent(p.nombre)}');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kP,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              )
            else if (p.requiereScq && p.scqCompletado && !p.scqAutorizadoEnvio)
              ElevatedButton.icon(
                icon: const Icon(Icons.send_outlined, size: 16),
                label: Text("Enviar solicitud",
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.bold, fontSize: 11)),
                onPressed: () async {
                  await ref
                      .read(dashboardServiceProvider)
                      .enviarCasoScqATerapeuta(p.id);
                  ref.invalidate(familiaDashboardProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Solicitud enviada al terapeuta.')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kP,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
        if (p.requiereScq) ...[
          const SizedBox(height: 10),
          Text(
            p.scqCompletado
                ? 'SCQ: ${p.scqNivel ?? 'Sin nivel'} (${p.scqPuntaje ?? 0} puntos)'
                : 'SCQ pendiente antes de enviar al terapeuta.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: _kSub, fontWeight: FontWeight.w600),
          ),
        ],
        if (p.planActivo != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.spatial_audio_off, size: 14, color: _kSub),
            const SizedBox(width: 6),
            Expanded(
                child: Text(p.planActivo!,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: _kSub))),
          ]),
        ],
      ]),
    );
  }
}
