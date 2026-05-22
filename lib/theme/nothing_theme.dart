import 'package:flutter/material.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  void toggle() { _mode = isDark ? ThemeMode.light : ThemeMode.dark; notifyListeners(); }
}

final themeNotifier = ThemeNotifier();

class NothingTheme {
  static const Color background  = Color(0xFF000000);
  static const Color surface     = Color(0xFF0C0C0C);
  static const Color cardColor   = Color(0xFF111111);
  static const Color primary     = Color(0xFFFFFFFF);
  static const Color secondary   = Color(0xFF8E8E93);
  static const Color divider     = Color(0xFF222222);

  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color surfaceLight    = Color(0xFFF2F2F2);
  static const Color cardLight       = Color(0xFFE8E8E8);
  static const Color primaryLight    = Color(0xFF000000);
  static const Color secondaryLight  = Color(0xFF555555);
  static const Color dividerLight    = Color(0xFFCCCCCC);

  static const Color accentGreen  = Color(0xFF34C759);
  static const Color accentPurple = Color(0xFFAF52DE);
  static const Color accentBlue   = Color(0xFF007AFF);
  static const Color accentOrange = Color(0xFFFF9500);
  static const Color error        = Color(0xFFFF453A);
  static const Color warning      = Color(0xFFFF9500);
  static const Color success      = Color(0xFF34C759);
  static const Color card2        = Color(0xFF161616);

  static Color bg(bool dark)   => dark ? background   : backgroundLight;
  static Color surf(bool dark) => dark ? surface       : surfaceLight;
  static Color card(bool dark) => dark ? cardColor     : cardLight;
  static Color prim(bool dark) => dark ? primary       : primaryLight;
  static Color sec(bool dark)  => dark ? secondary     : secondaryLight;
  static Color div(bool dark)  => dark ? divider       : dividerLight;

  static const TextStyle heading   = TextStyle(fontFamily:'monospace',fontSize:32,fontWeight:FontWeight.w900,letterSpacing:-0.5,color:primary);
  static const TextStyle title     = TextStyle(fontFamily:'monospace',fontSize:16,fontWeight:FontWeight.w700,letterSpacing:0.3,color:primary);
  static const TextStyle body      = TextStyle(fontFamily:'monospace',fontSize:12,color:secondary);
  static const TextStyle label     = TextStyle(fontFamily:'monospace',fontSize:9,fontWeight:FontWeight.w700,letterSpacing:2.5,color:secondary);
  static const TextStyle button    = TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2,color:primary);
  static const TextStyle buttonDark= TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2,color:background);

  static ThemeData get theme      => _build(Brightness.dark);
  static ThemeData get themeLight => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark  = brightness == Brightness.dark;
    final bg_   = dark ? background   : backgroundLight;
    final surf_ = dark ? surface      : surfaceLight;
    final card_ = dark ? cardColor    : cardLight;
    final prim_ = dark ? primary      : primaryLight;
    final sec_  = dark ? secondary    : secondaryLight;
    final div_  = dark ? divider      : dividerLight;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg_,
      primaryColor: prim_,
      fontFamily: 'monospace',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: prim_, onPrimary: bg_,
        secondary: accentGreen, onSecondary: background,
        surface: surf_, onSurface: prim_,
        error: error, onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
        titleTextStyle: TextStyle(fontFamily:'monospace',fontSize:13,fontWeight:FontWeight.w700,letterSpacing:2.5,color:prim_),
        iconTheme: IconThemeData(color:sec_,size:18),
      ),
      cardTheme: CardThemeData(
        color: card_, elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color:div_,width:0.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surf_,
        border: OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:div_,width:0.5)),
        enabledBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:div_,width:0.5)),
        focusedBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:BorderSide(color:prim_,width:0.5)),
        errorBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(8),borderSide:const BorderSide(color:error,width:0.5)),
        labelStyle: TextStyle(color:sec_,fontSize:10,fontFamily:'monospace'),
        hintStyle:  TextStyle(color:sec_,fontSize:11,fontFamily:'monospace'),
        contentPadding: const EdgeInsets.symmetric(horizontal:14,vertical:13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:prim_, foregroundColor:bg_, elevation:0,
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:13),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
          textStyle:const TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:prim_, side:BorderSide(color:div_,width:0.5),
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(8)),
          padding:const EdgeInsets.symmetric(horizontal:20,vertical:13),
          textStyle:const TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor:sec_,
          textStyle:const TextStyle(fontFamily:'monospace',fontSize:11,letterSpacing:1)),
      ),
      dividerTheme: DividerThemeData(color:div_,thickness:0.5),
      dialogTheme: DialogThemeData(
        backgroundColor:card_,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12),side:BorderSide(color:div_,width:0.5)),
      ),
    );
  }
}

// ── Widgets reutilizables ──

class NothingButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled, isLoading;
  final IconData? icon;
  final Color? color;
  const NothingButton({super.key,required this.label,required this.onTap,this.filled=true,this.isLoading=false,this.icon,this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c    = color ?? NothingTheme.prim(dark);
    final bg   = NothingTheme.bg(dark);
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds:150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical:13,horizontal:18),
        decoration: BoxDecoration(
          color: filled ? c : Colors.transparent,
          border: Border.all(color: filled ? c : c.withOpacity(0.4),width:0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: isLoading
          ? SizedBox(width:16,height:16,child:CircularProgressIndicator(color:filled?bg:c,strokeWidth:1.5))
          : Row(mainAxisSize:MainAxisSize.min,children:[
              if(icon!=null)...[Icon(icon,size:14,color:filled?bg:c),const SizedBox(width:8)],
              Text(label,style:TextStyle(fontFamily:'monospace',fontSize:11,fontWeight:FontWeight.w700,letterSpacing:2,color:filled?bg:c)),
            ])),
      ),
    );
  }
}

class NothingTextField extends StatelessWidget {
  final String label;
  final String? hint, helperText;
  final TextEditingController? controller;
  final bool obscureText, enabled;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onSuffixTap;
  final Widget? suffixIcon;
  final IconData? suffixIconData;
  final int? maxLength, maxLines;
  final void Function(String)? onChanged;
  const NothingTextField({super.key,required this.label,this.hint,this.helperText,this.controller,this.obscureText=false,this.keyboardType=TextInputType.text,this.validator,this.onSuffixTap,this.suffixIcon,this.suffixIconData,this.maxLength,this.enabled=true,this.maxLines=1,this.onChanged});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(label.toUpperCase(),style:TextStyle(fontFamily:'monospace',fontSize:9,fontWeight:FontWeight.w700,letterSpacing:2.5,color:NothingTheme.sec(dark))),
      const SizedBox(height:6),
      TextFormField(
        controller:controller,obscureText:obscureText,keyboardType:keyboardType,
        style:TextStyle(fontFamily:'monospace',fontSize:13,color:NothingTheme.prim(dark)),
        validator:validator,enabled:enabled,maxLength:maxLength,maxLines:maxLines,onChanged:onChanged,
        decoration:InputDecoration(hintText:hint,helperText:helperText,counterText:'',
          suffixIcon:suffixIcon??(suffixIconData!=null?GestureDetector(onTap:onSuffixTap,child:Icon(suffixIconData,color:NothingTheme.sec(dark),size:18)):null)),
      ),
    ]);
  }
}

class NothingCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? borderColor;
  const NothingCard({super.key,required this.child,this.onTap,this.padding=const EdgeInsets.all(14),this.borderColor});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(onTap:onTap,
      child:Container(padding:padding,
        decoration:BoxDecoration(color:NothingTheme.card(dark),borderRadius:BorderRadius.circular(10),
          border:Border.all(color:borderColor??NothingTheme.div(dark),width:0.5)),
        child:child));
  }
}

class NothingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showBackButton;
  const NothingAppBar({super.key,required this.title,this.actions,this.showBackButton=true});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      title:Text(title),centerTitle:true,backgroundColor:Colors.transparent,
      bottom:PreferredSize(preferredSize:const Size.fromHeight(0.5),
        child:Divider(height:0.5,thickness:0.5,color:NothingTheme.div(dark))),
      leading:showBackButton?IconButton(icon:const Icon(Icons.arrow_back_ios,size:16),onPressed:()=>Navigator.pop(context)):null,
      actions:actions,
    );
  }
  @override Size get preferredSize => const Size.fromHeight(56);
}

class NothingBadge extends StatelessWidget {
  final String label;
  final Color color;
  const NothingBadge({super.key,required this.label,required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
      decoration:BoxDecoration(color:color.withOpacity(0.1),border:Border.all(color:color.withOpacity(0.5),width:0.5),borderRadius:BorderRadius.circular(20)),
      child:Text(label,style:TextStyle(fontFamily:'monospace',fontSize:7,fontWeight:FontWeight.w700,letterSpacing:2.5,color:color)),
    );
  }
}

class NothingDivider extends StatelessWidget {
  final String text;
  const NothingDivider({super.key,required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(children:[
      Expanded(child:Divider(color:NothingTheme.div(dark),thickness:0.5)),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),
        child:Text(text,style:TextStyle(fontFamily:'monospace',fontSize:9,fontWeight:FontWeight.w700,letterSpacing:2.5,color:NothingTheme.sec(dark)))),
      Expanded(child:Divider(color:NothingTheme.div(dark),thickness:0.5)),
    ]);
  }
}

class NothingThemeToggle extends StatefulWidget {
  const NothingThemeToggle({super.key});
  @override State<NothingThemeToggle> createState() => _NothingThemeToggleState();
}
class _NothingThemeToggleState extends State<NothingThemeToggle> {
  @override void initState() { super.initState(); themeNotifier.addListener(_r); }
  @override void dispose()   { themeNotifier.removeListener(_r); super.dispose(); }
  void _r() => setState((){});

  @override
  Widget build(BuildContext context) {
    final dark = themeNotifier.isDark;
    return GestureDetector(
      onTap: themeNotifier.toggle,
      child: AnimatedContainer(
        duration:const Duration(milliseconds:300),
        width:56,height:30,
        decoration:BoxDecoration(
          color: dark ? NothingTheme.surface : NothingTheme.surfaceLight,
          borderRadius:BorderRadius.circular(15),
          border:Border.all(color: dark ? NothingTheme.divider : NothingTheme.dividerLight,width:0.5),
        ),
        child:Stack(children:[
          AnimatedPositioned(
            duration:const Duration(milliseconds:300),curve:Curves.easeInOut,
            left: dark ? 28 : 4, top:5,
            child:Container(width:20,height:20,
              decoration:BoxDecoration(color: dark ? NothingTheme.primary : NothingTheme.primaryLight,shape:BoxShape.circle),
              child:Icon(dark?Icons.dark_mode:Icons.light_mode,size:12,
                color: dark ? NothingTheme.background : NothingTheme.backgroundLight)),
          ),
        ]),
      ),
    );
  }
}
