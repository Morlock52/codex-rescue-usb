from __future__ import annotations

import argparse
from pathlib import Path

from codex_rescue.case_store import JsonlCaseStore
from codex_rescue.fixtures import FixtureRepository
from codex_rescue.http_server import build_server
from codex_rescue.service import CaseService


def valid_port(value: str) -> int:
    port = int(value)
    if not 0 <= port <= 65_535:
        raise argparse.ArgumentTypeError("port must be between 0 and 65535")
    return port


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the fixture-only Rescue Console")
    parser.add_argument("--port", type=valid_port, default=8080)
    parser.add_argument(
        "--case-dir",
        type=Path,
        default=Path.home() / ".codex-rescue" / "cases",
        help="directory for append-only fixture audit logs",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    service = CaseService(
        FixtureRepository(root / "fixtures"),
        case_store=JsonlCaseStore(args.case_dir),
    )
    server = build_server(service, root / "web", port=args.port)
    print(f"Codex Rescue USB fixture console: http://127.0.0.1:{server.server_port}")
    print("Fixture-only simulation. Host commands and disk writes are disabled.")
    print(f"Fixture audit logs: {args.case_dir.resolve()}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
