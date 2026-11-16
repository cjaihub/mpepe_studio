import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { optionalSecret } from './optionalSecrets';

const db = () => getFirestore();

function cacheKey(prefix: string, payload: unknown): string {
  const hash = crypto
    .createHash('sha256')
    .update(JSON.stringify(payload))
    .digest('hex')
    .slice(0, 32);
  return `${prefix}_${hash}`;
}

/** Decodes an encoded Google Maps polyline string into [{lat, lng}, ...]. */
function decodePolyline(encoded: string): Array<{ lat: number; lng: number }> {
  const points: Array<{ lat: number; lng: number }> = [];
  let index = 0;
  const len = encoded.length;
  let lat = 0;
  let lng = 0;

  while (index < len) {
    let b: number;
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

function stripHtml(html: string): string {
  return html
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim();
}

export const mapsGateway = onCall(
  {
    region: 'us-central1',
    memory: '256MiB',
    timeoutSeconds: 25,
    secrets: ['GOOGLE_MAPS_SERVER_KEY'],
  },
  async (request) => {
    const data = (request.data || {}) as Record<string, unknown>;
    const action = String(data.action || '').trim();
    const apiKey = await optionalSecret('GOOGLE_MAPS_SERVER_KEY');
    if (!apiKey) {
      throw new HttpsError(
        'failed-precondition',
        'GOOGLE_MAPS_SERVER_KEY is not configured.'
      );
    }

    // 1. Place Text Search (Places API New)
    if (action === 'search') {
      const query = String(data.query || '').trim();
      if (!query) return { places: [] };
      const lat = typeof data.lat === 'number' ? data.lat : null;
      const lng = typeof data.lng === 'number' ? data.lng : null;
      const limit = Math.min(Math.max(Number(data.limit || 6), 1), 15);

      const body: Record<string, unknown> = {
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
          'X-Goog-FieldMask':
            'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.regularOpeningHours.openNow',
        },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        throw new HttpsError('internal', `Places search failed (${res.status})`);
      }
      const json = (await res.json()) as { places?: Array<Record<string, unknown>> };
      const places = (json.places || []).map((p) => {
        const loc = (p.location || {}) as { latitude?: number; longitude?: number };
        const disp = (p.displayName || {}) as { text?: string };
        const hours = (p.regularOpeningHours || {}) as { openNow?: boolean };
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

      const body: Record<string, unknown> = {
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
          'X-Goog-FieldMask':
            'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.regularOpeningHours.openNow',
        },
        body: JSON.stringify(body),
      });

      if (!res.ok) {
        throw new HttpsError('internal', `Nearby search failed (${res.status})`);
      }
      const json = (await res.json()) as { places?: Array<Record<string, unknown>> };
      const places = (json.places || []).map((p) => {
        const loc = (p.location || {}) as { latitude?: number; longitude?: number };
        const disp = (p.displayName || {}) as { text?: string };
        const hours = (p.regularOpeningHours || {}) as { openNow?: boolean };
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
          if (d?.address) return { address: String(d.address) };
        }
      } catch (_) {}

      const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
      url.searchParams.set('latlng', `${lat},${lng}`);
      url.searchParams.set('key', apiKey);
      const res = await fetch(url.toString());
      if (!res.ok) return { address: null };
      const json = (await res.json()) as {
        results?: Array<{ formatted_address?: string }>;
      };
      const address = json.results?.[0]?.formatted_address || null;
      if (address) {
        db()
          .collection('geo_cache')
          .doc(roundedKey)
          .set({ address, updatedAt: FieldValue.serverTimestamp() })
          .catch(() => {});
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
      const travelMode =
        mode === 'walking' ? 'walking' : mode === 'cycling' ? 'bicycling' : 'driving';

      const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
      url.searchParams.set('origin', `${fromLat},${fromLng}`);
      url.searchParams.set('destination', `${toLat},${toLng}`);
      url.searchParams.set('mode', travelMode);
      url.searchParams.set('key', apiKey);

      const res = await fetch(url.toString());
      if (!res.ok) {
        throw new HttpsError('internal', `Directions failed (${res.status})`);
      }
      const json = (await res.json()) as {
        routes?: Array<{
          overview_polyline?: { points?: string };
          legs?: Array<{
            distance?: { value?: number };
            duration?: { value?: number };
            steps?: Array<{
              html_instructions?: string;
              maneuver?: string;
              distance?: { value?: number };
              duration?: { value?: number };
              end_location?: { lat?: number; lng?: number };
            }>;
          }>;
        }>;
      };
      const route = json.routes?.[0];
      if (!route) return { route: null };
      const leg = route.legs?.[0];
      const poly = route.overview_polyline?.points || '';
      const points = poly ? decodePolyline(poly) : [];
      const steps = (leg?.steps || []).map((st) => {
        const man = String(st.maneuver || 'continue');
        return {
          instruction: stripHtml(st.html_instructions || 'Continue'),
          maneuverType: man.includes('left') || man.includes('right') ? 'turn' : man,
          modifier: man.includes('left')
              ? 'left'
              : man.includes('right')
              ? 'right'
              : 'straight',
          distanceM: Number(st.distance?.value || 0),
          durationS: Number(st.duration?.value || 0),
          lat: Number(st.end_location?.lat || toLat),
          lng: Number(st.end_location?.lng || toLng),
        };
      });

      return {
        route: {
          points,
          distanceM: Number(leg?.distance?.value || 0),
          durationS: Number(leg?.duration?.value || 0),
          mode,
          steps,
        },
      };
    }

    throw new HttpsError('invalid-argument', `Unknown mapsGateway action: ${action}`);
  }
);
