local h = require("tests.harness")

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

local function empty_inventory()
  return {
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
end

local function stub_collector()
  local captured = {}
  return {
    captured = captured,
    start = function(options)
      captured.session = options.session
      captured.emit = options.emit
      captured.now_ms = options.now_ms
      captured.resolve_mapping = options.resolve_mapping
      return {
        stop = function()
          captured.stopped = true
        end,
      }
    end,
  }
end

local function observations_for(action_id)
  local observations = {}
  for ordinal = 1, 10 do
    local session = math.floor((ordinal - 1) / 4) + 1
    observations[ordinal] = {
      id = string.format("%d:%d", session, ordinal),
      session = session,
      ordinal = ordinal,
      at_ms = ordinal * 100,
      kind = "action",
      action_id = action_id,
      mode = "n",
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
  return observations
end

local function conflict_after_snapshot_inventory()
  local taken = false
  return {
    take = function()
      taken = true
    end,
    snapshot = function()
      if taken then
        return {
          revision = "inventory-2",
          complete = true,
          conventions = {
            leader = "<leader>",
            localleader = "<localleader>",
            prefixes = {},
          },
          mappings = {
            {
              mode = "n",
              lhs = "<leader>e",
              action_id = "command:Other",
              desc = "taken",
              buffer = false,
            },
          },
        }
      end
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
end

h.describe("KeyCoach public interface", function()
  h.it("reports disabled tracking when setup opts out", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = false })

    h.eq({ tracking = "disabled", ready_count = 0, pending_count = 0 }, keycoach.status())
    h.eq("KC off", keycoach.statusline())
  end)

  h.it("pauses and resumes an enabled tracker", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = true, collector = stub_collector() })

    h.eq(true, keycoach.pause())
    h.eq({ tracking = "paused", ready_count = 0, pending_count = 0 }, keycoach.status())
    h.eq("KC paused", keycoach.statusline())

    h.eq(true, keycoach.resume())
    h.eq({ tracking = "tracking", ready_count = 0, pending_count = 0 }, keycoach.status())
    h.eq("KC on", keycoach.statusline())
  end)

  h.it("resolves a mapping whose leader contains a percent sign", function()
    package.loaded["keycoach"] = nil

    local collector = stub_collector()
    local keycoach = require("keycoach")
    vim.g.mapleader = "%"
    keycoach.setup({
      enabled = true,
      inventory = {
        snapshot = function()
          return {
            revision = "inventory-1",
            complete = true,
            conventions = {
              leader = "<leader>",
              localleader = "<localleader>",
              prefixes = {},
            },
            mappings = {
              {
                mode = "n",
                lhs = "<leader>e",
                action_id = "command:Example",
                desc = "example",
                buffer = false,
              },
            },
          }
        end,
      },
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    local resolved = collector.captured.resolve_mapping("<leader>e", { mode = "n" })
    vim.g.mapleader = nil

    h.truthy(resolved)
    h.eq(true, resolved.bindable)
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
      "KeyCoachData",
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

  h.it("buffers live observations and exposes them as pending", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("pending/state.json")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })

    collector.captured.emit(observations_for("command:Example")[1])
    collector.captured.emit(observations_for("command:Example")[2])

    h.eq(2, keycoach.status().pending_count)
    h.eq("KC on", keycoach.statusline())
  end)

  h.it("flushes recorded observations and reloads the durable checkpoint", function()
    package.loaded["keycoach"] = nil
    local state_path = temporary_path("flush/state.json")
    local collector = stub_collector()

    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    collector.captured.emit({
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
      inventory = empty_inventory(),
    })
    h.eq(
      1,
      keycoach.inspect().checkpoint.actions["n|workspace.find_files|lua|file|none"].occurrences
    )
  end)

  h.it("appends an accepted mapping candidate and retires it on the next cycle", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("apply/state.json")
    local mapping_file = temporary_path("apply/mappings.lua")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      mapping_file = mapping_file,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })

    for _, observation in ipairs(observations_for("command:Example")) do
      collector.captured.emit(observation)
    end

    local transition, flush_problem = keycoach.flush()
    h.eq(nil, flush_problem)
    h.eq(1, #transition.recommendations)
    h.eq("mapping_candidate", transition.recommendations[1].kind)
    h.eq("KC 1", keycoach.statusline())

    local window = keycoach.open()
    local dashboard_lines =
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)
    local rendered = table.concat(dashboard_lines, "\n")
    h.truthy(rendered:find("Add mapping", 1, true), "dashboard should list the recommendation")
    h.truthy(rendered:find(transition.recommendations[1].mapping.lhs, 1, true))
    vim.api.nvim_win_close(window, true)

    local recommendation = transition.recommendations[1]
    local result, apply_problem = keycoach.apply(recommendation, { confirmed = true })

    h.eq(nil, apply_problem)
    h.eq(true, result.applied)
    local appended = read_file(mapping_file)
    h.truthy(appended:find("vim.keymap.set(", 1, true))
    h.truthy(appended:find(recommendation.mapping.lhs, 1, true))
    h.truthy(appended:find("<Cmd>Example<CR>", 1, true))

    local after_apply, after_problem = keycoach.flush(true)
    h.eq(nil, after_problem)
    h.eq(0, #after_apply.recommendations)
    h.eq("KC on", keycoach.statusline())
  end)

  h.it("regenerates a mapping candidate when its key is taken at apply time", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("regenerate/state.json")
    local mapping_file = temporary_path("regenerate/mappings.lua")
    local collector = stub_collector()
    local inventory = conflict_after_snapshot_inventory()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      mapping_file = mapping_file,
      inventory = inventory,
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })

    for _, observation in ipairs(observations_for("command:Example")) do
      collector.captured.emit(observation)
    end
    local transition, flush_problem = keycoach.flush()
    h.eq(nil, flush_problem)
    h.eq("<leader>e", transition.recommendations[1].mapping.lhs)

    inventory.take()
    local result, problem = keycoach.apply(transition.recommendations[1], { confirmed = true })
    h.eq(nil, problem)
    h.eq(true, result.regenerated)
    h.eq(0, vim.fn.filereadable(mapping_file))

    local regenerated, regenerate_problem = keycoach.flush(true)
    h.eq(nil, regenerate_problem)
    h.eq(1, #regenerated.recommendations)
    h.falsy(regenerated.recommendations[1].mapping.lhs == "<leader>e")
  end)

  h.it("clears stored evidence but keeps consent and the mappings file", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("clear/state.json")
    local mapping_file = temporary_path("clear/mappings.lua")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      mapping_file = mapping_file,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    collector.captured.emit(observations_for("command:Example")[1])
    keycoach.flush()

    h.eq(true, keycoach.clear({ confirmed = true }))
    h.eq(0, vim.fn.filereadable(state_path))
    h.eq(nil, keycoach.inspect().checkpoint)
    h.eq("tracking", keycoach.status().tracking)

    package.loaded["keycoach"] = nil
    keycoach = require("keycoach")
    keycoach.setup({
      enabled = false,
      state_path = state_path,
      mapping_file = mapping_file,
    })
    h.eq(mapping_file, keycoach.inspect().settings.mapping_file)
  end)

  h.it("runs onboarding without consent and starts tracking on completion", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("onboarding/state.json")
    local collector = stub_collector()
    local ran
    local keycoach = require("keycoach")
    keycoach.setup({
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
      onboarding = {
        run = function(options)
          ran = options
          options.on_complete("/tmp/keycoach_mappings.lua")
        end,
      },
    })

    h.eq("pending", keycoach.status().tracking)
    h.eq(false, keycoach.enable())
    h.eq("tracking", keycoach.status().tracking)
    h.truthy(ran)
    h.eq("/tmp/keycoach_mappings.lua", keycoach.inspect().settings.mapping_file)
    h.eq(1, collector.captured.session)
  end)

  h.it("records acknowledged feedback for existing mappings and native actions", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("ack/state.json")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })

    local result, problem = keycoach.apply({
      id = "existing:x",
      pattern_id = "action:n:telescope.find_files",
      kind = "existing_mapping",
      mapping = { lhs = "<leader>ff" },
    })
    h.eq(nil, problem)
    h.eq(true, result.acknowledged)
    h.truthy(keycoach.inspect().checkpoint.accepted["action:n:telescope.find_files"])
  end)

  h.it("rolls over to a new session after the idle gap", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("rollover/state.json")
    local collector = stub_collector()
    local current = 1000
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return current
      end,
      session_idle_minutes = 30,
    })

    h.eq(1, collector.captured.session)

    collector.captured.emit({
      id = "1:1",
      session = 1,
      ordinal = 1,
      at_ms = 1000,
      kind = "action",
      action_id = "key:j",
      mode = "n",
      source = "keys",
      bindable = false,
      cost = 1,
      context = { filetype = "lua", buffer_kind = "file", plugin_context = "none" },
    })

    current = 1000 + 31 * 60000
    collector.captured.emit({
      id = "1:2",
      session = 1,
      ordinal = 2,
      at_ms = 1000 + 31 * 60000,
      kind = "action",
      action_id = "key:j",
      mode = "n",
      source = "keys",
      bindable = false,
      cost = 1,
      context = { filetype = "lua", buffer_kind = "file", plugin_context = "none" },
    })

    h.eq(2, collector.captured.session)
    h.eq(2, keycoach.status().pending_count)
  end)

  h.it("allocates a fresh session when resuming after the session was persisted", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("resume/state.json")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })

    h.eq(1, collector.captured.session)
    collector.captured.emit(observations_for("command:Example")[1])
    local first_transition, first_problem = keycoach.flush()
    h.eq(nil, first_problem)
    h.eq(1, first_transition.checkpoint.last_session)

    keycoach.pause()
    keycoach.resume()

    h.eq(2, collector.captured.session)
    collector.captured.emit({
      id = "2:1",
      session = 2,
      ordinal = 1,
      at_ms = 2000,
      kind = "action",
      action_id = "command:Example",
      mode = "n",
      source = "command",
      bindable = true,
      cost = 5,
      context = {
        filetype = "lua",
        buffer_kind = "file",
        plugin_context = "none",
      },
    })
    local transition, problem = keycoach.flush(true)
    h.eq(nil, problem)
    h.eq(2, transition.checkpoint.last_session)
  end)

  h.it("drives pause, resume, and status through its user commands", function()
    package.loaded["keycoach"] = nil

    local keycoach = require("keycoach")
    keycoach.setup({ enabled = true, collector = stub_collector() })

    vim.cmd("KeyCoachPause")
    h.eq("paused", keycoach.status().tracking)

    vim.cmd("KeyCoachResume")
    h.eq("tracking", keycoach.status().tracking)
  end)

  h.it("opens the configured mappings file through its user command", function()
    package.loaded["keycoach"] = nil

    local mapping_file = temporary_path("mappings.lua")
    local keycoach = require("keycoach")
    keycoach.setup({ enabled = false, mapping_file = mapping_file })

    vim.cmd("KeyCoachMappings")
    h.eq(mapping_file, vim.fn.fnamemodify(vim.fn.expand("%:p"), ":p"))
  end)

  h.it("exports the durable checkpoint through the data command", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("export/state.json")
    local export_path = temporary_path("export/out.json")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    collector.captured.emit(observations_for("command:Example")[1])
    keycoach.flush()

    keycoach.data({ action = "export", path = export_path })
    local json = read_file(export_path)
    h.eq(
      "command:Example",
      vim.json.decode(json).actions["n|command:Example|lua|file|none"].action_id
    )
  end)

  h.it("inspects the checkpoint as pretty-printed JSON in a scratch buffer", function()
    package.loaded["keycoach"] = nil

    local state_path = temporary_path("inspect/state.json")
    local collector = stub_collector()
    local keycoach = require("keycoach")
    keycoach.setup({
      enabled = true,
      state_path = state_path,
      inventory = empty_inventory(),
      collector = collector,
      now_ms = function()
        return 2000
      end,
    })
    collector.captured.emit(observations_for("command:Example")[1])
    keycoach.flush()

    keycoach.data({ action = "inspect" })
    local buffer = vim.api.nvim_get_current_buf()
    h.eq("json", vim.bo[buffer].filetype)
    h.eq("nofile", vim.bo[buffer].buftype)
    h.eq(false, vim.bo[buffer].modifiable)
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    h.eq("{", lines[1])
    h.truthy(table.concat(lines, "\n"):match('"n|command:Example|lua|file|none"'))
  end)
end)
