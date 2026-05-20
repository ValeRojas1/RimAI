enum UserRole { admin, terapeuta, tutor }

class User {
  final int id;
  final String email;
  final UserRole role;
  final String nombreCompleto;

  User({
    required this.id,
    required this.email,
    required this.role,
    required this.nombreCompleto,
  });
}
