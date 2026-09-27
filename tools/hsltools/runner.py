"""Deterministic parallel job runner shared by tools/hsl.py and tools/verify_runner.py.

A job is (name, thunk); thunk() returns (exit code, output, seconds). Result lines are
printed sorted after every job finished, a failing job prints its full log, and a
heartbeat streams progress while running. Only the summary line differs per caller.
"""
from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Callable

Result = tuple[int, str, float]
Job = tuple[str, Callable[[], Result]]


def last_line(output: str) -> str:
    lines = [line for line in output.splitlines() if line.strip()]
    return lines[-1] if lines else "(no output)"


def run_parallel(label: str, jobs: list[Job], workers: int, summary_line: Callable[[str, str, float], str]) -> int:
    started = time.monotonic()
    results: dict[str, Result] = {}
    failures: list[str] = []
    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futures = {pool.submit(thunk): name for name, thunk in jobs}
        done = 0
        progress_every = max(1, len(jobs) // 20)
        for future in as_completed(futures):
            name = futures[future]
            code, output, seconds = future.result()
            results[name] = (code, output, seconds)
            done += 1
            if code == 0 and (done % progress_every == 0 or done == len(jobs) or seconds >= 30):
                print(f"[{label} {done}/{len(jobs)} {time.monotonic() - started:.0f}s] ok {name} ({seconds:.0f}s)", flush=True)
            if code != 0:
                failures.append(name)
                print(f"[{label} FAIL {done}/{len(jobs)} {seconds:.0f}s] {name}", flush=True)
                print(output.rstrip(), flush=True)
                print(f"[end of {name}]", flush=True)
    for name in sorted(results):
        code, output, seconds = results[name]
        if code == 0:
            print(summary_line(name, output, seconds), flush=True)
    elapsed = time.monotonic() - started
    if failures:
        print(f"{label}_FAIL failed={len(failures)} of={len(jobs)} seconds={elapsed:.0f}", flush=True)
        for name in failures:
            print(f"  FAILED: {name}", flush=True)
        return 1
    print(f"{label}_PASS jobs={len(jobs)} workers={workers} seconds={elapsed:.0f}", flush=True)
    return 0
