local h = require("tests.harness")

h.describe("checkhealth keycoach", function()
  local messages

  local function collect()
    messages = { start = nil, ok = {}, warn = {}, info = {}, error = {} }
    vim.health = {
      start = function(name)
        messages.start = name
      end,
      ok = function(msg)
        table.insert(messages.ok, msg)
      end,
      warn = function(msg, _)
        table.insert(messages.warn, msg)
      end,
      info = function(msg, _)
        table.insert(messages.info, msg)
      end,
      error = function(msg, _)
        table.insert(messages.error, msg)
      end,
    }
  end

  h.it("reports a writable data directory and consent status after setup", function()
    local root = vim.fn.tempname() .. "/keycoach-health"
    vim.fn.mkdir(root, "p")
    vim.g.keycoach_data_dir = root
    local file = io.open(root .. "/settings.json", "w")
    file:write('{"consent":true,"mapping_file":"' .. root .. '/mappings.lua"}')
    file:close()

    collect()
    require("vim.health.keycoach").check()

    h.eq("keycoach", messages.start)
    h.eq({}, messages.error)
    local joined = table.concat(messages.ok, "\n")
    h.truthy(joined:find(root, 1, true) ~= nil, "data directory is reported by path")
    h.truthy(joined:find("Consent recorded", 1, true) ~= nil)

    vim.g.keycoach_data_dir = nil
  end)

  h.it("flags an unwritable data directory as an error", function()
    vim.g.keycoach_data_dir = "/proc/keycoach-cannot-exist"

    collect()
    require("vim.health.keycoach").check()

    h.eq(1, #messages.error)
    h.truthy(messages.error[1]:find("not writable", 1, true) ~= nil)

    vim.g.keycoach_data_dir = nil
  end)

  h.it("stays informative before first setup", function()
    local root = vim.fn.tempname() .. "/keycoach-health-empty"
    vim.fn.mkdir(root, "p")
    vim.g.keycoach_data_dir = root

    collect()
    require("vim.health.keycoach").check()

    h.eq({}, messages.error)
    h.truthy(#messages.info >= 1, "setup hint is shown")

    vim.g.keycoach_data_dir = nil
  end)
end)
