import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class BeforeAfterSliderWidget extends StatefulWidget {
  final String urlBefore;
  final String urlAfter;

  const BeforeAfterSliderWidget({
    super.key,
    required this.urlBefore,
    required this.urlAfter,
  });

  @override
  State<BeforeAfterSliderWidget> createState() =>
      _BeforeAfterSliderWidgetState();
}

class _BeforeAfterSliderWidgetState extends State<BeforeAfterSliderWidget> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 260,
            child: LayoutBuilder(
              builder: (_, constraints) {
                final w = constraints.maxWidth;
                final splitX = w * _split;

                return Stack(
                  children: [
                    // Foto del DESPUÉS (fondo completo)
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: widget.urlAfter,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const ColoredBox(
                          color: Color(0xFFE8F5E9),
                        ),
                      ),
                    ),

                    // Foto del ANTES (recortada por el slider)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: splitX,
                      child: ClipRect(
                        child: CachedNetworkImage(
                          imageUrl: widget.urlBefore,
                          width: w,
                          fit: BoxFit.cover,
                          alignment: Alignment.centerLeft,
                          placeholder: (_, __) => const ColoredBox(
                            color: Color(0xFFFFEBEE),
                          ),
                        ),
                      ),
                    ),

                    // Línea divisoria
                    Positioned(
                      left: splitX - 1.5,
                      top: 0,
                      bottom: 0,
                      width: 3,
                      child: Container(color: Colors.white),
                    ),

                    // Ícono del divisor
                    Positioned(
                      left: splitX - 20,
                      top: 0,
                      bottom: 0,
                      width: 40,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.compare_arrows,
                              size: 22, color: Colors.black54),
                        ),
                      ),
                    ),

                    // Etiqueta ANTES
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _Label(text: 'ANTES', color: Colors.red.shade700),
                    ),

                    // Etiqueta DESPUÉS
                    Positioned(
                      right: 10,
                      top: 10,
                      child: _Label(
                          text: 'DESPUÉS', color: Colors.green.shade700),
                    ),

                    // Área de arrastre invisible
                    Positioned.fill(
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _split = (_split + d.delta.dx / w).clamp(0.05, 0.95);
                          });
                        },
                        behavior: HitTestBehavior.translucent,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: _split,
            onChanged: (v) => setState(() => _split = v),
            min: 0.05,
            max: 0.95,
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('← ANTES',
                style: TextStyle(fontSize: 11, color: Colors.red)),
            Text('DESPUÉS →',
                style: TextStyle(fontSize: 11, color: Colors.green)),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final Color color;
  const _Label({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
