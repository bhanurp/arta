#!/usr/bin/env python3
"""Emit example lifecycle events; no agent service or third-party dependency required."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("kind", choices=["turn.started", "turn.completed", "input.requested", "input.resolved"])
parser.add_argument("--session", default="example-session")
parser.add_argument("--turn", default="example-turn")
parser.add_argument("--request", default="example-question")
args = parser.parse_args()
root = Path(os.environ.get("ARTA_DATA_DIR", str(Path.home() / "Library/Application Support/ClaudeCompanion")))
inbox = root / "events-v1" / "example-agent"
inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
event = dict(schemaVersion=1, eventID=str(uuid.uuid4()), integrationID="example-agent",
             sourceInstanceID="local", sessionID=args.session, runID="example-run",
             kind=args.kind, occurredAt=time.time(), turnID=args.turn,
             project=str(Path.cwd()), message="Example agent event")
if args.kind.startswith("input."):
    event["requestID"] = args.request
filename = hashlib.sha256(event["eventID"].encode()).hexdigest() + ".json"
temporary = inbox / (filename + ".tmp")
fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as handle:
    json.dump(event, handle)
os.replace(temporary, inbox / filename)
print("Example event queued locally.")
