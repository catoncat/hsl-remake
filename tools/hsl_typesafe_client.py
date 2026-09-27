#!/usr/bin/env python3
"""TypeSafe System One command line: `models` lists the models the key can use, `ask` evaluates a
JSON request file {state, questions[, model]} (`--dry-run` validates the shape without network).
The client is hsltools.typesafe; the key comes from TYPESAFE_API_KEY only.
"""
from __future__ import annotations

import argparse
import json
import sys

from hsltools.typesafe import DEFAULT_MODEL, list_models, system_one


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("models", help="list models available to the key")
    ask = sub.add_parser("ask", help="evaluate a JSON request file {state, questions[, model]}")
    ask.add_argument("request", help="path to JSON with state and questions, or - for stdin")
    ask.add_argument("--model", default=None)
    ask.add_argument("--dry-run", action="store_true", help="validate the request shape without network")
    args = parser.parse_args()
    if args.command == "models":
        print(json.dumps(list_models(), indent=2, ensure_ascii=False))
        return 0
    raw = sys.stdin.read() if args.request == "-" else open(args.request, encoding="utf-8").read()
    request = json.loads(raw)
    questions = request["questions"]
    if not isinstance(questions, dict) or not questions:
        raise SystemExit("questions must be a non-empty object")
    for name, question in questions.items():
        if question.get("type") not in ("choice", "score", "noul") or "instructions" not in question:
            raise SystemExit(f"question {name!r} needs type choice|score|noul and instructions")
    if args.dry_run:
        print(f"TYPESAFE_REQUEST_OK questions={len(questions)} state_chars={len(json.dumps(request['state'], ensure_ascii=False))}")
        return 0
    response = system_one(request["state"], questions, model=args.model or request.get("model", DEFAULT_MODEL))
    print(json.dumps(response, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
