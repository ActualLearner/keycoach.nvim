local h = require("tests.harness")
local report = require("keycoach.report")

local NOW_MS = 1700000000000

local function checkpoint_with(details, accepted, suppressions)
  return {
    details = details,
    accepted = accepted or {},
    suppressions = suppressions or {},
  }
end

local function detail(action_id, at_ms, session)
  return {
    action_id = action_id,
    at_ms = at_ms,
    session = session,
    mode = "n",
    kind = "action",
  }
end

h.describe("weekly report", function()
  h.it("counts only the last seven days of observations", function()
    local lines = report.lines(
      checkpoint_with({
        detail("command:Telescope", NOW_MS - 1000, 4),
        detail("command:Telescope", NOW_MS - 2000, 5),
        detail("category:insert_input", NOW_MS - 3000, 5),
        detail("command:Telescope", NOW_MS - 8 * 86400000, 1),
      }),
      NOW_MS
    )
    local joined = table.concat(lines, "\n")

    h.truthy(joined:find("Observations this week: 3 across 2 session(s)", 1, true))
    h.truthy(joined:find("command:Telescope - 2", 1, true))
    h.falsy(joined:find("8 days ago", 1, true))
  end)

  h.it("ranks top actions by count with deterministic tiebreaks", function()
    local lines = report.lines(
      checkpoint_with({
        detail("command:b", NOW_MS - 1000, 1),
        detail("command:b", NOW_MS - 1100, 1),
        detail("command:a", NOW_MS - 1200, 1),
        detail("key:j", NOW_MS - 1300, 1),
        detail("key:k", NOW_MS - 1400, 1),
        detail("key:l", NOW_MS - 1500, 1),
        detail("key:h", NOW_MS - 1600, 1),
      }),
      NOW_MS
    )
    local joined = table.concat(lines, "\n")

    local position_b = joined:find("command:b - 2", 1, true)
    local position_a = joined:find("command:a - 1", 1, true)
    h.truthy(position_b and position_a and position_b < position_a, "higher counts rank first")
    h.truthy(joined:find("Top actions:", 1, true) ~= nil)
  end)

  h.it("summarises adoption and exclusions", function()
    local lines = report.lines(
      checkpoint_with({}, {
        pattern_one = { lhs = "<leader>t", adopted = true },
        pattern_two = { lhs = "<leader>w", adopted = false },
      }, { pattern_three = { excluded = true } }),
      NOW_MS
    )
    local joined = table.concat(lines, "\n")

    h.truthy(joined:find("Applied mappings: 2 (1 still in regular use)", 1, true))
    h.truthy(joined:find("Excluded patterns: 1", 1, true))
  end)

  h.it("stays readable when there is no data yet", function()
    local lines = report.lines(checkpoint_with({}), NOW_MS)
    local joined = table.concat(lines, "\n")

    h.truthy(joined:find("nothing observed yet", 1, true))
    h.truthy(joined:find("Applied mappings: 0", 1, true))
  end)
end)
