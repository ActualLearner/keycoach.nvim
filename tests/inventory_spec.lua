local h = require("tests.harness")

h.describe("Neovim mapping inventory", function()
  h.it("normalizes global and buffer mappings without exposing mapping bodies", function()
    local inventory = require("keycoach.nvim.inventory")

    local snapshot, problem = inventory.snapshot({
      modes = { "n" },
      buffers = { 7 },
      leader = " ",
      localleader = ",",
      get_keymap = function()
        return {
          {
            lhs = " ff",
            rhs = "<Cmd>Telescope find_files cwd=/private/project<CR>",
            desc = "Find files",
          },
        }
      end,
      get_buf_keymap = function()
        return {
          {
            lhs = ",r",
            rhs = "<Cmd>RunPrivate /private/project<CR>",
            desc = "Run task",
          },
        }
      end,
      hash = function()
        return "inventory-test"
      end,
    })

    h.eq(nil, problem)
    h.eq("inventory-test", snapshot.revision)
    h.eq(true, snapshot.complete)
    h.eq({
      leader = "<leader>",
      localleader = "<localleader>",
      prefixes = { "<leader>f" },
    }, snapshot.conventions)
    h.eq({
      {
        mode = "n",
        lhs = "<leader>ff",
        action_id = "command:Telescope",
        desc = "Find files",
        buffer = false,
      },
      {
        mode = "n",
        lhs = "<localleader>r",
        action_id = "command:RunPrivate",
        desc = "Run task",
        buffer = 7,
      },
    }, snapshot.mappings)

    h.eq(nil, snapshot.mappings[1].rhs)
    h.eq(nil, snapshot.mappings[2].rhs)
  end)

  h.it("finds exact and prefix conflicts across global and buffer mappings", function()
    local inventory = require("keycoach.nvim.inventory")
    local snapshot = {
      revision = "inventory-1",
      complete = true,
      mappings = {
        { mode = "n", lhs = "<leader>ff", action_id = "command:Files", buffer = false },
        { mode = "n", lhs = "<leader>g", action_id = "command:Git", buffer = 3 },
      },
    }

    local exact = inventory.conflict(snapshot, { mode = "n", lhs = "<leader>ff" })
    local candidate_prefix = inventory.conflict(snapshot, { mode = "n", lhs = "<leader>f" })
    local existing_prefix = inventory.conflict(snapshot, { mode = "n", lhs = "<leader>gg" })
    local free = inventory.conflict(snapshot, { mode = "n", lhs = "<leader>ss" })

    h.eq("exact", exact.kind)
    h.eq(false, exact.mapping.buffer)
    h.eq("candidate_prefix", candidate_prefix.kind)
    h.eq("existing_prefix", existing_prefix.kind)
    h.eq(nil, free)
  end)

  h.it("returns a structured problem when an editor mapping is malformed", function()
    local inventory = require("keycoach.nvim.inventory")

    local snapshot, problem = inventory.snapshot({
      modes = { "n" },
      buffers = {},
      get_keymap = function()
        return { false }
      end,
      get_buf_keymap = function()
        return {}
      end,
    })

    h.eq(nil, snapshot)
    h.eq("inventory_unavailable", problem.code)
    h.truthy(type(problem.message) == "string")
  end)
end)
