"""Pytest configuration — makes container/app.py importable as `app`."""
import sys
from pathlib import Path

# tests/ lives at container/tests/; container/ is the parent and holds app.py.
CONTAINER_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(CONTAINER_DIR))
