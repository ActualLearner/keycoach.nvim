local M = {}

local suites = {}
local active_suite

local function render(value)
  return vim.inspect(value)
end

function M.describe(name, callback)
  local suite = { name = name, tests = {} }
  table.insert(suites, suite)
  active_suite = suite
  callback()
  active_suite = nil
end

function M.it(name, callback)
  assert(active_suite, "it() must be called inside describe()")
  table.insert(active_suite.tests, { name = name, callback = callback })
end

function M.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(message or ("expected " .. render(expected) .. ", got " .. render(actual)), 2)
  end
end

function M.truthy(actual, message)
  if not actual then
    error(message or ("expected truthy value, got " .. render(actual)), 2)
  end
end

function M.falsy(actual, message)
  if actual then
    error(message or ("expected falsy value, got " .. render(actual)), 2)
  end
end

function M.matches(pattern, actual, message)
  if type(actual) ~= "string" or not actual:match(pattern) then
    error(message or ("expected " .. render(actual) .. " to match " .. render(pattern)), 2)
  end
end

function M.fake_hooks(overrides)
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
    now = 1000,
    translated = {},
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

function M.run()
  local passed = 0
  local failed = 0

  for _, suite in ipairs(suites) do
    io.stdout:write(suite.name .. "\n")
    for _, test in ipairs(suite.tests) do
      local ok, problem = xpcall(test.callback, debug.traceback)
      if ok then
        passed = passed + 1
        io.stdout:write("  PASS " .. test.name .. "\n")
      else
        failed = failed + 1
        io.stderr:write("  FAIL " .. test.name .. "\n" .. problem .. "\n")
      end
    end
  end

  io.stdout:write(string.format("\n%d passed, %d failed\n", passed, failed))

  if failed > 0 then
    vim.cmd("cquit 1")
  end
end

return M
