local collector = require("keycoach.nvim.collector")
local h = require("tests.harness")

local function fake_hooks(overrides)
  local hooks = {
    autocmds = {},
    context_value = {
      mode = "n",
      filetype = "lua",
      buffer_kind = "file",
      plugin_context = "none",
    },
    now = 1000,
  }

  function hooks.create_namespace()
    return 17
  end

  function hooks.on_key(callback)
    hooks.key_callback = callback
  end

  function hooks.create_augroup()
    return 23
  end

  function hooks.create_autocmd(events, options)
    if type(events) == "string" then
      events = { events }
    end
    for _, event in ipairs(events) do
      hooks.autocmds[event] = options.callback
    end
  end

  function hooks.delete_augroup(group)
    hooks.deleted_group = group
    hooks.autocmds = {}
  end

  function hooks.context()
    return vim.deepcopy(hooks.context_value)
  end

  function hooks.now_ms()
    return hooks.now
  end

  function hooks.keytrans(key)
    table.insert(hooks.translated, key)
    return key
  end

  function hooks.strchars(value)
    return vim.fn.strchars(value)
  end

  hooks.cmdline_value = {
    cmdtype = ":",
    abort = false,
    line = "",
  }

  function hooks.cmdline_context()
    return vim.deepcopy(hooks.cmdline_value)
  end

  hooks.translated = {}

  for key, value in pairs(overrides or {}) do
    hooks[key] = value
  end

  return hooks
end

h.describe("Neovim collector", function()
  h.it("captures typed keys and removes every hook when stopped", function()
    local hooks = fake_hooks()
    local emitted = {}
    local handle = collector.start({
      session = 8,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
    }, hooks)

    local key_callback = hooks.key_callback
    key_callback("mapped expansion", "")
    key_callback("j", "j")

    h.eq({
      {
        schema_version = 1,
        id = "8:1",
        session = 8,
        ordinal = 1,
        at_ms = 1000,
        kind = "action",
        action_id = "key:j",
        source = "keys",
        bindable = false,
        cost = 1,
        mode = "normal",
        lhs = "j",
        context = {
          filetype = "lua",
          buffer_kind = "file",
          plugin_context = "none",
        },
      },
    }, emitted)
    h.eq({ "j" }, hooks.translated)

    handle.stop()
    h.eq(nil, hooks.key_callback)
    h.eq(23, hooks.deleted_group)

    key_callback("k", "k")
    h.eq(1, #emitted)
  end)

  h.it("resolves a complete mapping lhs before capturing individual keys", function()
    local hooks = fake_hooks()
    local emitted = {}
    local candidates = {}
    local handle = collector.start({
      session = 9,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
      resolve_mapping = function(lhs, context)
        table.insert(candidates, { lhs = lhs, mode = context.mode })
        if lhs == "g" then
          return { pending = true }
        end
        if lhs == "gd" then
          return {
            action_id = "command:vim.lsp.buf.definition",
            category = "navigation",
            bindable = true,
          }
        end
      end,
    }, hooks)

    hooks.key_callback("g", "g")
    hooks.key_callback("d", "d")
    hooks.key_callback("mapped d", "")
    hooks.key_callback("j", "j")

    h.eq({
      { lhs = "g", mode = "n" },
      { lhs = "gd", mode = "n" },
      { lhs = "j", mode = "n" },
    }, candidates)
    h.eq(2, #emitted)
    h.eq({
      action_id = "command:vim.lsp.buf.definition",
      source = "mapping",
      bindable = true,
      cost = 2,
      lhs = "gd",
      ordinal = 1,
    }, {
      action_id = emitted[1].action_id,
      source = emitted[1].source,
      bindable = emitted[1].bindable,
      cost = emitted[1].cost,
      lhs = emitted[1].lhs,
      ordinal = emitted[1].ordinal,
    })
    h.eq({ action_id = "key:j", ordinal = 2 }, {
      action_id = emitted[2].action_id,
      ordinal = emitted[2].ordinal,
    })

    handle.stop()
  end)

  h.it("normalizes mouse tokens and never persists content-bearing keys", function()
    local hooks = fake_hooks()
    local emitted = {}
    local handle = collector.start({
      session = 10,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
    }, hooks)

    hooks.context_value.mode = "i"
    hooks.key_callback("secret", "secret")
    hooks.key_callback("left click", "<LeftMouse>")
    hooks.key_callback("left drag", "<LeftDrag>")
    hooks.key_callback("wheel", "<ScrollWheelDown>")
    hooks.context_value.mode = "c"
    hooks.key_callback("command argument", "private-command-argument")
    hooks.context_value.mode = "t"
    hooks.key_callback("terminal input", "private-shell-input")

    h.eq(
      {
        "category:insert_input",
        "mouse:left_click",
        "mouse:left_drag",
        "mouse:scroll_down",
        "category:command_line_input",
        "category:terminal_input",
      },
      vim.tbl_map(function(observation)
        return observation.action_id
      end, emitted)
    )
    for _, observation in ipairs(emitted) do
      h.falsy(observation.action_id:find("private", 1, true))
      if observation.source ~= "mouse" then
        h.eq(nil, observation.lhs)
      end
    end

    handle.stop()
  end)

  h.it("records an executed normal command identity without its arguments", function()
    local hooks = fake_hooks()
    local emitted = {}
    local handle = collector.start({
      session = 11,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
    }, hooks)

    hooks.cmdline_value = {
      cmdtype = ":",
      abort = false,
      line = "Telescope find_files cwd=/private/project",
    }
    hooks.autocmds.CmdlineLeave()

    h.eq(1, #emitted)
    local observation = emitted[1]
    h.eq("command:Telescope", observation.action_id)
    h.eq("command", observation.source)
    h.eq(true, observation.bindable)
    h.eq("normal", observation.mode)
    h.eq(nil, observation.lhs)
    h.eq(11, observation.session)
    h.eq(1, observation.ordinal)

    handle.stop()
  end)

  h.it("keeps the invoking mode when the live mode at CmdlineLeave is the cmdline", function()
    local hooks = fake_hooks()
    local emitted = {}
    local handle = collector.start({
      session = 14,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
    }, hooks)

    hooks.key_callback(":", ":")
    hooks.context_value.mode = "c"
    hooks.cmdline_value = {
      cmdtype = ":",
      abort = false,
      line = "Example",
    }
    hooks.autocmds.CmdlineLeave()

    h.eq(2, #emitted)
    local command = emitted[2]
    h.eq("command:Example", command.action_id)
    h.eq("normal", command.mode)
    h.eq(true, command.bindable)
    h.eq(nil, command.lhs)
    h.eq(14, command.session)
    h.eq(2, command.ordinal)

    handle.stop()
  end)

  h.it("ignores abandoned, non-colon, and terminal command lines", function()
    local cases = {
      {
        name = "aborted",
        context = { mode = "n", filetype = "lua", buffer_kind = "file", plugin_context = "none" },
        cmdline = { cmdtype = ":", abort = true, line = "w" },
      },
      {
        name = "search",
        context = { mode = "n", filetype = "lua", buffer_kind = "file", plugin_context = "none" },
        cmdline = { cmdtype = "/", abort = false, line = "secret" },
      },
      {
        name = "expression",
        context = { mode = "n", filetype = "lua", buffer_kind = "file", plugin_context = "none" },
        cmdline = { cmdtype = "=", abort = false, line = "secret" },
      },
      {
        name = "terminal buffer",
        context = { mode = "n", filetype = "", buffer_kind = "terminal", plugin_context = "none" },
        cmdline = { cmdtype = ":", abort = false, line = "git status" },
      },
      {
        name = "prompt buffer",
        context = { mode = "n", filetype = "", buffer_kind = "prompt", plugin_context = "none" },
        cmdline = { cmdtype = ":", abort = false, line = "secret" },
      },
    }

    for _, case in ipairs(cases) do
      local hooks = fake_hooks()
      hooks.context_value = case.context
      hooks.cmdline_value = case.cmdline
      local emitted = {}
      local handle = collector.start({
        session = 12,
        emit = function(observation)
          table.insert(emitted, observation)
        end,
      }, hooks)

      hooks.autocmds.CmdlineLeave()
      h.eq(0, #emitted, case.name .. " must not record an Observation")
      handle.stop()
    end
  end)

  h.it("stops observing commands when the collector is stopped", function()
    local hooks = fake_hooks()
    local emitted = {}
    local handle = collector.start({
      session = 13,
      emit = function(observation)
        table.insert(emitted, observation)
      end,
    }, hooks)

    h.truthy(hooks.autocmds.CmdlineLeave)

    handle.stop()
    h.eq({}, hooks.autocmds)
    h.eq(23, hooks.deleted_group)

    hooks.cmdline_value = { cmdtype = ":", abort = false, line = "write" }
    h.eq(0, #emitted)
  end)
end)
