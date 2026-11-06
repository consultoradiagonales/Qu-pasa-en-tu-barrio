import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/municipality_build_config.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/condi_logo.dart';
import '../../../core/widgets/municipality_autocomplete.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/georef_service.dart';

String municipalityReturnDestination(String? next) {
  switch (next) {
    case 'report':
      return '/report/new?resume=1';
    case 'profile':
      return '/profile';
    case 'home':
    default:
      return '/home';
  }
}

/// Elegir el municipio es lo único que hace falta para poder reportar: las
/// reglas de Firestore exigen que el municipio del reporte sea el del perfil.
class SelectMunicipalityScreen extends ConsumerStatefulWidget {
  const SelectMunicipalityScreen({super.key});

  @override
  ConsumerState<SelectMunicipalityScreen> createState() =>
      _SelectMunicipalityScreenState();
}

class _SelectMunicipalityScreenState
    extends ConsumerState<SelectMunicipalityScreen> {
  MunicipalitySuggestion? _selected;
  bool _saving = false;

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final municipality = MunicipalityBuildConfig.isLocked
        ? MunicipalitySuggestion(
            id: MunicipalityBuildConfig.municipalityId
                .replaceFirst('georef_', ''),
            name: MunicipalityBuildConfig.municipalityName,
            provinceId: MunicipalityBuildConfig.provinceId,
            province: MunicipalityBuildConfig.provinceName,
          )
        : _selected;
    if (user == null || municipality == null) return;
    final role = ref.read(currentUserRoleProvider);
    if (role != null && role != 'citizen') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Solo las cuentas ciudadanas pueden cambiar municipio.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateUser(user.uid, {
        'municipalityId': MunicipalityBuildConfig.isLocked
            ? MunicipalityBuildConfig.firestoreMunicipalityId
            : 'georef_${municipality.id}',
        'municipalityName': municipality.name,
        'provinceId': municipality.provinceId,
        'province': municipality.province,
        // Si antes había un detalle más fino de otro municipio, ya no vale.
        'departmentId': null,
        'department': null,
        'localityId': null,
        'locality': null,
        'settlementId': null,
        'settlement': null,
      });
      if (mounted) {
        context.go(municipalityReturnDestination(
          GoRouterState.of(context).uri.queryParameters['next'],
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensajeDeError(error)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tu municipio')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const Center(child: CondiLogo(fontSize: 34)),
              const SizedBox(height: 24),
              Text(
                MunicipalityBuildConfig.isLocked
                    ? 'Esta edición corresponde a ${MunicipalityBuildConfig.municipalityName}'
                    : '¿En qué municipio querés recibir alertas?',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                MunicipalityBuildConfig.isLocked
                    ? 'Tus reportes y la información visible se gestionan únicamente dentro de este municipio.'
                    : 'Escribí el nombre y elegilo de la lista. Quedará guardado en tu perfil para recibir alertas oficiales del SMN de tu zona y áreas aledañas.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              if (!MunicipalityBuildConfig.isLocked)
                MunicipalityAutocomplete(
                  onSelected: (value) => setState(() => _selected = value),
                ),
              const SizedBox(height: 24),
              ElevatedButton(
                key: const Key('save-municipality'),
                onPressed:
                    (!MunicipalityBuildConfig.isLocked && _selected == null) ||
                            _saving
                        ? null
                        : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar municipio'),
              ),
            ],
          ),
        ),
      );
}
