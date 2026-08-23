-- Validate the x-environment header.
local plugin = {
  PRIORITY = 900,
  VERSION = "1.0.0"
}

local function trim(str)
  return (str:match("^%s*(.-)%s*$"))
end

-- Parse and normalize allowed values.
local function parse_allowed(str)
  local result = {}
  for value in str:gmatch("[^,]+") do
    local cleaned = trim(value):upper()
    if cleaned ~= "" then
      table.insert(result, cleaned)
    end
  end
  return result
end

local function contains(list, value)
  for _, allowed in ipairs(list) do
    if value == allowed then
      return true
    end
  end
  return false
end

function plugin:access(config)
  local header_name = config.header_name or "x-environment"
  local allowed = parse_allowed(config.allowed_environments or "DEV,UAT,PROD")

  -- Reject an empty configuration.
  if #allowed == 0 then
    kong.log.err("x-environment-validator: allowed_environments resolved to an empty list")
    return kong.response.exit(500, { error = "Server misconfiguration" })
  end

  -- Read all headers to detect duplicates.
  local value = kong.request.get_headers()[header_name]

  -- Reject duplicate headers.
  if type(value) == "table" then
    return kong.response.exit(400, {
      error = "Duplicate " .. header_name .. " header"
    })
  end

  if value then
    value = trim(value)
  end

  if not value or value == "" then
    return kong.response.exit(400, {
      error = "Missing " .. header_name .. " header"
    })
  end

  if not contains(allowed, value:upper()) then
    return kong.response.exit(403, {
      error = "Invalid " .. header_name .. " header. Allowed values: " .. table.concat(allowed, ", ")
    })
  end
end

return plugin
