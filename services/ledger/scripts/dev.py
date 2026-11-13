"""Runs the ledger locally on a throwaway Postgres (pgserver): no auth, local only.

  .venv/bin/python scripts/dev.py [port]
Then point Cloud Functions (or the contract test) at LEDGER_URL=http://localhost:<port>.
"""
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pgserver  # noqa: E402
import uvicorn  # noqa: E402

from ledger import db  # noqa: E402

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
srv = pgserver.get_server(os.environ.get("LEDGER_PGDATA") or tempfile.mkdtemp(prefix="ledger-dev-"), cleanup_mode="stop")
os.environ.update(DATABASE_URL=srv.get_uri(), LEDGER_ENV="local", LEDGER_AUTH="off")
with db.connect() as conn:
    print("migrations applied:", db.migrate(conn) or "none")
uvicorn.run("ledger.api:app", host="127.0.0.1", port=port)
