import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/nothing_theme.dart';
import '../services/storage_service.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});
  @override State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  bool _notifViajes   = true;
  bool _notifSaldo    = true;
  bool _notifPromos   = false;

  // Biometría
  bool _bioDisponible  = false;
  bool _bioActivada    = false;
  final _localAuth     = LocalAuthentication();
  late StorageService  _store;

  @override
  void initState() {
    super.initState();
    _store = StorageService();
    themeNotifier.addListener(_rebuild);
    _cargarEstadoBio();
  }

  Future<void> _cargarEstadoBio() async {
    await _store.init();
    try {
      final disp   = await _localAuth.canCheckBiometrics;
      final tipos  = await _localAuth.getAvailableBiometrics();
      final ci     = _store.obtenerCIBio();
      setState(() {
        _bioDisponible = disp && tipos.isNotEmpty;
        _bioActivada   = ci != null && ci.isNotEmpty;
      });
    } catch (_) {
      setState(() { _bioDisponible = false; _bioActivada = false; });
    }
  }

  Future<void> _toggleBio(bool activar) async {
    if (activar) {
      // Para activar, pedir confirmación con huella
      try {
        final ok = await _localAuth.authenticate(
          localizedReason: 'Confirma tu huella para activar el acceso biométrico',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
        if (!ok) return;
        // El CI/PIN ya deben estar guardados del último login exitoso
        final ci = _store.obtenerCIBio();
        if (ci == null || ci.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Primero inicia sesión con CI y PIN para activar la huella.',
                  style: TextStyle(fontFamily: 'monospace')),
              backgroundColor: NothingTheme.accentOrange,
            ));
          }
          return;
        }
        setState(() => _bioActivada = true);
      } catch (_) {
        setState(() => _bioActivada = false);
      }
    } else {
      await _store.limpiarBio();
      setState(() => _bioActivada = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Acceso biométrico desactivado.',
              style: TextStyle(fontFamily: 'monospace')),
          backgroundColor: NothingTheme.accentGreen,
        ));
      }
    }
  }
  @override void dispose()   { themeNotifier.removeListener(_rebuild); super.dispose(); }
  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    final bg   = NothingTheme.bg(dark);
    final prim = NothingTheme.prim(dark);
    final sec  = NothingTheme.sec(dark);
    final div  = NothingTheme.div(dark);
    final surf = NothingTheme.surf(dark);

    return Scaffold(
      backgroundColor: bg,
      appBar: NothingAppBar(title:'AJUSTES'),
      body: ListView(padding:const EdgeInsets.all(20),children:[

        // ── Apariencia ──
        _SecLabel(text:'APARIENCIA', sec:sec),
        const SizedBox(height:12),
        NothingCard(child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Row(children:[
            Icon(dark?Icons.dark_mode:Icons.light_mode, size:18, color:prim),
            const SizedBox(width:12),
            Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('MODO', style:TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:1,color:prim)),
              Text(dark?'Oscuro':'Claro', style:TextStyle(fontFamily:'monospace',fontSize:10,color:sec)),
            ]),
          ]),
          const NothingThemeToggle(),
        ])),
        const SizedBox(height:8),

        // Preview colores
        NothingCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('VISTA PREVIA', style:TextStyle(fontFamily:'monospace',fontSize:9,fontWeight:FontWeight.w700,letterSpacing:2.5,color:sec)),
          const SizedBox(height:12),
          Row(children:[
            _ColorDot(color:NothingTheme.prim(dark), label:'PRIMARIO', border: dark ? null : NothingTheme.dividerLight),
            const SizedBox(width:12),
            _ColorDot(color:surf, label:'SUPERFICIE', border:div),
            const SizedBox(width:12),
            _ColorDot(color:NothingTheme.accentGreen, label:'ACENTO'),
            const SizedBox(width:12),
            _ColorDot(color:NothingTheme.accentPurple, label:'ESTUD.'),
          ]),
          const SizedBox(height:12),
          _GlyphLines(isDark:dark),
        ])),

        const SizedBox(height:24),
        Divider(color:div),
        const SizedBox(height:24),

        // ── Notificaciones ──
        _SecLabel(text:'NOTIFICACIONES', sec:sec),
        const SizedBox(height:12),
        NothingCard(child:Column(children:[
          _SwitchRow(label:'Viajes', sublabel:'Alertas de validación QR',
            value:_notifViajes, isDark:dark, onChanged:(v)=>setState(()=>_notifViajes=v)),
          Divider(color:div,height:1),
          _SwitchRow(label:'Saldo bajo', sublabel:'Cuando sea menor a Bs 5',
            value:_notifSaldo, isDark:dark, onChanged:(v)=>setState(()=>_notifSaldo=v)),
          Divider(color:div,height:1),
          _SwitchRow(label:'Promociones', sublabel:'Ofertas y descuentos',
            value:_notifPromos, isDark:dark, onChanged:(v)=>setState(()=>_notifPromos=v)),
        ])),

        const SizedBox(height:24),
        Divider(color:div),
        const SizedBox(height:24),

        // ── Seguridad ──
        _SecLabel(text:'SEGURIDAD', sec:sec),
        const SizedBox(height:12),
        NothingCard(child:Column(children:[
          if (_bioDisponible) ...[
            _SwitchRow(
              label:'Acceso con huella',
              sublabel: _bioActivada
                  ? 'Activado — toca para desactivar'
                  : 'Desactivado — toca para activar',
              value:_bioActivada,
              isDark:dark,
              icon:Icons.fingerprint,
              iconColor: _bioActivada ? NothingTheme.accentGreen : null,
              onChanged: _toggleBio,
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical:12, horizontal:4),
              child: Row(children:[
                Icon(Icons.fingerprint, size:18, color:sec.withOpacity(0.4)),
                const SizedBox(width:12),
                Expanded(child:Text(
                  'Tu dispositivo no tiene sensor de huella registrado',
                  style:TextStyle(fontFamily:'monospace', fontSize:11, color:sec),
                )),
              ]),
            ),
          ],
        ])),

        const SizedBox(height:24),
        Divider(color:div),
        const SizedBox(height:24),

        // ── Cuenta ──
        _SecLabel(text:'CUENTA', sec:sec),
        const SizedBox(height:12),
        NothingCard(child:Column(children:[
          _MenuRow(icon:Icons.person_outline,  label:'Editar perfil',   isDark:dark, onTap:()=>Navigator.pushNamed(context,'/editar-perfil')),
          Divider(color:div,height:1),
          _MenuRow(icon:Icons.history_outlined, label:'Mis viajes',     isDark:dark, onTap:()=>Navigator.pushNamed(context,'/viajes')),
          Divider(color:div,height:1),
          _MenuRow(icon:Icons.help_outline,    label:'Ayuda y soporte', isDark:dark, onTap:(){}),
          Divider(color:div,height:1),
          _MenuRow(icon:Icons.info_outline,    label:'Acerca de',       isDark:dark, onTap:()=>_mostrarAcercaDe(context, dark, sec, div)),
        ])),

        const SizedBox(height:32),

        // ── Versión / glifo ──
        Center(child:Column(children:[
          _GlyphLogo(isDark:dark),
          const SizedBox(height:12),
          Text('TRANSITAPP', style:TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:3,color:prim)),
          const SizedBox(height:4),
          Text('v1.0.0 — Nothing Edition', style:TextStyle(fontFamily:'monospace',fontSize:9,letterSpacing:1,color:sec)),
        ])),
        const SizedBox(height:32),
      ]),
    );
  }

  void _mostrarAcercaDe(BuildContext context, bool dark, Color sec, Color div) {
    showDialog(context:context,builder:(_)=>AlertDialog(
      title:const Text('ACERCA DE',style:TextStyle(fontFamily:'monospace',fontSize:13,fontWeight:FontWeight.w700,letterSpacing:2)),
      content:Text('TransitApp v1.0.0\nSistema de transporte público con pagos electrónicos.\nDiseñado con estilo Nothing Phone.',
        style:TextStyle(fontFamily:'monospace',fontSize:11,color:sec)),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('CERRAR'))],
    ));
  }
}

// ── Widgets auxiliares ──

class _SecLabel extends StatelessWidget {
  final String text; final Color sec;
  const _SecLabel({required this.text,required this.sec});
  @override
  Widget build(BuildContext context) => Text(text,
    style:TextStyle(fontFamily:'monospace',fontSize:9,fontWeight:FontWeight.w700,letterSpacing:2.5,color:sec));
}

class _ColorDot extends StatelessWidget {
  final Color color; final String label; final Color? border;
  const _ColorDot({required this.color,required this.label,this.border});
  @override
  Widget build(BuildContext context) => Column(children:[
    Container(width:30,height:30,
      decoration:BoxDecoration(color:color,shape:BoxShape.circle,
        border: border!=null ? Border.all(color:border!,width:0.5) : null)),
    const SizedBox(height:4),
    Text(label,style:const TextStyle(fontFamily:'monospace',fontSize:7,letterSpacing:1,color:NothingTheme.secondary)),
  ]);
}

class _GlyphLines extends StatelessWidget {
  final bool isDark;
  const _GlyphLines({required this.isDark});
  @override
  Widget build(BuildContext context) {
    final c = isDark ? Colors.white : Colors.black;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Container(height:0.5,width:double.infinity,color:c.withOpacity(0.15)),
      const SizedBox(height:4),
      Container(height:0.5,width:180,color:c.withOpacity(0.10)),
      const SizedBox(height:4),
      Container(height:0.5,width:220,color:c.withOpacity(0.07)),
      const SizedBox(height:4),
      Container(height:0.5,width:140,color:c.withOpacity(0.05)),
    ]);
  }
}

class _GlyphLogo extends StatelessWidget {
  final bool isDark;
  const _GlyphLogo({required this.isDark});
  @override
  Widget build(BuildContext context) => SizedBox(width:48,height:48,
    child:CustomPaint(painter:_GlyphPainter(color: isDark ? Colors.white : Colors.black)));
}

class _GlyphPainter extends CustomPainter {
  final Color color;
  const _GlyphPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()..color=color.withOpacity(0.8)..strokeWidth=1.5..style=PaintingStyle.stroke;
    final p2 = Paint()..color=color.withOpacity(0.4)..strokeWidth=1.0..style=PaintingStyle.stroke;
    canvas.drawCircle(Offset(size.width/2,size.height/2), size.width/2-1, p1);
    final cx=size.width/2; final cy=size.height/2;
    canvas.drawLine(Offset(cx-10,cy-6), Offset(cx+10,cy-6), p2);
    canvas.drawLine(Offset(cx-7,cy),    Offset(cx+7,cy),    p2);
    canvas.drawLine(Offset(cx-10,cy+6), Offset(cx+10,cy+6), p2);
  }
  @override bool shouldRepaint(_GlyphPainter o) => o.color!=color;
}

class _SwitchRow extends StatelessWidget {
  final String label,sublabel; final bool value,isDark; final ValueChanged<bool> onChanged; final IconData? icon; final Color? iconColor;
  const _SwitchRow({required this.label,required this.sublabel,required this.value,required this.isDark,required this.onChanged,this.icon,this.iconColor});
  @override
  Widget build(BuildContext context) => Padding(
    padding:const EdgeInsets.symmetric(vertical:10),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Row(children:[
        if(icon!=null)...[
          Icon(icon,size:18,color:iconColor??NothingTheme.sec(isDark)),
          const SizedBox(width:12),
        ],
        Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(label,style:TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:1,color:NothingTheme.prim(isDark))),
          Text(sublabel,style:TextStyle(fontFamily:'monospace',fontSize:9,color:NothingTheme.sec(isDark))),
        ]),
      ]),
      Switch(value:value,onChanged:onChanged,
        activeColor:NothingTheme.prim(isDark),
        activeTrackColor:NothingTheme.prim(isDark).withOpacity(0.3),
        inactiveThumbColor:NothingTheme.sec(isDark),
        inactiveTrackColor:NothingTheme.div(isDark)),
    ]));
}

class _MenuRow extends StatelessWidget {
  final IconData icon; final String label; final bool isDark; final VoidCallback onTap;
  const _MenuRow({required this.icon,required this.label,required this.isDark,required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap:onTap,child:Padding(
    padding:const EdgeInsets.symmetric(vertical:12),
    child:Row(children:[
      Icon(icon,size:16,color:NothingTheme.sec(isDark)),
      const SizedBox(width:12),
      Expanded(child:Text(label,style:TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w600,color:NothingTheme.prim(isDark)))),
      Icon(Icons.arrow_forward_ios,size:10,color:NothingTheme.sec(isDark)),
    ])));
}
