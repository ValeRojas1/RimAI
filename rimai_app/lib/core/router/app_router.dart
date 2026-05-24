import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:rimai_app/adapters/input/screens/auth/register_screen.dart';
import 'package:rimai_app/adapters/input/screens/auth/login_screen.dart';
import 'package:rimai_app/adapters/input/screens/auth/auth_shell_screen.dart';
import 'package:rimai_app/adapters/input/screens/profile/therapeutic_profile_screen.dart';
import 'package:rimai_app/adapters/input/screens/ia/ia_assistant_screen.dart';
import 'package:rimai_app/adapters/input/screens/session/active_session_screen.dart';
import 'package:rimai_app/adapters/input/screens/session/session_summary_screen.dart';
import 'package:rimai_app/adapters/input/screens/session/therapeutic_plan_screen.dart';
import 'package:rimai_app/adapters/input/screens/progress/progress_screen.dart';
import 'package:rimai_app/adapters/input/screens/validation/clinical_validation_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/dashboard_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/familia_dashboard_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/admin_dashboard_screen.dart';
import 'package:rimai_app/adapters/input/screens/admin/create_therapist_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/patient_admission_screen.dart';
import 'package:rimai_app/adapters/input/screens/dashboard/pending_patients_screen.dart';
import 'package:rimai_app/adapters/input/screens/terapeuta/therapist_inbox_screen.dart';
import 'package:rimai_app/adapters/input/screens/terapeuta/reporte_analitico_screen.dart';
import 'package:rimai_app/adapters/input/screens/terapeuta/activities_catalog_screen.dart';
import 'package:rimai_app/adapters/input/screens/terapeuta/plan_builder_screen.dart';
import 'package:rimai_app/adapters/input/screens/terapeuta/therapist_patient_selector_screen.dart';
import 'package:rimai_app/adapters/input/screens/familia/family_activity_session_screen.dart';
import 'package:rimai_app/adapters/input/screens/familia/family_plan_screen.dart';
import 'package:rimai_app/adapters/input/screens/familia/ejecucion_actividad_screen.dart';
import 'package:rimai_app/adapters/input/screens/familia/family_chatbot_screen.dart';
import 'package:rimai_app/domain/entities/reporte.dart';
import 'package:rimai_app/application/usecases/registrar_actividad_usecase.dart';
import 'package:rimai_app/application/usecases/sync_offline_usecase.dart';
import 'package:rimai_app/adapters/output/sqlite_db_repository.dart';
import 'package:rimai_app/adapters/output/api_sync_repository.dart';
import 'package:rimai_app/core/constants/api_constants.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';
import 'package:rimai_app/adapters/input/screens/admision/scq_form_screen.dart';
import 'package:rimai_app/adapters/input/screens/admision/scq_result_screen.dart';
import 'package:rimai_app/domain/entities/scq_result.dart';

/// Proveedor del enrutador principal de la aplicación, conectado al estado de Riverpod.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authStorage = ref.watch(authStorageProvider);

  return GoRouter(
    initialLocation: '/auth/login',
    redirect: (context, state) async {
      final token = await authStorage.getToken();
      final isAuthRoute = state.uri.toString().startsWith('/auth');

      // Sin token → siempre al login
      if (token == null) {
        return isAuthRoute ? null : '/auth/login';
      }

      // Con token en ruta de auth → verificar con el servidor si sigue válido
      if (isAuthRoute) {
        final isValid = await authStorage.isTokenValidOnServer();
        if (!isValid) {
          // Token expirado: sesión ya limpiada → permanecer en login
          return '/auth/login';
        }
        // Token válido → ir al dashboard correspondiente
        final role = await authStorage.getRole();
        if (role == 'terapeuta') return '/terapeuta/dashboard';
        if (role == 'padre_tutor' || role == 'tutor') {
          return '/familia/dashboard';
        }
        if (role == 'admin') return '/admin/dashboard';
        return '/terapeuta/dashboard'; // fallback
      }

      // Con token en ruta protegida → dejar pasar
      final role = await authStorage.getRole();
      final location = state.uri.toString();
      if (location.startsWith('/admin') && role != 'admin') {
        return '/auth/login';
      }
      if (location.startsWith('/terapeuta') && role != 'terapeuta') {
        return role == 'admin' ? '/admin/dashboard' : '/familia/dashboard';
      }
      if (location.startsWith('/familia') &&
          role != 'padre_tutor' &&
          role != 'tutor') {
        return role == 'admin' ? '/admin/dashboard' : '/terapeuta/dashboard';
      }
      return null;
    },
    routes: [
      // ── Auth ───────────────────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => AuthShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/auth',
            redirect: (_, __) => '/auth/login',
          ),
          GoRoute(
            path: '/auth/login',
            name: 'login',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const LoginScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/auth/register',
            name: 'register',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const RegisterScreen(),
              transitionDuration: const Duration(milliseconds: 400),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) =>
                      FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      ),

      // ── Terapeuta ──────────────────────────────────────────────────────────
      GoRoute(
        path: '/terapeuta/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/terapeuta/nino/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return TherapeuticProfileScreen(
            ninoId: ninoId,
            editMode: state.uri.queryParameters['editarPerfil'] == 'true',
          );
        },
      ),
      GoRoute(
        path: '/terapeuta/perfil/:ninoId',
        redirect: (_, state) =>
            '/terapeuta/nino/${state.pathParameters['ninoId']}',
      ),
      GoRoute(
        path: '/terapeuta/planes',
        builder: (context, state) => const TherapistPatientSelectorScreen(
          destination: TherapistPatientDestination.plan,
        ),
      ),
      GoRoute(
        path: '/terapeuta/plan/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return TherapeuticPlanScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/ia',
        builder: (context, state) => const TherapistPatientSelectorScreen(
          destination: TherapistPatientDestination.apoyo,
        ),
      ),
      GoRoute(
        path: '/terapeuta/ia/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return IAAssistantScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/admision',
        builder: (context, state) {
          final ninoId = state.uri.queryParameters['ninoId'];
          return PatientAdmissionScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/pendientes',
        builder: (context, state) => const PendingPatientsScreen(),
      ),
      GoRoute(
        path: '/terapeuta/actividades',
        builder: (context, state) => const ActivitiesCatalogScreen(),
      ),
      GoRoute(
        path: '/terapeuta/sesion',
        builder: (context, state) => const ActiveSessionScreen(sesionId: '1'),
      ),
      GoRoute(
        path: '/terapeuta/sesion/resumen',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final ajustesRaw = extra['ajustesDificultad'];
          final ajustes = ajustesRaw is List
              ? ajustesRaw
                  .whereType<Map>()
                  .map((item) => item.cast<String, dynamic>())
                  .toList()
              : <Map<String, dynamic>>[];
          return SessionSummaryScreen(
            totalAciertos: extra['aciertos'] as int? ?? 0,
            totalIntentos: extra['intentos'] as int? ?? 0,
            segundosTranscurridos: extra['segundos'] as int? ?? 0,
            nivelAyuda: extra['nivelAyuda'] as String? ?? 'Ninguna',
            ninoNombre: extra['ninoNombre'] as String? ?? 'Paciente',
            observaciones: extra['observaciones'] as String?,
            ninoId: extra['ninoId'] as String?,
            planId: extra['planId'] as String?,
            sesionId: extra['sesionId'] as String?,
            sesionNumero: extra['sesionNumero'] as int?,
            nivelDificultadRecomendado: extra['nivelRecomendado'] as String?,
            ajustesDificultad: ajustes,
          );
        },
      ),
      GoRoute(
        path: '/terapeuta/sesion/:sesionId',
        builder: (context, state) {
          final sesionId = state.pathParameters['sesionId'] ?? '1';
          return ActiveSessionScreen(sesionId: sesionId);
        },
      ),
      GoRoute(
        path: '/terapeuta/actividad/:actividadId',
        builder: (context, state) {
          final actividadId = state.pathParameters['actividadId'] ?? '';
          return ActiveSessionScreen(
            sesionId: actividadId,
            actividadId: actividadId,
            ninoId: state.uri.queryParameters['ninoId'],
            planId: state.uri.queryParameters['planId'],
            previewOnly: true,
          );
        },
      ),
      GoRoute(
        path: '/terapeuta/progreso',
        builder: (context, state) => const TherapistPatientSelectorScreen(
          destination: TherapistPatientDestination.progreso,
        ),
      ),
      GoRoute(
        path: '/terapeuta/progreso/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return ProgressScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/validacion/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '1';
          return ClinicalValidationScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/terapeuta/calendario',
        builder: (context, state) =>
            const _PlaceholderScreen(title: 'Calendario'),
      ),
      GoRoute(
        path: '/terapeuta/admision_bandeja',
        builder: (context, state) => const TherapistInboxScreen(),
      ),
      GoRoute(
        path: '/terapeuta/plan_builder',
        builder: (context, state) {
          final ninoId = state.uri.queryParameters['ninoId'] ?? '';
          final patientName = state.uri.queryParameters['nombre'] ?? 'Paciente';
          return PlanBuilderScreen(ninoId: ninoId, patientName: patientName);
        },
      ),
      GoRoute(
        path: '/terapeuta/reportes',
        builder: (context, state) {
          final reporte = state.extra as ReporteAnalitico?;
          if (reporte == null) {
            return const _PlaceholderScreen(title: 'No hay reporte');
          }
          return ReporteAnaliticoScreen(reporte: reporte);
        },
      ),

      // ── Familia / Admin ────────────────────────────────────────────────────
      GoRoute(
        path: '/familia/plan/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '';
          return FamilyPlanScreen(ninoId: ninoId);
        },
      ),
      GoRoute(
        path: '/familia/actividad/:actividadId',
        builder: (context, state) {
          final actividadId = state.pathParameters['actividadId'] ?? '';
          return FamilyActivitySessionScreen(
            actividadId: actividadId,
            ninoId: state.uri.queryParameters['ninoId'] ?? '',
            planId: state.uri.queryParameters['planId'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/familia/sesion/resumen',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final ajustesRaw = extra['ajustesDificultad'];
          final ajustes = ajustesRaw is List
              ? ajustesRaw
                  .whereType<Map>()
                  .map((item) => item.cast<String, dynamic>())
                  .toList()
              : <Map<String, dynamic>>[];
          return SessionSummaryScreen(
            totalAciertos: extra['aciertos'] as int? ?? 0,
            totalIntentos: extra['intentos'] as int? ?? 0,
            segundosTranscurridos: extra['segundos'] as int? ?? 0,
            nivelAyuda: extra['nivelAyuda'] as String? ?? 'Ninguna',
            ninoNombre: extra['ninoNombre'] as String? ?? 'Paciente',
            observaciones: extra['observaciones'] as String?,
            ninoId: extra['ninoId'] as String?,
            planId: extra['planId'] as String?,
            sesionId: extra['sesionId'] as String?,
            sesionNumero: extra['sesionNumero'] as int?,
            nivelDificultadRecomendado: extra['nivelRecomendado'] as String?,
            ajustesDificultad: ajustes,
            permitirAplicarSugerencia: false,
          );
        },
      ),
      GoRoute(
        path: '/familia/ejecucion',
        builder: (context, state) {
          // Instancias básicas para inyección en vista
          final localDb = SqliteDbRepository();
          final apiRepo = ApiSyncRepository(
            baseUrl: ApiConstants.baseUrl,
            tokenProvider: authStorage.getToken,
          );
          return EjecucionActividadScreen(
              registrarUsecase: RegistrarActividadUsecase(localDb),
              syncUsecase: SyncOfflineUsecase(localDb, apiRepo));
        },
      ),
      GoRoute(
        path: '/familia/dashboard',
        builder: (context, state) => const FamiliaDashboardScreen(),
      ),
      GoRoute(
        path: '/familia/chatbot',
        builder: (context, state) => const FamilyChatbotScreen(),
      ),
      GoRoute(
        path: '/padre/scq/resultados',
        builder: (context, state) {
          final result = state.extra;
          if (result is! SCQResult) {
            return const FamiliaDashboardScreen();
          }
          return SCQResultScreen(result: result);
        },
      ),
      GoRoute(
        path: '/padre/scq/:ninoId',
        builder: (context, state) {
          final ninoId = state.pathParameters['ninoId'] ?? '';
          final name = state.uri.queryParameters['nombre'];
          return SCQFormScreen(patientId: ninoId, patientName: name);
        },
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/nuevo-terapeuta',
        builder: (context, state) => const CreateTherapistScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const _PlaceholderScreen(title: 'Inicio'),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});

/// Pantalla temporal para rutas no implementadas aún.
class _PlaceholderScreen extends ConsumerWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F2),
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(authStorageProvider).clearSession();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 64, color: Color(0xFF58423B)),
            const SizedBox(height: 16),
            Text('$title — próximamente',
                style: const TextStyle(color: Color(0xFF58423B))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/terapeuta/dashboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB8D6B2),
                foregroundColor: const Color(0xFF1E1B16),
              ),
              child: const Text('Ir al Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
