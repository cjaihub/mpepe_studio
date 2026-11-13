"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BUDGET = void 0;
exports.modelIO = modelIO;
exports.countTriangles = countTriangles;
exports.statsOf = statsOf;
exports.optimizeModel = optimizeModel;
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
const core_1 = require("@gltf-transform/core");
const extensions_1 = require("@gltf-transform/extensions");
const functions_1 = require("@gltf-transform/functions");
const meshoptimizer_1 = require("meshoptimizer");
const convert_1 = require("./convert");
exports.BUDGET = {
    mobile: { triangles: 120000, texture: 1024 },
    hd: { triangles: 400000, texture: 2048 },
    ar: { triangles: 200000, texture: 2048 },
};
let ioPromise = null;
/** glTF reader/writer with every extension and the Draco + Meshopt codecs. */
function modelIO() {
    ioPromise !== null && ioPromise !== void 0 ? ioPromise : (ioPromise = (async () => {
        // eslint-disable-next-line @typescript-eslint/no-var-requires
        const draco3d = require('draco3dgltf');
        await Promise.all([meshoptimizer_1.MeshoptDecoder.ready, meshoptimizer_1.MeshoptEncoder.ready, meshoptimizer_1.MeshoptSimplifier.ready]);
        return new core_1.NodeIO().registerExtensions(extensions_1.ALL_EXTENSIONS).registerDependencies({
            'draco3d.decoder': await draco3d.createDecoderModule(),
            'draco3d.encoder': await draco3d.createEncoderModule(),
            'meshopt.decoder': meshoptimizer_1.MeshoptDecoder,
            'meshopt.encoder': meshoptimizer_1.MeshoptEncoder,
        });
    })());
    return ioPromise;
}
function primTriangles(p) {
    var _a, _b;
    var _c, _d;
    const mode = p.getMode();
    if (mode !== core_1.Primitive.Mode.TRIANGLES && mode !== core_1.Primitive.Mode.TRIANGLE_STRIP && mode !== core_1.Primitive.Mode.TRIANGLE_FAN)
        return 0;
    const n = (_d = (_c = (_a = p.getIndices()) === null || _a === void 0 ? void 0 : _a.getCount()) !== null && _c !== void 0 ? _c : (_b = p.getAttribute('POSITION')) === null || _b === void 0 ? void 0 : _b.getCount()) !== null && _d !== void 0 ? _d : 0;
    return mode === core_1.Primitive.Mode.TRIANGLES ? Math.floor(n / 3) : Math.max(0, n - 2);
}
function countTriangles(doc) {
    let t = 0;
    for (const mesh of doc.getRoot().listMeshes())
        for (const p of mesh.listPrimitives())
            t += primTriangles(p);
    return t;
}
function statsOf(doc) {
    var _a;
    var _b, _c;
    const root = doc.getRoot();
    let vertices = 0;
    for (const mesh of root.listMeshes())
        for (const p of mesh.listPrimitives())
            vertices += (_b = (_a = p.getAttribute('POSITION')) === null || _a === void 0 ? void 0 : _a.getCount()) !== null && _b !== void 0 ? _b : 0;
    const scene = (_c = root.getDefaultScene()) !== null && _c !== void 0 ? _c : root.listScenes()[0];
    const b = scene ? (0, functions_1.getBounds)(scene) : { min: [0, 0, 0], max: [0, 0, 0] };
    const size = [0, 1, 2].map((i) => {
        const d = b.max[i] - b.min[i];
        return Number.isFinite(d) ? Math.round(d * 1000) / 1000 : 0;
    });
    const variants = [];
    for (const ext of root.listExtensionsUsed()) {
        if (ext.extensionName !== 'KHR_materials_variants')
            continue;
        for (const prop of ext.listProperties()) {
            const name = prop.propertyType === 'Variant' ? prop.getName() : '';
            if (name)
                variants.push(name);
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
async function variant(io, base, budget, kind) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const sharp = require('sharp');
    const doc = (0, functions_1.cloneDocument)(base);
    const tris = countTriangles(doc);
    if (tris > budget.triangles) {
        await doc.transform((0, functions_1.simplify)({ simplifier: meshoptimizer_1.MeshoptSimplifier, ratio: budget.triangles / tris, error: 0.01 }));
    }
    const hasTextures = doc.getRoot().listTextures().length > 0;
    if (kind === 'view') {
        if (hasTextures) {
            await doc.transform((0, functions_1.textureCompress)({ encoder: sharp, targetFormat: 'webp', resize: [budget.texture, budget.texture], quality: 82 }));
        }
        await doc.transform((0, functions_1.meshopt)({ encoder: meshoptimizer_1.MeshoptEncoder, level: 'medium' }));
    }
    else {
        if (hasTextures) {
            // AR viewers need PNG or JPEG; keep the format unless the source is WebP / AVIF.
            const modern = doc.getRoot().listTextures().some((t) => /webp|avif|ktx/.test(t.getMimeType()));
            await doc.transform((0, functions_1.textureCompress)(Object.assign(Object.assign({ encoder: sharp }, (modern ? { targetFormat: 'png' } : {})), { resize: [budget.texture, budget.texture] })));
        }
        await doc.transform((0, functions_1.draco)());
    }
    await doc.transform((0, functions_1.prune)());
    return { bytes: await io.writeBinary(doc), triangles: countTriangles(doc) };
}
/** Reads, cleans and writes the three hosted variants of a product model. */
async function optimizeModel(bytes, format) {
    const io = await modelIO();
    let doc;
    try {
        doc = await (0, convert_1.readModel)(io, bytes, format);
    }
    catch (e) {
        if (e instanceof convert_1.ModelError)
            throw e;
        throw new convert_1.ModelError('This 3D file could not be opened. Export it again as .glb and retry.');
    }
    if (doc.getRoot().listMeshes().length === 0)
        throw new convert_1.ModelError('This file has no 3D shapes in it.');
    const source = statsOf(doc);
    if (source.triangles === 0)
        throw new convert_1.ModelError('This file has no surfaces to show.');
    doc.setLogger(new core_1.Logger(core_1.Logger.Verbosity.WARN));
    // Materials are never merged: sellers put textures on them by name.
    await doc.transform((0, functions_1.dedup)({ propertyTypes: [core_1.PropertyType.ACCESSOR, core_1.PropertyType.MESH, core_1.PropertyType.TEXTURE] }), (0, functions_1.prune)(), (0, functions_1.weld)(), (0, functions_1.resample)());
    const mobile = await variant(io, doc, exports.BUDGET.mobile, 'view');
    const hd = await variant(io, doc, exports.BUDGET.hd, 'view');
    const ar = await variant(io, doc, exports.BUDGET.ar, 'ar');
    return { mobile: mobile.bytes, hd: hd.bytes, ar: ar.bytes, source, mobileTriangles: mobile.triangles };
}
//# sourceMappingURL=optimize.js.map