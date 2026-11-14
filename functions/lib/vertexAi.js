"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GEMINI_FLASH_MODELS = void 0;
exports.vertexAi = vertexAi;
exports.generateVertexContent = generateVertexContent;
/**
 * Gemini through Vertex AI (or OpenRouter Gemini 2.5 Flash fallback when
 * Vertex AI model endpoints return 404 or are unavailable in the region).
 */
const genai_1 = require("@google/genai");
const LOCATION = process.env.VERTEX_LOCATION || 'us-central1';
exports.GEMINI_FLASH_MODELS = [
    process.env.GEMINI_MODEL || 'gemini-2.5-flash',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
];
let rawClient = null;
let wrappedClient = null;
function getRawVertexClient() {
    rawClient !== null && rawClient !== void 0 ? rawClient : (rawClient = new genai_1.GoogleGenAI({
        vertexai: true,
        project: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
        location: LOCATION,
    }));
    return rawClient;
}
/**
 * Returns a GoogleGenAI client whose `models.generateContent` automatically
 * falls back to OpenRouter (`google/gemini-2.5-flash`) if Vertex AI returns 404
 * or fails.
 */
function vertexAi() {
    if (wrappedClient)
        return wrappedClient;
    const base = getRawVertexClient();
    const modelsProxy = new Proxy(base.models, {
        get(target, prop, receiver) {
            if (prop === 'generateContent') {
                return (params) => generateVertexContent(params);
            }
            const val = Reflect.get(target, prop, receiver);
            return typeof val === 'function' ? val.bind(target) : val;
        },
    });
    wrappedClient = new Proxy(base, {
        get(target, prop, receiver) {
            if (prop === 'models')
                return modelsProxy;
            const val = Reflect.get(target, prop, receiver);
            return typeof val === 'function' ? val.bind(target) : val;
        },
    });
    return wrappedClient;
}
function normalizeJsonSchema(schema) {
    if (!schema || typeof schema !== 'object')
        return schema;
    if (Array.isArray(schema))
        return schema.map(normalizeJsonSchema);
    const out = {};
    for (const [k, v] of Object.entries(schema)) {
        if (k === 'type' && typeof v === 'string') {
            out[k] = v.toLowerCase();
        }
        else if (k === 'properties' && v && typeof v === 'object') {
            const props = {};
            for (const [pk, pv] of Object.entries(v)) {
                props[pk] = normalizeJsonSchema(pv);
            }
            out[k] = props;
        }
        else if (k === 'items') {
            out[k] = normalizeJsonSchema(v);
        }
        else {
            out[k] = v;
        }
    }
    return out;
}
function extractSystemText(sys) {
    if (!sys)
        return '';
    if (typeof sys === 'string')
        return sys.trim();
    if (Array.isArray(sys))
        return sys.map(extractSystemText).filter(Boolean).join('\n');
    if (typeof sys === 'object') {
        if (typeof sys.text === 'string')
            return sys.text.trim();
        if (Array.isArray(sys.parts)) {
            return sys.parts.map((p) => { var _a; return String((_a = p === null || p === void 0 ? void 0 : p.text) !== null && _a !== void 0 ? _a : ''); }).filter(Boolean).join('\n');
        }
    }
    return '';
}
function convertGeminiContentsToOpenAiMessages(contents, systemInstruction) {
    var _a;
    var _b, _c, _d;
    const messages = [];
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
        if (!item)
            continue;
        if (typeof item === 'string') {
            messages.push({ role: 'user', content: item });
            continue;
        }
        if (typeof item === 'object' && !Array.isArray(item.parts) && typeof item.text === 'string') {
            messages.push({ role: 'user', content: item.text });
            continue;
        }
        const rawRole = String((_b = item.role) !== null && _b !== void 0 ? _b : 'user').toLowerCase();
        const role = rawRole === 'model' || rawRole === 'assistant' ? 'assistant' : 'user';
        const parts = Array.isArray(item.parts) ? item.parts : [];
        const functionCalls = parts.filter((p) => p === null || p === void 0 ? void 0 : p.functionCall);
        const functionResponses = parts.filter((p) => p === null || p === void 0 ? void 0 : p.functionResponse);
        if (functionCalls.length > 0) {
            messages.push({
                role: 'assistant',
                content: '',
                tool_calls: functionCalls.map((p, i) => { var _a, _b, _c; return ({
                    id: String((_a = p.functionCall.id) !== null && _a !== void 0 ? _a : `call_${i}_${Date.now()}`),
                    type: 'function',
                    function: {
                        name: String((_b = p.functionCall.name) !== null && _b !== void 0 ? _b : ''),
                        arguments: JSON.stringify((_c = p.functionCall.args) !== null && _c !== void 0 ? _c : {}),
                    },
                }); }),
            });
            continue;
        }
        if (functionResponses.length > 0) {
            for (const p of functionResponses) {
                const fr = p.functionResponse;
                messages.push({
                    role: 'user',
                    content: `Tool "${fr.name}" output:\n${JSON.stringify((_c = fr.response) !== null && _c !== void 0 ? _c : {})}`,
                });
            }
            continue;
        }
        const contentParts = [];
        for (const part of parts) {
            if (typeof (part === null || part === void 0 ? void 0 : part.text) === 'string' && part.text.length > 0) {
                contentParts.push({ type: 'text', text: part.text });
            }
            else if ((_a = part === null || part === void 0 ? void 0 : part.inlineData) === null || _a === void 0 ? void 0 : _a.data) {
                const mime = String((_d = part.inlineData.mimeType) !== null && _d !== void 0 ? _d : 'image/jpeg').toLowerCase();
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
                }
                else {
                    contentParts.push({
                        type: 'image_url',
                        image_url: { url: `data:${mime};base64,${b64}` },
                    });
                }
            }
        }
        if (contentParts.length === 1 && contentParts[0].type === 'text') {
            messages.push({ role, content: contentParts[0].text });
        }
        else if (contentParts.length > 0) {
            messages.push({ role, content: contentParts });
        }
    }
    return messages;
}
function convertGeminiToolsToOpenAi(tools) {
    var _a, _b;
    if (!Array.isArray(tools) || tools.length === 0)
        return undefined;
    const out = [];
    for (const group of tools) {
        const decls = group === null || group === void 0 ? void 0 : group.functionDeclarations;
        if (!Array.isArray(decls))
            continue;
        for (const d of decls) {
            if (!(d === null || d === void 0 ? void 0 : d.name))
                continue;
            out.push({
                type: 'function',
                function: {
                    name: String(d.name),
                    description: String((_a = d.description) !== null && _a !== void 0 ? _a : ''),
                    parameters: normalizeJsonSchema((_b = d.parameters) !== null && _b !== void 0 ? _b : { type: 'object', properties: {} }),
                },
            });
        }
    }
    return out.length > 0 ? out : undefined;
}
async function generateViaOpenRouter(params, orKey) {
    var _a, _b;
    var _c, _d;
    const cfg = ((_c = params.config) !== null && _c !== void 0 ? _c : {});
    const messages = convertGeminiContentsToOpenAiMessages(params.contents, cfg.systemInstruction);
    const openAiTools = convertGeminiToolsToOpenAi(cfg.tools);
    const body = {
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
    const data = (await resp.json());
    const msg = (_d = (_b = (_a = data === null || data === void 0 ? void 0 : data.choices) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.message) !== null && _d !== void 0 ? _d : {};
    const text = typeof msg.content === 'string' ? msg.content : '';
    const rawToolCalls = Array.isArray(msg.tool_calls) ? msg.tool_calls : [];
    const functionCalls = rawToolCalls
        .map((tc) => {
        var _a, _b;
        const fn = tc === null || tc === void 0 ? void 0 : tc.function;
        if (!(fn === null || fn === void 0 ? void 0 : fn.name))
            return null;
        let parsedArgs = {};
        try {
            parsedArgs = typeof fn.arguments === 'string' ? JSON.parse(fn.arguments || '{}') : ((_a = fn.arguments) !== null && _a !== void 0 ? _a : {});
        }
        catch (_c) {
            parsedArgs = {};
        }
        return {
            id: String((_b = tc.id) !== null && _b !== void 0 ? _b : `call_${Date.now()}`),
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
                        ...functionCalls.map((fc) => ({ functionCall: fc })),
                    ],
                },
            },
        ],
    };
}
/**
 * Calls OpenRouter (`google/gemini-2.5-flash`) when `OPENROUTER_API_KEY` is
 * present (or falls back to it whenever Vertex AI returns 404/unavailable).
 */
async function generateVertexContent(params) {
    var _a, _b;
    var _c, _d;
    const orKey = ((_c = process.env.OPENROUTER_API_KEY) !== null && _c !== void 0 ? _c : '').trim();
    if (orKey) {
        try {
            return await generateViaOpenRouter(params, orKey);
        }
        catch (orErr) {
            console.warn('[vertexAi] OpenRouter primary attempt notice, trying Vertex:', orErr);
        }
    }
    const ai = getRawVertexClient();
    const candidates = params.model
        ? Array.from(new Set([params.model, ...exports.GEMINI_FLASH_MODELS]))
        : Array.from(new Set(exports.GEMINI_FLASH_MODELS));
    let lastErr;
    for (const model of candidates) {
        try {
            return await ai.models.generateContent(Object.assign(Object.assign({}, params), { model }));
        }
        catch (err) {
            lastErr = err;
            const jsonStr = (() => {
                try {
                    return JSON.stringify(err);
                }
                catch (_a) {
                    return '';
                }
            })();
            const msg = `${(_d = err === null || err === void 0 ? void 0 : err.message) !== null && _d !== void 0 ? _d : ''} ${jsonStr}`.toLowerCase();
            const isNotFound = (err === null || err === void 0 ? void 0 : err.status) === 404 ||
                (err === null || err === void 0 ? void 0 : err.code) === 404 ||
                (err === null || err === void 0 ? void 0 : err.status) === 'NOT_FOUND' ||
                ((_a = err === null || err === void 0 ? void 0 : err.error) === null || _a === void 0 ? void 0 : _a.code) === 404 ||
                ((_b = err === null || err === void 0 ? void 0 : err.error) === null || _b === void 0 ? void 0 : _b.status) === 'NOT_FOUND' ||
                msg.includes('404') ||
                msg.includes('not_found') ||
                msg.includes('not found') ||
                msg.includes('no longer available') ||
                msg.includes('does not have access');
            if (!isNotFound)
                break;
        }
    }
    throw lastErr;
}
//# sourceMappingURL=vertexAi.js.map