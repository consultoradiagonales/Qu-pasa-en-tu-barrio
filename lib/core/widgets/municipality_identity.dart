import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/municipality_branding.dart';

class MunicipalityIdentity extends StatelessWidget {
  const MunicipalityIdentity({
    super.key,
    this.municipalityId,
    this.municipalityName,
    this.subtitle,
    this.crestSize = 44,
    this.foregroundColor,
    this.titleStyle,
    this.subtitleStyle,
  });

  final String? municipalityId;
  final String? municipalityName;
  final String? subtitle;
  final double crestSize;
  final Color? foregroundColor;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context) {
    final branding = MunicipalityBranding.current(
      municipalityId: municipalityId,
      municipalityName: municipalityName,
    );
    final color = foregroundColor ?? const Color(0xFF17213A);
    final crest = branding.crestAssetPath == null
        ? Container(
            key: const Key('municipality-crest-generic'),
            width: crestSize,
            height: crestSize,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_outlined,
                color: color, size: crestSize * 0.55),
          )
        : SizedBox(
            key: Key('municipality-crest-${branding.key}'),
            width: crestSize,
            height: crestSize,
            child: branding.crestAssetPath!.endsWith('.svg')
                ? SvgPicture.asset(
                    branding.crestAssetPath!,
                    fit: BoxFit.contain,
                    semanticsLabel: 'Escudo de ${branding.name}',
                  )
                : Image.asset(branding.crestAssetPath!,
                    fit: BoxFit.contain,
                    semanticLabel: 'Escudo de ${branding.name}'),
          );

    return Semantics(
      label: branding.displayName,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          crest,
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  branding.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle ??
                      TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (subtitle?.trim().isNotEmpty == true)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle ??
                        TextStyle(
                          color: color.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
