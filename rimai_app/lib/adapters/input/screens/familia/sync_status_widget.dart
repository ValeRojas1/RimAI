import 'package:flutter/material.dart';
import '../../../../application/ports/local_db_port.dart';

// PMV 3: Indicador visual de estado offline/online
class SyncStatusWidget extends StatefulWidget {
  final ILocalDbPort localDb;

  const SyncStatusWidget({super.key, required this.localDb});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  int _pendientes = 0;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final list = await widget.localDb.getActividadesPendientes();
    setState(() {
      _pendientes = list.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isSynced = _pendientes == 0;
    Color color = isSynced ? const Color(0xFF48BB78) : Colors.orange;
    IconData icon = isSynced ? Icons.cloud_done : Icons.cloud_off;
    String text = isSynced ? "Sincronizado" : "$_pendientes pendientes de red";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
