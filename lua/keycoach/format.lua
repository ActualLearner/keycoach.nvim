local M = {}

local is_list = vim.islist or vim.tbl_islist

function M.recommendation_title(recommendation)
  if recommendation.kind == "existing_mapping" then
    return "Use existing mapping  " .. recommendation.mapping.lhs
  end
  if recommendation.kind == "native_action" then
    return "Use native action  " .. recommendation.native_action.keys
  end
  return "Add mapping  " .. (recommendation.mapping and recommendation.mapping.lhs or "")
end

function M.evidence_summary(evidence)
  evidence = evidence or {}
  return string.format(
    "%d uses across %d sessions · ~%d keys saved",
    evidence.occurrences or 0,
    evidence.sessions or 0,
    evidence.estimated_keystrokes_saved or 0
  )
end

function M.pretty_json(value, indent)
  indent = indent or 0
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end
  local pad = string.rep("  ", indent)
  if next(value) == nil then
    return "{}"
  end
  if is_list(value) then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = string.rep("  ", indent + 1) .. M.pretty_json(item, indent + 1)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
  end
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = string.format(
      "%s%s: %s",
      string.rep("  ", indent + 1),
      vim.json.encode(key),
      M.pretty_json(value[key], indent + 1)
    )
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
end

return M
