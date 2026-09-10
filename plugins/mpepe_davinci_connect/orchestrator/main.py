"""
CJ Grader Orchestrator — Entry Point

Starts the orchestration engine that interprets user requests and 
delegates tasks to the appropriate subagents.

Usage:
  GEMINI_API_KEY=your_key python main.py
"""
import logging
import sys
import os
import mjpeg_streamer
import remote_host

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("cj_grader.orchestrator")

import grpc
from concurrent import futures

from .provider_abstraction import GeminiProvider
from .director import DirectorAgent
from .executor import Executor
from .live_conversation_servicer import LiveConversationServicer
import live_conversation_pb2_grpc
import orchestrator_pb2_grpc
import orchestrator_pb2

class OrchestratorServicer(orchestrator_pb2_grpc.OrchestratorServicer):
    def __init__(self, director: DirectorAgent, executor: Executor):
        self.director = director
        self.executor = executor
        
    def SubmitPrompt(self, request, context):
        import uuid
        import threading
        task_id = str(uuid.uuid4())
        plan = self.director.analyze_intent(request.prompt)
        threading.Thread(target=self.executor.execute_plan, args=(plan, task_id), daemon=True).start()
        return orchestrator_pb2.PromptResponse(status="success", task_id=task_id)

def run():
    api_key = os.environ.get("GEMINI_API_KEY")
    proxy_url = os.environ.get("CJ_GRADER_PROXY_URL")
    bridge_host = os.environ.get("CJ_GRADER_BRIDGE_HOST", "localhost")
    bridge_port = int(os.environ.get("CJ_GRADER_BRIDGE_PORT", "50051"))
    grpc_port = int(os.environ.get("CJ_GRADER_ORCHESTRATOR_PORT", "50052"))

    provider = GeminiProvider(api_key=api_key, proxy_url=proxy_url)
    director = DirectorAgent(provider=provider)
    executor = Executor(bridge_host=bridge_host, bridge_port=bridge_port)

    # Start the PIP Streaming server
    mjpeg_streamer.start_streamer(port=5000)

    # Start the Remote Control WebSocket Server
    remote_host.start_remote_host(port=8080)

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Register the Live Conversational Service
    live_servicer = LiveConversationServicer(provider, director, executor)
    live_conversation_pb2_grpc.add_GeminiLiveServiceServicer_to_server(live_servicer, server)
    
    # Register the standard Orchestrator Service
    orch_servicer = OrchestratorServicer(director, executor)
    orchestrator_pb2_grpc.add_OrchestratorServicer_to_server(orch_servicer, server)
    
    server.add_insecure_port(f'[::]:{grpc_port}')
    server.start()
    logger.info(f"CJ Grader Orchestrator gRPC Server running on port {grpc_port}...")
    server.wait_for_termination()

if __name__ == "__main__":
    run()
