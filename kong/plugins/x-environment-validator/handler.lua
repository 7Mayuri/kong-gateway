-- Custom Kong plugin: blocks requests missing or failing the x-environment header check.
local plugin = {
  PRIORITY = 900,
  VERSION = "1.0.0"
}

-- Turns "dev, uat,prod" into {"DEV","UAT","PROD"}.
local function split_string(str)
  local result = {}
  for value in str:gmatch("[^,]+") do
    local trimmed = value:match("^%s*(.-)%s*$"):upper()
    table.insert(result, trimmed)
  end
  return result
end

local function is_allowed(value, allowed_list)
  for _, allowed in ipairs(allowed_list) do
    if value:upper() == allowed then
      return true
    end
  end
  return false
end

function plugin:access(config)
  local allowed_env_str = config.allowed_environments or "DEV,UAT,PROD"
  local header_name = config.header_name or "x-environment"

  local allowed_environments = split_string(allowed_env_str)

  -- Kong exposes headers as ngx vars with dashes turned into underscores.
  local header_var_name = "http_" .. header_name:lower():gsub("-", "_")
  local header_value = ngx.var[header_var_name]

  if not header_value or header_value == "" then
    ngx.status = 400
    ngx.header.content_type = "application/json"
    ngx.say('{"error":"Missing x-environment header"}')
    return ngx.exit(400)
  end

  if not is_allowed(header_value, allowed_environments) then
    ngx.status = 403
    ngx.header.content_type = "application/json"
    ngx.say('{"error":"Invalid x-environment header. Allowed values: DEV, UAT, PROD"}')
    return ngx.exit(403)
  end

  kong.log.debug("x-environment header validated: " .. header_value:upper())
end



return plugin
