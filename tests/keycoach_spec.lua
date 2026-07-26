local h = require("tests.harness")

h.describe("KeyCoach public interface", function()
  h.it("reports disabled tracking when setup opts out", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = false })

    h.eq({ tracking = "disabled", ready_count = 0 }, keycoach.status())
    h.eq("KC off", keycoach.statusline())
  end)

  h.it("pauses and resumes an enabled tracker", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = true })

    h.eq(true, keycoach.pause())
    h.eq({ tracking = "paused", ready_count = 0 }, keycoach.status())
    h.eq("KC paused", keycoach.statusline())

    h.eq(true, keycoach.resume())
    h.eq({ tracking = "tracking", ready_count = 0 }, keycoach.status())
    h.eq("KC on", keycoach.statusline())
  end)

  h.it("registers its user commands during setup", function()
    package.loaded["keycoach"] = nil

    require("keycoach").setup({ enabled = false })
    local commands = vim.api.nvim_get_commands({ builtin = false })

    for _, name in ipairs({
      "KeyCoach",
      "KeyCoachClear",
      "KeyCoachEnable",
      "KeyCoachMappings",
      "KeyCoachPause",
      "KeyCoachResume",
      "KeyCoachStatus",
    }) do
      h.truthy(commands[name], "missing user command " .. name)
    end
  end)

  h.it("opens a quiet dashboard when there are no recommendations", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = false })
    local window = keycoach.open()

    h.truthy(vim.api.nvim_win_is_valid(window))
    local buffer = vim.api.nvim_win_get_buf(window)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    h.eq("KeyCoach", lines[1])
    h.eq("Tracking disabled", lines[3])
    h.eq("No recommendations yet", lines[5])

    vim.api.nvim_win_close(window, true)
  end)

  h.it("flushes recorded observations and reloads the durable checkpoint", function()
    package.loaded["keycoach"] = nil
    local state_path = vim.fn.tempname() .. "/state.json"
    local inventory = {
      snapshot = function()
        return {
          revision = "inventory-1",
          complete = true,
          conventions = {
            leader = "<leader>",
            localleader = "<localleader>",
            prefixes = {},
          },
          mappings = {},
        }
      end,
    }
    local emit
    local collector = {
      start = function(options)
        emit = options.emit
        return {
          stop = function() end,
        }
      end,
    }

    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = inventory,
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    emit({
      id = "1:1",
      session = 1,
      ordinal = 1,
      at_ms = 1000,
      kind = "action",
      action_id = "workspace.find_files",
      mode = "n",
      source = "command",
      bindable = true,
      cost = 5,
      context = { filetype = "lua", buffer_kind = "file", plugin_context = "none" },
    })
    local transition, problem = keycoach.flush()

    h.eq(nil, problem)
    h.eq(1, transition.checkpoint.actions["n|workspace.find_files|lua|file|none"].occurrences)
    h.eq(0, keycoach.status().pending_count)

    package.loaded["keycoach"] = nil
    keycoach = require("keycoach")
    keycoach.setup({
      enabled = false,
      state_path = state_path,
      inventory = inventory,
    })
    h.eq(1, keycoach.inspect().checkpoint.actions["n|workspace.find_files|lua|file|none"].occurrences)
  end)
end)
