/**
 * Gemini through Vertex AI (or OpenRouter Gemini 2.5 Flash fallback when
 * Vertex AI model endpoints return 404 or are unavailable in the region).
 */
import { GoogleGenAI, GenerateContentParameters, GenerateContentResponse } from '@google/genai';

const LOCATION = process.env.VERTEX_LOCATION || 'us-central1';

export const GEMINI_FLASH_MODELS: readonly string[] = [
  process.env.GEMINI_MODEL || 'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-1.5-flash',
];

let rawClient: GoogleGenAI | null = null;
let wrappedClient: GoogleGenAI | null = null;

function getRawVertexClient(): GoogleGenAI {
  rawClient ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
    location: LOCATION,
  });
  return rawClient;
}

/**
 * Returns a GoogleGenAI client whose `models.generateContent` automatically
 * falls back to OpenRouter (`google/gemini-2.5-flash`) if Vertex AI returns 404
 * or fails.
 */
export function vertexAi(): GoogleGenAI {
  if (wrappedClient) return wrappedClient;
  const base = getRawVertexClient();
  const modelsProxy = new Proxy(base.models, {
    get(target, prop, receiver) {
      if (prop === 'generateContent') {
        return (params: GenerateContentParameters) => generateVertexContent(params);
      }
      const val = Reflect.get(target, prop, receiver);
      return typeof val === 'function' ? val.bind(target) : val;
    },
  });
  wrappedClient = new Proxy(base, {
    get(target, prop, receiver) {
      if (prop === 'models') return modelsProxy;
      const val = Reflect.get(target, prop, receiver);
      return typeof val === 'function' ? val.bind(target) : val;
    },
  });
  return wrappedClient;
}

function normalizeJsonSchema(schema: any): any {
  if (!schema || typeof schema !== 'object') return schema;
  if (Array.isArray(schema)) return schema.map(normalizeJsonSchema);
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(schema)) {
    if (k === 'type' && typeof v === 'string') {
      out[k] = v.toLowerCase();
    } else if (k === 'properties' && v && typeof v === 'object') {
      const props: Record<string, any> = {};
      for (const [pk, pv] of Object.entries(v as Record<string, any>)) {
        props[pk] = normalizeJsonSchema(pv);
      }
      out[k] = props;
    } else if (k === 'items') {
      out[k] = normalizeJsonSchema(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

function extractSystemText(sys: any): string {
  if (!sys) return '';
  if (typeof sys === 'string') return sys.trim();
  if (Array.isArray(sys)) return sys.map(extractSystemText).filter(Boolean).join('\n');
  if (typeof sys === 'object') {
    if (typeof sys.text === 'string') return sys.text.trim();
    if (Array.isArray(sys.parts)) {
      return sys.parts.map((p: any) => String(p?.text ?? '')).filter(Boolean).join('\n');
    }
  }
  return '';
}

function convertGeminiContentsToOpenAiMessages(
  contents: any,
  systemInstruction?: any,
): Array<Record<string, any>> {
  const messages: Array<Record<string, any>> = [];
  const sysText = extractSystemText(systemInstruction);
  if (sysText) {
    messages.push({ role: 'system', content: sysText });
  }

  if (typeof contents === 'string') {
    messages.push({ role: 'user', content: contents });
    return messages;
  }

  const items = Array.isArray(contents) ? contents : [contents];
  for (const item of items) {
    if (!item) continue;
    if (typeof item === 'string') {
      messages.push({ role: 'user', content: item });
      continue;
    }
    if (typeof item === 'object' && !Array.isArray(item.parts) && typeof item.text === 'string') {
      messages.push({ role: 'user', content: item.text });
      continue;
    }

    const rawRole = String(item.role ?? 'user').toLowerCase();
    const role = rawRole === 'model' || rawRole === 'assistant' ? 'assistant' : 'user';
    const parts = Array.isArray(item.parts) ? item.parts : [];

    const functionCalls = parts.filter((p: any) => p?.functionCall);
    const functionResponses = parts.filter((p: any) => p?.functionResponse);

    if (functionCalls.length > 0) {
      messages.push({
        role: 'assistant',
        content: '',
        tool_calls: functionCalls.map((p: any, i: number) => ({
          id: String(p.functionCall.id ?? `call_${i}_${Date.now()}`),
          type: 'function',
          function: {
            name: String(p.functionCall.name ?? ''),
            arguments: JSON.stringify(p.functionCall.args ?? {}),
          },
        })),
      });
      continue;
    }

    if (functionResponses.length > 0) {
      for (const p of functionResponses) {
        const fr = p.functionResponse;
        messages.push({
          role: 'user',
          content: `Tool "${fr.name}" output:\n${JSON.stringify(fr.response ?? {})}`,
        });
      }
      continue;
    }

    const contentParts: Array<Record<string, any>> = [];
    for (const part of parts) {
      if (typeof part?.text === 'string' && part.text.length > 0) {
        contentParts.push({ type: 'text', text: part.text });
      } else if (part?.inlineData?.data) {
        const mime = String(part.inlineData.mimeType ?? 'image/jpeg').toLowerCase();
        const b64 = String(part.inlineData.data);
        if (mime.startsWith('audio/')) {
          const fmt = mime.includes('wav')
            ? 'wav'
            : mime.includes('mp3') || mime.includes('mpeg')
              ? 'mp3'
              : 'mp4';
          contentParts.push({
            type: 'input_audio',
            input_audio: { data: b64, format: fmt },
          });
        } else {
          contentParts.push({
            type: 'image_url',
            image_url: { url: `data:${mime};base64,${b64}` },
          });
        }
      }
    }

    if (contentParts.length === 1 && contentParts[0].type === 'text') {
      messages.push({ role, content: contentParts[0].text });
    } else if (contentParts.length > 0) {
      messages.push({ role, content: contentParts });
    }
  }

  return messages;
}

function convertGeminiToolsToOpenAi(tools: any): Array<Record<string, any>> | undefined {
  if (!Array.isArray(tools) || tools.length === 0) return undefined;
  const out: Array<Record<string, any>> = [];
  for (const group of tools) {
    const decls = group?.functionDeclarations;
    if (!Array.isArray(decls)) continue;
    for (const d of decls) {
      if (!d?.name) continue;
      out.push({
        type: 'function',
        function: {
          name: String(d.name),
          description: String(d.description ?? ''),
          parameters: normalizeJsonSchema(d.parameters ?? { type: 'object', properties: {} }),
        },
      });
    }
  }
  return out.length > 0 ? out : undefined;
}

async function generateViaOpenRouter(
  params: Omit<GenerateContentParameters, 'model'> & { model?: string },
  orKey: string,
): Promise<GenerateContentResponse> {
  const cfg = (params.config ?? {}) as Record<string, any>;
  const messages = convertGeminiContentsToOpenAiMessages(
    params.contents,
    cfg.systemInstruction,
  );
  const openAiTools = convertGeminiToolsToOpenAi(cfg.tools);

  const body: Record<string, any> = {
    model: 'google/gemini-2.5-flash',
    messages,
  };
  if (typeof cfg.temperature === 'number') {
    body.temperature = cfg.temperature;
  }
  if (typeof cfg.maxOutputTokens === 'number') {
    body.max_tokens = cfg.maxOutputTokens;
  }
  if (cfg.responseMimeType === 'application/json') {
    body.response_format = { type: 'json_object' };
  }
  if (openAiTools) {
    body.tools = openAiTools;
  }

  const resp = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${orKey.trim()}`,
      'HTTP-Referer': 'https://mpepe-2b4bd.web.app',
      'X-Title': 'Oneova',
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    const errBody = await resp.text().catch(() => '');
    throw new Error(`OpenRouter HTTP ${resp.status}: ${errBody.slice(0, 240)}`);
  }

  const data = (await resp.json()) as Record<string, any>;
  const msg = data?.choices?.[0]?.message ?? {};
  const text = typeof msg.content === 'string' ? msg.content : '';
  const rawToolCalls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];

  const functionCalls = rawToolCalls
    .map((tc: any) => {
      const fn = tc?.function;
      if (!fn?.name) return null;
      let parsedArgs: Record<string, any> = {};
      try {
        parsedArgs = typeof fn.arguments === 'string' ? JSON.parse(fn.arguments || '{}') : (fn.arguments ?? {});
      } catch {
        parsedArgs = {};
      }
      return {
        id: String(tc.id ?? `call_${Date.now()}`),
        name: String(fn.name),
        args: parsedArgs,
      };
    })
    .filter(Boolean);

  return {
    text,
    functionCalls: functionCalls.length > 0 ? functionCalls : undefined,
    candidates: [
      {
        content: {
          role: 'model',
          parts: [
            ...(text ? [{ text }] : []),
            ...functionCalls.map((fc: any) => ({ functionCall: fc })),
          ],
        },
      },
    ],
  } as unknown as GenerateContentResponse;
}

/**
 * Calls OpenRouter (`google/gemini-2.5-flash`) when `OPENROUTER_API_KEY` is
 * present (or falls back to it whenever Vertex AI returns 404/unavailable).
 */
export async function generateVertexContent(
  params: Omit<GenerateContentParameters, 'model'> & { model?: string },
): Promise<GenerateContentResponse> {
  const orKey = (process.env.OPENROUTER_API_KEY ?? '').trim();
  if (orKey) {
    try {
      return await generateViaOpenRouter(params, orKey);
    } catch (orErr) {
      console.warn('[vertexAi] OpenRouter primary attempt notice, trying Vertex:', orErr);
    }
  }

  const ai = getRawVertexClient();
  const candidates = params.model
    ? Array.from(new Set([params.model, ...GEMINI_FLASH_MODELS]))
    : Array.from(new Set(GEMINI_FLASH_MODELS));

  let lastErr: unknown;
  for (const model of candidates) {
    try {
      return await ai.models.generateContent({ ...params, model });
    } catch (err: any) {
      lastErr = err;
      const jsonStr = (() => {
        try {
          return JSON.stringify(err);
        } catch {
          return '';
        }
      })();
      const msg = `${err?.message ?? ''} ${jsonStr}`.toLowerCase();
      const isNotFound =
        err?.status === 404 ||
        err?.code === 404 ||
        err?.status === 'NOT_FOUND' ||
        err?.error?.code === 404 ||
        err?.error?.status === 'NOT_FOUND' ||
        msg.includes('404') ||
        msg.includes('not_found') ||
        msg.includes('not found') ||
        msg.includes('no longer available') ||
        msg.includes('does not have access');
      if (!isNotFound) break;
    }
  }
  throw lastErr;
}
