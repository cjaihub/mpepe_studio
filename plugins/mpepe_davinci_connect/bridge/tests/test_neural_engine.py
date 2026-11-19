import unittest
from unittest.mock import MagicMock
import sys
import os

# Add bridge root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from bridge.tools.neural_engine_tools import create_magic_mask

class TestNeuralEngineTools(unittest.TestCase):
    def test_create_magic_mask(self):
        # Mock the resolve project
        mock_project = MagicMock()
        mock_timeline = MagicMock()
        mock_clip = MagicMock()
        
        mock_project.GetCurrentTimeline.return_value = mock_timeline
        mock_timeline.GetItemListInTrack.return_value = [mock_clip]
        mock_clip.CreateMagicMask.return_value = True
        
        # Mock get_current_project globally
        import bridge.tools.neural_engine_tools
        bridge.tools.neural_engine_tools.get_current_project = MagicMock(return_value=(MagicMock(), mock_project))

        # Magic Mask is a Studio feature: present a Studio build to the capability probe
        import bridge.capability_probe as probe
        studio = {"features": {"magic_mask": {"available": True, "mode": "automated"}}}
        original = probe.current_capabilities
        probe.current_capabilities = lambda: studio
        self.addCleanup(setattr, probe, "current_capabilities", original)
        
        result = create_magic_mask("test_timeline", 1, 1, "F")
        
        self.assertTrue(result)
        mock_clip.CreateMagicMask.assert_called_once_with("F")

if __name__ == '__main__':
    unittest.main()
