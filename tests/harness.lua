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
