import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class ClinicalProfileFormScreen extends StatefulWidget {
  @override
  _ClinicalProfileFormScreenState createState() => _ClinicalProfileFormScreenState();
}

class _ClinicalProfileFormScreenState extends State<ClinicalProfileFormScreen> {
  bool isMedicated = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgSecondary,
      appBar: AppBar(
        title: Text('Registro de Perfil Clínico'),
        backgroundColor: AppColors.primaryBlue,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Antecedentes Clínicos'),
            _buildTextField('Describa los antecedentes...'),
            SizedBox(height: 16),
            
            _buildSectionTitle('Escolaridad / Nivel Académico'),
            _buildTextField('Ej: Inicial, Primaria, etc.'),
            SizedBox(height: 16),
            
            _buildSectionTitle('Perfil Sensorial y Preferencias'),
            _buildTextField('Intereses específicos del niño...'),
            SizedBox(height: 16),
            
            _buildSectionTitle('Medicación Actual'),
            SwitchListTile(
              title: Text('¿Toma medicación?'),
              value: isMedicated,
              activeColor: AppColors.successGreen,
              onChanged: (val) => setState(() => isMedicated = val),
            ),
            if (isMedicated)
              _buildTextField('Describa dosis y frecuencia...'),
            SizedBox(height: 16),
            
            _buildSectionTitle('Rituales de Calma'),
            // Checklist para rituales
            CheckboxListTile(
              title: Text('Cambios de rutina'),
              value: false,
              onChanged: (val) {},
            ),
            CheckboxListTile(
              title: Text('Ambientes ruidosos'),
              value: false,
              onChanged: (val) {},
            ),
            CheckboxListTile(
              title: Text('Interacción social'),
              value: false,
              onChanged: (val) {},
            ),
            
            SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.successGreen,
                minimumSize: Size(double.infinity, 50),
              ),
              onPressed: () {
                // SubmitClinicalProfileUseCase.execute()
              },
              child: Text('GUARDAR PERFIL', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
      ),
    );
  }

  Widget _buildTextField(String hint) {
    return TextField(
      maxLines: 3,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.borderInactive),
        ),
      ),
    );
  }
}
