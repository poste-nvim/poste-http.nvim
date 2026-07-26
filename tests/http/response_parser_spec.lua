local parser = require("poste.http.response_parser")

describe("parse_headers_file", function()
  local parse = parser._test.parse_headers_file

  it("parses headers with LF line endings", function()
    local text = "HTTP/1.1 200 OK\nContent-Type: application/json\nContent-Length: 42\n"
    local r = parse(text)
    assert.equals(200, r.status)
    assert.equals("200 OK", r.status_text)
    assert.equals(2, #r.headers)
    assert.equals("Content-Type", r.headers[1][1])
    assert.equals("application/json", r.headers[1][2])
    assert.equals("Content-Length", r.headers[2][1])
    assert.equals("42", r.headers[2][2])
    assert.equals("application/json", r.content_type)
  end)

  it("parses headers with CRLF line endings", function()
    local text = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 42\r\n"
    local r = parse(text)
    assert.equals(200, r.status)
    assert.equals(2, #r.headers)
    assert.equals("Content-Type", r.headers[1][1])
  end)

  it("parses headers with trailing CR at end of file", function()
    local text = "HTTP/1.1 200 OK\nContent-Length: 546\nConnection: keep-alive\nContent-Type: application/json\nServer: uvicorn\r"
    local r = parse(text)
    assert.equals(200, r.status)
    assert.equals(4, #r.headers)
    assert.equals("Server", r.headers[4][1])
    assert.equals("uvicorn", r.headers[4][2])
  end)

  it("takes the last block when multiple responses (redirects)", function()
    local text = "HTTP/1.1 301 Moved\r\nLocation: /new\r\n\r\nHTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
    local r = parse(text)
    assert.equals(200, r.status)
    assert.equals("200 OK", r.status_text)
    assert.equals(1, #r.headers)
    assert.equals("Content-Type", r.headers[1][1])
  end)

  it("returns empty headers for empty input", function()
    local r = parse("")
    assert.equals(200, r.status)
    assert.equals("200 OK", r.status_text)
    assert.equals(0, #r.headers)
  end)

  it("returns empty headers for nil input", function()
    local r = parse(nil)
    assert.equals(200, r.status)
    assert.equals(0, #r.headers)
  end)

  it("handles mixed CRLF and LF in blocks", function()
    local text = "HTTP/1.1 200 OK\nContent-Type: text/plain\n\n"
    local r = parse(text)
    assert.equals(200, r.status)
    assert.equals(1, #r.headers)
    assert.equals("text/plain", r.content_type)
  end)

  it("extracts content-type case-insensitively", function()
    local text = "HTTP/1.1 200 OK\ncontent-type: application/json\n"
    local r = parse(text)
    assert.equals("application/json", r.content_type)
  end)

  it("handles status reason phrases", function()
    local text = "HTTP/1.1 404 Not Found\nContent-Type: text/plain\n"
    local r = parse(text)
    assert.equals(404, r.status)
    assert.equals("404 Not Found", r.status_text)
  end)
end)