/// Entidad de dominio: Usuario
class Usuario {
  final String? id;
  final String nombreCompleto;
  final String correo;
  final String? rol;
  final String? token;

  const Usuario({
    this.id,
    required this.nombreCompleto,
    required this.correo,
    this.rol,
    this.token,
  });

  Usuario copyWith({
    String? id,
    String? nombreCompleto,
    String? correo,
    String? rol,
    String? token,
  }) {
    return Usuario(
      id: id ?? this.id,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      correo: correo ?? this.correo,
      rol: rol ?? this.rol,
      token: token ?? this.token,
    );
  }

  @override
  String toString() =>
      'Usuario(id: $id, nombreCompleto: $nombreCompleto, correo: $correo, rol: $rol)';
}
