import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/widgets/condi_logo.dart';
import '../../../core/widgets/municipality_autocomplete.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/georef_service.dart';

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
    final municipality = _selected;
    if (user == null || municipality == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateUser(user.uid, {
        'municipalityId': 'georef_${municipality.id}',
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
        context.go(
          GoRouterState.of(context).uri.queryParameters['next'] == 'report'
              ? '/report/new?resume=1'
              : '/report/new?mode=camera',
        );
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
                '¿En qué municipio vivís?',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Escribí el nombre y elegilo de la lista. Tus reportes van a '
                'llegar a ese municipio.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              MunicipalityAutocomplete(
                onSelected: (value) => setState(() => _selected = value),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                key: const Key('save-municipality'),
                onPressed: _selected == null || _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continuar'),
              ),
            ],
          ),
        ),
      );
}
