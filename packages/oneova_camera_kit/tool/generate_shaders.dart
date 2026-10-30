// Cross-compiles shaders/look_engine.frag (the one Look source of truth) for
// the native processors with Flutter's own impellerc, so Live and Camera run
// the same compiled shader as the Flutter previews and exports.
//
// Run from packages/oneova_camera_kit after editing the shader:
//   dart run tool/generate_shaders.dart
//
// Outputs (do not edit by hand):
//   android/src/main/kotlin/com/oneova/camerakit/LookEngineShader.kt
//   ios/Classes/LookEngineShader.swift
import 'dart:convert';
import 'dart:io';

import 'package:oneova_camera_kit/src/shader_source_hash.dart';

const _shaderRel = '../../shaders/look_engine.frag';

Future<void> main() async {
  final pkg = File.fromUri(Platform.script).parent.parent;
  final shader = File('${pkg.path}/$_shaderRel');
  if (!shader.existsSync()) _fail('Shader not found: ${shader.path}');
  final source = shader.readAsBytesSync();
  final hash = shaderSourceHash(source);

  final engine = _engineArtifacts();
  final impellerc = File('${engine.path}/impellerc');
  if (!impellerc.existsSync()) _fail('impellerc not found in ${engine.path}');
  final tmp = Directory.systemTemp.createTempSync('oneova_shaders');
  try {
    final metal = _compile(impellerc, engine, shader, tmp, 'runtime-stage-metal');
    final gles = _compile(impellerc, engine, shader, tmp, 'runtime-stage-gles3');

    final uniforms = _floatUniforms(metal.reflection);
    final bufferIndex = {
      for (final m in RegExp(r'constant float\d?& (\w+) \[\[buffer\((\d+)\)\]\]').allMatches(metal.source))
        m.group(1)!: int.parse(m.group(2)!),
    };
    final textureIndex = {
      for (final m in RegExp(r'texture2d<float> (\w+) \[\[texture\((\d+)\)\]\]').allMatches(metal.source))
        m.group(1)!: int.parse(m.group(2)!),
    };
    final entry = RegExp(r'fragment \w+ (\w+)\(').firstMatch(metal.source)?.group(1);
    if (entry == null) _fail('No fragment entry point in the Metal output');
    for (final u in uniforms) {
      if (!bufferIndex.containsKey(u.name)) _fail('Uniform ${u.name} missing from the Metal signature');
    }
    for (final s in const ['uTexture', 'uLut', 'uCurves']) {
      if (!textureIndex.containsKey(s)) _fail('Sampler $s missing from the Metal signature');
    }

    // Native camera grading keeps full float precision (Flutter's GLES
    // backend defaults temporaries to mediump).
    final glesSource = gles.source.replaceFirst('precision mediump float;', 'precision highp float;');
    if (glesSource.contains(r'$') || glesSource.contains('"""')) {
      _fail('GLES source cannot be embedded in a Kotlin raw string');
    }

    _write('${pkg.path}/android/src/main/kotlin/com/oneova/camerakit/LookEngineShader.kt',
        _kotlin(hash, glesSource, uniforms));
    if (metal.source.contains('"""#')) _fail('Metal source cannot be embedded in a Swift raw string');
    _write('${pkg.path}/ios/Classes/LookEngineShader.swift',
        _swift(hash, entry, metal.source, uniforms, bufferIndex, textureIndex));
    stdout.writeln('Generated native Look shaders (source-hash $hash).');
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

class _Uniform {
  final String name;
  final int location;
  final int components;
  int offset = 0;
  _Uniform(this.name, this.location, this.components);
}

class _Compiled {
  final String source;
  final Map<String, dynamic> reflection;
  _Compiled(this.source, this.reflection);
}

Directory _engineArtifacts() {
  // .../flutter/bin/cache/dart-sdk/bin/dart → .../flutter/bin/cache
  final cache = File(Platform.resolvedExecutable).parent.parent.parent;
  final host = Platform.isMacOS
      ? 'darwin-x64'
      : Platform.isWindows
          ? 'windows-x64'
          : 'linux-x64';
  return Directory('${cache.path}/artifacts/engine/$host');
}

_Compiled _compile(File impellerc, Directory engine, File shader, Directory tmp, String stage) {
  final sl = '${tmp.path}/$stage.sl';
  final json = '${tmp.path}/$stage.json';
  final r = Process.runSync(impellerc.path, [
    '--$stage',
    '--input=${shader.path}',
    '--sl=$sl',
    '--spirv=${tmp.path}/$stage.spv',
    '--input-type=frag',
    '--include=${engine.path}/shader_lib',
    '--reflection-json=$json',
  ]);
  if (r.exitCode != 0) _fail('impellerc --$stage failed:\n${r.stdout}\n${r.stderr}');
  return _Compiled(
    File(sl).readAsStringSync(),
    jsonDecode(File(json).readAsStringSync()) as Map<String, dynamic>,
  );
}

/// Float uniforms in declaration order, with their offset in the flat list
/// produced by `LookCompiler.uniformValues`.
List<_Uniform> _floatUniforms(Map<String, dynamic> reflection) {
  final list = <_Uniform>[];
  for (final u in (reflection['uniforms'] as List).cast<Map<String, dynamic>>()) {
    final type = u['type'] as Map<String, dynamic>;
    if (type['type_name'] != 'ShaderType::kFloat') continue;
    if (type['columns'] != 1) _fail('Matrix uniform ${u['name']} is not supported');
    list.add(_Uniform(u['name'] as String, u['location'] as int, type['vec_size'] as int));
  }
  list.sort((a, b) => a.location.compareTo(b.location));
  var offset = 0;
  for (final u in list) {
    u.offset = offset;
    offset += u.components;
  }
  return list;
}

String _kotlin(String hash, String gles, List<_Uniform> uniforms) {
  final count = uniforms.fold<int>(0, (n, u) => n + u.components);
  final b = StringBuffer()
    ..writeln('// GENERATED by tool/generate_shaders.dart from shaders/look_engine.frag — do not edit.')
    ..writeln('package com.oneova.camerakit')
    ..writeln()
    ..writeln('internal object LookEngineShader {')
    ..writeln('    const val SOURCE_HASH = "$hash"')
    ..writeln()
    ..writeln('    /** Floats in LookCompiler.uniformValues (uSize first). */')
    ..writeln('    const val FLOAT_COUNT = $count')
    ..writeln()
    ..writeln('    class Uniform(val name: String, val offset: Int, val components: Int)')
    ..writeln()
    ..writeln('    val UNIFORMS = arrayOf(');
  for (final u in uniforms) {
    b.writeln('        Uniform("${u.name}", ${u.offset}, ${u.components}),');
  }
  b
    ..writeln('    )')
    ..writeln()
    ..writeln('    /** Texture units: source frame, LUT atlas, curves. */')
    ..writeln('    val SAMPLERS = arrayOf("uTexture", "uLut", "uCurves")')
    ..writeln()
    ..writeln('    /** Varying fed by the vertex stage: pixel position in the source frame. */')
    ..writeln('    const val FRAG_COORD_VARYING = "_fragCoord"')
    ..writeln()
    ..writeln('    val FRAGMENT = """')
    ..write(gles)
    ..writeln('""".trimIndent()')
    ..writeln('}');
  return b.toString();
}

String _swift(String hash, String entry, String msl, List<_Uniform> uniforms,
    Map<String, int> buffer, Map<String, int> texture) {
  final count = uniforms.fold<int>(0, (n, u) => n + u.components);
  final b = StringBuffer()
    ..writeln('// GENERATED by tool/generate_shaders.dart from shaders/look_engine.frag — do not edit.')
    ..writeln()
    ..writeln('enum LookEngineShader {')
    ..writeln('  static let sourceHash = "$hash"')
    ..writeln('  static let fragmentFunction = "$entry"')
    ..writeln()
    ..writeln('  /// Floats in LookCompiler.uniformValues (uSize first).')
    ..writeln('  static let floatCount = $count')
    ..writeln()
    ..writeln('  struct Uniform {')
    ..writeln('    let name: String')
    ..writeln('    let offset: Int')
    ..writeln('    let components: Int')
    ..writeln('    let bufferIndex: Int')
    ..writeln('  }')
    ..writeln()
    ..writeln('  static let uniforms: [Uniform] = [');
  for (final u in uniforms) {
    b.writeln('    Uniform(name: "${u.name}", offset: ${u.offset}, components: ${u.components}, '
        'bufferIndex: ${buffer[u.name]}),');
  }
  b
    ..writeln('  ]')
    ..writeln()
    ..writeln('  static let sourceTexture = ${texture['uTexture']}')
    ..writeln('  static let lutTexture = ${texture['uLut']}')
    ..writeln('  static let curvesTexture = ${texture['uCurves']}')
    ..writeln()
    ..writeln('  /// Compiled at runtime (the pod is a static framework, so it carries no metallib).')
    ..writeln('  static let metalSource = #"""')
    ..write(msl)
    ..writeln('"""#')
    ..writeln('}');
  return b.toString();
}

void _write(String path, String content) => File(path).writeAsStringSync(content);

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
