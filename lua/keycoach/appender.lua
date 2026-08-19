local uv = vim.uv or vim.loop

local M = {}

local MODE_ALIASES = {
  normal = "n",
  visual = "x",
  select = "s",
  operator_pending = "o",
  insert = "i",
  command_line = "c",
  terminal = "t",
}

local MODES = {
  n = true,
  v = true,
  x = true,
  s = true,
  o = true,
  i = true,
  l = true,
  c = true,
  t = true,
  ["!"] = true,
}

local OPTION_ORDER = {
  "desc",
  "silent",
  "expr",
  "nowait",
  "remap",
  "noremap",
  "replace_keycodes",
  "unique",
}

local BOOLEAN_OPTIONS = {
  silent = true,
  expr = true,
  nowait = true,
  remap = true,
  noremap = true,
  replace_keycodes = true,
  unique = true,
}

local function problem(code, message, path)
  return {
    code = code,
    message = message,
    path = path,
  }
end

local function quote(value)
  return string.format("%q", value)
end

local function normalize_mode(mode)
  return MODE_ALIASES[mode] or mode
end

local function normalized_modes(value)
  local source = type(value) == "table" and value or { value }
  local modes = {}
  local seen = {}

  for _, mode in ipairs(source) do
    mode = normalize_mode(mode)
    if type(mode) ~= "string" or not MODES[mode] or seen[mode] then
      return nil
    end
    seen[mode] = true
    table.insert(modes, mode)
  end

  if #modes == 0 then
    return nil
  end
  return modes
end

local function render_modes(modes)
  if #modes == 1 then
    return quote(modes[1])
  end

  local rendered = {}
  for _, mode in ipairs(modes) do
    table.insert(rendered, quote(mode))
  end
  return "{ " .. table.concat(rendered, ", ") .. " }"
end

local function render_options(options)
  local rendered = {}
  for _, name in ipairs(OPTION_ORDER) do
    local value = options[name]
    if value ~= nil then
      if name == "desc" then
        table.insert(rendered, name .. " = " .. quote(value))
      else
        table.insert(rendered, name .. " = " .. tostring(value))
      end
    end
  end

  if #rendered == 0 then
    return nil
  end
  return "{ " .. table.concat(rendered, ", ") .. " }"
end

local function validate_candidate(candidate, path)
  if type(candidate) ~= "table" then
    return nil, problem("invalid_candidate", "Mapping Candidate must be a table", path)
  end

  local modes = normalized_modes(candidate.mode)
  if not modes then
    return nil, problem("unsupported_mode", "Mapping Candidate has an unsupported mode", path)
  end
  if
    type(candidate.lhs) ~= "string"
    or candidate.lhs == ""
    or candidate.lhs:find("\0", 1, true)
  then
    return nil,
      problem("invalid_candidate", "Mapping Candidate lhs must be a non-empty string", path)
  end
  if
    type(candidate.rhs) ~= "string"
    or candidate.rhs == ""
    or candidate.rhs:find("\0", 1, true)
  then
    return nil,
      problem("unsupported_target", "Mapping Candidate target must be a non-empty string", path)
  end

  local options = candidate.opts or {}
  if type(options) ~= "table" then
    return nil, problem("invalid_candidate", "Mapping Candidate opts must be a table", path)
  end
  for name, value in pairs(options) do
    if name == "desc" then
      if type(value) ~= "string" then
        return nil, problem("invalid_candidate", "Mapping Candidate desc must be a string", path)
      end
    elseif BOOLEAN_OPTIONS[name] then
      if type(value) ~= "boolean" then
        return nil,
          problem(
            "invalid_candidate",
            "Mapping Candidate option " .. name .. " must be boolean",
            path
          )
      end
    else
      return nil,
        problem(
          "unsupported_target",
          "Mapping Candidate option " .. tostring(name) .. " is not appendable",
          path
        )
    end
  end
  if options.remap == true and options.noremap == true then
    return nil,
      problem("invalid_candidate", "Mapping Candidate cannot enable both remap and noremap", path)
  end

  local rendered_options = render_options(options)
  local arguments = {
    render_modes(modes),
    quote(candidate.lhs),
    quote(candidate.rhs),
  }
  if rendered_options then
    table.insert(arguments, rendered_options)
  end

  return {
    lhs = candidate.lhs,
    modes = modes,
    line = "vim.keymap.set(" .. table.concat(arguments, ", ") .. ")",
  },
    nil
end

local function contexts_for(mode)
  if mode == "v" then
    return { x = true, s = true }
  end
  if mode == "!" then
    return { i = true, c = true }
  end
  return { [mode] = true }
end

local function modes_overlap(left, right)
  local left_contexts = contexts_for(left)
  local right_contexts = contexts_for(right)
  for mode in pairs(left_contexts) do
    if right_contexts[mode] then
      return true
    end
  end
  return false
end

local function expand_leader(lhs, inventory)
  local leader = inventory.leader
  if type(leader) ~= "string" or leader == "" then
    leader = vim.g.mapleader or "\\"
  end
  local localleader = inventory.localleader
  if type(localleader) ~= "string" or localleader == "" then
    localleader = vim.g.maplocalleader or "\\"
  end

  return lhs
    :gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", leader)
    :gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", localleader)
end

local function canonical_lhs(lhs, inventory)
  local expanded = expand_leader(lhs, inventory)
  local ok, canonical = pcall(vim.api.nvim_replace_termcodes, expanded, true, true, true)
  return ok and canonical or expanded
end

local function starts_with(value, prefix)
  return prefix ~= "" and value:sub(1, #prefix) == prefix
end

local function conflicts(candidate, inventory)
  local candidate_lhs = canonical_lhs(candidate.lhs, inventory)
  for _, mapping in ipairs(inventory.mappings) do
    local mapping_modes = normalized_modes(mapping.mode)
    local mapping_lhs = mapping.lhs or mapping.raw_lhs
    if mapping_modes and type(mapping_lhs) == "string" then
      mapping_lhs = canonical_lhs(mapping_lhs, inventory)
      local keys_conflict = mapping_lhs == candidate_lhs
        or starts_with(mapping_lhs, candidate_lhs)
        or starts_with(candidate_lhs, mapping_lhs)

      for _, candidate_mode in ipairs(candidate.modes) do
        for _, mapping_mode in ipairs(mapping_modes) do
          if keys_conflict and modes_overlap(candidate_mode, mapping_mode) then
            return true
          end
        end
      end
    end
  end
  return false
end

local function read_existing(path)
  local stat, stat_message, stat_code = uv.fs_lstat(path)
  if not stat then
    if stat_code == "ENOENT" then
      return "", nil
    end
    return nil, problem("unsafe_target", stat_message or "could not inspect mappings file", path)
  end
  if stat.type ~= "file" then
    return nil,
      problem("unsafe_target", "mappings path must be a regular file and not a symbolic link", path)
  end

  local file, open_message = io.open(path, "rb")
  if not file then
    return nil, problem("read_failed", open_message or "could not open mappings file", path)
  end
  local contents = file:read("*a")
  local closed, close_message = file:close()
  if not contents or not closed then
    return nil, problem("read_failed", close_message or "could not read mappings file", path)
  end
  return contents, nil
end

local function validate_inventory(options, path)
  if
    type(options) ~= "table"
    or options.expected_revision == nil
    or type(options.current_inventory) ~= "function"
  then
    return nil,
      problem("invalid_options", "expected_revision and current_inventory are required", path)
  end

  local called, inventory, inventory_problem = pcall(options.current_inventory)
  if not called then
    return nil, problem("inventory_unavailable", inventory, path)
  end
  if inventory_problem then
    local message = type(inventory_problem) == "table" and inventory_problem.message or nil
    return nil, problem("inventory_unavailable", message or tostring(inventory_problem), path)
  end
  if
    type(inventory) ~= "table"
    or type(inventory.mappings) ~= "table"
    or inventory.complete ~= true
  then
    return nil, problem("inventory_unavailable", "current mapping inventory is incomplete", path)
  end
  if inventory.revision ~= options.expected_revision then
    return nil,
      problem(
        "stale_inventory",
        "mapping inventory changed; regenerate the Mapping Candidate",
        path
      )
  end

  local is_list = vim.islist or vim.tbl_islist
  if not is_list(inventory.mappings) then
    return nil,
      problem(
        "inventory_unavailable",
        "current mapping inventory has an invalid mappings list",
        path
      )
  end
  for _, mapping in ipairs(inventory.mappings) do
    local mapping_lhs = type(mapping) == "table" and (mapping.lhs or mapping.raw_lhs) or nil
    if
      not normalized_modes(type(mapping) == "table" and mapping.mode or nil)
      or type(mapping_lhs) ~= "string"
    then
      return nil,
        problem(
          "inventory_unavailable",
          "current mapping inventory contains an invalid mapping",
          path
        )
    end
  end
  return inventory, nil
end

local function append_bytes(path, bytes)
  local parent = vim.fn.fnamemodify(path, ":h")
  local made_parent, mkdir_result = pcall(vim.fn.mkdir, parent, "p")
  if not made_parent or mkdir_result == 0 and not uv.fs_stat(parent) then
    return nil, problem("append_failed", "could not create mappings directory", path)
  end

  local file, open_message = io.open(path, "ab")
  if not file then
    return nil,
      problem("append_failed", open_message or "could not open mappings file for append", path)
  end
  local wrote, write_message = file:write(bytes)
  local closed, close_message = file:close()
  if not wrote or not closed then
    return nil,
      problem("append_failed", write_message or close_message or "could not append mapping", path)
  end
  return true, nil
end

function M.append(path, candidate, options)
  if type(path) ~= "string" or path == "" or path:find("\0", 1, true) or path:sub(-4) ~= ".lua" then
    return nil, problem("unsafe_target", "mappings path must name a .lua file", path)
  end

  local rendered, candidate_problem = validate_candidate(candidate, path)
  if candidate_problem then
    return nil, candidate_problem
  end

  local inventory, inventory_problem = validate_inventory(options, path)
  if inventory_problem then
    return nil, inventory_problem
  end
  if conflicts(rendered, inventory) then
    return nil, problem("mapping_conflict", "Mapping Candidate is no longer free", path)
  end

  local existing, read_problem = read_existing(path)
  if read_problem then
    return nil, read_problem
  end

  local separator = existing ~= "" and existing:sub(-1) ~= "\n" and "\n" or ""
  local bytes = separator .. rendered.line .. "\n"
  local compiled, compile_message = loadstring(existing .. bytes, "@" .. path)
  if not compiled then
    return nil, problem("invalid_lua", compile_message, path)
  end

  local appended, append_problem = append_bytes(path, bytes)
  if not appended then
    return nil, append_problem
  end

  return {
    line = rendered.line,
    bytes_written = #bytes,
  }, nil
end

return M
