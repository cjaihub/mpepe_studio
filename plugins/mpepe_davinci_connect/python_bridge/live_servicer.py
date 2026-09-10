"""
live_servicer.py — gRPC service for Gemini Live Bidirectional Streaming.
"""
import grpc
import logging
import json
import time
import live_conversation_pb2
import live_conversation_pb2_grpc
from orchestrator.provider_abstraction import GeminiProvider
from orchestrator.director import DirectorAgent
from bridge.tools.voice_tools import transcribe_audio, synthesize_speech

logger = logging.getLogger("cj_grader.live_servicer")

class GeminiLiveServicer(live_conversation_pb2_grpc.GeminiLiveServiceServicer):
    def __init__(self, provider: GeminiProvider, orchestrator=None):
        self.provider = provider
        self.orchestrator = orchestrator # to trigger plans directly if needed
        self.director = DirectorAgent(provider)

    def ConverseLive(self, request_iterator, context):
        """
        Bidirectional stream.
        Client sends chunks of audio and/or text.
        Server processes and sends back chunks.
        """
        logger.info("Live conversation stream connected")
        
        # We accumulate audio bytes for a turn
        current_audio = b""
        current_frame = b""
        current_region = None
        
        try:
            for chunk in request_iterator:
                # Accumulate data
                if chunk.audio_data:
                    current_audio += chunk.audio_data
                if chunk.frame_jpeg:
                    current_frame = chunk.frame_jpeg
                if chunk.HasField("region"):
                    current_region = chunk.region

                # If the client signals end of turn, process the accumulated audio
                if chunk.end_of_turn:
                    logger.info("End of turn received, processing...")
                    
                    user_text = ""
                    if chunk.text:
                        user_text = chunk.text
                    elif current_audio:
                        # Fallback STT processing if real Gemini Live isn't hooked up yet
                        user_text = transcribe_audio(current_audio, self.provider)
                    
                    if user_text:
                        logger.info(f"User said: {user_text}")
                        # Send text transcript back to client
                        yield live_conversation_pb2.LiveChunk(
                            text=user_text,
                            role="user",
                            event_type="text"
                        )
                        
                        # Analyze intent
                        # Convert region to dict if present
                        region_dict = None
                        if current_region:
                            region_dict = {
                                "x": current_region.x,
                                "y": current_region.y,
                                "width": current_region.width,
                                "height": current_region.height,
                                "label": current_region.label
                            }
                            
                        plan = self.director.analyze_intent(
                            user_text, 
                            guided_mode=False,
                            region_mask=region_dict
                        )
                        
                        # Tell client about the plan
                        if plan and plan.get("plan"):
                            yield live_conversation_pb2.LiveChunk(
                                role="system",
                                event_type="plan_triggered",
                                plan_json=json.dumps(plan)
                            )
                            
                        # Generate verbal response
                        response_text = "Okay, I'll apply those changes."
                        if plan and plan.get("plan"):
                            first_task = plan["plan"][0].get("task", "")
                            if first_task:
                                response_text = f"Sure, I will {first_task.lower()}."
                                
                        # TTS
                        resp_audio = synthesize_speech(response_text, self.provider)
                        
                        yield live_conversation_pb2.LiveChunk(
                            text=response_text,
                            audio_data=resp_audio,
                            role="assistant",
                            event_type="audio",
                            end_of_turn=True
                        )
                    
                    # Reset turn buffers
                    current_audio = b""
                    current_frame = b""
                    current_region = None
                    
        except grpc.RpcError as e:
            logger.warning(f"Live stream closed/errored: {e}")
        except Exception as e:
            logger.error(f"Live stream error: {e}")
        finally:
            logger.info("Live conversation stream disconnected")
