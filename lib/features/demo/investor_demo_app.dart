import 'package:flutter/material.dart';

class InvestorDemoApp extends StatelessWidget {
  const InvestorDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123E68)),
      scaffoldBackgroundColor: const Color(0xFFF6F8F7),
    ),
    home: const _DemoHome(),
  );
}

enum _Role { citizen, coordinator, field }

class _DemoHome extends StatefulWidget {
  const _DemoHome();
  @override
  State<_DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<_DemoHome> {
  _Role _role = _Role.citizen;
  String _status = 'Pendiente';
  int _supports = 12;
  int _rating = 0;
  bool _newReport = false;

  Color get _statusColor => switch (_status) {
    'Pendiente' => const Color(0xFFE96B53),
    'Asignado' => const Color(0xFFE9A23B),
    'En curso' => const Color(0xFF387FBB),
    _ => const Color(0xFF34986C),
  };

  void _advance() => setState(() {
    if (_role == _Role.coordinator && _status == 'Pendiente') {
      _status = 'Asignado';
    }
    if (_role == _Role.field && _status == 'Asignado') _status = 'En curso';
    if (_role == _Role.field && _status == 'En curso') _status = 'Resuelto';
  });

  String get _action => switch ((_role, _status)) {
    (_Role.coordinator, 'Pendiente') => 'Asignar Cuadrilla Norte',
    (_Role.field, 'Asignado') => 'Registrar llegada y foto',
    (_Role.field, 'En curso') => 'Trabajo terminado',
    _ => 'Sin acción disponible',
  };

  bool get _canAdvance =>
      (_role == _Role.coordinator && _status == 'Pendiente') ||
      (_role == _Role.field &&
          (_status == 'Asignado' || _status == 'En curso'));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xFF123E68),
      foregroundColor: Colors.white,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUÉ PASA EN TU BARRIO',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text('Demo nativa · datos locales', style: TextStyle(fontSize: 10)),
        ],
      ),
      actions: [
        IconButton(onPressed: _reset, icon: const Icon(Icons.restart_alt)),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SegmentedButton<_Role>(
            segments: const [
              ButtonSegment(
                value: _Role.citizen,
                label: Text('Vecino'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: _Role.coordinator,
                label: Text('Coord.'),
                icon: Icon(Icons.dashboard_outlined),
              ),
              ButtonSegment(
                value: _Role.field,
                label: Text('Cuadrilla'),
                icon: Icon(Icons.engineering_outlined),
              ),
            ],
            selected: {_role},
            onSelectionChanged: (roles) => setState(() => _role = roles.first),
          ),
          const SizedBox(height: 18),
          _hero(),
          if (_role == _Role.coordinator) ...[
            const SizedBox(height: 16),
            _coordinatorPanel(),
          ],
          if (_role == _Role.field) ...[
            const SizedBox(height: 16),
            _fieldPanel(),
          ],
          const SizedBox(height: 16),
          _reportCard(),
          if (_status == 'Resuelto') ...[
            const SizedBox(height: 16),
            _comparison(),
          ],
          const SizedBox(height: 18),
          if (_role == _Role.citizen) _citizenActions() else _staffActions(),
        ],
      ),
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF123E68),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Una ciudad que se hace cargo.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Reportes, coordinación y evidencia visual de cada solución.',
          style: TextStyle(color: Color(0xFFD3E4ED), height: 1.4),
        ),
      ],
    ),
  );

  Widget _reportCard() => Card(
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 128,
          color: const Color(0xFFCADCD0),
          child: const Center(
            child: Icon(
              Icons.lightbulb_outline,
              size: 62,
              color: Color(0xFF496B5E),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _chip(_status, _statusColor),
                  _chip('Alumbrado', const Color(0xFF5F7F72)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _newReport
                    ? 'Reporte nuevo del vecino'
                    : 'Luminaria apagada en la esquina',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'La esquina está a oscuras desde hace varios días. Es una zona transitada durante la noche.',
                style: TextStyle(color: Color(0xFF64756D), height: 1.45),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 17),
                  const SizedBox(width: 5),
                  const Expanded(child: Text('Esquina del barrio · hace 2 h')),
                  const Icon(Icons.people_alt_outlined, size: 17),
                  Text(' $_supports'),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _coordinatorPanel() => _panel('Tablero municipal', const [
    Row(
      children: [
        Expanded(child: _Metric('12', 'Pendientes')),
        Expanded(child: _Metric('5', 'En curso')),
        Expanded(child: _Metric('31', 'Resueltos')),
      ],
    ),
    SizedBox(height: 12),
    Text('La actualización en tiempo real se activa al conectar Firebase.'),
  ]);

  Widget _fieldPanel() => _panel('Tarea de hoy', [
    Text(
      _status == 'Asignado'
          ? 'Nueva asignación disponible.'
          : _status == 'En curso'
          ? 'Cronómetro activo y evidencia en proceso.'
          : _status == 'Resuelto'
          ? 'La evidencia fue enviada al vecino.'
          : 'Esperando asignación de coordinación.',
    ),
  ]);

  Widget _comparison() => _panel('Antes y después', const [
    _BeforeAfter(),
    SizedBox(height: 10),
    Text('La solución queda documentada para el vecino y el municipio.'),
  ]);

  Widget _citizenActions() => Column(
    children: [
      if (_status != 'Resuelto')
        FilledButton.icon(
          onPressed: () => setState(() => _supports++),
          icon: const Icon(Icons.thumb_up_outlined),
          label: Text('Apoyar reporte ($_supports)'),
        ),
      if (_status == 'Resuelto') ...[
        const Text(
          '¿Cómo calificás la solución?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (i) => IconButton(
              onPressed: () => setState(() => _rating = i + 1),
              icon: Icon(
                i < _rating ? Icons.star : Icons.star_border,
                color: const Color(0xFFF4A93E),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _newReport = true;
          _status = 'Pendiente';
        }),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Crear reporte de prueba'),
      ),
    ],
  );

  Widget _staffActions() => FilledButton.icon(
    onPressed: _canAdvance ? _advance : null,
    icon: const Icon(Icons.check_circle_outline),
    label: Text(_action),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE1EAE5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _chip(String label, Color color) => Chip(
    label: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
    backgroundColor: color,
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
  );
  void _reset() => setState(() {
    _role = _Role.citizen;
    _status = 'Pendiente';
    _supports = 12;
    _rating = 0;
    _newReport = false;
  });
}

class _Metric extends StatelessWidget {
  final String number, label;
  const _Metric(this.number, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        number,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xFF123E68),
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF6A7E75)),
      ),
    ],
  );
}

class _BeforeAfter extends StatefulWidget {
  const _BeforeAfter();
  @override
  State<_BeforeAfter> createState() => _BeforeAfterState();
}

class _BeforeAfterState extends State<_BeforeAfter> {
  double split = .5;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: LayoutBuilder(
      builder: (_, constraints) => GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() {
          split = (split + d.delta.dx / constraints.maxWidth).clamp(.08, .92);
        }),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF9ACFA7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  'DESPUÉS · Luminaria reparada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF164B35),
                  ),
                ),
              ),
            ),
            ClipRect(
              clipper: _SplitClipper(split),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF59646C),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'ANTES · Luminaria apagada',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * split - 2,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: Colors.white),
            ),
            Positioned(
              left: constraints.maxWidth * split - 20,
              top: 65,
              child: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.compare_arrows, color: Color(0xFF123E68)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SplitClipper extends CustomClipper<Rect> {
  final double split;
  _SplitClipper(this.split);
  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width * split, s.height);
  @override
  bool shouldReclip(_SplitClipper old) => old.split != split;
}
