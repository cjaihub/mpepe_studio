"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.mapsGateway = void 0;
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const optionalSecrets_1 = require("./optionalSecrets");
const db = () => (0, firestore_1.getFirestore)();
function cacheKey(prefix, payload) {
    const hash = crypto
        .createHash('sha256')
        .update(JSON.stringify(payload))
        .digest('hex')
        .slice(0, 32);
    return `${prefix}_${hash}`;
}
/** Decodes an encoded Google Maps polyline string into [{lat, lng}, ...]. */
function decodePolyline(encoded) {
    const points = [];
    let index = 0;
    const len = encoded.length;
    let lat = 0;
    let lng = 0;
    while (index < len) {
        let b;
        let shift = 0;
        let result = 0;
        do {
            b = encoded.charCodeAt(index++) - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20 && index <= len);
        const dlat = result & 1 ? ~(result >> 1) : result >> 1;
        lat += dlat;
        shift = 0;
        result = 0;
        do {
            b = encoded.charCodeAt(index++) - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20 && index <= len);
        const dlng = result & 1 ? ~(result >> 1) : result >> 1;
        lng += dlng;
        points.push({ lat: lat / 1e5, lng: lng / 1e5 });
    }
    return points;
}
function stripHtml(html) {
    return html
        .replace(/<[^>]*>/g, ' ')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&')
        .replace(/\s+/g, ' ')
        .trim();
}
exports.mapsGateway = (0, https_1.onCall)({
    region: 'us-central1',
    memory: '256MiB',
    timeoutSeconds: 25,
    secrets: ['GOOGLE_MAPS_SERVER_KEY'],
}, async (request) => {
    var _a, _b, _c, _d, _e, _f, _g;
    const data = (request.data || {});
    const action = String(data.action || '').trim();
    const apiKey = await (0, optionalSecrets_1.optionalSecret)('GOOGLE_MAPS_SERVER_KEY');
    if (!apiKey) {
        throw new https_1.HttpsError('failed-precondition', 'GOOGLE_MAPS_SERVER_KEY is not configured.');
    }
    // 1. Place Text Search (Places API New)
    if (action === 'search') {
        const query = String(data.query || '').trim();
        if (!query)
            return { places: [] };
        const lat = typeof data.lat === 'number' ? data.lat : null;
        const lng = typeof data.lng === 'number' ? data.lng : null;
        const limit = Math.min(Math.max(Number(data.limit || 6), 1), 15);
        const body = {
            textQuery: query,
            maxResultCount: limit,
        };
        if (lat !== null && lng !== null) {
            body.locationBias = {
                circle: {
                    center: { latitude: lat, longitude: lng },
                    radius: 25000.0,
                },
            };
        }
        const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': apiKey,
                'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.regularOpeningHours.openNow',
            },
            body: JSON.stringify(body),
        });
        if (!res.ok) {
            throw new https_1.HttpsError('internal', `Places search failed (${res.status})`);
        }
        const json = (await res.json());
        const places = (json.places || []).map((p) => {
            const loc = (p.location || {});
            const disp = (p.displayName || {});
            const hours = (p.regularOpeningHours || {});
            return {
                name: disp.text || 'Place',
                lat: Number(loc.latitude || 0),
                lng: Number(loc.longitude || 0),
                category: typeof p.primaryType === 'string' ? p.primaryType : null,
                address: typeof p.formattedAddress === 'string' ? p.formattedAddress : null,
                openNow: typeof hours.openNow === 'boolean' ? hours.openNow : null,
            };
        });
        return { places };
    }
    // 2. Nearby Places Search (Places API New)
    if (action === 'nearby') {
        const lat = Number(data.lat);
        const lng = Number(data.lng);
        const what = String(data.what || 'restaurant').trim();
        const radiusM = Math.min(Math.max(Number(data.radiusM || 1500), 200), 15000);
        const limit = Math.min(Math.max(Number(data.limit || 8), 1), 15);
        const body = {
            textQuery: what || 'places',
            maxResultCount: limit,
            locationBias: {
                circle: {
                    center: { latitude: lat, longitude: lng },
                    radius: radiusM,
                },
            },
        };
        const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': apiKey,
                'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.regularOpeningHours.openNow',
            },
            body: JSON.stringify(body),
        });
        if (!res.ok) {
            throw new https_1.HttpsError('internal', `Nearby search failed (${res.status})`);
        }
        const json = (await res.json());
        const places = (json.places || []).map((p) => {
            const loc = (p.location || {});
            const disp = (p.displayName || {});
            const hours = (p.regularOpeningHours || {});
            return {
                name: disp.text || 'Place',
                lat: Number(loc.latitude || 0),
                lng: Number(loc.longitude || 0),
                category: typeof p.primaryType === 'string' ? p.primaryType : null,
                address: typeof p.formattedAddress === 'string' ? p.formattedAddress : null,
                openNow: typeof hours.openNow === 'boolean' ? hours.openNow : null,
            };
        });
        return { places };
    }
    // 3. Reverse Geocode (Google Geocoding API with cache)
    if (action === 'reverse') {
        const lat = Number(data.lat);
        const lng = Number(data.lng);
        const roundedKey = cacheKey('rev', {
            lat: Number(lat.toFixed(4)),
            lng: Number(lng.toFixed(4)),
        });
        try {
            const cached = await db().collection('geo_cache').doc(roundedKey).get();
            if (cached.exists) {
                const d = cached.data();
                if (d === null || d === void 0 ? void 0 : d.address)
                    return { address: String(d.address) };
            }
        }
        catch (_) { }
        const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
        url.searchParams.set('latlng', `${lat},${lng}`);
        url.searchParams.set('key', apiKey);
        const res = await fetch(url.toString());
        if (!res.ok)
            return { address: null };
        const json = (await res.json());
        const address = ((_b = (_a = json.results) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.formatted_address) || null;
        if (address) {
            db()
                .collection('geo_cache')
                .doc(roundedKey)
                .set({ address, updatedAt: firestore_1.FieldValue.serverTimestamp() })
                .catch(() => { });
        }
        return { address };
    }
    // 4. Route & Turn-by-Turn Directions (Google Directions API)
    if (action === 'route') {
        const fromLat = Number(data.fromLat);
        const fromLng = Number(data.fromLng);
        const toLat = Number(data.toLat);
        const toLng = Number(data.toLng);
        const mode = String(data.mode || 'driving');
        const travelMode = mode === 'walking' ? 'walking' : mode === 'cycling' ? 'bicycling' : 'driving';
        const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
        url.searchParams.set('origin', `${fromLat},${fromLng}`);
        url.searchParams.set('destination', `${toLat},${toLng}`);
        url.searchParams.set('mode', travelMode);
        url.searchParams.set('key', apiKey);
        const res = await fetch(url.toString());
        if (!res.ok) {
            throw new https_1.HttpsError('internal', `Directions failed (${res.status})`);
        }
        const json = (await res.json());
        const route = (_c = json.routes) === null || _c === void 0 ? void 0 : _c[0];
        if (!route)
            return { route: null };
        const leg = (_d = route.legs) === null || _d === void 0 ? void 0 : _d[0];
        const poly = ((_e = route.overview_polyline) === null || _e === void 0 ? void 0 : _e.points) || '';
        const points = poly ? decodePolyline(poly) : [];
        const steps = ((leg === null || leg === void 0 ? void 0 : leg.steps) || []).map((st) => {
            var _a, _b, _c, _d;
            const man = String(st.maneuver || 'continue');
            return {
                instruction: stripHtml(st.html_instructions || 'Continue'),
                maneuverType: man.includes('left') || man.includes('right') ? 'turn' : man,
                modifier: man.includes('left')
                    ? 'left'
                    : man.includes('right')
                        ? 'right'
                        : 'straight',
                distanceM: Number(((_a = st.distance) === null || _a === void 0 ? void 0 : _a.value) || 0),
                durationS: Number(((_b = st.duration) === null || _b === void 0 ? void 0 : _b.value) || 0),
                lat: Number(((_c = st.end_location) === null || _c === void 0 ? void 0 : _c.lat) || toLat),
                lng: Number(((_d = st.end_location) === null || _d === void 0 ? void 0 : _d.lng) || toLng),
            };
        });
        return {
            route: {
                points,
                distanceM: Number(((_f = leg === null || leg === void 0 ? void 0 : leg.distance) === null || _f === void 0 ? void 0 : _f.value) || 0),
                durationS: Number(((_g = leg === null || leg === void 0 ? void 0 : leg.duration) === null || _g === void 0 ? void 0 : _g.value) || 0),
                mode,
                steps,
            },
        };
    }
    throw new https_1.HttpsError('invalid-argument', `Unknown mapsGateway action: ${action}`);
});
//# sourceMappingURL=mapsGateway.js.map