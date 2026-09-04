"""Poste WebSocket test server — a JSON-aware echo service.

Behavior per inbound text frame:
  {"type": "ping"}                      -> {"type": "pong", "ts": ...}
  {"type": "subscribe", "channel": X}   -> {"type": "subscribed", "channel": X}
  {"type": "emit", "channel": X}        -> 3 pushed {"type": "message"} frames
  anything else                         -> echoed back verbatim

Non-JSON frames are echoed verbatim, so manual batch tests have predictable
output. Accepts (but does not require) client subprotocols.
"""

import asyncio
import json
import os
import time

import websockets

PUSH_COUNT = 3


async def handler(ws):
    async for message in ws:
        reply = None
        try:
            data = json.loads(message)
            kind = data.get("type") if isinstance(data, dict) else None
            if kind == "ping":
                reply = json.dumps({"type": "pong", "ts": time.time()})
            elif kind == "subscribe":
                await ws.send(json.dumps({
                    "type": "subscribed",
                    "channel": data.get("channel") or "default",
                }))
                continue
            elif kind == "emit":
                channel = data.get("channel") or "default"
                for seq in range(PUSH_COUNT):
                    await ws.send(json.dumps({
                        "type": "message", "channel": channel, "seq": seq,
                    }))
                continue
        except (ValueError, AttributeError):
            pass
        if reply is None:
            reply = message
        await ws.send(reply)


async def main():
    port = int(os.environ.get("POSTE_WS_PORT", "8892"))
    async with websockets.serve(handler, "0.0.0.0", port):
        print(f"poste-ws-echo listening on :{port}", flush=True)
        await asyncio.Future()


asyncio.run(main())
