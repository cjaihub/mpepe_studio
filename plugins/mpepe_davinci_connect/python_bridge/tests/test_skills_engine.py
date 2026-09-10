import sys
import os
import unittest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from orchestrator.skills_engine import SkillsEngine

class TestSkillsEngine(unittest.TestCase):
    def setUp(self):
        self.mock_provider = MagicMock()
        self.mock_store = MagicMock()
        
        # Patch get_memory_store to return mock
        import orchestrator.skills_engine
        orchestrator.skills_engine.get_memory_store = MagicMock(return_value=self.mock_store)
        
        self.engine = SkillsEngine(self.mock_provider)

    def test_analyze_and_save_skill(self):
        # Mock provider response
        self.mock_provider.analyze_image.return_value = {
            "content": '{"description": "Cool look", "tags": ["moody"], "cdl": {"slope_r": 1.0}}'
        }
        
        # Mock store
        self.mock_store.save_skill.return_value = 1
        self.mock_store.get_skill.return_value = {"id": 1, "name": "Test"}
        
        skill = self.engine.analyze_and_save_skill(b"fakebytes", "image/jpeg", "Test", ["cinematic"])
        
        self.assertIsNotNone(skill)
        self.assertEqual(skill["name"], "Test")
        self.mock_provider.analyze_image.assert_called_once()
        self.mock_store.save_skill.assert_called_once()
        
    def test_apply_skill(self):
        import bridge.tools.cdl_tools
        bridge.tools.cdl_tools.set_cdl = MagicMock(return_value=True)
        
        self.mock_store.get_skill.return_value = {
            "id": 1,
            "name": "Test",
            "cdl_json": '{"slope_r": 1.1, "offset_g": 0.05}'
        }
        
        success = self.engine.apply_skill(1, "timeline1", 1, 1)
        self.assertTrue(success)
        bridge.tools.cdl_tools.set_cdl.assert_called_once()

if __name__ == '__main__':
    unittest.main()
