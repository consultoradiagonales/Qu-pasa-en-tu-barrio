import 'package:flutter/material.dart';

/// Logotipo oficial de ConDi.
class CondiLogo extends StatelessWidget {
  const CondiLogo({super.key, this.fontSize = 40});

  final double fontSize;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(fontSize * .45),
    child: Image.asset(
      'assets/images/condi_logo.png',
      width: fontSize * 2.7,
      height: fontSize * 2.7,
      fit: BoxFit.cover,
    ),
  );
}
