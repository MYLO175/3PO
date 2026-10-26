#!/usr/bin/env python3
"""Print a read-only digest of 3PO's saved records: each key with its byte
size and SHA-256, never the record contents. Used by install.sh to prove an
installation left personal records unchanged."""
import hashlib
import json
import sqlite3
import sys
from pathlib import Path

store = Path(sys.argv[1])
if not store.exists():
    print(json.dumps({"records": {}, "count": 0}))
    sys.exit(0)
connection = sqlite3.connect(f"file:{store}?mode=ro", uri=True)
table = next(name for (name,) in connection.execute("select name from sqlite_master where type='table'") if name.upper() == "ZCACHEDDASHBOARD")
records = {key: {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
           for key, data in connection.execute(f"select ZKEY, ZDATA from {table}")}
print(json.dumps({"records": records, "count": len(records)}, sort_keys=True, indent=1))
