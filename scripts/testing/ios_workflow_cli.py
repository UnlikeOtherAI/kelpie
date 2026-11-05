"""Drive the built CLI entry point against the disposable, paired iOS simulator fixture."""
import hashlib
import json
import re
import subprocess
from pathlib import Path


def invoke(args, timeout=60):
    command = ["node", "packages/cli/bin/kelpie.js", "--device", "127.0.0.1:28429",
               "--format", "json", "--timeout", "45000", *args]
    result = subprocess.run(command, capture_output=True, timeout=timeout)
    if result.returncode:
        # Pairing and transport stdout/stderr never enter the uploaded evidence.
        code = "CLI_FAILURE"
        try:
            body = json.loads(result.stdout)
            value = body.get("result", body).get("error", {}).get("code")
            if isinstance(value, str) and re.fullmatch("[A-Z0-9_]{1,80}", value):
                code = value
        except (ValueError, AttributeError):
            pass
        raise RuntimeError(f"{args[0]} exited {result.returncode} ({code})")
    return json.loads(result.stdout)


def run_fixture(tab: str, evidence: Path):
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", tab):
        raise ValueError("Invalid fixture tab ID")
    evidence.mkdir(parents=True, exist_ok=False)
    paired = invoke(["pair", "--client-name", "Hosted CLI workflow", "--timeout-ms", "35000"])
    if paired.get("success") is not True:
        raise ValueError("CLI pairing refused")
    recipe = {"version": 1, "tabId": tab, "inputs": {"entry": {"type": "string"}}, "actions": [
        {"action": "fill", "target": {"label": "Entry"}, "text": {"input": "entry"}},
        {"action": "tap", "target": {"role": "button", "name": "Submit"}},
        {"action": "output", "name": "page", "source": "title"},
        {"action": "screenshot", "name": "afterClick"}],
        "capture": {"formats": ["screenshots", "gif", "video"], "fps": 8, "maxWidth": 384},
        "tapIndicator": {"color": "#00FF00", "radius": 22}}
    recipe_path = evidence / "recipe.json"
    inputs_path = evidence / "inputs.json"
    recipe_path.write_text(json.dumps(recipe))
    inputs_path.write_text(json.dumps({"entry": "Hosted typed input"}))
    played = invoke(["script", "run", str(recipe_path), "--inputs", str(inputs_path), "--output", str(evidence / "downloads")])
    result = played["result"]
    if not result["success"] or result["outputs"].get("page") != "Count 1":
        raise ValueError("CLI workflow outcome did not match the click")
    run_id = result["runId"]
    status = invoke(["script", "status", "--run-id", run_id, "--pinned"])
    if status.get("state") != "completed" or status.get("runSuccess") is not True or "outputs" in status:
        raise ValueError("Pinned CLI status did not recover metadata")
    manifests = {item["id"]: item for item in result["artifacts"]}
    if {item["mimeType"] for item in manifests.values()} != {"image/png", "image/gif", "video/mp4"}:
        raise ValueError("Missing CLI capture format")
    if {item["id"] for item in played["downloaded"]} != set(manifests):
        raise ValueError("CLI download set differs from manifest")
    records = []
    for downloaded in played["downloaded"]:
        manifest = manifests[downloaded["id"]]
        path = Path(downloaded["file"]).resolve()
        if evidence.resolve() not in path.parents:
            raise ValueError("Unexpected artifact destination")
        blob = path.read_bytes()
        digest = hashlib.sha256(blob).hexdigest()
        if digest != manifest["sha256"] or len(blob) != manifest["byteLength"]:
            raise ValueError("Downloaded bytes do not match manifest")
        records.append({"mimeType": manifest["mimeType"], "file": str(path.relative_to(evidence)),
                        "bytes": len(blob), "sha256": digest})
    (evidence / "report.json").write_text(json.dumps({"passed": True, "state": status["state"],
        "runId": run_id, "artifacts": records}, indent=2))
