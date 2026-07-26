local rv = require("poste.http.request_vars")

describe("find_request_variable_refs", function()
  local find = rv._test.find_request_variable_refs

  it("finds simple {{Name.response.body}} ref", function()
    local refs = find("GET {{jq.response.body}}/path")
    assert.equals(1, #refs)
    assert.equals("jq", refs[1].request_name)
  end)

  it("finds ref with jq filter inside prompt options", function()
    local text = '<<method [ {{jq.response.body | {name: .[].commit.author.name} }} ]'
    local refs = find(text)
    assert.equals(1, #refs)
    assert.equals("jq", refs[1].request_name)
  end)

  it("finds ref with array indexing", function()
    local text = "GET {{users.response.body.items[0].id}}"
    local refs = find(text)
    assert.equals(1, #refs)
    assert.equals("users", refs[1].request_name)
  end)

  it("finds {{Name.request.headers.X}} ref", function()
    local text = "{{login.request.headers.Authorization}}"
    local refs = find(text)
    assert.equals(1, #refs)
    assert.equals("login", refs[1].request_name)
  end)

  it("finds multiple refs", function()
    local text = "{{jq.response.body}} and {{login.response.headers.Token}}"
    local refs = find(text)
    assert.equals(2, #refs)
  end)

  it("ignores plain {{var}} without .response. or .request.", function()
    local refs = find("{{base_url}}/get?q={{query}}")
    assert.equals(0, #refs)
  end)

  it("finds ref inside prompt options with nested brackets", function()
    local text = '<<item [{{jq.response.body.[].parents[].sha}}]'
    local refs = find(text)
    assert.equals(1, #refs)
    assert.equals("jq", refs[1].request_name)
  end)
end)

describe("find_dynamic_prompt_refs", function()
  local find = rv._test.find_dynamic_prompt_refs

  it("finds ref inside <<var [{{...}}] prompt", function()
    local text = '<<method [ {{jq.response.body | {name: .[].commit.author.name} }} ]'
    local refs = find(text)
    assert.equals(1, #refs)
    assert.equals("jq", refs[1].request_name)
  end)

  it("returns empty for prompt without ref", function()
    local refs = find("<<name [admin, user]")
    assert.equals(0, #refs)
  end)
end)

describe("collect_requests_from_content", function()
  local collect = rv._test.collect_requests_from_content

  it("finds named requests in content", function()
    local content = "### jq\nGET https://api.example.com/jq\n\n### prompt_enhance\nGET /get\n"
    local requests = collect(content)
    assert.equals(2, #requests)
    assert.equals("jq", requests[1].name)
    assert.equals("prompt_enhance", requests[2].name)
  end)

  it("returns empty for content with no ###", function()
    local requests = collect("GET /test")
    assert.equals(0, #requests)
  end)

  it("returns empty for empty content", function()
    local requests = collect("")
    assert.equals(0, #requests)
  end)
end)