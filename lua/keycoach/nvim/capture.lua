local M = {}

local EXACT_MODES = {
  normal = true,
  operator_pending = true,
  select = true,
  visual = true,
}

local INPUT_CATEGORIES = {
  command_line = "command_line_input",
  insert = "insert_input",
  prompt = "prompt_input",
  replace = "replace_input",
  search = "search_input",
  terminal = "terminal_input",
  unknown = "other_input",
}

local MOUSE_BUTTONS = {
  left = true,
  middle = true,
  right = true,
  x1 = true,
  x2 = true,
}

local MOUSE_PHASES = {
  click = true,
  double_click = true,
  drag = true,
  release = true,
}

local SCROLL_DIRECTIONS = {
  down = true,
  left = true,
  right = true,
  up = true,
}

local ACTION_CATEGORIES = {
  command = true,
  edit = true,
  mode_change = true,
  navigation = true,
  other = true,
  redo = true,
  search = true,
  selection = true,
  terminal = true,
  undo = true,
}

local SOURCES = {
  command = true,
  editor = true,
  keys = true,
  mapping = true,
  mouse = true,
}

local EDITOR_ACTIONS = {
  cursor_move = "navigation",
  edit = "edit",
  mode_change = "mode_change",
  redo = "redo",
  selection_change = "selection",
  undo = "undo",
}

local BUFFER_KINDS = {
  acwrite = true,
  file = true,
  help = true,
  nofile = true,
  nowrite = true,
  prompt = true,
  quickfix = true,
  terminal = true,
}

local MAX_SAFE_INTEGER = 9007199254740991

local function safe_integer(value, minimum)
  return type(value) == "number"
    and value >= minimum
    and value <= MAX_SAFE_INTEGER
    and value == math.floor(value)
end

local function safe_label(value, empty_value, invalid_value)
  if value == nil or value == "" then
    return empty_value
  end
  if type(value) ~= "string" or #value > 64 or not value:match("^[%w_.+%-]+$") then
    return invalid_value
  end

  return value
end

local function safe_key(key, environment)
  if type(key) ~= "string" or key == "" or #key > 32 or key:find("%c") then
    return nil
  end
  if key:match("^<[%w_%-]+>$") then
    return key
  end

  local strchars = environment.strchars or function(value)
    return vim.fn.strchars(value)
  end
  if strchars(key) == 1 then
    return key
  end

  return nil
end

local function safe_action_id(action_id)
  return type(action_id) == "string"
    and #action_id <= 128
    and action_id:match("^[%w][%w_.:%-]*$") ~= nil
end

local function action_category(signal)
  return ACTION_CATEGORIES[signal.category] and signal.category or "other"
end

local function mouse_action(signal)
  if SCROLL_DIRECTIONS[signal.scroll] then
    return "mouse:scroll_" .. signal.scroll
  end
  if MOUSE_BUTTONS[signal.button] and MOUSE_PHASES[signal.phase] then
    return "mouse:" .. signal.button .. "_" .. signal.phase
  end

  return "mouse:other"
end

local function canonical_mode(raw_mode, buffer_kind)
  if buffer_kind == "prompt" then
    return "prompt"
  end
  if buffer_kind == "terminal" then
    return "terminal"
  end
  if raw_mode == "search" then
    return "search"
  end
  if raw_mode == "V" or raw_mode == "\22" or raw_mode == "visual" then
    return "visual"
  end
  if raw_mode == "S" or raw_mode == "\19" or raw_mode == "select" then
    return "select"
  end
  if type(raw_mode) ~= "string" then
    return "unknown"
  end
  if raw_mode:sub(1, 2) == "no" or raw_mode == "operator_pending" then
    return "operator_pending"
  end
  if raw_mode:sub(1, 1) == "n" or raw_mode == "normal" then
    return "normal"
  end
  if raw_mode:sub(1, 1) == "v" then
    return "visual"
  end
  if raw_mode:sub(1, 1) == "s" then
    return "select"
  end
  if raw_mode:sub(1, 1) == "i" or raw_mode == "insert" then
    return "insert"
  end
  if raw_mode:sub(1, 1) == "R" or raw_mode == "replace" then
    return "replace"
  end
  if raw_mode:sub(1, 1) == "c" or raw_mode == "command_line" then
    return "command_line"
  end
  if raw_mode:sub(1, 1) == "t" or raw_mode == "terminal" then
    return "terminal"
  end

  return "unknown"
end

local function context_from(environment)
  local raw = environment.context()
  local buffer_kind = BUFFER_KINDS[raw.buffer_kind] and raw.buffer_kind or "unknown"

  return {
    filetype = safe_label(raw.filetype, "none", "unknown"),
    buffer_kind = buffer_kind,
    plugin_context = safe_label(raw.plugin_context, "none", "none"),
  },
    canonical_mode(raw.mode, buffer_kind)
end

function M.observe(signal, environment)
  if not safe_integer(signal.session_id, 1) or not safe_integer(signal.ordinal, 1) then
    return nil
  end

  local at_ms = environment.now_ms()
  if not safe_integer(at_ms, 0) then
    return nil
  end

  local context, mode = context_from(environment)
  local exact = EXACT_MODES[mode]
  local is_mouse = signal.kind == "mouse"
  local is_editor = signal.kind == "editor" and EDITOR_ACTIONS[signal.action] ~= nil
  local is_action = signal.kind == "action" or is_editor
  local translated_key = exact
      and not is_mouse
      and not is_action
      and environment.keytrans(signal.key)
    or nil
  local key = translated_key and safe_key(translated_key, environment) or nil
  local candidate_action_id = is_editor and ("editor:" .. signal.action) or signal.action_id
  local category = is_editor and EDITOR_ACTIONS[signal.action] or action_category(signal)
  local valid_action = is_action and exact and safe_action_id(candidate_action_id)
  local action_id
  local source
  local lhs

  if is_mouse then
    action_id = mouse_action(signal)
    source = "mouse"
  elseif is_action then
    action_id = valid_action and candidate_action_id or ("category:" .. category)
    source = is_editor and "editor" or (SOURCES[signal.source] and signal.source or "editor")
    lhs = valid_action and signal.lhs or nil
  else
    action_id = key and ("key:" .. key)
      or ("category:" .. (INPUT_CATEGORIES[mode] or "other_input"))
    source = "keys"
    lhs = key
  end

  return {
    schema_version = 1,
    id = signal.session_id .. ":" .. signal.ordinal,
    session = signal.session_id,
    ordinal = signal.ordinal,
    at_ms = at_ms,
    kind = "action",
    action_id = action_id,
    source = source,
    bindable = valid_action and signal.bindable == true or false,
    cost = is_action and signal.cost or 1,
    mode = mode,
    lhs = lhs,
    context = context,
  }
end

return M
