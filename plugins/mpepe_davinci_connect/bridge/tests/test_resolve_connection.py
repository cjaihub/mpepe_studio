import sys
import os
import unittest
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

class TestResolveConnection(unittest.TestCase):
    def setUp(self):
        # Reset globals before each test
        import bridge.resolve_connection as rc
        rc._resolve_singleton = None
        rc._resolve_version = "Unknown"
        rc._is_studio = False

    def test_init_resolve_success(self):
        # Create a mock Resolve script app
        mock_bmd = MagicMock()
        mock_resolve = MagicMock()
        mock_resolve.GetVersionString.return_value = "21.1.0"
        mock_bmd.scriptapp.return_value = mock_resolve
        
        # Inject into sys.modules
        sys.modules["DaVinciResolveScript"] = mock_bmd
        
        import bridge.resolve_connection as rc
        
        resolve = rc.init_resolve()
        
        self.assertIsNotNone(resolve)
        self.assertEqual(rc._resolve_version, "21.1.0")
        self.assertTrue(rc._is_studio)
        
        # Cleanup
        del sys.modules["DaVinciResolveScript"]
        
    def test_init_resolve_failure_graceful(self):
        # Ensure it's not in sys.modules
        if "DaVinciResolveScript" in sys.modules:
            del sys.modules["DaVinciResolveScript"]
            
        import bridge.resolve_connection as rc
        
        # Temporarily alter environ so it doesn't find the real one if it exists
        original_env = os.environ.get("RESOLVE_SCRIPT_API")
        os.environ["RESOLVE_SCRIPT_API"] = "/fake/path/that/does/not/exist"
        
        resolve = rc.init_resolve()
        
        self.assertIsNone(resolve)
        
        if original_env is not None:
            os.environ["RESOLVE_SCRIPT_API"] = original_env
        else:
            del os.environ["RESOLVE_SCRIPT_API"]

    def test_get_capabilities_unconnected(self):
        import bridge.resolve_connection as rc
        rc._resolve_singleton = None
        
        caps = rc.get_capabilities()
        
        self.assertFalse(caps["is_connected"])
        self.assertFalse(caps["is_studio"])
        self.assertFalse(caps["has_magic_mask"])
        self.assertEqual(caps["resolve_version"], "Not Connected")
        self.assertNotEqual(caps["error_message"], "")

if __name__ == '__main__':
    unittest.main()
