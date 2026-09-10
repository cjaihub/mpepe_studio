import unittest
from unittest.mock import MagicMock
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from bridge.tools.cdl_tools import set_cdl

class TestCDLTools(unittest.TestCase):
    def test_set_cdl(self):
        # Mock the resolve project
        mock_project = MagicMock()
        mock_timeline = MagicMock()
        mock_clip = MagicMock()
        
        mock_project.GetCurrentTimeline.return_value = mock_timeline
        mock_project.GetTimelineById.return_value = mock_timeline
        mock_timeline.GetItemListInTrack.return_value = [mock_clip]
        mock_clip.SetCDL.return_value = True
        
        # Mock get_current_project globally
        import bridge.tools.cdl_tools
        bridge.tools.cdl_tools.get_current_project = MagicMock(return_value=(MagicMock(), mock_project))
        
        slope = {"r": 1.1, "g": 1.0, "b": 1.0, "y": 1.0}
        offset = {"r": 0.0, "g": 0.0, "b": 0.0, "y": 0.0}
        power = {"r": 1.0, "g": 1.0, "b": 1.0, "y": 1.0}
        
        result = set_cdl("test_timeline", 1, 1, 1, slope, offset, power, 1.0)
        
        self.assertTrue(result)
        mock_clip.SetCDL.assert_called_once_with(
            {"Slope": [1.1, 1.0, 1.0, 1.0], "Offset": [0.0, 0.0, 0.0, 0.0], "Power": [1.0, 1.0, 1.0, 1.0], "Saturation": [1.0, 1.0, 1.0, 1.0]}
        )

if __name__ == '__main__':
    unittest.main()
