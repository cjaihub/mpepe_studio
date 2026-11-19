"""
End-to-end checks that every CJ Grader agent loads, is reachable by name, and really
calls Resolve. A MagicMock Resolve stands in for DaVinci so the suite runs anywhere.
"""
import base64
import json
import os
import re
from unittest.mock import MagicMock

import pytest

from bridge.connection import ResolveConnection
import orchestrator.memory_store as memory_store


# ── Fixtures ──────────────────────────────────────────────────────────────

def _frame(rgb, w=8, h=8):
    """A flat Resolve-style thumbnail dict of one colour."""
    return {"width": w, "height": h, "format": "RGB 8 bit",
            "data": base64.b64encode(bytes(rgb) * (w * h)).decode()}


@pytest.fixture
def resolve(tmp_path, monkeypatch):
    fake = MagicMock(name="Resolve")
    fake.GetProductName.return_value = "DaVinci Resolve Studio"
    fake.GetVersionString.return_value = "20.2.0"
    project = fake.GetProjectManager.return_value.GetCurrentProject.return_value
    timeline = project.GetCurrentTimeline.return_value
    project.GetTimelineById.return_value = timeline
    timeline.GetSetting.return_value = "24"
    clips = []
    for i in range(3):
        clip = MagicMock(name=f"clip{i + 1}")
        clip.GetName.return_value = f"A00{i + 1}"
        clip.GetStart.return_value = 86400 + i * 100
        clip.GetEnd.return_value = 86400 + (i + 1) * 100
        clip.GetDuration.return_value = 100
        clip.GetNumNodes.return_value = 2
        clip.GetVersionNameList.return_value = []
        clips.append(clip)
    timeline.GetItemListInTrack.return_value = clips
    timeline.GetCurrentClipThumbnailImage.return_value = _frame((120, 118, 116))
    project.AddRenderJob.return_value = "job-1"

    monkeypatch.setattr(ResolveConnection.get_instance(), "_resolve", fake)
    monkeypatch.setattr(memory_store, "_instance", memory_store.MemoryStore(str(tmp_path / "memory.db")))

    lut_root = tmp_path / "LUT"
    (lut_root / "Film Looks").mkdir(parents=True)
    (lut_root / "Film Looks" / "Rec709 Kodak 2383 D65.cube").write_text("LUT_3D_SIZE 2\n")
    (lut_root / "Film Looks" / "Rec709 Fujifilm 3513DI D65.cube").write_text("LUT_3D_SIZE 2\n")
    (lut_root / "Teal Orange.cube").write_text("LUT_3D_SIZE 2\n")
    monkeypatch.setenv("CJ_GRADER_LUT_DIR", str(lut_root))

    fake.project, fake.timeline, fake.clips = project, timeline, clips
    return fake


@pytest.fixture
def executor(resolve):
    from orchestrator.executor import Executor
    return Executor()


def run(executor, *steps, auto_confirm=True):
    """Runs a plan and returns the final DONE/ERROR event of each step."""
    from orchestrator.executor import create_task_bus
    task_id = f"t{id(steps)}"
    bus = create_task_bus(task_id)
    executor.execute_plan({"status": "success", "plan": list(steps)}, task_id=task_id, auto_confirm=auto_confirm)
    finals = {}
    while not bus.empty():
        ev = bus.get()
        if ev.get("status") in ("DONE", "ERROR"):
            finals[ev["step_index"]] = ev
    return [finals[i] for i in sorted(finals)]


CDL = {"slope_r": 1.1, "slope_g": 1.0, "slope_b": 0.9, "offset_r": 0.02, "offset_g": 0.0,
       "offset_b": -0.01, "power_r": 1.0, "power_g": 1.0, "power_b": 1.0, "saturation": 1.2}


# ── Registry ──────────────────────────────────────────────────────────────

def test_every_director_agent_is_registered(executor):
    from orchestrator.director import _SYSTEM_PROMPT
    section = _SYSTEM_PROMPT.split("Available agents", 1)[1].split("ALWAYS respond", 1)[0]
    advertised = re.findall(r"^- ([A-Za-z ]+):", section, flags=re.M)
    assert len(advertised) >= 19
    for name in advertised:
        assert executor.get_agent(name) is not None, name


@pytest.mark.parametrize("alias, canonical", [
    ("SkillApply", "Skill"), ("ReferenceAgent", "Reference"), ("LutAgent", "LUT"),
    ("ColorScientist", "Color Scientist"), ("color scientist", "Color Scientist"),
    ("AuditorAgent", "Auditor"), ("Look Profile", "LookProfile"), ("hdr", "HDR"),
])
def test_aliases(alias, canonical):
    from orchestrator.executor import canonical_agent_name
    assert canonical_agent_name(alias) == canonical


def test_unknown_agent_is_an_error(executor):
    (ev,) = run(executor, {"agent": "Teleporter", "task": "beam"})
    assert ev["status"] == "ERROR" and "Unknown agent" in ev["detail"]


# ── Agents against fake Resolve ──────────────────────────────────────────

def test_color_scientist_applies_cdl_and_records_it(executor, resolve):
    (ev,) = run(executor, {"agent": "Color Scientist", "task": "Warm it up", "params": CDL,
                           "clip_index": 2})
    assert ev["status"] == "DONE" and ev["detail"].startswith("[GRADE_PARAMS]")
    resolve.clips[1].SetCDL.assert_called_once()
    applied = resolve.clips[1].SetCDL.call_args[0][0]
    assert applied["Slope"][:3] == [1.1, 1.0, 0.9] and applied["Saturation"][0] == 1.2
    resolve.clips[1].AddVersion.assert_called()  # non-destructive snapshot first
    history = memory_store.get_memory_store().get_history("", 1, 2)
    assert history and history[0]["action_type"] == "SET_CDL"


def test_color_scientist_reports_resolve_failure(executor, resolve):
    resolve.clips[0].SetCDL.return_value = False
    (ev,) = run(executor, {"agent": "Color Scientist", "task": "grade", "params": CDL})
    assert ev["status"] == "ERROR"


def test_timeline_scope_grades_every_clip(executor, resolve):
    (ev,) = run(executor, {"agent": "Color Scientist", "task": "grade", "scope": "timeline", "params": CDL})
    assert ev["status"] == "DONE"
    assert all(c.SetCDL.called for c in resolve.clips)


def test_skill_learn_then_apply(executor, resolve):
    run(executor, {"agent": "Color Scientist", "task": "grade", "params": CDL})
    learn, apply_ = run(
        executor,
        {"agent": "Skill", "task": "Learn skill", "params": {"skill_name": "Golden", "action": "learn"}},
        {"agent": "SkillApply", "task": "Apply Golden", "params": {"skill_name": "golden"}, "clip_index": 3},
    )
    assert learn["status"] == "DONE" and apply_["status"] == "DONE"
    assert resolve.clips[2].SetCDL.call_args[0][0]["Slope"][:3] == [1.1, 1.0, 0.9]


def test_missing_skill_is_an_error(executor):
    (ev,) = run(executor, {"agent": "Skill", "task": "apply", "params": {"skill_name": "Nope"}})
    assert ev["status"] == "ERROR" and "No skill named" in ev["detail"]


def test_film_agent_finds_bundled_lut_and_applies_last_node(executor, resolve):
    (ev,) = run(executor, {"agent": "Film", "task": "Film print", "params": {"look": "kodak_2383"}})
    assert ev["status"] == "DONE"
    resolve.clips[0].SetLUT.assert_called_once_with(2, "Film Looks/Rec709 Kodak 2383 D65.cube")


def test_lut_agent_search_and_apply(executor, resolve):
    search, apply_ = run(
        executor,
        {"agent": "LUT", "task": "Find LUT", "params": {"keyword": "teal"}},
        {"agent": "LUT", "task": "Apply LUT", "params": {"keyword": "3513", "apply": True}},
    )
    assert search["detail"].startswith("[LUT_RESULTS]")
    assert json.loads(search["detail"].split(" ", 1)[1])["luts"][0]["name"] == "Teal Orange"
    assert apply_["status"] == "DONE"
    resolve.clips[0].SetLUT.assert_called_with(1, "Film Looks/Rec709 Fujifilm 3513DI D65.cube")


def test_match_copies_grade_to_other_clips(executor, resolve):
    (ev,) = run(executor, {"agent": "Match", "task": "Copy grade", "params": {}})
    assert ev["status"] == "DONE"
    targets = resolve.clips[0].CopyGrades.call_args[0][0]
    assert targets == resolve.clips[1:]


def test_match_color_group(executor, resolve):
    resolve.project.GetColorGroupsList.return_value = []
    (ev,) = run(executor, {"agent": "Match", "task": "Color group", "params": {"group_name": "Interview"}})
    assert ev["status"] == "DONE"
    resolve.project.AddColorGroup.assert_called_once_with("Interview")


def test_tracking_skin_hdr_audio_enhance(executor, resolve):
    events = run(
        executor,
        {"agent": "Tracking", "task": "Stabilize clip"},
        {"agent": "Tracking", "task": "Smart Reframe"},
        {"agent": "Skin", "task": "Isolate skin"},
        {"agent": "HDR", "task": "Analyze Dolby Vision"},
        {"agent": "Audio", "task": "Voice isolation"},
        {"agent": "Enhance", "task": "Speed", "params": {"speed": 0.5}},
    )
    assert [e["status"] for e in events] == ["DONE"] * 6, events
    clip = resolve.clips[0]
    clip.Stabilize.assert_called_once()
    clip.SmartReframe.assert_called_once()
    clip.CreateMagicMask.assert_called_once_with("F")
    clip.AnalyzeDolbyVision.assert_called_once()
    clip.SetVoiceIsolationState.assert_called_once_with(True)
    clip.SetProperty.assert_any_call("Speed", "0.5")


def test_studio_features_skip_on_free(executor, resolve):
    resolve.GetProductName.return_value = "DaVinci Resolve"
    (ev,) = run(executor, {"agent": "Tracking", "task": "Smart Reframe"})
    assert ev["status"] == "DONE" and ev["detail"].startswith("Skipped:")
    resolve.clips[0].SmartReframe.assert_not_called()


def test_quality_is_guided_not_faked(executor, resolve):
    (ev,) = run(executor, {"agent": "Quality", "task": "Noise reduction", "params": {"strength": 4}})
    assert ev["detail"].startswith("[GUIDED]")
    resolve.clips[0].SetNodeLabel.assert_called_once_with(2, "NR")


def test_memory_versions_and_history(executor, resolve):
    save, hist = run(
        executor,
        {"agent": "Memory", "task": "Save grade version", "params": {"version_name": "v1"}},
        {"agent": "Memory", "task": "Grade history"},
    )
    assert save["status"] == "DONE" and hist["detail"].startswith("[HISTORY]")
    resolve.clips[0].AddVersion.assert_called_with("v1", 0)


def test_render_queues_and_starts(executor, resolve, tmp_path):
    (ev,) = run(executor, {"agent": "Render", "task": "Render timeline",
                           "params": {"target_dir": str(tmp_path / "out"), "custom_name": "final"}})
    assert ev["status"] == "DONE"
    settings = resolve.project.SetRenderSettings.call_args[0][0]
    assert settings["CustomName"] == "final" and settings["TargetDir"].endswith("out")
    resolve.project.StartRendering.assert_called_once()


def test_cloud_backup_and_consent_gate(executor):
    backup, sync = run(executor, {"agent": "Cloud", "task": "Backup"},
                       {"agent": "Cloud", "task": "Sync", "params": {"user_id": 1}})
    assert backup["status"] == "DONE" and os.path.exists(backup["detail"].rsplit(" ", 1)[1].rstrip("."))
    assert sync["detail"].startswith("Skipped:")  # no consent -> nothing uploaded


def test_reference_and_look_profile_use_vision(executor, resolve, tmp_path):
    from orchestrator.agents.reference_agent import ReferenceAgent
    from orchestrator.agents.look_profile_agent import LookProfileAgent
    provider = MagicMock()
    provider.analyze_image.return_value = {"content": "```json\n" + json.dumps(
        {"description": "warm dusk", "tags": ["warm"], "cdl": CDL}) + "\n```"}
    executor._agents["Reference"] = ReferenceAgent(provider=provider)
    executor._agents["LookProfile"] = LookProfileAgent(provider=provider)
    img = tmp_path / "ref.jpg"
    img.write_bytes(b"\xff\xd8fake")

    ref, look = run(executor,
                    {"agent": "ReferenceAgent", "task": "Match reference", "params": {"image_path": str(img)}},
                    {"agent": "LookProfile", "task": "Look", "params": {"image_path": str(img)}})
    assert ref["status"] == "DONE" and ref["detail"].startswith("[GRADE_PARAMS]")
    assert look["status"] == "DONE" and "warm dusk" in look["detail"]
    assert resolve.clips[0].SetCDL.call_args[0][0]["Saturation"][0] == 1.2


def test_reference_without_model_fails_honestly(executor):
    from orchestrator.agents.reference_agent import ReferenceAgent
    from orchestrator.provider_abstraction import GeminiProvider
    executor._agents["Reference"] = ReferenceAgent(provider=GeminiProvider(api_key=None))
    (ev,) = run(executor, {"agent": "Reference", "task": "match", "params": {"frame_bytes": b"img"}})
    assert ev["status"] == "ERROR"


def test_os_agent_launch(executor, monkeypatch):
    import orchestrator.executor as ex
    calls = []
    monkeypatch.setattr(ex.subprocess, "Popen", lambda args: calls.append(args))
    (ev,) = run(executor, {"agent": "OS", "task": "Launch DaVinci"})
    assert ev["status"] == "DONE" and calls


def test_user_step_waits_for_confirmation(executor):
    import threading
    from orchestrator.executor import create_task_bus
    bus = create_task_bus("confirm-me")
    t = threading.Thread(target=executor.execute_plan, args=(
        {"status": "success", "plan": [{"agent": "User", "task": "Draw a window", "requires_confirmation": True}]},),
        kwargs={"task_id": "confirm-me"})
    t.start()
    assert bus.get(timeout=5)["status"] == "WAITING_CONFIRMATION"
    for _ in range(50):
        if ("confirm-me", 1) in executor._confirmations:
            break
        threading.Event().wait(0.02)
    executor.confirm_step("confirm-me", 1)
    t.join(timeout=5)
    statuses = []
    while not bus.empty():
        statuses.append(bus.get()["status"])
    assert statuses[-2:] == ["DONE", "__DONE__"]


# ── Auditor ───────────────────────────────────────────────────────────────

def test_auditor_measures_frames(executor, resolve):
    frames = [_frame((120, 118, 116)), _frame((0, 0, 0)), _frame((90, 140, 90))]
    resolve.timeline.GetCurrentClipThumbnailImage.side_effect = frames
    (ev,) = run(executor, {"agent": "Auditor", "task": "Audit timeline"})
    assert ev["status"] == "DONE"
    flagged = json.loads(ev["detail"].split(" ", 1)[1])["flagged_clips"]
    by_clip = {f["clip_index"]: f["issue_type"] for f in flagged}
    assert 1 not in by_clip
    assert by_clip[2] == "Exposure"
    assert any(f["clip_index"] == 3 and "green" in f["message"] for f in flagged)


def test_auditor_is_deterministic(executor, resolve):
    a = run(executor, {"agent": "Auditor", "task": "audit"})[0]["detail"]
    b = run(executor, {"agent": "Auditor", "task": "audit"})[0]["detail"]
    assert a == b


# ── Director offline planner ─────────────────────────────────────────────

@pytest.mark.parametrize("prompt, agents", [
    ("render the timeline", ["Render"]),
    ("make it warmer with more contrast", ["Color Scientist"]),
    ("audit the timeline", ["Auditor"]),
    ("stabilize this and add a 2383 film look", ["Tracking", "Film"]),
    ("apply the golden hour skill", ["Skill"]),
    ("open davinci", ["OS"]),
    ("isolate the dialogue", ["Audio"]),
])
def test_offline_planner_routes_to_the_right_agent(prompt, agents):
    from orchestrator.director import offline_plan
    plan = offline_plan(prompt)
    assert plan["status"] == "success"
    assert [s["agent"] for s in plan["plan"]] == agents


def test_offline_planner_never_invents_a_grade():
    from orchestrator.director import offline_plan
    assert offline_plan("hello there")["status"] == "error"


def test_director_without_key_uses_offline_plan(resolve):
    from orchestrator.director import DirectorAgent
    from orchestrator.provider_abstraction import GeminiProvider
    plan = DirectorAgent(GeminiProvider(api_key=None)).analyze_intent("render the timeline")
    assert [s["agent"] for s in plan["plan"]] == ["Render"]
