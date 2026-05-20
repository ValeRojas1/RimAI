enum CalmingRitualType {
  cambiosRutina,
  ambientesRuidosos,
  interaccionSocial
}

class Medication {
  final bool isMedicated;
  final String? description;

  Medication({required this.isMedicated, this.description});

  Map<String, dynamic> toJson() => {
    'is_medicated': isMedicated,
    'description': description,
  };
}

class CalmingRitual {
  final CalmingRitualType ritualType;
  final String description;

  CalmingRitual({required this.ritualType, required this.description});

  Map<String, dynamic> toJson() => {
    'ritual_type': ritualType.name.toUpperCase(),
    'description': description,
  };
}

class PatientProfile {
  final int? id;
  final int patientId;
  final String antecedentesClinicos;
  final String escolaridad;
  final int perfilSensorialScore;
  final int contextoFamiliarScore;
  final String preferencias;
  final Medication medication;
  final List<CalmingRitual> calmingRituals;
  final String? source;

  PatientProfile({
    this.id,
    required this.patientId,
    required this.antecedentesClinicos,
    required this.escolaridad,
    required this.perfilSensorialScore,
    required this.contextoFamiliarScore,
    required this.preferencias,
    required this.medication,
    required this.calmingRituals,
    this.source,
  });

  Map<String, dynamic> toJson() => {
    'patient_id': patientId,
    'antecedentes_clinicos': antecedentesClinicos,
    'escolaridad': escolaridad,
    'perfil_sensorial_score': perfilSensorialScore,
    'contexto_familiar_score': contextoFamiliarScore,
    'preferencias': preferencias,
    'medication': medication.toJson(),
    'calming_rituals': calmingRituals.map((e) => e.toJson()).toList(),
    'source': source,
  };
}
