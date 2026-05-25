import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/storage_service.dart';
import '../theme/nothing_theme.dart';

class PanelAdminContratosScreen extends StatefulWidget {
  const PanelAdminContratosScreen({super.key});

  @override
  State<PanelAdminContratosScreen> createState() => _PanelAdminContratosScreenState();
}

class _PanelAdminContratosScreenState extends State<PanelAdminContratosScreen> {
  late SupabaseService supabaseService;
  late StorageService storageService;

  bool _cargando = true;
  List<dynamic> contratosPendientes = [];
  int _procesandoIndex = -1;

  @override
  void initState() {
    super.initState();
    storageService = StorageService();
    supabaseService = SupabaseService(storageService);
    _cargarContratos();
  }

  Future<void> _cargarContratos() async {
    setState(() => _cargando = true);

    try {
      final contratos = await supabaseService.obtenerContratosPendientes();
      setState(() {
        contratosPendientes = contratos;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: NothingTheme.error,
          ),
        );
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _aprobarContrato(String contratoId, int index) async {
    setState(() => _procesandoIndex = index);

    final resultado = await supabaseService.aprobarContratoConductor(
      contratoId: contratoId,
    );

    if (resultado['exito'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Contrato aprobado'),
          backgroundColor: NothingTheme.success,
        ),
      );
      _cargarContratos();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${resultado['mensaje']}'),
          backgroundColor: NothingTheme.error,
        ),
      );
      setState(() => _procesandoIndex = -1);
    }
  }

  Future<void> _rechazarContrato(String contratoId, int index) async {
    final razonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NothingTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rechazar Contrato'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa la razón del rechazo:',
              style: NothingTheme.body,
            ),
            const SizedBox(height: 12),
            NothingTextField(
              label: 'RAZÓN',
              hint: 'Motivo del rechazo...',
              controller: razonController,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: NothingTheme.body),
          ),
          NothingButton(
            label: 'RECHAZAR',
            onTap: () async {
              Navigator.pop(context);
              if (razonController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una razón'),
                    backgroundColor: NothingTheme.error,
                  ),
                );
                return;
              }

              setState(() => _procesandoIndex = index);

              final resultado = await supabaseService.rechazarContratoConductor(
                contratoId: contratoId,
                razonRechazo: razonController.text,
              );

              if (resultado['exito'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✓ Contrato rechazado'),
                    backgroundColor: NothingTheme.warning,
                  ),
                );
                _cargarContratos();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${resultado['mensaje']}'),
                    backgroundColor: NothingTheme.error,
                  ),
                );
                setState(() => _procesandoIndex = -1);
              }
            },
            filled: false,
            color: NothingTheme.error,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NothingTheme.background,
      appBar: NothingAppBar(
        title: 'APROBACIÓN CONTRATOS',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _cargarContratos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : contratosPendientes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inbox, size: 64, color: NothingTheme.secondary),
                      const SizedBox(height: 16),
                      const Text(
                        'SIN CONTRATOS PENDIENTES',
                        style: NothingTheme.label,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No hay solicitudes para revisar',
                        style: NothingTheme.body.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarContratos,
                  color: NothingTheme.primary,
                  backgroundColor: NothingTheme.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: contratosPendientes.length,
                    itemBuilder: (context, index) {
                      final contrato = contratosPendientes[index];
                      final conductor = contrato['conductor'];
                      final fecha = DateTime.parse(
                        contrato['fecha_solicitud'] ?? DateTime.now().toIso8601String(),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          backgroundColor: NothingTheme.cardColor,
                          collapsedBackgroundColor: NothingTheme.cardColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: NothingTheme.divider, width: 0.5),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: NothingTheme.divider, width: 0.5),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${conductor['nombre']} ${conductor['apellido']}',
                                style: NothingTheme.title.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'CI: ${conductor['ci']}',
                                style: NothingTheme.body.copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.business, size: 14, color: NothingTheme.secondary),
                                const SizedBox(width: 4),
                                Text(
                                  contrato['empresa'] ?? 'Sin empresa',
                                  style: NothingTheme.body.copyWith(fontSize: 11),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.calendar_today, size: 14, color: NothingTheme.secondary),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(fecha),
                                  style: NothingTheme.body.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(color: NothingTheme.divider),
                                  const SizedBox(height: 16),

                                  // Datos del conductor
                                  _buildInfoRow('Email', conductor['email'] ?? 'N/A', Icons.email),
                                  const SizedBox(height: 12),
                                  _buildInfoRow('Teléfono', conductor['telefono'] ?? 'N/A', Icons.phone),
                                  const SizedBox(height: 12),
                                  _buildInfoRow('Dirección', conductor['direccion'] ?? 'N/A', Icons.location_on),
                                  const SizedBox(height: 12),
                                  _buildInfoRow('Licencia', conductor['numero_licencia'] ?? 'N/A', Icons.card_travel),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    'Vigencia Licencia',
                                    conductor['vigencia_licencia'] != null
                                        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(conductor['vigencia_licencia']))
                                        : 'No especificada',
                                    Icons.calendar_today,
                                  ),
                                  const SizedBox(height: 16),

                                  // Términos del contrato
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: NothingTheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('TÉRMINOS DEL CONTRATO', style: NothingTheme.label),
                                        const SizedBox(height: 8),
                                        Text(
                                          contrato['terminos_condiciones'] ?? 'Sin especificar',
                                          style: NothingTheme.body.copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Detalles del contrato
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: NothingTheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('DETALLES DEL CONTRATO', style: NothingTheme.label),
                                        const SizedBox(height: 8),
                                        _buildInfoRow('Comisión', '${contrato['comision_porcentaje'] ?? 10}%', Icons.percent),
                                        const SizedBox(height: 8),
                                        _buildInfoRow('Horario', contrato['horario_trabajo'] ?? 'No especificado', Icons.schedule),
                                        const SizedBox(height: 8),
                                        _buildInfoRow('Rutas', contrato['rutas_permitidas'] ?? 'Todas', Icons.route),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Botones de acción
                                  if (_procesandoIndex == index)
                                    const Center(child: CircularProgressIndicator())
                                  else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: NothingButton(
                                            label: 'APROBAR',
                                            onTap: () => _aprobarContrato(contrato['id'], index),
                                            filled: true,
                                            icon: Icons.check,
                                            color: NothingTheme.success,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: NothingButton(
                                            label: 'RECHAZAR',
                                            onTap: () => _rechazarContrato(contrato['id'], index),
                                            filled: false,
                                            icon: Icons.close,
                                            color: NothingTheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: NothingTheme.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: NothingTheme.label.copyWith(fontSize: 9)),
              const SizedBox(height: 2),
              Text(
                value,
                style: NothingTheme.body.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}