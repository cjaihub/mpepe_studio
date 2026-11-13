/**
 * Mobile optimizer for product models.
 *
 * One source model becomes three hosted files:
 *   mobile  phones: ≤ 120k triangles, 1024px WebP textures, Meshopt geometry
 *   hd      tablets and zoom: ≤ 400k triangles, 2048px WebP textures, Meshopt
 *   ar      "view in your room": ≤ 200k triangles, 2048px PNG/JPEG, Draco
 *           (the system AR viewers don't read WebP or Meshopt)
 *
 * Animations, material names and material variants are kept, because the
 * product viewer drives them (looks, textures, presenter animations).
 */
import { Document, Logger, NodeIO, Primitive, PropertyType } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { cloneDocument, dedup, draco, getBounds, meshopt, prune, resample, simplify, textureCompress, weld } from '@gltf-transform/functions';
import { MeshoptDecoder, MeshoptEncoder, MeshoptSimplifier } from 'meshoptimizer';
import { ModelError, ModelFormat, readModel } from './convert';

export interface ModelStats {
  triangles: number;
  vertices: number;
  materials: string[];
  textures: number;
  animations: string[];
  variants: string[];
  /** Width, height, depth in the model's own units. */
  size: [number, number, number];
}

export interface OptimizedModel {
  mobile: Uint8Array;
  hd: Uint8Array;
  ar: Uint8Array;
  source: ModelStats;
  /** Triangles in the phone file after simplifying. */
  mobileTriangles: number;
}

export const BUDGET = {
  mobile: { triangles: 120_000, texture: 1024 },
  hd: { triangles: 400_000, texture: 2048 },
  ar: { triangles: 200_000, texture: 2048 },
} as const;

let ioPromise: Promise<NodeIO> | null = null;

/** glTF reader/writer with every extension and the Draco + Meshopt codecs. */
export function modelIO(): Promise<NodeIO> {
  ioPromise ??= (async () => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const draco3d = require('draco3dgltf');
    await Promise.all([MeshoptDecoder.ready, MeshoptEncoder.ready, MeshoptSimplifier.ready]);
    return new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({
      'draco3d.decoder': await draco3d.createDecoderModule(),
      'draco3d.encoder': await draco3d.createEncoderModule(),
      'meshopt.decoder': MeshoptDecoder,
      'meshopt.encoder': MeshoptEncoder,
    });
  })();
  return ioPromise;
}

function primTriangles(p: Primitive): number {
  const mode = p.getMode();
  if (mode !== Primitive.Mode.TRIANGLES && mode !== Primitive.Mode.TRIANGLE_STRIP && mode !== Primitive.Mode.TRIANGLE_FAN) return 0;
  const n = p.getIndices()?.getCount() ?? p.getAttribute('POSITION')?.getCount() ?? 0;
  return mode === Primitive.Mode.TRIANGLES ? Math.floor(n / 3) : Math.max(0, n - 2);
}

export function countTriangles(doc: Document): number {
  let t = 0;
  for (const mesh of doc.getRoot().listMeshes()) for (const p of mesh.listPrimitives()) t += primTriangles(p);
  return t;
}

export function statsOf(doc: Document): ModelStats {
  const root = doc.getRoot();
  let vertices = 0;
  for (const mesh of root.listMeshes()) for (const p of mesh.listPrimitives()) vertices += p.getAttribute('POSITION')?.getCount() ?? 0;
  const scene = root.getDefaultScene() ?? root.listScenes()[0];
  const b = scene ? getBounds(scene) : { min: [0, 0, 0], max: [0, 0, 0] };
  const size = [0, 1, 2].map((i) => {
    const d = b.max[i] - b.min[i];
    return Number.isFinite(d) ? Math.round(d * 1000) / 1000 : 0;
  }) as [number, number, number];
  const variants: string[] = [];
  for (const ext of root.listExtensionsUsed()) {
    if (ext.extensionName !== 'KHR_materials_variants') continue;
    for (const prop of ext.listProperties()) {
      const name = (prop as any).propertyType === 'Variant' ? prop.getName() : '';
      if (name) variants.push(name);
    }
  }
  return {
    triangles: countTriangles(doc),
    vertices,
    materials: root.listMaterials().map((m) => m.getName()).filter(Boolean).slice(0, 40),
    textures: root.listTextures().length,
    animations: root.listAnimations().map((a, i) => a.getName() || `Animation ${i + 1}`).slice(0, 20),
    variants: variants.slice(0, 24),
    size,
  };
}

async function variant(
  io: NodeIO,
  base: Document,
  budget: { triangles: number; texture: number },
  kind: 'view' | 'ar',
): Promise<{ bytes: Uint8Array; triangles: number }> {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const sharp = require('sharp');
  const doc = cloneDocument(base);
  const tris = countTriangles(doc);
  if (tris > budget.triangles) {
    await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: budget.triangles / tris, error: 0.01 }));
  }
  const hasTextures = doc.getRoot().listTextures().length > 0;
  if (kind === 'view') {
    if (hasTextures) {
      await doc.transform(textureCompress({ encoder: sharp, targetFormat: 'webp', resize: [budget.texture, budget.texture], quality: 82 }));
    }
    await doc.transform(meshopt({ encoder: MeshoptEncoder, level: 'medium' }));
  } else {
    if (hasTextures) {
      // AR viewers need PNG or JPEG; keep the format unless the source is WebP / AVIF.
      const modern = doc.getRoot().listTextures().some((t) => /webp|avif|ktx/.test(t.getMimeType()));
      await doc.transform(textureCompress({
        encoder: sharp,
        ...(modern ? { targetFormat: 'png' as const } : {}),
        resize: [budget.texture, budget.texture],
      }));
    }
    await doc.transform(draco());
  }
  await doc.transform(prune());
  return { bytes: await io.writeBinary(doc), triangles: countTriangles(doc) };
}

/** Reads, cleans and writes the three hosted variants of a product model. */
export async function optimizeModel(bytes: Uint8Array, format: ModelFormat): Promise<OptimizedModel> {
  const io = await modelIO();
  let doc: Document;
  try {
    doc = await readModel(io, bytes, format);
  } catch (e) {
    if (e instanceof ModelError) throw e;
    throw new ModelError('This 3D file could not be opened. Export it again as .glb and retry.');
  }
  if (doc.getRoot().listMeshes().length === 0) throw new ModelError('This file has no 3D shapes in it.');
  const source = statsOf(doc);
  if (source.triangles === 0) throw new ModelError('This file has no surfaces to show.');
  doc.setLogger(new Logger(Logger.Verbosity.WARN));
  // Materials are never merged: sellers put textures on them by name.
  await doc.transform(dedup({ propertyTypes: [PropertyType.ACCESSOR, PropertyType.MESH, PropertyType.TEXTURE] }), prune(), weld(), resample());
  const mobile = await variant(io, doc, BUDGET.mobile, 'view');
  const hd = await variant(io, doc, BUDGET.hd, 'view');
  const ar = await variant(io, doc, BUDGET.ar, 'ar');
  return { mobile: mobile.bytes, hd: hd.bytes, ar: ar.bytes, source, mobileTriangles: mobile.triangles };
}
