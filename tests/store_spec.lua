local h = require("tests.harness")

local function temporary_path(name)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  return root .. "/" .. name
end

h.describe("checkpoint store", function()
  h.it("treats a missing checkpoint as empty state", function()
    local store = require("keycoach.store")

    local checkpoint, problem = store.load(temporary_path("missing.json"))

    h.eq(nil, checkpoint)
    h.eq(nil, problem)
  end)

  h.it("round-trips a portable checkpoint through a new parent directory", function()
    local store = require("keycoach.store")
    local path = temporary_path("nested/state.json")
    local expected = {
      version = 1,
      sessions = { 2, 4 },
      evidence = { ["native:counted-motion"] = 12 },
    }

    local saved, save_problem = store.save(path, expected)
    local actual, load_problem = store.load(path)

    h.eq(true, saved)
    h.eq(nil, save_problem)
    h.eq(expected, actual)
    h.eq(nil, load_problem)
  end)

  h.it("exports the stored checkpoint as portable JSON", function()
    local store = require("keycoach.store")
    local path = temporary_path("state.json")
    local checkpoint = { version = 1, patterns = { "motion:j", "command:write" } }
    h.eq(true, store.save(path, checkpoint))

    local json, problem = store.export(path)

    h.eq(nil, problem)
    h.eq(checkpoint, vim.json.decode(json))
  end)

  h.it("deletes a checkpoint idempotently", function()
    local store = require("keycoach.store")
    local path = temporary_path("state.json")
    h.eq(true, store.save(path, { version = 1 }))

    local first, first_problem = store.delete(path)
    local second, second_problem = store.delete(path)
    local checkpoint, load_problem = store.load(path)

    h.eq(true, first)
    h.eq(nil, first_problem)
    h.eq(true, second)
    h.eq(nil, second_problem)
    h.eq(nil, checkpoint)
    h.eq(nil, load_problem)
  end)

  h.it("returns a structured problem for corrupt checkpoint JSON", function()
    local store = require("keycoach.store")
    local path = temporary_path("state.json")
    local file = assert(io.open(path, "wb"))
    assert(file:write("{not-json"))
    assert(file:close())

    local checkpoint, problem = store.load(path)

    h.eq(nil, checkpoint)
    h.eq("invalid_json", problem.code)
    h.eq(path, problem.path)
    h.truthy(type(problem.message) == "string" and problem.message ~= "")
  end)

  h.it("rejects a nil checkpoint so it cannot be confused with missing state", function()
    local store = require("keycoach.store")
    local path = temporary_path("state.json")

    local saved, problem = store.save(path, nil)
    local checkpoint, load_problem = store.load(path)

    h.eq(nil, saved)
    h.eq("invalid_checkpoint", problem.code)
    h.eq(nil, checkpoint)
    h.eq(nil, load_problem)
  end)

  h.it("rejects a stored JSON value that is not a checkpoint table", function()
    local store = require("keycoach.store")
    local path = temporary_path("state.json")
    local file = assert(io.open(path, "wb"))
    assert(file:write("42"))
    assert(file:close())

    local checkpoint, problem = store.load(path)

    h.eq(nil, checkpoint)
    h.eq("invalid_checkpoint", problem.code)
    h.eq(path, problem.path)
  end)
end)
