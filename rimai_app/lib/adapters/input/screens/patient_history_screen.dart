import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class PatientHistoryScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Pantalla cronológica asíncrona
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Historial del Niño'),
        backgroundColor: AppColors.primaryBlue,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildHistoryItem(
            'Perfil Inicial', 
            'Antecedentes y escolaridad...',
            'Tutor',
            '10/05/2026'
          ),
          _buildHistoryItem(
            'Actualización Terapéutica', 
            'Se añaden rituales de calma observados.',
            'Terapeuta',
            '15/05/2026'
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String title, String desc, String source, String date) {
    bool isTutor = source.toLowerCase() == 'tutor';
    
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderInactive.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(date, style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            SizedBox(height: 8),
            Text(desc, style: TextStyle(color: AppColors.textPrimary)),
            SizedBox(height: 12),
            if (isTutor)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tutorBadge,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Datos provistos por Tutor',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                ),
              )
          ],
        ),
      ),
    );
  }
}
