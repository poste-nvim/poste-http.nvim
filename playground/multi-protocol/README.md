# Multi-Protocol Playground

Local backends for manually testing Poste's non-HTTP protocols: GRAPHQL,
GRPC, and WEBSOCKET. HTTP testing lives in [the HTTP playground](../http/README.md).

## Services

| Service | Port | What it gives you |
|---------|------|-------------------|
| `graphql` | 8890 | Real graphql-js engine: `hello`, `user(id)` with variables, `add` mutation, validation errors envelope |
| `grpc` | 8891 | grpcio echo with **server reflection**: unary `Echo` (echoes metadata), server-streaming `EchoStream`, `Fail` RPC returning a controllable status code |
| `websocket` | 8892 | JSON-aware echo: `{"type":"ping"}` → pong, `{"type":"subscribe"}` → ack, `{"type":"emit"}` → 3 pushed frames, anything else echoed verbatim |

## Quick Start

```bash
# Start all three (builds on first run)
docker compose -f playground/multi-protocol/docker-compose.yml up -d --build

# Health checks
curl -s localhost:8890/health
docker compose -f playground/multi-protocol/docker-compose.yml exec grpc \
  python -c "import grpc; grpc.channel_ready_future(grpc.insecure_channel('localhost:8891')).result(timeout=3); print('grpc ok')"

# Stop
docker compose -f playground/multi-protocol/docker-compose.yml down
```

## Manual testing from Poste

Client tools are needed for two of the protocols (Poste checks them with
`:checkhealth poste-http`):

```bash
brew install grpcurl websocat
```

Then open the scenario file and execute requests with the cursor on them:

```
playground/multi-protocol/scenarios/multi_protocol_demo.http
```

What to look for per protocol:

- **GRAPHQL** — requests execute as POST; the Body tab shows the
  `{data}` / `{errors}` envelope; `{{Name.response.body.data.user.name}}`
  references work (see the variables request).
- **GRPC** — headers become metadata (the unary echo returns them in
  `response.metadata`... `metadata` map inside the message); the streaming
  request appends three frames to the body; the `Fail` request shows
  status 5 (NotFound) with the error indicator.
- **WEBSOCKET** — the Msgs tab (`M`) shows `→` sent / `←` received frames;
  the interactive request streams frames live (`s` to send, `c` to close).

No docker? The same scenarios mostly work against public endpoints
(e.g. `https://swapi-graphql.netlify.app/.netlify/functions/index` for
GraphQL), but the local services are deterministic and offline.
