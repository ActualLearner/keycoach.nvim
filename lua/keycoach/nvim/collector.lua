local capture = require("keycoach.nvim.capture")

local M = {}

local MAX_SAFE_INTEGER = 9007199254740991

local function safe_positive_integer(value)
  return type(value) == "number"
    and value >= 1
    and value <= MAX_SAFE_INTEGER
    and value == math.floor(value)
end

local function exact_context(context)
  if context.buffer_kind == "prompt" or context.buffer_kind == "terminal" then
    return false
  end

  local mode = context.mode
  if type(mode) ~= "string" then
    return false
  end

  return mode == "normal"
    or mode == "visual"
    or mode == "select"
    or mode == "operator_pending"
    or mode == "V"
    or mode == "S"
    or mode == "\22"
    or mode == "\19"
    or mode:sub(1, 2) == "no"
    or mode:sub(1, 1) == "n"
    or mode:sub(1, 1) == "v"
    or mode:sub(1, 1) == "s"
end

local function context_key(context)
  return table.concat({
    context.mode or "",
    context.filetype or "",
    context.buffer_kind or "",
    context.plugin_context or "",
  }, "\0")
end

local MOUSE_BUTTON_NAMES = {
  Left = "left",
  Middle = "middle",
  Right = "right",
  X1 = "x1",
  X2 = "x2",
}

local SCROLL_NAMES = {
  Down = "down",
  Left = "left",
  Right = "right",
  Up = "up",
}

local function mouse_signal(key)
  local direction = key:match("^<ScrollWheel(%a+)>$")
  if SCROLL_NAMES[direction] then
    return { kind = "mouse", scroll = SCROLL_NAMES[direction] }
  end

  local token = key:match("^<(.+)>$")
  if not token then
    return nil
  end

  local double_click = token:sub(1, 2) == "2-"
  if double_click then
    token = token:sub(3)
  end

  for name, button in pairs(MOUSE_BUTTON_NAMES) do
    if token == name .. "Mouse" then
      return {
        kind = "mouse",
        button = button,
        phase = double_click and "double_click" or "click",
      }
    end
    if not double_click and token == name .. "Drag" then
      return { kind = "mouse", button = button, phase = "drag" }
    end
    if not double_click and token == name .. "Release" then
      return { kind = "mouse", button = button, phase = "release" }
    end
  end

  return nil
end

local function neovim_hooks()
  local uv = vim.uv or vim.loop

  return {
    create_namespace = function(name)
      return vim.api.nvim_create_namespace(name)
    end,
    on_key = function(callback, namespace)
      vim.on_key(callback, namespace)
    end,
    create_augroup = function(name)
      return vim.api.nvim_create_augroup(name, { clear = true })
    end,
    create_autocmd = function(events, options)
      vim.api.nvim_create_autocmd(events, options)
    end,
    delete_augroup = function(group)
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
    context = function()
      local buffer = vim.api.nvim_get_current_buf()
      local buffer_options = vim.bo[buffer]
      local buffer_kind = buffer_options.buftype
      if buffer_kind == "" then
        buffer_kind = "file"
      end

      return {
        mode = vim.api.nvim_get_mode().mode,
        filetype = buffer_options.filetype,
        buffer_kind = buffer_kind,
        plugin_context = "none",
      }
    end,
    now_ms = function()
      return math.floor(uv.hrtime() / 1000000)
    end,
    keytrans = function(key)
      return vim.fn.keytrans(key)
    end,
    strchars = function(value)
      return vim.fn.strchars(value)
    end,
  }
end

function M.start(options, hooks)
  options = options or {}
  assert(safe_positive_integer(options.session), "collector session must be a positive safe integer")
  assert(type(options.emit) == "function", "collector emit must be a function")

  hooks = hooks or neovim_hooks()

  local active = true
  local ordinal = 0
  local pending_keys = {}
  local pending_context
  local namespace = hooks.create_namespace("keycoach.collector")
  local group = hooks.create_augroup("KeyCoachCollector")

  local function emit_signal(signal, context)
    if not active then
      return
    end

    ordinal = ordinal + 1
    signal.session_id = options.session
    signal.ordinal = ordinal
    local observation = capture.observe(signal, {
      context = function()
        return context or hooks.context()
      end,
      now_ms = hooks.now_ms,
      keytrans = function(value)
        return value
      end,
      strchars = hooks.strchars,
    })
    if observation then
      options.emit(observation)
    end
  end

  local function clear_pending()
    pending_keys = {}
    pending_context = nil
  end

  local function flush_pending()
    local keys = pending_keys
    local context = pending_context
    clear_pending()
    for _, key in ipairs(keys) do
      emit_signal({ kind = "key", key = key }, context)
    end
  end

  local function collect_key(translated, context)
    if type(options.resolve_mapping) ~= "function" or not exact_context(context) then
      flush_pending()
      emit_signal({ kind = "key", key = translated }, context)
      return
    end

    if pending_context and context_key(pending_context) ~= context_key(context) then
      flush_pending()
    end
    pending_context = pending_context or context
    table.insert(pending_keys, translated)

    local lhs = table.concat(pending_keys)
    local ok, resolution = pcall(options.resolve_mapping, lhs, context)
    if ok and type(resolution) == "table" and resolution.pending == true then
      return
    end

    if ok and type(resolution) == "table" and resolution.action_id then
      local cost = #pending_keys
      clear_pending()
      emit_signal({
        kind = "action",
        action_id = resolution.action_id,
        source = "mapping",
        category = resolution.category,
        bindable = resolution.bindable ~= false,
        cost = cost,
        lhs = lhs,
      }, context)
      return
    end

    flush_pending()
  end

  hooks.on_key(function(_, typed)
    if not active or type(typed) ~= "string" or typed == "" then
      return
    end

    local translated = hooks.keytrans(typed)
    if type(translated) ~= "string" or translated == "" then
      return
    end

    local context = hooks.context()
    local mouse = mouse_signal(translated)
    if mouse then
      flush_pending()
      emit_signal(mouse, context)
      return
    end

    collect_key(translated, context)
  end, namespace)

  local handle = {}

  function handle.stop()
    if not active then
      return
    end

    flush_pending()
    active = false
    hooks.on_key(nil, namespace)
    hooks.delete_augroup(group)
  end

  return handle
end

return M
