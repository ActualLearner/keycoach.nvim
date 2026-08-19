local capture = require("keycoach.nvim.capture")
local h = require("tests.harness")

local function environment(context)
  return {
    now_ms = function()
      return 1720000000123
    end,
    context = function()
      return context
    end,
    keytrans = function(key)
      return key
    end,
  }
end

h.describe("Neovim observation capture", function()
  h.it("keeps an exact Normal-mode key and only safe editor context", function()
    local observation = capture.observe(
      {
        kind = "key",
        key = "j",
        session_id = 4,
        ordinal = 9,
        text = "must not escape",
        path = "/private/project/main.lua",
      },
      environment({
        mode = "n",
        filetype = "lua",
        buffer_kind = "file",
        plugin_context = "telescope",
      })
    )

    h.eq({
      schema_version = 1,
      id = "4:9",
      session = 4,
      ordinal = 9,
      at_ms = 1720000000123,
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
        plugin_context = "telescope",
      },
    }, observation)
  end)

  h.it("reduces Insert-mode keys to an aggregate input category", function()
    local env = environment({
      mode = "i",
      filetype = "markdown",
      buffer_kind = "file",
      plugin_context = "none",
    })
    env.keytrans = function()
      error("content-bearing keys must not be normalized")
    end

    local observation = capture.observe({
      kind = "key",
      key = "hunter2",
      session_id = 5,
      ordinal = 1,
    }, env)

    h.eq({
      schema_version = 1,
      id = "5:1",
      session = 5,
      ordinal = 1,
      at_ms = 1720000000123,
      kind = "action",
      action_id = "category:insert_input",
      source = "keys",
      bindable = false,
      cost = 1,
      mode = "insert",
      context = {
        filetype = "markdown",
        buffer_kind = "file",
        plugin_context = "none",
      },
    }, observation)
  end)

  h.it("keeps exact keys in Visual, Select, and Operator-pending modes", function()
    local cases = {
      { raw = "v", expected = "visual" },
      { raw = "s", expected = "select" },
      { raw = "no", expected = "operator_pending" },
    }
    local actual = {}

    for index, case in ipairs(cases) do
      local observation = capture.observe(
        {
          kind = "key",
          key = "w",
          session_id = 6,
          ordinal = index,
        },
        environment({
          mode = case.raw,
          filetype = "lua",
          buffer_kind = "file",
          plugin_context = "none",
        })
      )
      actual[index] = {
        mode = observation.mode,
        action_id = observation.action_id,
        lhs = observation.lhs,
      }
    end

    h.eq({
      { mode = "visual", action_id = "key:w", lhs = "w" },
      { mode = "select", action_id = "key:w", lhs = "w" },
      { mode = "operator_pending", action_id = "key:w", lhs = "w" },
    }, actual)
  end)

  h.it("uses distinct aggregate categories in every content-bearing mode", function()
    local cases = {
      { raw = "i", buffer_kind = "file", mode = "insert", category = "insert_input" },
      { raw = "R", buffer_kind = "file", mode = "replace", category = "replace_input" },
      { raw = "search", buffer_kind = "file", mode = "search", category = "search_input" },
      {
        raw = "c",
        buffer_kind = "file",
        mode = "command_line",
        category = "command_line_input",
      },
      { raw = "n", buffer_kind = "prompt", mode = "prompt", category = "prompt_input" },
      { raw = "n", buffer_kind = "terminal", mode = "terminal", category = "terminal_input" },
    }
    local actual = {}

    for index, case in ipairs(cases) do
      local env = environment({
        mode = case.raw,
        filetype = "",
        buffer_kind = case.buffer_kind,
        plugin_context = "none",
      })
      env.keytrans = function()
        error("content-bearing keys must not be normalized")
      end
      local observation = capture.observe({
        kind = "key",
        key = "private input",
        session_id = 7,
        ordinal = index,
      }, env)
      actual[index] = {
        mode = observation.mode,
        action_id = observation.action_id,
        lhs = observation.lhs,
      }
    end

    h.eq({
      { mode = "insert", action_id = "category:insert_input" },
      { mode = "replace", action_id = "category:replace_input" },
      { mode = "search", action_id = "category:search_input" },
      { mode = "command_line", action_id = "category:command_line_input" },
      { mode = "prompt", action_id = "category:prompt_input" },
      { mode = "terminal", action_id = "category:terminal_input" },
    }, actual)
  end)

  h.it("normalizes mouse buttons and scrolling without key payloads", function()
    local signals = {
      { kind = "mouse", button = "left", phase = "click" },
      { kind = "mouse", button = "right", phase = "release" },
      { kind = "mouse", scroll = "up" },
      { kind = "mouse", scroll = "left" },
    }
    local actual = {}
    local env = environment({
      mode = "i",
      filetype = "lua",
      buffer_kind = "file",
      plugin_context = "none",
    })

    for index, signal in ipairs(signals) do
      signal.session_id = 8
      signal.ordinal = index
      local observation = capture.observe(signal, env)
      actual[index] = {
        action_id = observation.action_id,
        source = observation.source,
        mode = observation.mode,
        lhs = observation.lhs,
      }
    end

    h.eq({
      { action_id = "mouse:left_click", source = "mouse", mode = "insert" },
      { action_id = "mouse:right_release", source = "mouse", mode = "insert" },
      { action_id = "mouse:scroll_up", source = "mouse", mode = "insert" },
      { action_id = "mouse:scroll_left", source = "mouse", mode = "insert" },
    }, actual)
  end)

  h.it("keeps a bindable action identity but discards command arguments", function()
    local observation = capture.observe(
      {
        kind = "action",
        action_id = "command:Telescope.find_files",
        source = "command",
        category = "command",
        bindable = true,
        cost = 7,
        lhs = "<leader>ff",
        arguments = { "/private/project" },
        rhs = "Telescope find_files cwd=/private/project",
        session_id = 9,
        ordinal = 2,
      },
      environment({
        mode = "n",
        filetype = "lua",
        buffer_kind = "file",
        plugin_context = "telescope",
      })
    )

    h.eq({
      schema_version = 1,
      id = "9:2",
      session = 9,
      ordinal = 2,
      at_ms = 1720000000123,
      kind = "action",
      action_id = "command:Telescope.find_files",
      source = "command",
      bindable = true,
      cost = 7,
      mode = "normal",
      lhs = "<leader>ff",
      context = {
        filetype = "lua",
        buffer_kind = "file",
        plugin_context = "telescope",
      },
    }, observation)
  end)

  h.it("keeps editor actions only in non-content-bearing modes", function()
    local cases = {
      { raw_mode = "n", expected_action = "editor:undo", expected_bindable = true },
      { raw_mode = "i", expected_action = "category:undo", expected_bindable = false },
    }
    local actual = {}

    for index, case in ipairs(cases) do
      local observation = capture.observe(
        {
          kind = "editor",
          action = "undo",
          bindable = true,
          session_id = 10,
          ordinal = index,
        },
        environment({
          mode = case.raw_mode,
          filetype = "lua",
          buffer_kind = "file",
          plugin_context = "none",
        })
      )
      actual[index] = {
        action_id = observation.action_id,
        source = observation.source,
        bindable = observation.bindable,
        lhs = observation.lhs,
      }
    end

    h.eq({
      { action_id = "editor:undo", source = "editor", bindable = true },
      { action_id = "category:undo", source = "editor", bindable = false },
    }, actual)
  end)

  h.it("rejects multi-key chunks and unsafe context labels", function()
    local observation = capture.observe(
      {
        kind = "key",
        key = "pasted secret",
        session_id = 11,
        ordinal = 3,
      },
      environment({
        mode = "n",
        filetype = "lua /private/file",
        buffer_kind = "/private/buffer",
        plugin_context = "plugin private project",
      })
    )

    h.eq({
      schema_version = 1,
      id = "11:3",
      session = 11,
      ordinal = 3,
      at_ms = 1720000000123,
      kind = "action",
      action_id = "category:other_input",
      source = "keys",
      bindable = false,
      cost = 1,
      mode = "normal",
      context = {
        filetype = "unknown",
        buffer_kind = "unknown",
        plugin_context = "none",
      },
    }, observation)
  end)

  h.it("drops signals without a portable identity or timestamp", function()
    local context = {
      mode = "n",
      filetype = "lua",
      buffer_kind = "file",
      plugin_context = "none",
    }
    local invalid_time = environment(context)
    invalid_time.now_ms = function()
      return -1
    end

    local actual = {
      capture.observe(
        { kind = "key", key = "j", session_id = 0, ordinal = 1 },
        environment(context)
      ),
      capture.observe(
        { kind = "key", key = "j", session_id = 1, ordinal = 1.5 },
        environment(context)
      ),
      capture.observe({ kind = "key", key = "j", session_id = 1, ordinal = 1 }, invalid_time),
    }

    h.eq({}, actual)
  end)
end)
