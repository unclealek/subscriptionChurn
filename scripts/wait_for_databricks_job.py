import json
import os
import sys
import time
import urllib.error
import urllib.request


def databricks_request(path: str, payload: dict | None = None) -> dict:
    host = os.environ["DATABRICKS_HOST"].rstrip("/")
    token = os.environ["DATABRICKS_TOKEN"]
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = urllib.request.Request(
        f"{host}{path}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST" if payload is not None else "GET",
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        raise RuntimeError(f"Databricks API request failed: {exc.code} {body}") from exc


def main() -> int:
    job_id = os.environ["DATABRICKS_JOB_ID"]
    timeout_seconds = int(os.getenv("DATABRICKS_RUN_TIMEOUT_SECONDS", "7200"))
    poll_seconds = int(os.getenv("DATABRICKS_RUN_POLL_SECONDS", "30"))

    run_response = databricks_request("/api/2.1/jobs/run-now", {"job_id": int(job_id)})
    run_id = run_response["run_id"]
    print(f"Triggered Databricks job {job_id}, run_id={run_id}")

    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        run = databricks_request(f"/api/2.1/jobs/runs/get?run_id={run_id}")
        state = run.get("state", {})
        life_cycle_state = state.get("life_cycle_state")
        result_state = state.get("result_state")
        state_message = state.get("state_message", "")
        print(f"run_id={run_id} life_cycle_state={life_cycle_state} result_state={result_state} {state_message}")

        if life_cycle_state in {"TERMINATED", "SKIPPED", "INTERNAL_ERROR"}:
            if result_state == "SUCCESS":
                return 0
            print(json.dumps(state, indent=2))
            return 1

        time.sleep(poll_seconds)

    print(f"Timed out waiting for Databricks run_id={run_id}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
