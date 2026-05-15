import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:rimai_app/core/providers/admin_providers.dart';
import 'package:rimai_app/core/providers/auth_providers.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estadisticasAsync = ref.watch(estadisticasAdminProvider);
    final usuariosAsync = ref.watch(listaUsuariosProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F2),
        elevation: 0,
        title: Text(
          'Centro de Mando',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF1E1B16),
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF58423B)),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              await ref.read(authStorageProvider).clearSession();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(estadisticasAdminProvider);
          ref.invalidate(listaUsuariosProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── Sección: KPIs / Estadísticas ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: estadisticasAsync.when(
                  loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFA43714))),
                  error: (err, stack) => Text('Error al cargar stats: $err'),
                  data: (stats) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Métricas Globales',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFA43714),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 1.5,
                        children: [
                          _buildStatCard(
                              'Terapeutas',
                              stats.totalTerapeutas.toString(),
                              Icons.psychology,
                              const Color(0xFFB8D6B2)),
                          _buildStatCard(
                              'Familias',
                              stats.totalFamilias.toString(),
                              Icons.family_restroom,
                              const Color(0xFFE5DCC4)),
                          _buildStatCard('Niños', stats.totalNinos.toString(),
                              Icons.child_care, const Color(0xFFDFB7B7)),
                          _buildStatCard(
                              'Sesiones',
                              stats.totalSesiones.toString(),
                              Icons.check_circle,
                              const Color(0xFF4A624D),
                              isDark: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Título Lista Usuarios ──
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Gestión de Usuarios',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFA43714),
                  ),
                ),
              ),
            ),

            // ── Sección: Lista de Usuarios ──
            usuariosAsync.when(
              loading: () => const SliverToBoxAdapter(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFFB8D6B2)))),
              error: (err, stack) => SliverToBoxAdapter(
                  child: Center(
                      child: Text('Error: $err',
                          style: const TextStyle(color: Colors.red)))),
              data: (usuarios) {
                if (usuarios.isEmpty) {
                  return const SliverToBoxAdapter(
                      child:
                          Center(child: Text('No hay usuarios registrados.')));
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = usuarios[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 1,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: user.rol == 'terapeuta'
                                  ? const Color(0xFFB8D6B2)
                                  : user.rol == 'admin'
                                      ? const Color(0xFFDFB7B7)
                                      : const Color(0xFFE5DCC4),
                              child: Icon(
                                user.rol == 'terapeuta'
                                    ? Icons.psychology
                                    : user.rol == 'admin'
                                        ? Icons.admin_panel_settings
                                        : Icons.family_restroom,
                                color: const Color(0xFF1E1B16),
                              ),
                            ),
                            title: Text(user.nombre,
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.email,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12, color: Colors.black54)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5EDE4),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(user.rol.toUpperCase(),
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: user.activo,
                                  activeColor: const Color(0xFF4A624D),
                                  onChanged: (val) async {
                                    try {
                                      await ref
                                          .read(adminServiceProvider)
                                          .actualizarEstado(user.id, val);
                                      ref.invalidate(listaUsuariosProvider);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text('Error: $e')));
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  tooltip: 'Eliminar usuario',
                                  onPressed: () => _mostrarDialogoEliminar(
                                      context, ref, user.id, user.nombre),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: usuarios.length,
                    ),
                  ),
                );
              },
            ),

            const SliverPadding(
                padding: EdgeInsets.only(bottom: 80)), // Espacio para el FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/nuevo-terapeuta'),
        backgroundColor: const Color(0xFFA43714),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: Text('Nuevo Terapeuta',
            style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _mostrarDialogoEliminar(
      BuildContext context, WidgetRef ref, String id, String nombre) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Text('Eliminar Usuario',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar a "$nombre"?\n\nEsta acción es permanente.',
          style: GoogleFonts.plusJakartaSans(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(adminServiceProvider).eliminarUsuario(id);
                ref.invalidate(listaUsuariosProvider);
                ref.invalidate(estadisticasAdminProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Usuario eliminado exitosamente'),
                        backgroundColor: Color(0xFF4A624D)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                      backgroundColor: Colors.red.shade800,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
            child: const Text('Sí, eliminar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color,
      {bool isDark = false}) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E1B16);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 24),
              const Spacer(),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
