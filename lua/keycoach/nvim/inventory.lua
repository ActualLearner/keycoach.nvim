local M = {}

local DEFAULT_MODES = { "n", "v", "x", "s", "o" }

local function problem(message)
  return {
    code = "inventory_unavailable",
    message = tostring(message or "could not inspect Neovim mappings"),
  }
end

local function starts_with(value, prefix)
  return prefix ~= "" and value:sub(1, #prefix) == prefix
end

local function symbolic_lhs(lhs, leader, localleader)
  if leader == " " and starts_with(lhs, "<Space>") then
    return "<leader>" .. lhs:sub(8)
  end
  if starts_with(lhs, leader) then
    return "<leader>" .. lhs:sub(#leader + 1)
  end
  if starts_with(lhs, localleader) then
    return "<localleader>" .. lhs:sub(#localleader + 1)
  end
  return lhs
end

local function safe_description(value)
  if type(value) ~= "string" or value == "" or #value > 80 then
    return nil
  end
  if value:find("[%c/\\]") then
    return nil
  end
  return value
end

local function slug(value)
  local result = value:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return result:sub(1, 48)
end

local function command_action(rhs)
  if type(rhs) ~= "string" then
    return nil
  end

  local name = rhs:match("^%s*<[Cc][Mm][Dd]>%s*([%a][%w_]*)") or rhs:match("^%s*:%s*([%a][%w_]*)")
  return name and ("command:" .. name) or nil
end

local function default_hash(value)
  return vim.fn.sha256(value):sub(1, 16)
end

local function action_id_for(mapping, mode, lhs, hash)
  if
    type(mapping.action_id) == "string"
    and mapping.action_id:match("^[%w][%w_.:%-]*$")
    and #mapping.action_id <= 128
  then
    return mapping.action_id
  end

  local command = command_action(mapping.rhs)
  if command then
    return command
  end

  local description = safe_description(mapping.desc)
  local description_slug = description and slug(description) or ""
  if description_slug ~= "" then
    return "mapping:" .. description_slug
  end

  return "mapping:opaque_" .. hash(mode .. "|" .. lhs)
end

local function production_buffers()
  local result = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) then
      table.insert(result, buffer)
    end
  end
  return result
end

local function add_mapping(result, seen, raw, mode, buffer, leader, localleader, hash)
  if type(raw) ~= "table" or type(raw.lhs) ~= "string" or raw.lhs == "" then
    return nil, problem("Neovim returned a malformed mapping")
  end

  local lhs = symbolic_lhs(raw.lhs, leader, localleader)
  local identity = table.concat({ mode, lhs, tostring(buffer) }, "|")
  if seen[identity] then
    return true, nil
  end
  seen[identity] = true

  local mapping = {
    mode = mode,
    lhs = lhs,
    action_id = action_id_for(raw, mode, lhs, hash),
    buffer = buffer,
  }
  local description = safe_description(raw.desc)
  if description then
    mapping.desc = description
  end
  table.insert(result, mapping)
  return true, nil
end

local function collect_prefixes(mappings)
  local result = {}
  local seen = {}
  for _, mapping in ipairs(mappings) do
    local tail = mapping.lhs:match("^<leader>(.+)$")
    if tail and tail ~= "" then
      local prefix = "<leader>" .. tail:sub(1, 1)
      if not seen[prefix] then
        seen[prefix] = true
        table.insert(result, prefix)
      end
    end
  end
  table.sort(result)
  return result
end

local function mapping_sort(left, right)
  if left.mode ~= right.mode then
    return left.mode < right.mode
  end
  if left.lhs ~= right.lhs then
    return left.lhs < right.lhs
  end
  if left.buffer == right.buffer then
    return left.action_id < right.action_id
  end
  if left.buffer == false then
    return true
  end
  if right.buffer == false then
    return false
  end
  return left.buffer < right.buffer
end

function M.snapshot(options)
  options = options or {}
  local modes = options.modes or DEFAULT_MODES
  local buffers = options.buffers or production_buffers()
  local get_keymap = options.get_keymap or vim.api.nvim_get_keymap
  local get_buf_keymap = options.get_buf_keymap or vim.api.nvim_buf_get_keymap
  local leader = options.leader or vim.g.mapleader or "\\"
  local localleader = options.localleader or vim.g.maplocalleader or "\\"
  local hash = options.hash or default_hash
  local mappings = {}
  local seen = {}

  for _, mode in ipairs(modes) do
    local ok, globals = pcall(get_keymap, mode)
    if not ok or type(globals) ~= "table" then
      return nil, problem(globals)
    end
    for _, raw in ipairs(globals) do
      local added, add_problem =
        add_mapping(mappings, seen, raw, mode, false, leader, localleader, hash)
      if not added then
        return nil, add_problem
      end
    end

    for _, buffer in ipairs(buffers) do
      local buffer_ok, locals = pcall(get_buf_keymap, buffer, mode)
      if not buffer_ok or type(locals) ~= "table" then
        return nil, problem(locals)
      end
      for _, raw in ipairs(locals) do
        local added, add_problem =
          add_mapping(mappings, seen, raw, mode, buffer, leader, localleader, hash)
        if not added then
          return nil, add_problem
        end
      end
    end
  end

  table.sort(mappings, mapping_sort)
  local revision_parts = { leader, localleader }
  for _, mapping in ipairs(mappings) do
    if not mapping.buffer then
      table.insert(
        revision_parts,
        table.concat({
          mapping.mode,
          mapping.lhs,
          mapping.action_id,
        }, "|")
      )
    end
  end

  return {
    revision = hash(table.concat(revision_parts, "\n")),
    complete = true,
    conventions = {
      leader = "<leader>",
      localleader = "<localleader>",
      prefixes = collect_prefixes(mappings),
    },
    mappings = mappings,
  },
    nil
end

local function modes_overlap(left, right)
  if left == right then
    return true
  end
  return left == "v" and (right == "x" or right == "s")
    or right == "v" and (left == "x" or left == "s")
end

function M.conflict(snapshot, candidate)
  if type(snapshot) ~= "table" or type(snapshot.mappings) ~= "table" then
    return nil
  end
  if
    type(candidate) ~= "table"
    or type(candidate.mode) ~= "string"
    or type(candidate.lhs) ~= "string"
  then
    return nil
  end

  for _, mapping in ipairs(snapshot.mappings) do
    if modes_overlap(mapping.mode, candidate.mode) then
      local kind
      if mapping.lhs == candidate.lhs then
        kind = "exact"
      elseif starts_with(mapping.lhs, candidate.lhs) then
        kind = "candidate_prefix"
      elseif starts_with(candidate.lhs, mapping.lhs) then
        kind = "existing_prefix"
      end
      if kind then
        return { kind = kind, mapping = mapping }
      end
    end
  end

  return nil
end

return M
