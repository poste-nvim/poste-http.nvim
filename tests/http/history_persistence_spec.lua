-- Tests for history disk persistence (F21).
--
-- Covers: serialization round-trip (save → load), `_jq` transient state not
-- persisted, id counter restored from the loaded max id, cap enforcement on
-- load, and respect for the persist_history toggle.

local history = require("poste-http.http.history")
local state = require("poste-http.state")
local format = require("poste-http.http.format")

local tmp_dir = "/private/tmp/poste-history-test"

local function reset()
  state.http_history = {}
  state.http_history_id_counter = 0
  state.config.persist_history = true
  state.config.history_file = tmp_dir .. "/history.json"
  os.remove(tmp_dir .. "/history.json")
end

describe("history persistence", function()
  before_each(reset)

  it("persists entries to disk on add and restores them via load", function()
    local resp = { status = 200, body = "{\"ok\":true}", headers = {}, metadata = { method = "GET" } }
    history.add_entry("GetUser", resp, nil, nil, "/tmp/user.http")

    state.http_history = {}
    state.http_history_id_counter = 0

    history.load()

    assert.equals(1, #state.http_history)
    assert.equals("GetUser", state.http_history[1].name)
    assert.equals(200, state.http_history[1].response.status)
    assert.equals("{\"ok\":true}", state.http_history[1].response.body)
    assert.equals("/tmp/user.http", state.http_history[1].source_file)
  end)

  it("restores the id counter to the max loaded id", function()
    history.add_entry("A", { status = 200, metadata = {} })
    history.add_entry("B", { status = 201, metadata = {} })

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    assert.equals(2, state.http_history_id_counter)
    history.add_entry("C", { status = 204, metadata = {} })
    assert.equals("C", state.http_history[1].name)
    assert.equals(3, state.http_history[1].id)
  end)

  it("keeps newest-first order after a load/add cycle", function()
    history.add_entry("Old", { status = 200, metadata = {} })
    history.add_entry("New", { status = 201, metadata = {} })

    state.http_history = {}
    history.load()
    assert.equals("New", state.http_history[1].name)
    assert.equals("Old", state.http_history[2].name)
  end)

  it("drops the transient _jq field when persisting", function()
    local entry_payload = { status = 200, body = "{}", metadata = {} }
    history.add_entry("JqEntry", entry_payload)
    state.http_history[1]._jq = { query = ".foo", original_lines = { "x", "y" } }
    local in_memory = state.http_history[1]

    -- The realistic leak: a LATER add re-persists the whole list, so the
    -- earlier entry's _jq (set after its own add) must be stripped then —
    -- not just absent because the file predates it.
    history.add_entry("Later", { status = 201, metadata = {} })

    state.http_history = {}
    history.load()

    assert.is_nil(state.http_history[1]._jq)
    assert.is_nil(state.http_history[2]._jq)
    assert.equals("{}", state.http_history[2].response.body)
    -- the live in-memory entry keeps its filter state
    assert.equals(".foo", in_memory._jq.query)
  end)

  it("respects persist_history=false (no file written)", function()
    state.config.persist_history = false
    history.add_entry("NoPersist", { status = 200, metadata = {} })

    assert.equals(0, vim.fn.filereadable(tmp_dir .. "/history.json"))
    assert.equals(1, #state.http_history)
  end)

  it("applies http_history_max cap after loading a larger file", function()
    for i = 1, 5 do
      history.add_entry("Req" .. i, { status = 200, metadata = {} })
    end

    state.http_history = {}
    state.config.http_history_max = 3
    history.load()

    assert.equals(3, #state.http_history)
    assert.equals("Req5", state.http_history[1].name)
    assert.equals("Req3", state.http_history[3].name)
  end)

  it("delete_entry persists the removal", function()
    history.add_entry("A", { status = 200, metadata = {} })
    history.add_entry("B", { status = 201, metadata = {} })

    state.http_history = {}
    history.load()
    assert.equals(2, #state.http_history)

    history.delete_entry(state.http_history[1].id)
    state.http_history = {}
    history.load()

    assert.equals(1, #state.http_history)
    assert.equals("A", state.http_history[1].name)
  end)

  it("load is a no-op when the file does not exist", function()
    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()
    assert.equals(0, #state.http_history)
    assert.equals(0, state.http_history_id_counter)
  end)

  it("load tolerates corrupt JSON without crashing", function()
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write("{ not valid json !!!")
    fd:close()

    state.http_history = {}
    history.load()

    assert.equals(0, #state.http_history)
  end)

  it("skips entries with a non-numeric id but keeps the rest", function()
    -- One hand-edited "id": "abc" used to throw on `e.id > max_id`; the
    -- setup pcall swallowed it and every entry silently vanished.
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = "abc", name = "corrupt" },
      { id = 7, name = "good" },
      { name = "idless" },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    assert.equals(1, #state.http_history)
    assert.equals("good", state.http_history[1].name)
    assert.equals(7, state.http_history_id_counter)
  end)

  it("clear wipes the ring, the id counter, and the persisted file", function()
    history.add_entry("A", { status = 200, metadata = {} })
    history.add_entry("B", { status = 200, metadata = {} })
    assert.equals(2, #state.http_history)
    assert.equals(1, vim.fn.filereadable(tmp_dir .. "/history.json"))

    history.clear()

    assert.equals(0, #state.http_history)
    assert.equals(0, state.http_history_id_counter)
    assert.equals(0, vim.fn.filereadable(tmp_dir .. "/history.json"))
    -- the next run starts from a clean, fresh file
    history.add_entry("C", { status = 200, metadata = {} })
    assert.equals(1, #state.http_history)
    assert.equals(1, state.http_history_id_counter)
  end)

  it("load drops drifted inner fields instead of shipping them to the views", function()
    -- Regression: the detail views index entry.response / #script_logs /
    -- the assertions shape as tables. A hand-edited or old-format entry
    -- (response = 42, script_logs = "x", assertion_results = 7) used to
    -- reach format_view verbatim and raise mid-render; the entry itself
    -- (name/time) stays listed.
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = 99, name = "drifted", time = os.time(),
        response = 42, script_logs = "not-a-table", assertion_results = 7 },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    assert.equals(1, #state.http_history)
    local e = state.http_history[1]
    assert.equals("drifted", e.name, "the entry survives the sanitize")
    assert.is_nil(e.response, "a non-table response is dropped at the boundary")
    assert.is_nil(e.script_logs, "non-table script logs are dropped")
    assert.is_nil(e.assertion_results, "non-table assertion results are dropped")
    assert.equals(99, state.http_history_id_counter)
  end)

  it("load drops drifted INNER response fields, and the views still render", function()
    -- Regression: the boundary checked response as a whole but not its
    -- inner fields — a hand-edited {"headers": 42} / {"body": 7} /
    -- {"content_type": 8} / {"metadata": "x"} sailed through and raised
    -- mid-render in format_view (ipairs over a number, # on a number).
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = 5, name = "inner", time = os.time(),
        response = { status = 200, headers = 42, body = 7, content_type = 8, metadata = "x" } },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    local r = state.http_history[1].response
    assert.equals(200, r.status, "well-typed fields survive")
    assert.is_nil(r.headers)
    assert.is_nil(r.body)
    assert.is_nil(r.content_type)
    assert.is_nil(r.metadata)

    -- Every detail view renders the sanitized entry instead of crashing.
    for _, view in ipairs({ "body", "verbose", "request" }) do
      assert.has_no_errors(function()
        format.format_view(view, r, {})
      end)
    end
  end)

  it("load drops malformed header ENTRIES, not just a non-table headers field", function()
    -- Regression: the boundary checked `headers` was a table but not that
    -- each entry is a {name, value} string pair. A hand-edited
    -- `"headers": [[42, "x"]]` reached has_attachment_disposition, whose
    -- `h[1]:lower()` raised "attempt to index a number value" mid-render.
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = 6, name = "hdr", time = os.time(),
        response = {
          status = 200,
          headers = {
            { 42, "x" },                                    -- name not a string
            { "X-Ok", "yes" },                              -- good
            { "Content-Disposition", nil },                 -- value missing
            { "Content-Disposition", "attachment; filename=a.txt" }, -- good
          },
          body = "data",
          metadata = {},
        } },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    local r = state.http_history[1].response
    assert.equals(2, #r.headers, "only the well-formed pairs survive")
    assert.equals("X-Ok", r.headers[1][1])
    assert.equals("Content-Disposition", r.headers[2][1])

    for _, view in ipairs({ "body", "verbose", "request" }) do
      assert.has_no_errors(function()
        format.format_view(view, r, {})
      end)
    end
  end)

  it("load sanitizes SCALAR drift the list row reads (time / latency / url / metadata)", function()
    -- Regression: the boundary checked containers but not the scalars next
    -- to them. A hand-edited "time": "not-a-number" reached os.date
    -- ("bad argument #2 to 'date'"), "latency_ms": "slow" reached a
    -- `>= 1000` comparison in the Verbose tab, "url": {} reached a
    -- concatenation, and metadata.file_size / request_body /
    -- request_headers reached arithmetic / gmatch / indexing. Every one of
    -- them killed the whole list or detail pane.
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = 11, name = "scalars", time = "not-a-number", time_usec = "xyz",
        source_file = 7,
        response = {
          status = "200", latency_ms = "slow", url = {}, status_text = {},
          cookies = "nope", ok = "yes", protocol = 3,
          body = "hello",
          metadata = {
            method = {}, request_headers = 42, request_body = {},
            timestamp = 5, env = {}, file_size = "big",
            file_path = 9, file_content_type = {}, verbose = 3,
          },
        } },
      { id = 13, name = { bad = true }, time = os.time() },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    local e = state.http_history[1]
    assert.equals(2, #state.http_history, "both entries survive")
    assert.equals("scalars", e.name, "a well-typed name survives")
    assert.equals("", state.http_history[2].name, "a non-string name becomes an empty string")
    assert.is_nil(e.time, "a non-numeric time is dropped")
    assert.is_nil(e.time_usec, "a non-numeric time_usec is dropped")
    assert.equals("", e.source_file, "a non-string source_file becomes an empty string")

    local r = e.response
    assert.equals(200, r.status, "a numeric string status is coerced")
    assert.is_nil(r.latency_ms)
    assert.is_nil(r.url)
    assert.is_nil(r.status_text)
    assert.is_nil(r.cookies)
    assert.is_nil(r.ok)
    assert.is_nil(r.protocol)
    assert.equals("hello", r.body, "well-typed fields survive")

    local m = r.metadata
    assert.is_nil(m.method)
    assert.is_nil(m.request_headers)
    assert.is_nil(m.request_body)
    assert.is_nil(m.timestamp)
    assert.is_nil(m.env)
    assert.is_nil(m.file_size)
    assert.is_nil(m.file_path)
    assert.is_nil(m.file_content_type)
    assert.is_nil(m.verbose)

    -- The list row and every detail view render the sanitized entry.
    assert.has_no_errors(function()
      local line = history.format_list_line(e, 53)
      assert.is_string(line)
    end)
    for _, view in ipairs({ "body", "verbose", "request", "assertions", "script_logs" }) do
      assert.has_no_errors(function()
        format.format_view(view, r, {})
      end)
    end
  end)

  it("load coerces numeric metadata.file_size so the Verbose size line renders", function()
    local file = tmp_dir .. "/history.json"
    os.execute("mkdir -p " .. tmp_dir)
    local fd = io.open(file, "w")
    fd:write(vim.json.encode({
      { id = 12, name = "size", time = os.time(),
        response = {
          status = 200, headers = {}, body = "x",
          metadata = { file_path = "/tmp/x.bin", file_size = "2048" },
        } },
    }))
    fd:close()

    state.http_history = {}
    state.http_history_id_counter = 0
    history.load()

    local r = state.http_history[1].response
    assert.equals(2048, r.metadata.file_size, "a numeric string is coerced to a number")
    local lines = format.format_view("verbose", r, {})
    local joined = table.concat(lines, "\n")
    assert.is_truthy(joined:find("2.0 KB", 1, true), "the size renders as a human size")
  end)
end)
