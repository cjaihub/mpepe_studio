import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;

import '../../shared/theme/app_theme.dart';
import '../models/shop_models.dart';
import 'stage_style.dart';

/// Where the camera looks from. A presenter's pose is sent to every viewer of
/// a live stage so they see the product from the same side.
@immutable
class CameraPose {
  const CameraPose({required this.theta, required this.phi, required this.radius, required this.fov});

  /// Radians around the product, radians down from the top, metres away.
  final double theta, phi, radius;

  /// Field of view in degrees (zoom).
  final double fov;

  static CameraPose? parse(Object? raw) {
    if (raw is! Map) return null;
    double? n(String k) => (raw[k] as num?)?.toDouble();
    final th = n('th'), ph = n('ph'), r = n('r'), fov = n('fov');
    if (th == null || ph == null || r == null || fov == null || r <= 0) return null;
    return CameraPose(theta: th, phi: ph, radius: r, fov: fov);
  }

  Map<String, dynamic> toMap() => {'th': theta, 'ph': phi, 'r': radius, 'fov': fov};

  String get key => '${theta.toStringAsFixed(3)},${phi.toStringAsFixed(3)},${radius.toStringAsFixed(3)},${fov.toStringAsFixed(1)}';
}

/// Named views a presenter (or Ova, from a typed request) can jump to.
enum ProductView {
  front('Front', 0, 75),
  side('Side', 90, 75),
  back('Back', 180, 75),
  top('Top', 0, 12),
  under('Underside', 0, 168),
  detail('Close-up', 35, 65, zoom: 0.55);

  const ProductView(this.label, this.thetaDeg, this.phiDeg, {this.zoom = 1});
  final String label;
  final double thetaDeg, phiDeg;

  /// Fraction of the default distance (smaller = closer).
  final double zoom;
}

/// Drives a [Product3DViewer] from outside: views, spin and animations.
class Product3DController {
  _Product3DViewerState? _state;

  void show(ProductView v) => _state?._run(
      "mv.cameraOrbit='${v.thetaDeg}deg ${v.phiDeg}deg ${(105 * v.zoom).round()}%';mv.fieldOfView='auto';");

  void reset() => _state?._run("mv.cameraOrbit='auto auto auto';mv.fieldOfView='auto';");

  void pose(CameraPose p) => _state?._applyPose(p);

  void spin(bool on) => _state?._applySpin(on);

  /// Plays one of the model's own animations (null stops).
  void animate(String? name) => _state?._applyAnimation(name);
}

/// GLB/GLTF product viewer backed by `<model-viewer>`.
///
/// * [interactive] — rotate, pinch-zoom, tap-to-focus and AR. Off in the
///   swipe feed (the web view would swallow the vertical swipe); the feed
///   opens the full product screen for that.
/// * [live] — when false only the poster image is drawn, so a feed keeps a
///   single web view alive (the visible page) on slower phones.
/// * Falls back to the product photos when there is no model or it fails.
class Product3DViewer extends StatefulWidget {
  const Product3DViewer({
    super.key,
    required this.product,
    required this.style,
    this.variant,
    this.interactive = false,
    this.live = true,
    this.autoRotate = true,
    this.onVariantsFound,
    this.textures,
    this.onMaterialsFound,
    this.controller,
    this.onUserCamera,
    this.followPose,
    this.animation,
    this.spin,
  });

  /// Turntable on / off, changeable while the model is shown (null = leave
  /// it as [autoRotate] set it).
  final bool? spin;

  final Product3DController? controller;

  /// The person on this phone moved the camera (throttled). Presenters send
  /// this to their viewers.
  final ValueChanged<CameraPose>? onUserCamera;

  /// A presenter's camera to follow; null leaves the camera alone.
  final CameraPose? followPose;

  /// One of the model's animations to play (null = none).
  final String? animation;

  /// Textures to put on the model; null = the product's own defaults.
  final List<ProductTexture>? textures;

  /// Material names found in the model (for the seller's texture editor).
  final ValueChanged<List<String>>? onMaterialsFound;

  final ShopProduct product;
  final StageStyle style;
  final ProductVariant? variant;
  final bool interactive;
  final bool live;
  final bool autoRotate;

  /// Material variants found inside the model (for the seller's editor).
  final ValueChanged<List<String>>? onVariantsFound;

  @override
  State<Product3DViewer> createState() => _Product3DViewerState();
}

enum _Load { loading, ready, failed }

class _Product3DViewerState extends State<Product3DViewer> {
  _Load _state = _Load.loading;
  double _progress = 0;
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  void _run(String js) => _web?.runJavaScript("(function(){var mv=document.querySelector('model-viewer');if(!mv)return;$js})();");

  void _applyPose(CameraPose p) =>
      _run("mv.cameraOrbit='${p.theta}rad ${p.phi}rad ${p.radius}m';mv.fieldOfView='${p.fov}deg';");

  void _applySpin(bool on) => _run(on ? "mv.setAttribute('auto-rotate','');" : "mv.removeAttribute('auto-rotate');");

  void _applyAnimation(String? name) => _run(name == null
      ? 'mv.pause();'
      : 'mv.animationName=${jsonEncode(name)};mv.play();');

  bool get _supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void didUpdateWidget(Product3DViewer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) widget.controller?._state = this;
    if (widget.followPose != null && widget.followPose!.key != old.followPose?.key) _applyPose(widget.followPose!);
    if (widget.animation != old.animation) _applyAnimation(widget.animation);
    if (widget.spin != null && widget.spin != old.spin) _applySpin(widget.spin!);
    if (old.product.model3dUrl != widget.product.model3dUrl) {
      _state = _Load.loading;
      _progress = 0;
      _web = null;
    } else if (old.variant?.modelVariant != widget.variant?.modelVariant) {
      _applyVariant();
      _applyTextures();
    } else if (_texKey(old) != _texKey(widget)) {
      _applyTextures();
    }
  }

  List<ProductTexture> _texturesOf(Product3DViewer w) => w.textures ?? w.product.textures;

  String _texKey(Product3DViewer w) => _texturesOf(w).map((t) => '${t.material}|${t.texture.url}|${t.texture.scale}').join(',');

  /// Puts the textures on the model's materials (all when material is '').
  /// The model's own textures are kept and come back when the list is empty.
  void _applyTextures() {
    final list = [
      for (final t in _texturesOf(widget))
        {
          'material': t.material,
          'url': t.texture.url,
          'roughness': t.texture.roughness,
          'metallic': t.texture.metallic,
          'scale': t.texture.scale,
        },
    ];
    _web?.runJavaScript('''
(async function(L){
  var mv=document.querySelector('model-viewer'); if(!mv||!mv.model) return;
  var mats=mv.model.materials;
  if(!mv.__orig){ mv.__orig=mats.map(function(m){var p=m.pbrMetallicRoughness;return {t:p.baseColorTexture.texture,r:p.roughnessFactor,m:p.metallicFactor,c:p.baseColorFactor};}); }
  mats.forEach(function(m,i){var o=mv.__orig[i]; if(!o) return; var p=m.pbrMetallicRoughness;
    p.baseColorTexture.setTexture(o.t); p.setRoughnessFactor(o.r); p.setMetallicFactor(o.m); p.setBaseColorFactor(o.c);});
  var cache={};
  for(var i=0;i<L.length;i++){ var t=L[i];
    try{
      var tex=cache[t.url]||(cache[t.url]=await mv.createTexture(t.url));
      if(tex.sampler&&tex.sampler.setScale){ tex.sampler.setScale({u:t.scale,v:t.scale}); }
      mats.forEach(function(m){ if(t.material&&m.name!==t.material) return; var p=m.pbrMetallicRoughness;
        p.baseColorTexture.setTexture(tex); p.setBaseColorFactor([1,1,1,1]); p.setRoughnessFactor(t.roughness); p.setMetallicFactor(t.metallic);});
    }catch(e){}
  }
})(${jsonEncode(list)});
''');
  }

  void _applyVariant() {
    final name = widget.variant?.modelVariant;
    _web?.runJavaScript(
      "var mv=document.querySelector('model-viewer');if(mv){mv.variantName=${jsonEncode(name)};}",
    );
  }

  void _onMessage(String raw) {
    if (!mounted) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      switch (m['t']) {
        case 'progress':
          setState(() => _progress = (m['p'] as num?)?.toDouble() ?? _progress);
        case 'load':
          setState(() => _state = _Load.ready);
          _applyVariant();
          _applyTextures();
          if (widget.followPose != null) _applyPose(widget.followPose!);
          if (widget.animation != null) _applyAnimation(widget.animation);
          if (widget.spin != null) _applySpin(widget.spin!);
          final found = (m['variants'] as List?)?.whereType<String>().toList() ?? const <String>[];
          widget.onVariantsFound?.call(found);
          final mats = (m['materials'] as List?)?.whereType<String>().where((n) => n.isNotEmpty).toSet().toList() ?? const <String>[];
          widget.onMaterialsFound?.call(mats);
        case 'cam':
          final pose = CameraPose.parse(m);
          if (pose != null) widget.onUserCamera?.call(pose);
        case 'error':
          setState(() => _state = _Load.failed);
      }
    } catch (_) {/* ignore malformed bridge messages */}
  }

  static const _bridgeJs = '''
(function(){
  var mv = document.querySelector('model-viewer');
  if (!mv) return;
  function post(o){ try { Shop3D.postMessage(JSON.stringify(o)); } catch(e) {} }
  mv.addEventListener('progress', function(e){ post({t:'progress', p: e.detail.totalProgress}); });
  mv.addEventListener('load', function(){
    var mats = []; try { mats = mv.model ? mv.model.materials.map(function(m){ return m.name || ''; }) : []; } catch(e) {}
    post({t:'load', variants: mv.availableVariants || [], materials: mats});
  });
  mv.addEventListener('error', function(){ post({t:'error'}); });
  var last = 0;
  mv.addEventListener('camera-change', function(e){
    if (!e.detail || e.detail.source !== 'user-interaction') return;
    var now = Date.now(); if (now - last < 220) return; last = now;
    var o = mv.getCameraOrbit();
    post({t:'cam', th:o.theta, ph:o.phi, r:o.radius, fov:mv.getFieldOfView()});
  });
})();
''';

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final poster = p.gallery.isEmpty ? null : p.gallery.first;
    final use3d = p.has3d && _supported && widget.live && _state != _Load.failed;

    if (!use3d) {
      return _Fallback(
        product: p,
        style: widget.style,
        failed: _state == _Load.failed,
        showSwipe: widget.interactive,
      );
    }

    // Tablets get the sharper file; phones the light one.
    final src = p.viewUrl(large: MediaQuery.sizeOf(context).shortestSide >= 600)!;
    // Optimized models carry their own AR file (the system viewer can't read
    // the compressed one), opened from the room button below.
    final arFile = defaultTargetPlatform == TargetPlatform.android && (p.model3dArUrl ?? '').startsWith('https://') ? p.model3dArUrl : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        ModelViewer(
          key: ValueKey('mv_${p.id}_${src}_${widget.interactive}'),
          id: 'mv',
          src: src,
          iosSrc: p.model3dIosUrl,
          poster: poster,
          alt: p.name,
          backgroundColor: Colors.transparent,
          loading: Loading.eager,
          reveal: Reveal.auto,
          cameraControls: widget.interactive,
          disableZoom: !widget.interactive,
          disablePan: true,
          disableTap: !widget.interactive,
          autoRotate: widget.autoRotate,
          autoRotateDelay: widget.interactive ? 3000 : 0,
          rotationPerSecond: widget.interactive ? '18deg' : '24deg',
          interactionPrompt: widget.interactive ? InteractionPrompt.auto : InteractionPrompt.none,
          ar: widget.interactive && arFile == null && (p.model3dHdUrl == null || p.model3dIosUrl != null),
          arModes: const ['scene-viewer', 'webxr', 'quick-look'],
          shadowIntensity: 1,
          shadowSoftness: 0.9,
          exposure: widget.style.dark ? 1.05 : 0.95,
          variantName: widget.variant?.modelVariant,
          relatedJs: _bridgeJs,
          javascriptChannels: {
            JavascriptChannel('Shop3D', onMessageReceived: (msg) => _onMessage(msg.message)),
          },
          onWebViewCreated: (c) => _web = c,
        ),
        if (widget.interactive && arFile != null && _state == _Load.ready)
          Positioned(
            right: 10,
            bottom: 10,
            child: Tooltip(
              message: 'View in your room',
              child: GestureDetector(
                onTap: () => launchUrl(
                  Uri.https('arvr.google.com', '/scene-viewer/1.0', {'file': arFile, 'mode': 'ar_preferred', 'title': p.name}),
                  mode: LaunchMode.externalApplication,
                ),
                child: GlassPanel(
                  style: widget.style,
                  radius: AppRadius.full,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.view_in_ar_rounded, size: 15, color: widget.style.accent),
                    const SizedBox(width: 5),
                    Text('In your room', style: AppTypography.caption(widget.style.fg).copyWith(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        if (_state == _Load.loading)
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.85),
              child: _LoadingBar(progress: _progress, style: widget.style),
            ),
          ),
      ],
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.progress, required this.style});
  final double progress;
  final StageStyle style;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      style: style,
      radius: AppRadius.full,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 70,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 3,
                color: style.accent,
                backgroundColor: style.hairline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('Loading 3D', style: AppTypography.caption(style.fgSecondary)),
        ],
      ),
    );
  }
}

/// Photo presentation when there is no model (or it could not load): the
/// product floats gently above the platform; swipe through photos when
/// [showSwipe] is on.
class _Fallback extends StatefulWidget {
  const _Fallback({required this.product, required this.style, required this.failed, required this.showSwipe});
  final ShopProduct product;
  final StageStyle style;
  final bool failed;
  final bool showSwipe;

  @override
  State<_Fallback> createState() => _FallbackState();
}

class _FallbackState extends State<_Fallback> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final images = widget.product.gallery;
    final still = MediaQuery.of(context).disableAnimations;
    Widget frame(String url) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: StageImage(url: url, style: widget.style, fit: BoxFit.contain, cacheWidth: 900),
          ),
        );

    Widget body;
    if (images.isEmpty) {
      body = Center(child: Icon(Icons.view_in_ar_outlined, size: 56, color: widget.style.fgMuted));
    } else if (!widget.showSwipe || images.length == 1) {
      body = frame(images.first);
    } else {
      body = PageView.builder(
        itemCount: images.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => frame(images[i]),
      );
    }

    if (!still) {
      body = body
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: 4, end: -4, duration: 2600.ms, curve: Curves.easeInOut);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        body,
        if (widget.showSwipe && images.length > 1)
          Align(
            alignment: const Alignment(0, 0.96),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < images.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _page ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == _page ? widget.style.accent : widget.style.hairline,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.failed)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('3D view unavailable — showing photos', style: AppTypography.caption(widget.style.fgMuted)),
            ),
          ),
      ],
    );
  }
}
