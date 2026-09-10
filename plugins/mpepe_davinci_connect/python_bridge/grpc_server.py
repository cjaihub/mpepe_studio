import grpc
from concurrent import futures
import logging
import sys
import os
import uuid
import threading

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import bridge_pb2
import bridge_pb2_grpc
import orchestrator_pb2
import orchestrator_pb2_grpc
import ledger_pb2
import ledger_pb2_grpc
import skills_pb2_grpc
import suggestions_pb2_grpc
import live_conversation_pb2_grpc
from bridge.skills_servicer import SkillsServicer
from bridge.suggestion_servicer import SuggestionServicer
from bridge.live_servicer import GeminiLiveServicer
from orchestrator.provider_abstraction import GeminiProvider

from .tools.cdl_tools import set_cdl
from .tools.neural_engine_tools import create_magic_mask, stabilize, smart_reframe
from .resolve_connection import get_capabilities, init_resolve
from orchestrator.ledger import ActionLedger

logger = logging.getLogger("cj_grader.grpc")

# Singleton ledger for the session
action_ledger = ActionLedger()


# ---------------------------------------------------------------------------
# Track A — Resolve Tools (CDL, Masks, Node Graph)
# ---------------------------------------------------------------------------

class ResolveToolsServicer(bridge_pb2_grpc.ResolveToolsServicer):
    def SetCDL(self, request, context):
        logger.info(f"SetCDL called for timeline {request.timeline_id}")
        result = set_cdl(
            request.timeline_id,
            request.track_index,
            request.clip_index,
            request.node_index,
            slope=dict(request.slope),
            offset=dict(request.offset),
            power=dict(request.power),
            saturation=request.saturation,
            append_new_node=request.append_new_node,
        )
        success = result.get("success", False)
        snapshot = result.get("snapshot", "")

        # Auto-write to ledger every time a CDL is applied
        if success:
            import json
            action_ledger.record_action(
                timeline_id=request.timeline_id,
                track_index=request.track_index,
                clip_index=request.clip_index,
                node_index=request.node_index,
                action_type="SET_CDL",
                payload={
                    "slope": dict(request.slope),
                    "offset": dict(request.offset),
                    "power": dict(request.power),
                    "saturation": request.saturation,
                    "snapshot": snapshot,
                },
                agent_id="grpc_server",
            )

        return bridge_pb2.ToolResponse(success=success)

    def CreateMagicMask(self, request, context):
        logger.info(f"CreateMagicMask called for timeline {request.timeline_id}")
        success = create_magic_mask(
            request.timeline_id,
            request.track_index,
            request.clip_index,
            request.mode,
        )
        return bridge_pb2.ToolResponse(success=success)

    def GetNodeGraph(self, request, context):
        from .tools.node_tools import get_node_graph
        nodes = get_node_graph(request.track_index, request.clip_index)
        response = bridge_pb2.NodeGraphResponse(success=True)
        for node in nodes:
            pb_node = response.nodes.add()
            pb_node.index = node.get("index", 1)
            pb_node.label = node.get("label", "")
            pb_node.is_enabled = node.get("is_enabled", True)
        return response

    def OpenPage(self, request, context):
        logger.info(f"OpenPage called for '{request.page_name}'")
        from .tools.page_tools import open_page
        success = open_page(request.page_name)
        return bridge_pb2.ToolResponse(success=success)

    def GetCapabilities(self, request, context):
        logger.info("GetCapabilities called")
        caps = get_capabilities()
        return bridge_pb2.CapabilityResponse(
            is_connected=caps["is_connected"],
            resolve_version=caps["resolve_version"],
            is_studio=caps["is_studio"],
            has_magic_mask=caps["has_magic_mask"],
            error_message=caps["error_message"]
        )

# ---------------------------------------------------------------------------
# Track B — Orchestrator (prompt submission + live plan streaming)
# ---------------------------------------------------------------------------
# Singleton executor for the session
from orchestrator.executor import Executor
action_executor = Executor()

class OrchestratorServicer(orchestrator_pb2_grpc.OrchestratorServicer):
    def __init__(self):
        super().__init__()
        self.executor_pool = futures.ThreadPoolExecutor(max_workers=4)

    def SubmitPrompt(self, request, context):
        """
        Accepts a chat prompt, spins up the Director + Executor in a background
        thread, and returns a task_id immediately. The Flutter client then calls
        StreamPlanEvents(task_id) to receive live per-step updates.
        """
        from orchestrator.executor import create_task_bus
        from orchestrator.director import DirectorAgent
        from orchestrator.provider_abstraction import GeminiProvider

        task_id = str(uuid.uuid4())[:8]
        task_bus = create_task_bus(task_id)

        def run_grading_task():
            try:
                provider = GeminiProvider(api_key=os.environ.get("GEMINI_API_KEY", ""))
                director = DirectorAgent(provider=provider)

                # Fetch clip metadata if this is a timeline-scoped prompt
                if request.scope == "timeline":
                    from .tools.timeline_tools import get_timeline_clips
                    clips = get_timeline_clips(request.timeline_id, request.track_index)
                    plan = director.plan_timeline(request.prompt, clips, guided_mode=request.guided_mode)
                else:
                    plan = director.analyze_intent(request.prompt, guided_mode=request.guided_mode)

                if plan.get("status") == "success":
                    for step in plan.get("plan", []):
                        step["timeline_id"] = request.timeline_id
                        step["track_index"] = request.track_index
                        step["clip_index"]  = request.clip_index

                    action_executor.execute_plan(plan, task_id=task_id)
                else:
                    logger.error(f"Director plan failed: {plan}")
                    from orchestrator.executor import get_task_bus, remove_task_bus
                    q = get_task_bus(task_id)
                    if q:
                        q.put({"status": "__DONE__"})
                    remove_task_bus(task_id)
            except Exception as e:
                logger.error(f"SubmitPrompt background task failed: {e}")

        self.executor_pool.submit(run_grading_task)

        logger.info(f"Accepted prompt → task_id={task_id}")
        return orchestrator_pb2.PromptResponse(
            accepted=True,
            task_id=task_id,
            message="Processing your request...",
        )

    def StreamPlanEvents(self, request, context):
        """
        Server-streaming RPC. Blocks until the Executor finishes, yielding a
        PlanEvent proto for every RUNNING/DONE/ERROR step transition.
        """
        from orchestrator.executor import get_task_bus
        import queue

        task_id = request.task_id
        logger.info(f"StreamPlanEvents: client subscribed task_id={task_id}")

        # Wait up to 10 s for the task bus to appear (race between SubmitPrompt
        # returning and the client opening the stream).
        for _ in range(100):
            bus = get_task_bus(task_id)
            if bus:
                break
            import time
            time.sleep(0.1)

        if not bus:
            logger.warning(f"StreamPlanEvents: no bus found for task_id={task_id}")
            return

        while True:
            try:
                event = bus.get(timeout=30)
            except queue.Empty:
                logger.warning(f"StreamPlanEvents: timed out waiting for task {task_id}")
                return

            if event.get("status") == "__DONE__":
                return

            yield orchestrator_pb2.PlanEvent(
                task_id=event.get("task_id", ""),
                step_index=event.get("step_index", 0),
                total_steps=event.get("total_steps", 0),
                agent=event.get("agent", ""),
                task_description=event.get("task_description", ""),
                status=event.get("status", ""),
                detail=event.get("detail", ""),
            )

    def ConfirmStep(self, request, context):
        logger.info(f"ConfirmStep: task_id={request.task_id} step={request.step_index}")
        action_executor.confirm_step(request.task_id, request.step_index)
        return orchestrator_pb2.ConfirmResponse(success=True, message="Confirmed")

    def RejectStep(self, request, context):
        logger.info(f"RejectStep: task_id={request.task_id} step={request.step_index} reason={request.reason}")
        action_executor.reject_step(request.task_id, request.step_index, request.reason)
        return orchestrator_pb2.ConfirmResponse(success=True, message=f"Rejected: {request.reason}")


# ---------------------------------------------------------------------------
# Track C — Grade Ledger
# ---------------------------------------------------------------------------

class GradeLedgerServicer(ledger_pb2_grpc.GradeLedgerServicer):
    def RecordAction(self, request, context):
        import json
        payload = {}
        try:
            payload = json.loads(request.payload_json)
        except Exception:
            pass

        action_ledger.record_action(
            request.timeline_id, request.track_index, request.clip_index,
            request.node_index, request.action_type, payload, request.agent_id,
        )
        return ledger_pb2.RecordResponse(success=True)

    def GetHistory(self, request, context):
        history = action_ledger.get_history(
            request.timeline_id, request.track_index, request.clip_index,
        )
        import json
        response = ledger_pb2.HistoryResponse()
        for entry in history:
            pb_entry = response.entries.add()
            pb_entry.timestamp = entry.get("timestamp", "")
            pb_entry.action_type = entry.get("action_type", "")
            pb_entry.payload_json = json.dumps(entry.get("payload", {}))
            pb_entry.agent_id = entry.get("agent_id", "")
        return response

    def UndoAction(self, request, context):
        success = action_ledger.undo_last_action(
            request.timeline_id, request.track_index, request.clip_index,
        )
        return ledger_pb2.UndoResponse(
            success=success,
            message="Undid last action" if success else "Nothing to undo or failed",
        )

# ---------------------------------------------------------------------------
# Track D — Look Profile
# ---------------------------------------------------------------------------

import look_profile_pb2
import look_profile_pb2_grpc

class LookProfileServicer(look_profile_pb2_grpc.LookProfileServiceServicer):
    def AnalyzeImage(self, request, context):
        from orchestrator.agents.look_profile_agent import LookProfileAgent
        agent = LookProfileAgent()
        
        # Save bytes to a temp file since our agent currently expects a file path
        import tempfile
        import os
        
        try:
            fd, path = tempfile.mkstemp(suffix=".jpg")
            with os.fdopen(fd, 'wb') as f:
                f.write(request.image_data)
                
            result = agent._analyze_image_file(path, "Analyze image")
            
            os.remove(path)
            
            if result.get("status") == "success":
                return look_profile_pb2.AnalyzeImageResponse(
                    success=True,
                    message=result.get("message", ""),
                    profile_json=result.get("profile", "")
                )
            else:
                return look_profile_pb2.AnalyzeImageResponse(
                    success=False,
                    message=result.get("message", ""),
                )
        except Exception as e:
            return look_profile_pb2.AnalyzeImageResponse(
                success=False,
                message=str(e),
            )

    def GenerateLookFromText(self, request, context):
        from orchestrator.agents.look_profile_agent import LookProfileAgent
        agent = LookProfileAgent()
        result = agent._generate_from_text(request.description, {})
        
        return look_profile_pb2.AnalyzeImageResponse(
            success=result.get("status") == "success",
            message=result.get("message", "")
        )

# ---------------------------------------------------------------------------
# Track E — Voice (STT / TTS)
# ---------------------------------------------------------------------------

try:
    import voice_pb2
    import voice_pb2_grpc
    _VOICE_AVAILABLE = True
except ImportError:
    _VOICE_AVAILABLE = False
    logger.warning("voice_pb2 not found — Voice service will not be registered.")

if _VOICE_AVAILABLE:
    class VoiceServicer(voice_pb2_grpc.VoiceServiceServicer):
        def TranscribeAudio(self, request, context):
            from .tools.voice_tools import transcribe_audio
            text = transcribe_audio(request.audio_data, mime_type=request.mime_type)
            return voice_pb2.TranscribeResponse(text=text)

        def SpeakText(self, request, context):
            from .tools.voice_tools import synthesize_speech
            audio_bytes = synthesize_speech(request.text)
            return voice_pb2.SpeakResponse(audio_data=audio_bytes)


# ---------------------------------------------------------------------------
# Server bootstrap
# ---------------------------------------------------------------------------

def serve_grpc(port: int = 50051):
    logger.info("Initializing DaVinci Resolve connection...")
    init_resolve()
    
    logger.info(f"Starting gRPC server on port {port}")
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    bridge_pb2_grpc.add_ResolveToolsServicer_to_server(ResolveToolsServicer(), server)
    orchestrator_pb2_grpc.add_OrchestratorServicer_to_server(OrchestratorServicer(), server)
    ledger_pb2_grpc.add_GradeLedgerServicer_to_server(GradeLedgerServicer(), server)
    look_profile_pb2_grpc.add_LookProfileServiceServicer_to_server(LookProfileServicer(), server)
    if _VOICE_AVAILABLE:
        voice_pb2_grpc.add_VoiceServiceServicer_to_server(VoiceServicer(), server)
        logger.info("Voice service registered.")
        
    # Provider is required for the new engines
    provider = GeminiProvider()
    
    # Register new servicers
    skills_pb2_grpc.add_SkillsServiceServicer_to_server(SkillsServicer(provider), server)
    suggestions_pb2_grpc.add_SuggestionServiceServicer_to_server(SuggestionServicer(provider), server)
    live_conversation_pb2_grpc.add_GeminiLiveServiceServicer_to_server(GeminiLiveServicer(provider), server)
    
    logger.info("Skills, Suggestion, and Live services registered.")
    server.add_insecure_port(f'[::]:{port}')
    server.start()
    server.wait_for_termination()
