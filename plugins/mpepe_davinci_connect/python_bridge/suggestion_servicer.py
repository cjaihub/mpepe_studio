"""
suggestion_servicer.py — gRPC service for providing proactive grading suggestions.
"""
import grpc
import logging
import suggestions_pb2
import suggestions_pb2_grpc
from orchestrator.suggestion_engine import SuggestionEngine

logger = logging.getLogger("cj_grader.suggestion_servicer")

class SuggestionServicer(suggestions_pb2_grpc.SuggestionServiceServicer):
    def __init__(self, provider):
        self.engine = SuggestionEngine(provider)

    def GetSuggestions(self, request, context):
        logger.info("GetSuggestions requested")
        try:
            raw_suggestions = self.engine.generate_suggestions(
                frame_jpeg=request.frame_jpeg,
                history_json=request.history_json,
                context_text=request.context
            )
            
            resp = suggestions_pb2.SuggestionResponse()
            for s in raw_suggestions:
                resp.suggestions.append(suggestions_pb2.Suggestion(
                    text=s.get("text", ""),
                    prompt=s.get("prompt", ""),
                    category=s.get("category", "creative"),
                    confidence=s.get("confidence", 0.5)
                ))
            return resp
        except Exception as e:
            logger.error(f"GetSuggestions failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(str(e))
            return suggestions_pb2.SuggestionResponse()
