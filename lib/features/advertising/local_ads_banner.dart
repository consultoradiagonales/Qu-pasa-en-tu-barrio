import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'local_ad.dart';

/// Banner pequeño en el zócalo ciudadano. La pauta define si puede cerrarse
/// inmediatamente o si el control se habilita después de siete segundos.
class LocalAdsBanner extends ConsumerStatefulWidget {
  const LocalAdsBanner({super.key, required this.municipalityId});

  final String municipalityId;

  @override
  ConsumerState<LocalAdsBanner> createState() => _LocalAdsBannerState();
}

class _LocalAdsBannerState extends ConsumerState<LocalAdsBanner> {
  Timer? _refreshTimer;
  bool _closedForSession = false;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LocalAdsBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.municipalityId != widget.municipalityId) {
      _closedForSession = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _open(LocalAd ad) async {
    if (!LocalAd.validLink(ad.link)) return;
    try {
      if (!await launchUrl(Uri.parse(ad.link),
          mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No pudimos abrir el enlace del comercio.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.municipalityId.isEmpty || _closedForSession) {
      return const SizedBox.shrink();
    }
    final ads = ref
            .watch(localAdsProvider(widget.municipalityId))
            .valueOrNull
            ?.where((ad) => ad.visibleAt(DateTime.now()))
            .toList() ??
        const <LocalAd>[];
    if (ads.isEmpty) return const SizedBox.shrink();

    ads.sort((a, b) => a.business.compareTo(b.business));
    final rotation = DateTime.now().millisecondsSinceEpoch ~/
        const Duration(minutes: 1).inMilliseconds;
    final ad = ads[rotation % ads.length];
    return SafeArea(
      top: false,
      child: _SponsoredAdCard(
        key: ValueKey(ad.id),
        ad: ad,
        onOpen: () => _open(ad),
        onClose: () => setState(() => _closedForSession = true),
      ),
    );
  }
}

class _SponsoredAdCard extends StatefulWidget {
  const _SponsoredAdCard({
    super.key,
    required this.ad,
    required this.onOpen,
    required this.onClose,
  });

  final LocalAd ad;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<_SponsoredAdCard> createState() => _SponsoredAdCardState();
}

class _SponsoredAdCardState extends State<_SponsoredAdCard> {
  Timer? _countdown;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.ad.dismissDelaySeconds;
    if (_secondsLeft > 0) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        if (_secondsLeft <= 1) {
          timer.cancel();
          setState(() => _secondsLeft = 0);
        } else {
          setState(() => _secondsLeft -= 1);
        }
      });
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _secondsLeft == 0;
    return Material(
      color: Colors.white,
      child: Container(
        height: 82,
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          border: Border.all(color: const Color(0xFFDDE6F1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Row(
                    children: [
                      _AdImage(url: widget.ad.imageUrl),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'PUBLICIDAD',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: .8,
                                color: Color(0xFF71829A),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.ad.business,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF17213A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.ad.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF52647D),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.open_in_new,
                            size: 16, color: Color(0xFF2669C7)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: canClose
                  ? IconButton(
                      tooltip: 'Cerrar publicidad',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close,
                          size: 19, color: Color(0xFF61738C)),
                    )
                  : Center(
                      child: Text(
                        '${_secondsLeft}s',
                        style: const TextStyle(
                          color: Color(0xFF61738C),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdImage extends StatelessWidget {
  const _AdImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FB),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.storefront_outlined,
          color: Color(0xFF2669C7), size: 27),
    );
    if (url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        url,
        width: 58,
        height: 58,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}
