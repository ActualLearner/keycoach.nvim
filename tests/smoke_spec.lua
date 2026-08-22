local h = require("tests.harness")
local real_collector = require("keycoach.nvim.collector")

local function temporary_path(name)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  return root .. "/" .. name
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  assert(file:close())
  return contents
end

local function fake_hooks(overrides)
  local hooks = {
    autocmds = {},
    context_value = {
      mode = "n",
      filetype = "lua",
      buffer_kind = "file",
      plugin_context = "none",
    },
    cmdline_value = {
      cmdtype = ":",
      abort = false,
      line = "",
    },
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
    return hooks.now or 1000
  end

  function hooks.keytrans(key)
    return key
  end

  function hooks.strchars(value)
    return vim.fn.strchars(value)
  end

  function hooks.parse_command(line)
    if type(hooks.parse_override) == "table" and hooks.parse_override[line] ~= nil then
      return hooks.parse_override[line]
    end
    local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})
    if ok and type(parsed) == "table" then
      return parsed
    end
    return nil
  end

  function hooks.cmdline_context()
    return vim.deepcopy(hooks.cmdline_value)
  end

  for key, value in pairs(overrides or {}) do
    hooks[key] = value
  end

  return hooks
end

-- Wraps the real collector with scripted hooks and captures the options
-- init.lua passes, so tests can drive command/editor signals and read the
-- live emit callback.
local function wired_collector(hooks)
  local captured = {}
  return {
    captured = captured,
    start = function(options)
      captured.options = options
      return real_collector.start(options, hooks)
    end,
  }
end

local function onboarding_stub()
  return {
    run = function(options)
      options.on_complete(options.preset_mapping_file or options.default_mapping_file)
    end,
  }
end

local function command_observations(action_id, mode)
  local observations = {}
  local index = 0
  for session, count in ipairs({ 3, 4, 3 }) do
    for ordinal = 1, count do
      index = index + 1
      observations[index] = {
        id = string.format("%d:%d", session, ordinal),
        session = session,
        ordinal = ordinal,
        at_ms = 1000 + index * 100,
        kind = "action",
        action_id = action_id,
        mode = mode,
        source = "command",
        bindable = true,
        cost = 5,
        context = {
          filetype = "lua",
          buffer_kind = "file",
          plugin_context = "none",
        },
      }
    end
  end
  return observations
end

local function fresh_setup(hooks, options)
  package.loaded["keycoach"] = nil
  local keycoach = require("keycoach")
  keycoach.setup({
    state_path = options.state_path,
    mapping_file = options.mapping_file,
    inventory = require("keycoach.nvim.inventory"),
    collector = options.collector or wired_collector(hooks),
    onboarding = onboarding_stub(),
    now_ms = function()
      return 4000
    end,
  })
  return keycoach
end

h.describe("wired plugin smoke", function()
  h.it(
    "installs fresh, onboards, and records an executed command through the real collector",
    function()
      local state_path = temporary_path("smoke/state.json")
      local hooks = fake_hooks()
      local keycoach = fresh_setup(hooks, { state_path = state_path })

      h.eq("pending", keycoach.status().tracking)
      h.eq(false, keycoach.enable())
      h.eq("tracking", keycoach.status().tracking)
      h.eq(true, keycoach.inspect().settings.consent)

      hooks.parse_override = { Example = { cmd = "Example", range = {} } }
      hooks.key_callback(nil, ":")
      hooks.context_value.mode = "c"
      hooks.cmdline_value = { cmdtype = ":", abort = false, line = "Example" }
      hooks.autocmds.CmdlineLeave()

      local transition, problem = keycoach.flush()
      h.eq(nil, problem)
      local command_detail
      for _, detail in ipairs(transition.checkpoint.details) do
        if detail.action_id == "command:Example" then
          command_detail = detail
        end
      end
      h.truthy(command_detail)
      h.eq("n", command_detail.mode)
      h.eq("command", command_detail.source)
      h.eq(nil, command_detail.lhs)

      local observed = 0
      for _, aggregate in pairs(transition.checkpoint.actions) do
        if aggregate.action_id == "command:Example" then
          observed = observed + aggregate.occurrences
        end
      end
      h.eq(1, observed)
    end
  )

  h.it(
    "recommends, applies, and retires a Mapping Candidate through the fully wired plugin",
    function()
      local state_path = temporary_path("smoke/apply/state.json")
      local mapping_file = temporary_path("smoke/apply/mappings.lua")
      local hooks = fake_hooks()
      local collector = wired_collector(hooks)
      local keycoach = fresh_setup(hooks, {
        state_path = state_path,
        mapping_file = mapping_file,
        collector = collector,
      })
      keycoach.enable()

      for _, observation in ipairs(command_observations("command:Example", "normal")) do
        collector.captured.options.emit(observation)
      end

      local transition, flush_problem = keycoach.flush()
      h.eq(nil, flush_problem)
      h.eq(1, #transition.recommendations)
      local recommendation = transition.recommendations[1]
      h.eq("mapping_candidate", recommendation.kind)
      h.eq("command:Example", recommendation.mapping.action_id)
      h.truthy(recommendation.mapping.lhs:sub(1, 8) == "<leader>")
      h.eq("KC 1", keycoach.statusline())

      local window = keycoach.open()
      local rendered = table.concat(
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false),
        "\n"
      )
      h.truthy(rendered:find("Add mapping", 1, true))
      h.truthy(rendered:find(recommendation.mapping.lhs, 1, true))
      vim.api.nvim_win_close(window, true)

      local result, apply_problem = keycoach.apply(recommendation, { confirmed = true })
      h.eq(nil, apply_problem)
      h.eq(true, result.applied)
      local appended = read_file(mapping_file)
      h.truthy(appended:find('vim.keymap.set("n",', 1, true))
      h.truthy(appended:find(recommendation.mapping.lhs, 1, true))
      h.truthy(appended:find("<Cmd>Example<CR>", 1, true))

      local after_apply, after_problem = keycoach.flush(true)
      h.eq(nil, after_problem)
      h.eq(0, #after_apply.recommendations)
      h.eq("KC on", keycoach.statusline())
    end
  )

  h.it("applies a Mapping Candidate while its own dashboard is open", function()
    local state_path = temporary_path("smoke/open-apply/state.json")
    local mapping_file = temporary_path("smoke/open-apply/mappings.lua")
    local hooks = fake_hooks()
    local collector = wired_collector(hooks)
    local keycoach = fresh_setup(hooks, {
      state_path = state_path,
      mapping_file = mapping_file,
      collector = collector,
    })
    keycoach.enable()

    for _, observation in ipairs(command_observations("command:Example", "normal")) do
      collector.captured.options.emit(observation)
    end

    local transition, flush_problem = keycoach.flush()
    h.eq(nil, flush_problem)
    h.eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]

    local window = keycoach.open()
    h.truthy(window)

    local result, apply_problem = keycoach.apply(recommendation, { confirmed = true })
    h.eq(nil, apply_problem)
    h.eq(true, result.applied)
    local appended = read_file(mapping_file)
    h.truthy(appended:find('vim.keymap.set("n",', 1, true))

    vim.api.nvim_win_close(window, true)
  end)

  h.it("recommends the Existing Mapping already present in the real inventory", function()
    vim.keymap.set("n", "<leader>ex", "<Cmd>Example<CR>", { desc = "Open example" })

    local state_path = temporary_path("smoke/existing/state.json")
    local hooks = fake_hooks()
    local collector = wired_collector(hooks)
    local keycoach = fresh_setup(hooks, {
      state_path = state_path,
      collector = collector,
    })
    keycoach.enable()

    for _, observation in ipairs(command_observations("command:Example", "normal")) do
      collector.captured.options.emit(observation)
    end

    local transition, problem = keycoach.flush()
    h.eq(nil, problem)
    h.eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]
    h.eq("existing_mapping", recommendation.kind)
    h.eq("<leader>ex", recommendation.mapping.lhs)
    h.eq("command:Example", recommendation.action_id)
  end)
end)
