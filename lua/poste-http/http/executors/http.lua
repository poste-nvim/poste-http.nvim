--- HTTP executor: thin wrapper over curl_exec, which owns the curl subprocess.
--- Kept as its own module so executor dispatch stays uniform across protocols
--- (docs/dev/multi-protocol-design.md).

local M = {}
local curl_exec = require("poste-http.http.curl_exec")

function M.run(req, callback)
  curl_exec.execute(req, callback)
end

return M
