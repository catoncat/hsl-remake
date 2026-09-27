"""Minimal TypeSafe System One client for repository tools.

Jev answers typed questions (choice / score / noul) about a text state and returns
calibrated probabilities. It does not run code, read images or generate text. Use it
to offload many small semantic judgments that would otherwise cost an LLM agent
thousands of tokens; keep exact facts (counts, offsets, arithmetic) in code
(hsltools.checks.function_catalog judges decompiled functions through system_one_many).

The API key is read from TYPESAFE_API_KEY only. Never write the key to disk. With
jiantieban run: jiantieban resolve jt://secret/<id> --env TYPESAFE_API_KEY --exec <cmd>.
The command line is tools/hsl_typesafe_client.py (models / ask).
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import os
import time
import urllib.error
import urllib.request

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
MODELS_ENDPOINT = "https://api.typesafe.ai/v1/models"
DEFAULT_MODEL = "jev-latest"
ENV_KEY = "TYPESAFE_API_KEY"
# Documented limits: ~64k tokens for state+questions, 32k for state+longest question.
STATE_CHAR_BUDGET = 110000


class TypeSafeError(RuntimeError):
    pass


def api_key() -> str:
    key = os.environ.get(ENV_KEY, "").strip()
    if not key:
        raise TypeSafeError(
            f"{ENV_KEY} is not set. Run through jiantieban: "
            f"jiantieban resolve jt://secret/<id> --env {ENV_KEY} --exec <command>"
        )
    return key


def _post(url: str, body: dict | None, key: str, timeout: float) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        method="POST" if data is not None else "GET",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def system_one(
    state,
    questions: dict,
    *,
    model: str = DEFAULT_MODEL,
    retries: int = 5,
    timeout: float = 60.0,
) -> dict:
    """POST one state and a map of questions; return the parsed response.

    Retries 429/529/5xx with exponential backoff. Raises TypeSafeError for
    validation (422) and authentication (401) failures because retrying cannot fix them.
    """
    key = api_key()
    body = {"state": state, "model": model, "questions": questions}
    delay = 1.0
    for attempt in range(retries + 1):
        try:
            return _post(ENDPOINT, body, key, timeout)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:500]
            if error.code in (400, 401, 422):
                raise TypeSafeError(f"HTTP {error.code}: {detail}") from None
            if attempt == retries:
                raise TypeSafeError(f"HTTP {error.code} after {retries} retries: {detail}") from None
            retry_after = error.headers.get("retry-after") if error.headers else None
            time.sleep(float(retry_after) if retry_after else delay)
            delay = min(delay * 2, 30.0)
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            if attempt == retries:
                raise TypeSafeError(f"connection failed after {retries} retries: {error}") from None
            time.sleep(delay)
            delay = min(delay * 2, 30.0)
    raise TypeSafeError("unreachable")


def system_one_many(jobs: list[tuple], *, model: str = DEFAULT_MODEL, workers: int = 8) -> list:
    """Evaluate many independent (state, questions) jobs concurrently.

    Returns one entry per job: the response dict, or a dict with an 'error' key.
    """
    def run(job):
        state, questions = job
        try:
            return system_one(state, questions, model=model)
        except TypeSafeError as error:
            return {"error": str(error)}

    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(run, jobs))


def list_models() -> dict:
    return _post(MODELS_ENDPOINT, None, api_key(), 30.0)
