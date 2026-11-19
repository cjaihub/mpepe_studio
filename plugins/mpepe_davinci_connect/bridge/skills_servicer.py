"""
skills_servicer.py — gRPC service for managing Skills (reusable color grades).
"""
import grpc
import logging
import json
import skills_pb2
import skills_pb2_grpc
from orchestrator.skills_engine import SkillsEngine

logger = logging.getLogger("cj_grader.skills_servicer")

class SkillsServicer(skills_pb2_grpc.SkillsServiceServicer):
    def __init__(self, provider):
        self.engine = SkillsEngine(provider)

    def AnalyzeAndSaveSkill(self, request, context):
        logger.info(f"AnalyzeAndSaveSkill: {request.name}")
        try:
            skill_dict = self.engine.analyze_and_save_skill(
                image_bytes=request.image_data,
                mime_type=request.mime_type or "image/jpeg",
                name=request.name,
                user_tags=list(request.tags)
            )
            return skills_pb2.Skill(
                id=skill_dict["id"],
                name=skill_dict["name"],
                description=skill_dict["description"],
                tags=json.loads(skill_dict["tags"]),
                cdl_json=skill_dict["cdl_json"],
                created_at=skill_dict["created_at"],
                thumbnail_b64=skill_dict["thumbnail_b64"]
            )
        except Exception as e:
            logger.error(f"AnalyzeAndSaveSkill failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(str(e))
            return skills_pb2.Skill()

    def ListSkills(self, request, context):
        try:
            skills = self.engine.list_skills()
            resp = skills_pb2.SkillList()
            for s in skills:
                resp.skills.append(skills_pb2.Skill(
                    id=s["id"],
                    name=s["name"],
                    description=s["description"],
                    tags=json.loads(s["tags"]),
                    cdl_json=s["cdl_json"],
                    created_at=s["created_at"],
                    thumbnail_b64=s["thumbnail_b64"]
                ))
            return resp
        except Exception as e:
            logger.error(f"ListSkills failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(str(e))
            return skills_pb2.SkillList()

    def ApplySkill(self, request, context):
        try:
            success = self.engine.apply_skill(
                skill_id=request.skill_id,
                timeline_id=request.timeline_id,
                track_index=request.track_index,
                clip_index=request.clip_index
            )
            return skills_pb2.ApplySkillResponse(
                success=success,
                message="Applied successfully" if success else "Failed to apply skill",
                skill_name=""
            )
        except Exception as e:
            logger.error(f"ApplySkill failed: {e}")
            return skills_pb2.ApplySkillResponse(success=False, message=str(e))

    def DeleteSkill(self, request, context):
        try:
            success = self.engine.delete_skill(request.id)
            return skills_pb2.DeleteResponse(
                success=success,
                message="Deleted successfully" if success else "Skill not found"
            )
        except Exception as e:
            logger.error(f"DeleteSkill failed: {e}")
            return skills_pb2.DeleteResponse(success=False, message=str(e))

    def GetSkill(self, request, context):
        try:
            skill = self.engine.get_skill(request.id)
            if not skill:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details("Skill not found")
                return skills_pb2.Skill()
            return skills_pb2.Skill(
                id=skill["id"],
                name=skill["name"],
                description=skill["description"],
                tags=json.loads(skill["tags"]),
                cdl_json=skill["cdl_json"],
                created_at=skill["created_at"],
                thumbnail_b64=skill["thumbnail_b64"]
            )
        except Exception as e:
            logger.error(f"GetSkill failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(str(e))
            return skills_pb2.Skill()
