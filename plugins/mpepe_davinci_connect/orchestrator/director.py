import logging
import json
import re
from .provider_abstraction import GeminiProvider

logger = logging.getLogger("cj_grader.director")

_SYSTEM_PROMPT = """You are the Director Agent for CJ Grader, an expert Senior Colorist and DIT for DaVinci Resolve.

Your job is to translate the user's natural-language grading request into a precise, executable step-by-step plan.
If guided_mode is enabled:
- Use plain English for task descriptions (e.g., "Warm up the shadows", not "Increase offset_r").
- Set "requires_confirmation" to true for EVERY step.
- If a required feature is marked as "guided", create a step explaining what the user should click manually.

Available agents (use these exact names):
- Color Scientist: CDL grade (params slope_r/g/b, offset_r/g/b, power_r/g/b, saturation, append_new_node) or a LUT (params lut_path or lut keyword).
- Skin: isolate faces with Magic Mask, optional subtle skin CDL params. Task mentions "refine" for Face Refinement.
- Tracking: tasks "Magic Mask", "Stabilize", "Smart Reframe".
- Quality: tasks "Noise reduction" (params strength) or "Sharpen" (params amount). These become guided steps.
- HDR: task "Analyze Dolby Vision".
- Match: task "Copy grade" / "Match shots" (params target_clips: [clip indices], omit for all clips) or "Color group" (params group_name).
- Enhance: tasks "Speed" (params speed), "Dynamic zoom", "Crop" (left/right/top/bottom), "Transform" (pan, tilt, zoom, rotation).
- Audio: tasks "Voice isolation", "Transcribe", "Classify audio".
- Film: film print emulation (params look: kodak_2383, kodak_2393, fuji_3513, or any LUT keyword).
- LUT: find LUTs (params keyword, apply: true to apply the best match).
- Skill: apply a saved skill (params skill_name) or learn one from the current grade (params skill_name, action: "learn").
- Reference: match a reference image (params image_path).
- LookProfile: build a reusable look from text (params description) or an image (params image_path).
- Auditor: scan every clip for exposure and white balance problems.
- Memory: "Save grade version" (params version_name), "Load version", "List versions", "Grade history", "Remember preference" (key, value).
- Render: "Render timeline" (params target_dir, custom_name, start), "Render status".
- Cloud: "Backup" local memory, or "Sync" (requires params consent: true and user_id).
- User: a manual step the user performs (always requires_confirmation).
- OS: "Launch DaVinci" / "Close DaVinci".

ALWAYS respond with ONLY a JSON object matching this schema (no prose, no markdown fences):
{
  "status": "success",
  "plan": [
    {
      "agent": "<AgentName>",
      "task": "<short description>",
      "scope": "<'clip' or 'timeline'>",
      "requires_confirmation": <bool>,
      "params": { <key-value pairs relevant to the agent> }
    }
  ]
}

Rules:
- Scope: Set "scope" to "timeline" if the user wants to apply the look to the whole timeline, or "clip" for the selected clip.
- Confirmation: Set "requires_confirmation" to true for destructive actions or multi-clip scopes.
- For grading requests, start with a "Color Scientist" step for basic CDL grading (Slope, Offset, Power, Saturation). Non-grading requests (render, audit, audio, versions, launching Resolve) need no Color Scientist step.
- Understand colorist terms:
  - "Gold skintone": Use Skin agent with a hue shift to orange/yellow + saturation lift in skin qualifier.
  - "Milky shadows": Lifted blacks (offset > 0.02) and reduced contrast.
  - "Bleach bypass": Desaturate (saturation ~0.6) + increase contrast + slight green/cyan offset.
  - "Match BTS feel": If referencing an image, use the Reference agent; if referencing a saved look, use the Skill agent.
- Region Masks: If a region_mask is provided in the context, you MUST specify the operation should be restricted to that region using a Power Window or qualifier. Add "region" to params.
- If the user asks to "apply the [Name] skill" or "use [Name]", use the "Skill" agent with params: {"skill_name": "[Name]"}.
- You can specify "append_new_node": true in the Color Scientist params to create a new serial node before applying the CDL, which is great for preserving the existing grade.
- If the user asks to open or close DaVinci Resolve, use the "OS" agent with task "Launch DaVinci" or "Close DaVinci".
- Keep plans to 3-5 steps maximum.
"""

_NEUTRAL = {"slope_r": 1.0, "slope_g": 1.0, "slope_b": 1.0, "offset_r": 0.0, "offset_g": 0.0,
            "offset_b": 0.0, "power_r": 1.0, "power_g": 1.0, "power_b": 1.0, "saturation": 1.0}

# Grading vocabulary -> CDL nudges (added to neutral). Order matters only for readability.
_GRADE_TERMS = {
    ("warm",): {"slope_r": 0.06, "slope_b": -0.05, "offset_r": 0.01, "offset_b": -0.01},
    ("cool", "cold", "blue"): {"slope_r": -0.05, "slope_b": 0.06, "offset_b": 0.01},
    ("contrast", "punch", "pop"): {"power_r": 0.08, "power_g": 0.08, "power_b": 0.08,
                                   "slope_r": 0.05, "slope_g": 0.05, "slope_b": 0.05},
    ("flat", "soft", "less contrast"): {"power_r": -0.06, "power_g": -0.06, "power_b": -0.06},
    ("bright", "lift exposure", "brighter", "exposure up"): {"offset_r": 0.03, "offset_g": 0.03, "offset_b": 0.03},
    ("dark", "darker", "moody", "exposure down"): {"offset_r": -0.03, "offset_g": -0.03, "offset_b": -0.03},
    ("milky",): {"offset_r": 0.03, "offset_g": 0.03, "offset_b": 0.03, "power_r": -0.05, "power_g": -0.05, "power_b": -0.05},
    ("bleach bypass",): {"saturation": -0.4, "power_r": 0.1, "power_g": 0.1, "power_b": 0.1, "offset_g": 0.005, "offset_b": 0.005},
    ("saturat", "vibrant", "colorful"): {"saturation": 0.15},
    ("desaturat", "muted", "washed"): {"saturation": -0.25},
    ("cinematic", "teal and orange", "teal & orange"): {"slope_r": 0.04, "offset_b": 0.015, "offset_r": -0.005, "saturation": 0.05},
    ("black and white", "black & white", "monochrome", "b&w"): {"saturation": -1.0},
}

# (keywords, step) for non-grading agents; first match wins per agent.
_ROUTES = [
    (("audit", "check exposure", "check white balance", "scan"), {"agent": "Auditor", "task": "Audit timeline exposure and white balance"}),
    (("render status", "render progress"), {"agent": "Render", "task": "Render status"}),
    (("render", "export", "deliver"), {"agent": "Render", "task": "Render timeline", "requires_confirmation": True}),
    (("stabiliz", "stabilis", "shaky"), {"agent": "Tracking", "task": "Stabilize clip"}),
    (("reframe", "vertical", "9:16"), {"agent": "Tracking", "task": "Smart Reframe"}),
    (("magic mask", "track the"), {"agent": "Tracking", "task": "Magic Mask"}),
    (("skin", "face"), {"agent": "Skin", "task": "Isolate skin with Magic Mask"}),
    (("noise", "grain", "denoise"), {"agent": "Quality", "task": "Noise reduction", "params": {"strength": 5.0}}),
    (("sharpen", "crisp"), {"agent": "Quality", "task": "Sharpen", "params": {"amount": 0.5}}),
    (("dolby", "hdr"), {"agent": "HDR", "task": "Analyze Dolby Vision"}),
    (("color group", "colour group"), {"agent": "Match", "task": "Color group"}),
    (("match", "copy grade", "all clips"), {"agent": "Match", "task": "Copy grade to other clips", "requires_confirmation": True}),
    (("voice", "dialog", "dialogue"), {"agent": "Audio", "task": "Voice isolation"}),
    (("transcri", "caption", "subtitle"), {"agent": "Audio", "task": "Transcribe"}),
    (("slow motion", "slow-mo", "speed"), {"agent": "Enhance", "task": "Speed", "params": {"speed": 0.5}}),
    (("crop",), {"agent": "Enhance", "task": "Crop"}),
    (("2383", "2393", "3513", "film look", "film print", "film emulation"), {"agent": "Film", "task": "Film print emulation"}),
    (("lut",), {"agent": "LUT", "task": "Find LUT"}),
    (("list versions",), {"agent": "Memory", "task": "List versions"}),
    (("load version",), {"agent": "Memory", "task": "Load version"}),
    (("save version", "snapshot", "save grade"), {"agent": "Memory", "task": "Save grade version"}),
    (("history", "what did you do"), {"agent": "Memory", "task": "Grade history"}),
    (("backup", "back up"), {"agent": "Cloud", "task": "Backup"}),
    (("open davinci", "launch davinci", "open resolve", "launch resolve", "start resolve"), {"agent": "OS", "task": "Launch DaVinci"}),
    (("close davinci", "quit davinci", "close resolve", "quit resolve"), {"agent": "OS", "task": "Close DaVinci", "requires_confirmation": True}),
]


def offline_plan(user_input: str, guided_mode: bool = False) -> dict:
    """Keyword planner used when no model is reachable. Never invents a grade the user didn't ask for."""
    text = user_input.lower()
    scope = "timeline" if any(w in text for w in ("whole timeline", "all clips", "every clip", "entire timeline")) else "clip"
    steps = []

    skill = re.search(r"(?:apply|use) (?:the )?[\"']?([\w \-]+?)[\"']? skill", text)
    learn = re.search(r"(?:learn|save|remember) (?:this|the grade|it)? ?as (?:a )?(?:skill )?[\"']?([\w \-]+)[\"']?", text)
    if learn:
        steps.append({"agent": "Skill", "task": "Learn skill", "params": {"skill_name": learn.group(1).strip(), "action": "learn"}})
    elif skill:
        steps.append({"agent": "Skill", "task": f"Apply {skill.group(1).strip()} skill", "params": {"skill_name": skill.group(1).strip()}})

    cdl = dict(_NEUTRAL)
    matched_terms = []
    for terms, nudge in _GRADE_TERMS.items():
        if any(t in text for t in terms):
            matched_terms.append(terms[0])
            for k, v in nudge.items():
                cdl[k] = round(max(0.0, cdl[k] + v), 4)
    if matched_terms:
        steps.insert(0, {"agent": "Color Scientist", "task": f"Apply CDL: {', '.join(matched_terms)}",
                         "params": {**cdl, "append_new_node": True}})

    used_agents = set()
    for keywords, step in _ROUTES:
        if step["agent"] in used_agents and step["agent"] not in ("Memory", "Tracking", "Audio", "Quality"):
            continue
        if any(k in text for k in keywords):
            new ={**step, "params": dict(step.get("params", {}))}
            if new["agent"] == "Film":
                m = re.search(r"(2383|2393|3513)", text)
                new["params"]["look"] = {"2383": "kodak_2383", "2393": "kodak_2393", "3513": "fuji_3513"}.get(
                    m.group(1) if m else "", "kodak_2383")
            if new["agent"] == "LUT":
                m = re.search(r"([\w\- ]+?) lut", text)
                new["params"].update({"keyword": (m.group(1).split()[-1] if m else ""), "apply": "apply" in text})
            if new["agent"] == "Memory":
                m = re.search(r"version (?:called |named )?[\"']?([\w\-]+)", text)
                if m and m.group(1) not in ("history",):
                    new["params"]["version_name"] = m.group(1)
            steps.append(new)
            used_agents.add(step["agent"])
        if len(steps) >= 5:
            break

    if not steps:
        return {"status": "error", "plan": [],
                "message": "I couldn't map that to an action without the AI model. Try e.g. "
                           "'make it warmer', 'audit the timeline', 'stabilize', or 'render'."}

    for step in steps:
        step.setdefault("scope", scope)
        step.setdefault("params", {})
        step["requires_confirmation"] = bool(guided_mode or step.get("requires_confirmation", False))
    return {"status": "success", "plan": steps[:5], "source": "offline"}


class DirectorAgent:
    def __init__(self, provider: GeminiProvider):
        self.provider = provider

    def analyze_intent(self, user_input: str, guided_mode: bool = False) -> dict:
        """
        Calls Gemini to translate user intent into a concrete execution plan.
        Falls back to a demo plan when no API key is configured.
        """
        logger.info(f"Director analyzing: '{user_input}' (Guided: {guided_mode})")
        
        # Inject capabilities into prompt
        from bridge.capability_probe import current_capabilities
        from .rag_engine import get_rag

        # 1. Query Vector DB for relevant color theory (optional dependency)
        theory_context = get_rag().query_theory(user_input)

        caps = current_capabilities()

        system_prompt = _SYSTEM_PROMPT
        if guided_mode:
            system_prompt += "\n\nCRITICAL: guided_mode is ENABLED for this request. You MUST set requires_confirmation=true for all steps, and use plain English task descriptions."
            
        if caps.get("features"):
            system_prompt += "\n\nAvailable Features Matrix:\n"
            system_prompt += json.dumps(caps.get("features", {}), indent=2)
            system_prompt += "\nDo not schedule agents for tasks if the required feature is marked as unavailable. If marked as 'guided', create a manual instruction step."

        if theory_context:
            system_prompt += f"\n\nProfessional Color Theory Context (Use this to guide your CDL Math):\n{theory_context}"

        raw = self.provider.generate_response(
            system_prompt=system_prompt,
            user_prompt=user_input,
        )

        # If the provider returned a real content string, parse it
        content = raw.get("content", "") if isinstance(raw, dict) else ""

        if content and "mocked" not in content:
            try:
                # Strip markdown fences if the model wrapped the JSON
                clean = re.sub(r"```(?:json)?", "", content).strip("` \n")
                plan = json.loads(clean)
                if not isinstance(plan.get("plan"), list) or not plan["plan"]:
                    raise json.JSONDecodeError("plan has no steps", clean, 0)
                plan.setdefault("status", "success")
                logger.info(f"Director parsed plan with {len(plan.get('plan', []))} steps")
                return plan
            except json.JSONDecodeError as e:
                logger.error(f"Director: JSON parse failed ({e}), falling back to demo plan")

        # No model available (or unusable reply): route by keywords so every agent stays reachable.
        logger.info("Director: no usable model reply, using offline keyword planner")
        return offline_plan(user_input, guided_mode)

    def plan_timeline(self, user_input: str, clips: list, guided_mode: bool = False) -> dict:
        """
        Timeline-wide planning: passes clip metadata to Gemini so it can generate
        a multi-clip plan (e.g. matching clips, applying a look across everything).
        """
        logger.info(f"Director analyzing timeline scope ({len(clips)} clips): '{user_input}' (Guided: {guided_mode})")
        
        # Build context from clips
        clip_context = "Timeline Clips:\n"
        for clip in clips[:10]: # Limit context for now to avoid token overflow
            clip_context += f"- Track {clip.get('track_index', 1)}, Clip {clip['clip_index']}: {clip['name']} ({clip['duration']} frames)\n"
            
        full_prompt = f"{user_input}\n\nContext:\n{clip_context}"
        
        # For now, reuse analyze_intent which will use the same system prompt
        # The system prompt was updated to know how to emit scope="timeline"
        return self.analyze_intent(full_prompt, guided_mode)

