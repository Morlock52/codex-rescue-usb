from __future__ import annotations

import argparse
from pathlib import Path

from codex_rescue.fixtures import FixtureRepository
from codex_rescue.http_server import build_server
from codex_rescue.service import CaseService


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the fixture-only Rescue Console")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    service = CaseService(FixtureRepository(root / "fixtures"))
    server = build_server(service, root / "web", port=args.port)
    print(f"Codex Rescue USB fixture console: http://127.0.0.1:{server.server_port}")
    print("Fixture-only simulation. Host commands and disk writes are disabled.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
