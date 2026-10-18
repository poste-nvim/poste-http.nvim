# Poste Playground

Local backends and `.http` scenarios for manually exercising every protocol
Poste speaks. All services live behind **one** compose file, so a single command
brings the whole playground up.

## Services

| Service | Port | What it gives you |
|---------|------|-------------------|
| `http` | 8888 | httpbin-like HTTP server — echo, auth, upload, streaming, redirects, a stateful `/api/*` demo |
| `graphql` | 8890 | Real graphql-js engine: `hello`, `user(id)`, `add` mutation, validation errors |
| `grpc` | 8891 | grpcio with **server reflection**: `EchoService` (unary/stream/fail) + `OrderService` (rich types) |
| `websocket` | 8892 | JSON-aware echo: `ping` → pong, `subscribe` → ack, `emit` → 3 frames |

## Quick Start

```bash
# From the repo root — build and start everything
docker compose -f playground/docker-compose.yml up -d --build

# Health
curl -s localhost:8888/health
curl -s localhost:8890/health

# Follow logs
docker compose -f playground/docker-compose.yml logs -f

# Stop everything
docker compose -f playground/docker-compose.yml down
```

Or `cd playground` first and drop the `-f playground/docker-compose.yml` prefix.

Start only what you need by naming services:

```bash
docker compose -f playground/docker-compose.yml up -d http              # HTTP only
docker compose -f playground/docker-compose.yml up -d graphql grpc websocket
```

## Layout

```
playground/
├── docker-compose.yml       All four backends (one command to start them all)
├── README.md                (this file)
├── http/
│   ├── server/              FastAPI test server + Dockerfile
│   ├── scenarios/           .http files for HTTP features
│   └── data/                Fixtures (txt, Lua vars, env.json)
└── multi-protocol/
    ├── graphql|grpc|websocket/server/   Per-protocol backends + Dockerfiles
    └── scenarios/           .http files for GRAPHQL, GRPC, WEBSOCKET
```

## Where to go next

- **HTTP features** — [`http/README.md`](http/README.md)
- **GRAPHQL / GRPC / WEBSOCKET** — [`multi-protocol/README.md`](multi-protocol/README.md)
- **Running the server directly** — [`http/server/README.md`](http/server/README.md)

## No Docker?

The scenarios target the local services: everything runs offline once the
compose stack is up. A few examples under [`../examples/http/`](../examples/http/)
additionally demo public APIs (GitHub, pokeapi) that need network access.
