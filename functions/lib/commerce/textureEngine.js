"use strict";
/**
 * Oneova texture engine: seamless (tileable) material textures drawn on the
 * server, no I/O here (unit tested). textures.ts renders them to PNG, hosts
 * them in Storage and lists them for sellers and the 3D viewer.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.BUILT_IN = exports.TEXTURE_KINDS = exports.MATERIAL = void 0;
exports.hexToRgb = hexToRgb;
exports.renderTexture = renderTexture;
/** Physical look the viewer applies with the image. */
exports.MATERIAL = {
    wood: { roughness: 0.7, metallic: 0, scale: 1, label: 'Wood', category: 'Natural' },
    marble: { roughness: 0.25, metallic: 0, scale: 1, label: 'Marble', category: 'Stone' },
    carbon: { roughness: 0.35, metallic: 0.2, scale: 4, label: 'Carbon fibre', category: 'Tech' },
    denim: { roughness: 0.9, metallic: 0, scale: 3, label: 'Denim', category: 'Fabric' },
    leather: { roughness: 0.6, metallic: 0, scale: 2, label: 'Leather', category: 'Leather' },
    brushed_metal: { roughness: 0.3, metallic: 1, scale: 1, label: 'Brushed metal', category: 'Metal' },
    glitter: { roughness: 0.4, metallic: 0.6, scale: 2, label: 'Glitter', category: 'Party' },
    knit: { roughness: 0.95, metallic: 0, scale: 4, label: 'Knit', category: 'Fabric' },
    terrazzo: { roughness: 0.45, metallic: 0, scale: 1, label: 'Terrazzo', category: 'Stone' },
    camo: { roughness: 0.85, metallic: 0, scale: 1, label: 'Camo', category: 'Pattern' },
    concrete: { roughness: 0.9, metallic: 0, scale: 1, label: 'Concrete', category: 'Stone' },
    velvet: { roughness: 1, metallic: 0, scale: 2, label: 'Velvet', category: 'Fabric' },
};
exports.TEXTURE_KINDS = Object.keys(exports.MATERIAL);
function hexToRgb(hex) {
    const h = String(hex !== null && hex !== void 0 ? hex : '').replace('#', '');
    if (!/^[0-9a-fA-F]{6}$/.test(h))
        return [128, 128, 128];
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
}
const mix = (a, b, t) => {
    const k = Math.min(1, Math.max(0, t));
    return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
};
const shade = (c, f) => [c[0] * f, c[1] * f, c[2] * f];
/** Integer hash → [0,1). */
function hash(x, y, seed) {
    let h = (x * 374761393 + y * 668265263 + seed * 2147483647) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
}
/** Periodic value noise: wraps every [period] cells, so the image tiles. */
function noise(x, y, period, seed) {
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    const w = (n) => ((n % period) + period) % period;
    const a = hash(w(xi), w(yi), seed), b = hash(w(xi + 1), w(yi), seed);
    const c = hash(w(xi), w(yi + 1), seed), d = hash(w(xi + 1), w(yi + 1), seed);
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}
/** Fractal noise in [0,1], tileable over the unit square at base [freq]. */
function fbm(u, v, freq, seed, octaves = 4) {
    let sum = 0, amp = 0.5, f = freq, norm = 0;
    for (let o = 0; o < octaves; o++) {
        sum += amp * noise(u * f, v * f, f, seed + o * 17);
        norm += amp;
        amp *= 0.5;
        f *= 2;
    }
    return sum / norm;
}
/** RGBA pixels (size × size × 4) for [spec]. Same spec + seed → same image. */
function renderTexture(spec) {
    var _a, _b;
    const size = Math.min(Math.max((_a = spec.size) !== null && _a !== void 0 ? _a : 512, 64), 1024);
    const seed = (_b = spec.seed) !== null && _b !== void 0 ? _b : 7;
    const c = (i, fallback) => { var _a; return hexToRgb((_a = spec.colors[i]) !== null && _a !== void 0 ? _a : fallback); };
    const out = new Uint8Array(size * size * 4);
    const chips = [];
    if (spec.kind === 'terrazzo') {
        for (let i = 0; i < 140; i++) {
            chips.push({ x: hash(i, 1, seed), y: hash(i, 2, seed), r: 0.008 + hash(i, 3, seed) * 0.03, col: c(1 + (i % 3), ['#C94F3D', '#2F5D8A', '#E8B04B'][i % 3]) });
        }
    }
    for (let py = 0; py < size; py++) {
        for (let px = 0; px < size; px++) {
            const u = px / size, v = py / size;
            let col;
            switch (spec.kind) {
                case 'wood': {
                    const d = fbm(u, v, 4, seed) * 6;
                    const rings = Math.sin((u * 18 + d) * Math.PI * 2) * 0.5 + 0.5;
                    const grain = noise(u * 256, v * 8, 256, seed + 3) * 0.25;
                    col = mix(c(0, '#5A3A22'), c(1, '#A06B3F'), rings * 0.8 + grain);
                    break;
                }
                case 'marble': {
                    const t = Math.abs(Math.sin((u * 3 + v * 2 + fbm(u, v, 3, seed, 5) * 4) * Math.PI));
                    col = mix(c(1, '#3A3A40'), c(0, '#F2F0EB'), Math.pow(t, 0.35));
                    break;
                }
                case 'carbon': {
                    const n = 16, cx = Math.floor(u * n), cy = Math.floor(v * n);
                    const fx = u * n - cx, fy = v * n - cy;
                    const horiz = (cx + cy) % 2 === 0;
                    const band = horiz ? Math.sin(fy * Math.PI) : Math.sin(fx * Math.PI);
                    col = shade(mix(c(0, '#15171A'), c(1, '#3A3F47'), band * 0.9), 0.85 + 0.15 * band);
                    break;
                }
                case 'denim': {
                    const twill = Math.sin((u * 96 + v * 96) * Math.PI * 2) * 0.5 + 0.5;
                    const slub = fbm(u, v, 8, seed) * 0.5;
                    col = mix(c(0, '#1E3A5F'), c(1, '#6F8FB3'), twill * 0.35 + slub * 0.5 + noise(u * 512, v * 512, 512, seed) * 0.15);
                    break;
                }
                case 'leather': {
                    const pores = noise(u * 128, v * 128, 128, seed) * 0.6 + noise(u * 256, v * 256, 256, seed + 1) * 0.4;
                    const crease = Math.pow(1 - Math.abs(fbm(u, v, 6, seed + 9) * 2 - 1), 8);
                    col = shade(mix(c(0, '#4B2B1A'), c(1, '#7C4A2D'), fbm(u, v, 3, seed)), 0.8 + pores * 0.25 - crease * 0.25);
                    break;
                }
                case 'brushed_metal': {
                    const streak = noise(u * 2, v * 512, 512, seed) * 0.7 + noise(u * 4, v * 256, 256, seed + 5) * 0.3;
                    col = mix(c(0, '#8E9399'), c(1, '#E3E6EA'), streak);
                    break;
                }
                case 'glitter': {
                    const h = hash(px, py, seed);
                    const sparkle = h > 0.985 ? 1 : h > 0.96 ? 0.5 : 0;
                    col = mix(mix(c(0, '#B23A7A'), c(1, '#F4B8D9'), fbm(u, v, 6, seed) * 0.6), [255, 255, 255], sparkle);
                    break;
                }
                case 'knit': {
                    const n = 24, cx = u * n, cy = v * n * 1.5;
                    const fx = cx - Math.floor(cx), fy = cy - Math.floor(cy);
                    const vShape = Math.abs(fx - 0.5) * 2 - fy;
                    const stitch = Math.exp(-Math.pow(vShape * 3, 2));
                    col = shade(mix(c(0, '#7A2E3A'), c(1, '#C9606F'), stitch), 0.75 + 0.25 * stitch);
                    break;
                }
                case 'terrazzo': {
                    col = mix(c(0, '#EDE8E0'), [210, 205, 198], noise(u * 64, v * 64, 64, seed) * 0.4);
                    for (const k of chips) {
                        const dx = Math.min(Math.abs(u - k.x), 1 - Math.abs(u - k.x));
                        const dy = Math.min(Math.abs(v - k.y), 1 - Math.abs(v - k.y));
                        if (dx * dx + dy * dy < k.r * k.r)
                            col = k.col;
                    }
                    break;
                }
                case 'camo': {
                    const a = fbm(u, v, 3, seed), b = fbm(u, v, 4, seed + 50);
                    col = a > 0.56 ? c(2, '#2E3A23') : b > 0.52 ? c(1, '#6B6B3A') : c(0, '#A39465');
                    break;
                }
                case 'concrete': {
                    const base = fbm(u, v, 4, seed, 5);
                    const speck = hash(px, py, seed) > 0.97 ? -0.15 : 0;
                    col = shade(mix(c(0, '#8A8A86'), c(1, '#BDBCB7'), base), 1 + speck);
                    break;
                }
                case 'velvet':
                default: {
                    const sheen = fbm(u, v, 5, seed) * 0.7 + noise(u * 512, v * 512, 512, seed) * 0.3;
                    col = mix(c(0, '#3D0F2E'), c(1, '#8A2A5E'), sheen);
                    break;
                }
            }
            const o = (py * size + px) * 4;
            out[o] = Math.max(0, Math.min(255, Math.round(col[0])));
            out[o + 1] = Math.max(0, Math.min(255, Math.round(col[1])));
            out[o + 2] = Math.max(0, Math.min(255, Math.round(col[2])));
            out[o + 3] = 255;
        }
    }
    return out;
}
/** The built-in library: every kind in a few colorways. */
exports.BUILT_IN = [
    ['wood', 'Walnut', ['#4A2F1C', '#8C5A33']], ['wood', 'Oak', ['#8A6239', '#D2A66E']], ['wood', 'Ebony', ['#1C1410', '#3E2C22']],
    ['marble', 'White marble', ['#F4F2EE', '#5A5A60']], ['marble', 'Black marble', ['#2A2A2E', '#D8D4CC']], ['marble', 'Rose marble', ['#F6E3E1', '#B06A6A']],
    ['carbon', 'Carbon black', ['#121315', '#34383F']], ['carbon', 'Blue carbon', ['#0B1E3A', '#0C4FA8']],
    ['denim', 'Indigo denim', ['#1E3A5F', '#6F8FB3']], ['denim', 'Washed denim', ['#4A6D93', '#A9C1DB']], ['denim', 'Black denim', ['#1B1C20', '#4C4F57']],
    ['leather', 'Cognac leather', ['#5C311A', '#9A5A32']], ['leather', 'Black leather', ['#141414', '#383636']], ['leather', 'Tan leather', ['#8A5A36', '#C99566']],
    ['brushed_metal', 'Steel', ['#8E9399', '#E3E6EA']], ['brushed_metal', 'Gold', ['#9C7A2E', '#F2D489']], ['brushed_metal', 'Rose gold', ['#A5675A', '#F1C3B6']],
    ['glitter', 'Pink glitter', ['#B23A7A', '#FF2D87']], ['glitter', 'Silver glitter', ['#7D8088', '#E6E8EC']], ['glitter', 'Blue glitter', ['#0C4FA8', '#7FB2FF']],
    ['knit', 'Red knit', ['#7A2E3A', '#C9606F']], ['knit', 'Grey knit', ['#5A5D63', '#A6AAB1']],
    ['terrazzo', 'Terrazzo', ['#EDE8E0', '#C94F3D', '#2F5D8A', '#E8B04B']],
    ['camo', 'Forest camo', ['#A39465', '#6B6B3A', '#2E3A23']], ['camo', 'Urban camo', ['#B5B7BA', '#6E7176', '#2E3034']],
    ['concrete', 'Concrete', ['#8A8A86', '#BDBCB7']],
    ['velvet', 'Plum velvet', ['#3D0F2E', '#8A2A5E']], ['velvet', 'Royal velvet', ['#0A1F4A', '#2C5AB8']],
].map(([kind, name, colors]) => ({
    id: `${kind}_${String(name).toLowerCase().replace(/[^a-z0-9]+/g, '_')}`,
    name: name,
    spec: { kind: kind, colors: colors },
}));
//# sourceMappingURL=textureEngine.js.map