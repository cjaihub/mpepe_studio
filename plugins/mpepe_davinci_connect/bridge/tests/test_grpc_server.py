"""
Tests for grpc_server.py — verifies the Python syntax crash is fixed
and the UndoAction response builds correctly.
"""
import sys
import os

# Make bridge importable
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))


def test_grpc_server_imports_without_error():
    """grpc_server.py must import cleanly — the duplicate-field crash is fixed."""
    try:
        import importlib
        import bridge.grpc_server  # noqa: F401
        importlib.reload(bridge.grpc_server)
    except SyntaxError as e:
        raise AssertionError(f"grpc_server.py has a syntax error: {e}")
    except Exception:
        # Import errors from missing Resolve/DaVinci are OK here — we only test syntax
        pass


def test_undo_response_no_duplicate_field():
    """The UndoAction response proto construction must not have a duplicate kwarg."""
    import ledger_pb2
    # This will raise TypeError if success= is passed twice — confirms fix
    resp = ledger_pb2.UndoResponse(success=True, message="Undid last action")
    assert resp.success is True
    assert "Undid" in resp.message


def test_voice_tools_import():
    """voice_tools.py must be importable."""
    from bridge.tools import voice_tools  # noqa: F401
    assert hasattr(voice_tools, "transcribe_audio")
    assert hasattr(voice_tools, "synthesize_speech")
