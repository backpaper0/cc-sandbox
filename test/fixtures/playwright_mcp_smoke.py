#!/usr/bin/env python3
"""Exercise Playwright MCP over its public stdio JSON-RPC transport."""

import glob
import json
import os
import select
import subprocess
import sys
import time


def send(process, message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()


def receive(process, request_id, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        ready, _, _ = select.select([process.stdout], [], [], deadline - time.monotonic())
        if not ready:
            break
        line = process.stdout.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                raise RuntimeError(json.dumps(message["error"]))
            return message["result"]
    raise TimeoutError(f"no MCP response for request {request_id}")


def call(process, request_id, method, params):
    send(
        process,
        {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params},
    )
    result = receive(process, request_id)
    if result.get("isError"):
        raise RuntimeError(json.dumps(result))
    return result


def main():
    output_dir = "/tmp/playwright-mcp-output"
    os.makedirs(output_dir, exist_ok=True)
    existing_screenshots = set(glob.glob(os.path.join(output_dir, "*.png")))

    server = subprocess.Popen(
        [
            "playwright-mcp",
            "--headless",
            "--browser",
            "chromium",
            "--no-sandbox",
            "--output-dir",
            output_dir,
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    try:
        send(
            server,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "sandbox-e2e", "version": "1"},
                },
            },
        )
        receive(server, 1)
        send(server, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        navigation = call(
            server,
            2,
            "tools/call",
            {
                "name": "browser_navigate",
                "arguments": {"url": "http://127.0.0.1:4173"},
            },
        )
        if "Ticket 10 Playwright MCP" not in json.dumps(navigation):
            raise RuntimeError("navigation result did not contain the fixture page title")

        screenshot_result = call(
            server,
            3,
            "tools/call",
            {
                "name": "browser_take_screenshot",
                "arguments": {},
            },
        )
        new_screenshots = set(glob.glob(os.path.join(output_dir, "*.png"))) - existing_screenshots
        if not new_screenshots or not all(os.path.getsize(path) for path in new_screenshots):
            raise RuntimeError(
                "Playwright MCP did not produce a screenshot: "
                + json.dumps(screenshot_result)
            )
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(error, file=sys.stderr)
        sys.exit(1)
