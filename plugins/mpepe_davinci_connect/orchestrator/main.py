"""
CJ Grader Orchestrator — Entry Point

Starts the orchestration engine that interprets user requests and
delegates tasks to the appropriate agents.

Usage (from plugins/mpepe_davinci_connect):
  GEMINI_API_KEY=your_key python -m orchestrator.main
"""
import logging
import os
import sys
from concurrent import futures

_HERE = os.path.dirname(os.path.abspath(__file__))
for _path in (os.path.dirname(_HERE), _HERE):  # package root, then generated *_pb2 modules
    if _path not in sys.path:
        sys.path.insert(0, _path)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("cj_grader.orchestrator")

import grpc  # noqa: E402

from orchestrator.provider_abstraction import GeminiProvider  # noqa: E402
from orchestrator.director import DirectorAgent  # noqa: E402
from orchestrator.live_conversation_servicer import LiveConversationServicer  # noqa: E402
import live_conversation_pb2_grpc  # noqa: E402
import orchestrator_pb2_grpc  # noqa: E402


def _start_optional_services():
    """Preview streaming and remote control need extra packages; run without them if missing."""
    try:
        from orchestrator import mjpeg_streamer
        mjpeg_streamer.start_streamer(port=int(os.environ.get("CJ_GRADER_PIP_PORT", "5000")))
    except Exception as e:
        logger.warning(f"Preview streamer disabled: {e}")
    try:
        from orchestrator import remote_host
        remote_host.start_remote_host(port=int(os.environ.get("CJ_GRADER_REMOTE_PORT", "8080")))
    except Exception as e:
        logger.warning(f"Remote control host disabled: {e}")


def run():
    api_key = os.environ.get("GEMINI_API_KEY")
    proxy_url = os.environ.get("CJ_GRADER_PROXY_URL")
    grpc_port = int(os.environ.get("CJ_GRADER_ORCHESTRATOR_PORT", "50052"))

    provider = GeminiProvider(api_key=api_key, proxy_url=proxy_url)
    director = DirectorAgent(provider=provider)

    # One Executor and one Orchestrator implementation shared with the bridge server,
    # so plan streaming and step confirmations behave the same on either port.
    from bridge.grpc_server import OrchestratorServicer, action_executor

    _start_optional_services()

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    live_conversation_pb2_grpc.add_GeminiLiveServiceServicer_to_server(
        LiveConversationServicer(provider, director, action_executor), server)
    orchestrator_pb2_grpc.add_OrchestratorServicer_to_server(OrchestratorServicer(), server)

    server.add_insecure_port(f"[::]:{grpc_port}")
    server.start()
    logger.info(f"CJ Grader Orchestrator gRPC Server running on port {grpc_port} "
                f"with agents: {', '.join(action_executor.agent_names)}")
    server.wait_for_termination()


if __name__ == "__main__":
    run()
