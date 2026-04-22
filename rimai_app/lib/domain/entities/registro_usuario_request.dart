/// DTO para el registro de usuario
class RegistroUsuarioRequest {
  final String nombreCompleto;
  final String correo;
  final String contrasena;

  const RegistroUsuarioRequest({
    required this.nombreCompleto,
    required this.correo,
    required this.contrasena,
  });
}
