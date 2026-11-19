import sys
import os
import unittest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from orchestrator.suggestion_engine import SuggestionEngine

class TestSuggestionEngine(unittest.TestCase):
    def setUp(self):
        self.mock_provider = MagicMock()
        self.engine = SuggestionEngine(self.mock_provider)

    def test_generate_suggestions(self):
        self.mock_provider.analyze_image.return_value = {
            "content": '{"suggestions": [{"text": "Lift shadows", "prompt": "lift shadows", "category": "exposure", "confidence": 0.9}]}'
        }
        
        suggestions = self.engine.generate_suggestions(b"fakebytes", "[]", "Last action: set CDL")
        
        self.assertEqual(len(suggestions), 1)
        self.assertEqual(suggestions[0]["prompt"], "lift shadows")
        self.mock_provider.analyze_image.assert_called_once()
        
    def test_generate_suggestions_no_frame(self):
        suggestions = self.engine.generate_suggestions(b"", "[]", "")
        self.assertEqual(len(suggestions), 0)

if __name__ == '__main__':
    unittest.main()
