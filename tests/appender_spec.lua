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

local function current_inventory(revision, mappings)
  return function()
    return {
      revision = revision,
      complete = true,
      mappings = mappings or {},
    }
  end
end

h.describe("mapping appender", function()
  h.it("appends one readable keymap statement to a selected Lua file", function()
    local appender = require("keycoach.appender")
    local path = temporary_path("mappings.lua")
    local expected_line =
      'vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<CR>", { desc = "Find files", silent = true })'

    local result, problem = appender.append(path, {
      mode = "n",
      lhs = "<leader>ff",
      rhs = "<cmd>Telescope find_files<CR>",
      opts = { desc = "Find files", silent = true },
    }, {
      expected_revision = "inventory-7",
      current_inventory = current_inventory("inventory-7"),
    })

    h.eq(nil, problem)
    h.eq(expected_line, result.line)
    h.eq(#expected_line + 1, result.bytes_written)
    h.eq(expected_line .. "\n", read_file(path))
  end)

  h.it("returns a structured problem when the live inventory is malformed", function()
    local appender = require("keycoach.appender")
    local path = temporary_path("mappings.lua")

    local result, problem = appender.append(path, {
      mode = "n",
      lhs = "<leader>ff",
      rhs = "<cmd>Telescope find_files<CR>",
    }, {
      expected_revision = "inventory-7",
      current_inventory = current_inventory("inventory-7", { false }),
    })

    h.eq(nil, result)
    h.eq("inventory_unavailable", problem.code)
    h.eq(path, problem.path)
    h.eq(0, vim.fn.filereadable(path))
  end)

  h.it("contains non-table inventory failures instead of throwing", function()
    local appender = require("keycoach.appender")
    local path = temporary_path("mappings.lua")

    local result, problem = appender.append(path, {
      mode = "n",
      lhs = "<leader>ff",
      rhs = "<cmd>Telescope find_files<CR>",
    }, {
      expected_revision = "inventory-7",
      current_inventory = function()
        return nil, 42
      end,
    })

    h.eq(nil, result)
    h.eq("inventory_unavailable", problem.code)
    h.eq("42", problem.message)
    h.eq(0, vim.fn.filereadable(path))
  end)

  h.it("rejects exact and prefix conflicts in overlapping global and buffer modes", function()
    local appender = require("keycoach.appender")
    local cases = {
      {
        candidate = { mode = "n", lhs = "<leader>ff" },
        mapping = { mode = "n", raw_lhs = " ff", buffer = false },
      },
      {
        candidate = { mode = "v", lhs = "<leader>f" },
        mapping = { mode = "x", raw_lhs = " ff", buffer = 3 },
      },
      {
        candidate = { mode = "s", lhs = "<leader>gg" },
        mapping = { mode = "v", raw_lhs = " g", buffer = 7 },
      },
    }

    for _, case in ipairs(cases) do
      local path = temporary_path("mappings.lua")
      local result, problem = appender.append(path, {
        mode = case.candidate.mode,
        lhs = case.candidate.lhs,
        rhs = "<cmd>Example<CR>",
      }, {
        expected_revision = "inventory-7",
        current_inventory = function()
          return {
            revision = "inventory-7",
            complete = true,
            leader = " ",
            mappings = { case.mapping },
          }
        end,
      })

      h.eq(nil, result)
      h.eq("mapping_conflict", problem.code)
      h.eq(path, problem.path)
      h.eq(0, vim.fn.filereadable(path))
    end
  end)
end)
