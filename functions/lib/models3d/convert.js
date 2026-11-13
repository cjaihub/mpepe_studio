"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ModelError = exports.MAX_SOURCE_BYTES = exports.MODEL_FORMATS = void 0;
exports.detectFormat = detectFormat;
exports.parseStl = parseStl;
exports.parseObj = parseObj;
exports.flatNormals = flatNormals;
exports.readModel = readModel;
/**
 * Turns the 3D files sellers upload into one glTF document the optimizer can
 * work on. GLB / GLTF are read as they are; STL and OBJ (geometry formats
 * without a scene) are rebuilt as a single mesh with computed normals.
 *
 * Pure: no Firebase, no network. Tested in __tests__/models3d.test.ts.
 */
const core_1 = require("@gltf-transform/core");
exports.MODEL_FORMATS = ['glb', 'gltf', 'obj', 'stl'];
/** Largest source file the worker will open. */
exports.MAX_SOURCE_BYTES = 100 * 1024 * 1024;
class ModelError extends Error {
}
exports.ModelError = ModelError;
/** Format from the file name, confirmed against the first bytes where the format has a signature. */
function detectFormat(name, head) {
    var _a;
    const ext = (_a = name.toLowerCase().split('.').pop()) !== null && _a !== void 0 ? _a : '';
    const magic = Buffer.from(head.subarray(0, 4)).toString('latin1');
    if (magic === 'glTF')
        return 'glb';
    if (ext === 'glb')
        return null; // named .glb but isn't one
    if (ext === 'gltf')
        return 'gltf';
    if (ext === 'obj')
        return 'obj';
    if (ext === 'stl')
        return 'stl';
    return null;
}
// ── STL ─────────────────────────────────────────────────────────────────
/** Triangle soup (xyz per vertex, three vertices per triangle) from binary or ASCII STL. */
function parseStl(bytes) {
    const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (buf.length >= 84) {
        const count = buf.readUInt32LE(80);
        // Binary STL: 80-byte header, count, then 50 bytes per triangle.
        if (count > 0 && 84 + count * 50 === buf.length) {
            const out = new Float32Array(count * 9);
            for (let t = 0; t < count; t++) {
                const o = 84 + t * 50 + 12; // skip the facet normal
                for (let i = 0; i < 9; i++)
                    out[t * 9 + i] = buf.readFloatLE(o + i * 4);
            }
            return out;
        }
    }
    const text = buf.toString('utf8');
    if (!/^\s*solid/i.test(text))
        throw new ModelError('This STL file is damaged.');
    const nums = [];
    const re = /vertex\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)/g;
    let m;
    while ((m = re.exec(text)))
        nums.push(Number(m[1]), Number(m[2]), Number(m[3]));
    if (nums.length < 9 || nums.length % 9 !== 0)
        throw new ModelError('This STL file has no triangles.');
    return Float32Array.from(nums);
}
/**
 * Wavefront OBJ → one triangle soup per `usemtl` group. Polygons are fan
 * triangulated; negative (relative) indices are supported. Normals and UVs are
 * kept only when every corner of the group has them.
 */
function parseObj(text) {
    var _a;
    const v = [];
    const vt = [];
    const vn = [];
    const groups = new Map();
    let cur = '';
    const group = () => {
        let g = groups.get(cur);
        if (!g) {
            g = { material: cur, positions: [], normals: [], uvs: [], okN: true, okT: true };
            groups.set(cur, g);
        }
        return g;
    };
    const idx = (raw, count) => {
        if (!raw)
            return -1;
        const n = parseInt(raw, 10);
        if (!Number.isFinite(n) || n === 0)
            return -1;
        return n > 0 ? n - 1 : count + n;
    };
    for (const line of text.split(/\r?\n/)) {
        const p = line.trim().split(/\s+/);
        switch (p[0]) {
            case 'v':
                v.push(+p[1], +p[2], +p[3]);
                break;
            case 'vt':
                vt.push(+p[1], +((_a = p[2]) !== null && _a !== void 0 ? _a : 0));
                break;
            case 'vn':
                vn.push(+p[1], +p[2], +p[3]);
                break;
            case 'usemtl':
                cur = p.slice(1).join(' ');
                break;
            case 'f': {
                const g = group();
                const corners = p.slice(1).map((c) => {
                    const [a, b, n] = c.split('/');
                    return { p: idx(a, v.length / 3), t: idx(b, vt.length / 2), n: idx(n, vn.length / 3) };
                });
                for (let i = 1; i + 1 < corners.length; i++) {
                    for (const c of [corners[0], corners[i], corners[i + 1]]) {
                        if (c.p < 0 || c.p * 3 + 2 >= v.length)
                            throw new ModelError('This OBJ file points at a vertex that is not there.');
                        g.positions.push(v[c.p * 3], v[c.p * 3 + 1], v[c.p * 3 + 2]);
                        if (c.n >= 0 && c.n * 3 + 2 < vn.length)
                            g.normals.push(vn[c.n * 3], vn[c.n * 3 + 1], vn[c.n * 3 + 2]);
                        else
                            g.okN = false;
                        // glTF's V axis runs the other way.
                        if (c.t >= 0 && c.t * 2 + 1 < vt.length)
                            g.uvs.push(vt[c.t * 2], 1 - vt[c.t * 2 + 1]);
                        else
                            g.okT = false;
                    }
                }
                break;
            }
        }
    }
    const out = [];
    for (const g of groups.values()) {
        if (g.positions.length === 0)
            continue;
        out.push({ material: g.material, positions: g.positions, normals: g.okN ? g.normals : [], uvs: g.okT ? g.uvs : [] });
    }
    if (out.length === 0)
        throw new ModelError('This OBJ file has no faces.');
    return out;
}
/** Flat normals for a triangle soup. */
function flatNormals(positions) {
    const out = new Float32Array(positions.length);
    for (let i = 0; i + 8 < positions.length; i += 9) {
        const ax = positions[i + 3] - positions[i], ay = positions[i + 4] - positions[i + 1], az = positions[i + 5] - positions[i + 2];
        const bx = positions[i + 6] - positions[i], by = positions[i + 7] - positions[i + 1], bz = positions[i + 8] - positions[i + 2];
        let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
        const len = Math.hypot(nx, ny, nz) || 1;
        nx /= len;
        ny /= len;
        nz /= len;
        for (let k = 0; k < 3; k++) {
            out[i + k * 3] = nx;
            out[i + k * 3 + 1] = ny;
            out[i + k * 3 + 2] = nz;
        }
    }
    return out;
}
function soupDocument(groups, name) {
    const doc = new core_1.Document();
    const buffer = doc.createBuffer();
    const mesh = doc.createMesh(name);
    for (const g of groups) {
        const pos = Float32Array.from(g.positions);
        if (pos.some((n) => !Number.isFinite(n)))
            throw new ModelError('This model has broken coordinates.');
        const prim = doc.createPrimitive()
            .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(pos).setBuffer(buffer))
            .setAttribute('NORMAL', doc.createAccessor().setType('VEC3')
            .setArray(g.normals.length === g.positions.length ? Float32Array.from(g.normals) : Float32Array.from(flatNormals(pos))).setBuffer(buffer))
            .setMaterial(doc.createMaterial(g.material || 'Material').setRoughnessFactor(0.6).setMetallicFactor(0));
        if (g.uvs.length / 2 === g.positions.length / 3) {
            prim.setAttribute('TEXCOORD_0', doc.createAccessor().setType('VEC2').setArray(Float32Array.from(g.uvs)).setBuffer(buffer));
        }
        mesh.addPrimitive(prim);
    }
    doc.createScene(name).addChild(doc.createNode(name).setMesh(mesh));
    return doc;
}
/** Reads any supported source into a glTF document. */
async function readModel(io, bytes, format) {
    var _a, _b;
    if (bytes.byteLength > exports.MAX_SOURCE_BYTES)
        throw new ModelError('3D files must be under 100 MB.');
    switch (format) {
        case 'glb':
            return io.readBinary(bytes);
        case 'gltf': {
            let json;
            try {
                json = JSON.parse(Buffer.from(bytes).toString('utf8'));
            }
            catch (_c) {
                throw new ModelError('This .gltf file is not valid.');
            }
            const external = [...((_a = json.buffers) !== null && _a !== void 0 ? _a : []), ...((_b = json.images) !== null && _b !== void 0 ? _b : [])]
                .some((r) => typeof r.uri === 'string' && !r.uri.startsWith('data:'));
            if (external)
                throw new ModelError('This .gltf needs extra files. Export it as a single .glb instead.');
            return io.readJSON({ json, resources: {} });
        }
        case 'stl':
            return soupDocument([{ material: 'Material', positions: Array.from(parseStl(bytes)), normals: [], uvs: [] }], 'Model');
        case 'obj':
            return soupDocument(parseObj(Buffer.from(bytes).toString('utf8')), 'Model');
    }
}
//# sourceMappingURL=convert.js.map