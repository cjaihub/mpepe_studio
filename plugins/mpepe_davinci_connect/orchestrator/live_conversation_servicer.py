import logging
import threading
import uuid
import json
import re

import live_conversation_pb2
import live_conversation_pb2_grpc
from provider_abstraction import GeminiProvider
from director import DirectorAgent
from executor import Executor, get_active_tasks
import database

logger = logging.getLogger("cj_grader.live_conversation")

class LiveConversationServicer(live_conversation_pb2_grpc.GeminiLiveServiceServicer):
    def __init__(self, provider: GeminiProvider, director: DirectorAgent, executor: Executor):
        self.provider = provider
        self.director = director
        self.executor = executor
        # Memory can be a simple list of dicts for this session
        self.history = []

    def _get_system_prompt(self):
        active_tasks = get_active_tasks()
        tasks_desc = "None"
        if active_tasks:
            tasks_desc = json.dumps(active_tasks, indent=2)
            
        return f"""You are CJ, a friendly and expert Senior Colorist assistant in DaVinci Resolve.
You are conversing with the user in real-time. Keep responses concise, natural, and conversational.

Currently active background tasks running in DaVinci Resolve:
{tasks_desc}

If the user asks for progress or status, use the active tasks information to answer them accurately. 

If the user's message is a request to perform a grading action, color change, or editing task (e.g. "make it warmer", "match this clip", "render the timeline"), you MUST include this exact tag in your response:
<TRIGGER>the core instruction</TRIGGER>
For example: "I'll get right on that. <TRIGGER>make the shadows cooler and lift the exposure</TRIGGER>"

Do NOT use the <TRIGGER> tag if the user is just asking a question or chatting.
"""

    def ConverseLive(self, request_iterator, context):
        logger.info("Live conversation stream connected.")
        user_text_buffer = []
        last_frame = None
        
        for chunk in request_iterator:
            # Handle incoming text
            if chunk.text:
                user_text_buffer.append(chunk.text)
            
            # Handle incoming audio (transcribe it)
            if chunk.audio_data:
                transcript = self.provider.transcribe(chunk.audio_data)
                if transcript:
                    user_text_buffer.append(transcript)
                    
            # Handle incoming frame
            if chunk.frame_jpeg:
                last_frame = chunk.frame_jpeg
                analysis = self.provider.analyze_image(
                    "Describe the visual characteristics of this video frame (e.g., color balance, exposure, skin tones).",
                    chunk.frame_jpeg
                )
                desc = analysis.get("content", "A video frame was provided, but could not be analyzed.")
                user_text_buffer.append(f"[System context - Current frame visual analysis: {desc}]")
                
            if chunk.end_of_turn:
                user_message = " ".join(user_text_buffer).strip()
                user_text_buffer = [] # Reset for next turn
                
                # Check for Match Reference mode
                if "[MATCH_REFERENCE]" in user_message and last_frame:
                    clean_prompt = user_message.replace("[MATCH_REFERENCE]", "").strip()
                    yield live_conversation_pb2.LiveChunk(text="\n*Initiating Reference Match...*", role='assistant')
                    
                    task_id = str(uuid.uuid4())
                    self.executor.execute_plan(
                        [{
                            "agent": "ReferenceAgent",
                            "action": "Match Reference Look",
                            "parameters": {
                                "prompt": clean_prompt,
                                "frame_bytes": last_frame
                            }
                        }],
                        task_id=task_id
                    )
                    
                    yield live_conversation_pb2.LiveChunk(text="\n*I'm analyzing the reference image and applying the look.*", role='assistant', end_of_turn=True)
                    continue
                
                # Check for Login/Register/Project commands
                if user_message.startswith("[LOGIN]"):
                    try:
                        data = json.loads(user_message.replace("[LOGIN]", "").strip())
                        success, result = database.login_user(data.get("username"), data.get("password"))
                        if success:
                            yield live_conversation_pb2.LiveChunk(text=f"[AUTH_SUCCESS] {json.dumps(result)}", role='system', end_of_turn=True)
                        else:
                            yield live_conversation_pb2.LiveChunk(text=f"[AUTH_FAIL] {result}", role='system', end_of_turn=True)
                    except Exception as e:
                        yield live_conversation_pb2.LiveChunk(text=f"[AUTH_FAIL] {str(e)}", role='system', end_of_turn=True)
                    continue
                    
                if user_message.startswith("[REGISTER]"):
                    try:
                        data = json.loads(user_message.replace("[REGISTER]", "").strip())
                        success, result = database.register_user(data.get("username"), data.get("password"))
                        if success:
                            yield live_conversation_pb2.LiveChunk(text=f"[AUTH_SUCCESS] {result}", role='system', end_of_turn=True)
                        else:
                            yield live_conversation_pb2.LiveChunk(text=f"[AUTH_FAIL] {result}", role='system', end_of_turn=True)
                    except Exception as e:
                        yield live_conversation_pb2.LiveChunk(text=f"[AUTH_FAIL] {str(e)}", role='system', end_of_turn=True)
                    continue
                    
                if user_message.startswith("[NEW_PROJECT]"):
                    try:
                        data = json.loads(user_message.replace("[NEW_PROJECT]", "").strip())
                        project_id = database.create_project(data.get("user_id"), data.get("project_name"), data.get("category"))
                        # Update AI Provider context here
                        self.provider.system_prompt += f"\nUser is working on a new project: {data.get('project_name')} (Category: {data.get('category')}). Bias grades accordingly."
                        yield live_conversation_pb2.LiveChunk(text=f"[PROJECT_SUCCESS] {project_id}", role='system', end_of_turn=True)
                    except Exception as e:
                        yield live_conversation_pb2.LiveChunk(text=f"[PROJECT_FAIL] {str(e)}", role='system', end_of_turn=True)
                    continue

                if not user_message:
                    continue
                    
                logger.info(f"User (Live): {user_message}")
                self.history.append({"role": "user", "content": user_message})
                
                # Get response from conversational agent
                system_prompt = self._get_system_prompt()
                assistant_response = self.provider.chat(system_prompt, self.history, user_message)
                
                # Check if it triggered an action
                trigger_match = re.search(r"<TRIGGER>(.*?)</TRIGGER>", assistant_response, re.IGNORECASE | re.DOTALL)
                clean_response = re.sub(r"<TRIGGER>.*?</TRIGGER>", "", assistant_response, flags=re.IGNORECASE | re.DOTALL).strip()
                
                self.history.append({"role": "assistant", "content": clean_response})
                
                # Stream the text back
                yield live_conversation_pb2.LiveChunk(
                    text=clean_response,
                    role="assistant",
                    end_of_turn=True
                )
                
                # Also convert to speech and send audio if possible
                audio_bytes = self.provider.speak(clean_response)
                if audio_bytes:
                    yield live_conversation_pb2.LiveChunk(
                        audio_data=audio_bytes,
                        role="assistant",
                        end_of_turn=False
                    )

                # If triggered, run the director/executor in background
                if trigger_match:
                    instruction = trigger_match.group(1).strip()
                    logger.info(f"Conversational agent triggered background task: {instruction}")
                    
                    def run_background_task():
                        task_id = str(uuid.uuid4())
                        plan = self.director.analyze_intent(instruction)
                        self.executor.execute_plan(plan, task_id=task_id)
                        
                    t = threading.Thread(target=run_background_task, daemon=True)
                    t.start()
