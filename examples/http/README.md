# Poste HTTP Examples

Feature-oriented `.http` examples. Everything runs against the local
playground HTTP server unless a file says otherwise:

```bash
docker compose -f playground/docker-compose.yml up -d http   # :8888
```

Then open a file in Neovim, put the cursor on a request line and press
`<CR>` (or `:PosteHttpRun`). Requests run top to bottom; a few blocks
depend on earlier ones (they say so in a comment).

| File | What it shows |
|------|---------------|
| `getting_started.http` | start here: request shapes, pre/post scripts, assertions, `@var` override, magic vars, `import`/`run` |
| `variables.http` | file-level vs request-level variables |
| `magic_vars.http` | `{{$uuid}}`, `{{$timestamp}}`, `{{$date}}`, `{{$randomInt}}` with assertions |
| `request_vars.http` | response chaining: `{{Name.response.body...}}` |
| `form_data.http` | url-encoded form, multipart upload, `< file` includes |
| `scripts.http` | pre/post scripts, external script files, `client.global` |
| `assertions.http` | `client.test` blocks, including an intentional failure |
| `feature_suite.http` | the full feature verification suite: numbered blocks, per-feature assertions, visual checks |
| `md5_auth.http` | `md5()` sandbox function |
| `env_vars.http` | `env.json` environments (`{{base_url}}`, `{{api_key}}`) |
| `prompt_variables.http` | interactive `<<prompt` inputs (public API: pokeapi) |
| `prompt_completion.http` | short/medium/long option lists for prompts |
| `dynamic_prompts.http` | prompt options computed from a previous response (public API: GitHub) |
| `global_header.http` + `global_header_flow.http` | persistent global headers + a `client.run` flow over them |
| `helper_auth.http`, `helper_batch.http`, `fixtures/` | import targets used by `getting_started.http` / `feature_suite.http` |

Public-API examples (`prompt_variables.http`, `dynamic_prompts.http`) need
internet access; everything else is fully local.

## Multi-protocol

Everything above speaks plain HTTP. GRAPHQL, GRPC and WebSocket scenarios
live in the playground:
[`../../playground/multi-protocol/scenarios/multi_protocol_demo.http`](../../playground/multi-protocol/scenarios/multi_protocol_demo.http)
— start those services with
`docker compose -f playground/docker-compose.yml up -d --build`, and install
`grpcurl` / `websocat` (`:checkhealth poste-http` verifies them for you).
