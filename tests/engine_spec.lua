local h = require("tests.harness")

local describe = h.describe
local it = h.it
local eq = h.eq

local function empty_inventory()
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
end

local function analysis_cycle(now_ms, observations)
  return {
    now_ms = now_ms,
    observations = observations or {},
    feedback = {},
    inventory = empty_inventory(),
  }
end

local function repeated_actions(action_id)
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
        plugin_context = "",
      },
    }
  end
  return observations
end

local function repeated_sequence(first_action, second_action)
  local observations = {}
  local index = 0
  for session = 1, 3 do
    for repetition = 1, 2 do
      local base_ms = session * 10000 + repetition * 3000
      for offset, action_id in ipairs({ first_action, second_action }) do
        index = index + 1
        local ordinal = (repetition - 1) * 2 + offset
        observations[index] = {
          id = string.format("%d:%d", session, ordinal),
          session = session,
          ordinal = ordinal,
          at_ms = base_ms + offset * 100,
          kind = "action",
          action_id = action_id,
          mode = "n",
          source = "keys",
          bindable = true,
          cost = 2,
          context = {
            filetype = "lua",
            buffer_kind = "file",
            plugin_context = "",
          },
        }
      end
    end
  end
  return observations
end

local function repeated_motion(action_id, lhs)
  local observations = {}
  local index = 0
  for session = 1, 3 do
    for repetition = 1, 2 do
      local base_ms = session * 100000 + repetition * 10000
      for ordinal_in_run = 1, 5 do
        index = index + 1
        local ordinal = (repetition - 1) * 5 + ordinal_in_run
        observations[index] = {
          id = string.format("%d:%d", session, ordinal),
          session = session,
          ordinal = ordinal,
          at_ms = base_ms + ordinal_in_run * 100,
          kind = "action",
          action_id = action_id,
          mode = "n",
          source = "keys",
          bindable = false,
          cost = 1,
          context = {
            filetype = "lua",
            buffer_kind = "file",
            plugin_context = "",
          },
          lhs = lhs,
        }
      end
    end
  end
  return observations
end

describe("recommendation engine", function()
  it("creates an empty checkpoint from a valid analysis cycle", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 1000,
      observations = {},
      feedback = {},
      inventory = {
        revision = "inventory-1",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = { "<leader>f" },
        },
        mappings = {},
      },
    })

    eq(nil, problem)
    eq(1, transition.checkpoint.version)
    eq({}, transition.recommendations)
    eq({}, transition.exclusions)
    eq({}, transition.adoptions)
    eq({}, transition.notices)
  end)

  it("rejects content-bearing fields outside the closed Observation schema", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 1000,
      observations = {
        {
          id = "1:1",
          session = 1,
          ordinal = 1,
          at_ms = 900,
          kind = "action",
          action_id = "workspace.find_files",
          mode = "n",
          source = "command",
          bindable = true,
          cost = 4,
          context = {
            filetype = "lua",
            buffer_kind = "file",
            plugin_context = "telescope",
          },
          inserted_text = "secret",
        },
      },
      feedback = {},
      inventory = {
        revision = "inventory-1",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = {},
        },
        mappings = {},
      },
    })

    eq(nil, transition)
    eq("invalid_observation", problem.code)
    eq("cycle.observations[1].inserted_text", problem.path)
  end)

  it("rejects malformed cycles, checkpoints, required fields, and inventories", function()
    local engine = require("keycoach.engine")

    local cases = {
      {
        previous = nil,
        cycle = nil,
        code = "invalid_cycle",
        path = "cycle",
      },
      {
        previous = { version = 99 },
        cycle = analysis_cycle(1000),
        code = "invalid_checkpoint",
        path = "checkpoint.version",
      },
      {
        previous = nil,
        cycle = analysis_cycle(1000, {
          {
            id = "1:1",
            session = 1,
            ordinal = 1,
            at_ms = 900,
            kind = "action",
            action_id = "workspace.find_files",
            mode = "n",
            source = "command",
            bindable = true,
            context = {
              filetype = "lua",
              buffer_kind = "file",
              plugin_context = "",
            },
          },
        }),
        code = "invalid_observation",
        path = "cycle.observations[1].cost",
      },
      {
        previous = nil,
        cycle = {
          now_ms = 1000,
          observations = {},
          feedback = {},
          inventory = {
            complete = true,
            conventions = {
              leader = "<leader>",
              localleader = "<localleader>",
              prefixes = {},
            },
            mappings = {},
          },
        },
        code = "invalid_inventory",
        path = "cycle.inventory.revision",
      },
    }

    for _, case in ipairs(cases) do
      local ok, transition, problem = pcall(engine.advance, case.previous, case.cycle)
      eq(true, ok)
      eq(nil, transition)
      eq(case.code, problem.code)
      eq(case.path, problem.path)
    end
  end)

  it("keeps retries idempotent and rejects time, order, and identity collisions", function()
    local engine = require("keycoach.engine")
    local observation = repeated_actions("workspace.find_files")[1]
    observation.at_ms = 900
    local first, first_problem = engine.advance(nil, analysis_cycle(1000, { observation }))

    eq(nil, first_problem)
    local retried, retry_problem = engine.advance(first.checkpoint, analysis_cycle(1000, { observation }))
    eq(nil, retry_problem)
    eq(first.checkpoint, retried.checkpoint)

    local collision = vim.deepcopy(observation)
    collision.action_id = "workspace.other_action"
    collision.at_ms = 1100
    local collision_transition, collision_problem = engine.advance(
      first.checkpoint,
      analysis_cycle(1200, { collision })
    )
    eq(nil, collision_transition)
    eq("id_collision", collision_problem.code)
    eq("cycle.observations[1].id", collision_problem.path)

    local out_of_order = vim.deepcopy(observation)
    out_of_order.id = "1:other"
    out_of_order.at_ms = 1100
    local order_transition, order_problem = engine.advance(
      first.checkpoint,
      analysis_cycle(1200, { out_of_order })
    )
    eq(nil, order_transition)
    eq("observation_order", order_problem.code)
    eq("cycle.observations[1].ordinal", order_problem.path)

    local time_transition, time_problem = engine.advance(first.checkpoint, analysis_cycle(999))
    eq(nil, time_transition)
    eq("time_regression", time_problem.code)
    eq("cycle.now_ms", time_problem.path)

    local future = vim.deepcopy(observation)
    future.id = "1:2"
    future.ordinal = 2
    future.at_ms = 1300
    local future_transition, future_problem = engine.advance(
      first.checkpoint,
      analysis_cycle(1200, { future })
    )
    eq(nil, future_transition)
    eq("time_regression", future_problem.code)
    eq("cycle.observations[1].at_ms", future_problem.path)

    local late = vim.deepcopy(observation)
    late.id = "2:1"
    late.session = 2
    late.at_ms = 999
    local late_transition, late_problem = engine.advance(
      first.checkpoint,
      analysis_cycle(1200, { late })
    )
    eq(nil, late_transition)
    eq("time_regression", late_problem.code)
    eq("cycle.observations[1].at_ms", late_problem.path)
  end)

  it("recommends an Existing Mapping for a frequent action across Sessions", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 2000,
      observations = repeated_actions("workspace.find_files"),
      feedback = {},
      inventory = {
        revision = "inventory-1",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = { "<leader>f" },
        },
        mappings = {
          {
            mode = "n",
            lhs = "<leader>ff",
            action_id = "workspace.find_files",
            desc = "Find files",
            buffer = false,
          },
        },
      },
    })

    eq(nil, problem)
    eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]
    eq("existing_mapping", recommendation.kind)
    eq("<leader>ff", recommendation.mapping.lhs)
    eq("workspace.find_files", recommendation.action_id)
    eq(10, recommendation.evidence.occurrences)
    eq(3, recommendation.evidence.sessions)
  end)

  it("proposes a conflict-free Mapping Candidate for a frequent unmapped action", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 2000,
      observations = repeated_actions("workspace.find_files"),
      feedback = {},
      inventory = {
        revision = "inventory-7",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = { "<leader>f" },
        },
        mappings = {
          {
            mode = "n",
            lhs = "<leader>ff",
            action_id = "workspace.other_action",
            desc = "Occupied",
            buffer = false,
          },
        },
      },
    })

    eq(nil, problem)
    eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]
    eq("mapping_candidate", recommendation.kind)
    eq(false, recommendation.mapping.lhs == "<leader>ff")
    eq("workspace.find_files", recommendation.mapping.action_id)
    eq("inventory-7", recommendation.inventory_revision)
  end)

  it("rejects exact and prefix conflicts when allocating a Mapping Candidate", function()
    local engine = require("keycoach.engine")
    local inventory = empty_inventory()
    inventory.conventions.prefixes = { "<leader>f" }
    inventory.mappings = {
      {
        mode = "n",
        lhs = "<leader>f",
        action_id = "workspace.prefix",
        buffer = false,
      },
      {
        mode = "n",
        lhs = "<leader>wfa",
        action_id = "workspace.longer",
        buffer = 7,
      },
    }
    local cycle = analysis_cycle(2000, repeated_actions("workspace.find_files"))
    cycle.inventory = inventory

    local transition, problem = engine.advance(nil, cycle)

    eq(nil, problem)
    eq(1, #transition.recommendations)
    eq("<leader>aa", transition.recommendations[1].mapping.lhs)
  end)

  it("proposes a Mapping Candidate for a repeated multi-action sequence", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 40000,
      observations = repeated_sequence("selection.expand", "edit.delete"),
      feedback = {},
      inventory = {
        revision = "inventory-1",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = {},
        },
        mappings = {},
      },
    })

    eq(nil, problem)
    eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]
    eq("mapping_candidate", recommendation.kind)
    eq({ "selection.expand", "edit.delete" }, recommendation.workflow.actions)
    eq(6, recommendation.evidence.occurrences)
    eq(3, recommendation.evidence.sessions)
  end)

  it("recommends a shorter native action for repeated primitive motions", function()
    local engine = require("keycoach.engine")

    local transition, problem = engine.advance(nil, {
      now_ms = 400000,
      observations = repeated_motion("cursor.down", "j"),
      feedback = {},
      inventory = {
        revision = "inventory-1",
        complete = true,
        conventions = {
          leader = "<leader>",
          localleader = "<localleader>",
          prefixes = {},
        },
        mappings = {},
      },
    })

    eq(nil, problem)
    eq(1, #transition.recommendations)
    local recommendation = transition.recommendations[1]
    eq("native_action", recommendation.kind)
    eq("{count}j", recommendation.native_action.keys)
    eq(6, recommendation.evidence.occurrences)
    eq(3, recommendation.evidence.sessions)
  end)

  local function later_actions(action_id, sessions, per_session, base_ms, source, lhs)
    local observations = {}
    local index = 0
    for _, session in ipairs(sessions) do
      for ordinal = 1, per_session do
        index = index + 1
        observations[index] = {
          id = string.format("%d:%d", session, ordinal),
          session = session,
          ordinal = ordinal,
          at_ms = base_ms + index * 100,
          kind = "action",
          action_id = action_id,
          mode = "n",
          source = source or "command",
          bindable = true,
          cost = 5,
          lhs = lhs,
          context = {
            filetype = "lua",
            buffer_kind = "file",
            plugin_context = "",
          },
        }
      end
    end
    return observations
  end

  local function feedback_item(kind, pattern_id, at_ms, lhs)
    return {
      id = string.format("feedback:%s:%d", kind, at_ms),
      at_ms = at_ms,
      kind = kind,
      pattern_id = pattern_id,
      lhs = lhs,
    }
  end

  local function triggered_transition()
    local engine = require("keycoach.engine")
    local transition = engine.advance(nil, analysis_cycle(2000, repeated_actions("workspace.find_files")))
    return engine, transition, transition.recommendations[1]
  end

  it("suppresses a snoozed Workflow Pattern until time and stronger evidence return", function()
    local engine, transition, recommendation = triggered_transition()
    local pattern = recommendation.pattern_id

    local snoozed = engine.advance(transition.checkpoint, {
      now_ms = 3000,
      observations = {},
      feedback = { feedback_item("snoozed", pattern, 3000) },
      inventory = empty_inventory(),
    })
    eq({}, snoozed.recommendations)

    -- 31 days later with only a little new recurrence: still silent.
    local month_ms = 31 * 86400000
    local weak = engine.advance(snoozed.checkpoint, {
      now_ms = 3000 + month_ms,
      observations = later_actions("workspace.find_files", { 4 }, 4, 3000 + month_ms - 1000),
      feedback = {},
      inventory = empty_inventory(),
    })
    eq({}, weak.recommendations)

    -- Recurrence since the Snooze now exceeds the original evidence.
    local strong = engine.advance(weak.checkpoint, {
      now_ms = 5000 + month_ms,
      observations = later_actions("workspace.find_files", { 5, 6 }, 4, 4000 + month_ms),
      feedback = {},
      inventory = empty_inventory(),
    })
    eq(1, #strong.recommendations)
    eq(pattern, strong.recommendations[1].pattern_id)
  end)

  it("excludes a Workflow Pattern permanently and restores it on request", function()
    local engine, transition, recommendation = triggered_transition()
    local pattern = recommendation.pattern_id

    local excluded = engine.advance(transition.checkpoint, {
      now_ms = 3000,
      observations = {},
      feedback = { feedback_item("excluded", pattern, 3000) },
      inventory = empty_inventory(),
    })
    eq({}, excluded.recommendations)
    eq({ { pattern_id = pattern } }, excluded.exclusions)

    local restored = engine.advance(excluded.checkpoint, {
      now_ms = 4000,
      observations = {},
      feedback = { feedback_item("restored", pattern, 4000) },
      inventory = empty_inventory(),
    })
    eq({}, restored.exclusions)
    eq(1, #restored.recommendations)
    eq(pattern, restored.recommendations[1].pattern_id)
  end)

  it("never re-proposes a key rejected for the same Workflow Pattern", function()
    local engine, transition, recommendation = triggered_transition()
    local pattern = recommendation.pattern_id
    local first_key = recommendation.mapping.lhs

    local regenerated = engine.advance(transition.checkpoint, {
      now_ms = 3000,
      observations = {},
      feedback = { feedback_item("rejected_key", pattern, 3000, first_key) },
      inventory = empty_inventory(),
    })
    eq(1, #regenerated.recommendations)
    local replacement = regenerated.recommendations[1].mapping.lhs
    eq(pattern, regenerated.recommendations[1].pattern_id)
    eq(true, replacement ~= first_key)
  end)

  it("retires an accepted Recommendation once later Sessions adopt the mapping", function()
    local engine, transition, recommendation = triggered_transition()
    local pattern = recommendation.pattern_id
    local accepted_key = recommendation.mapping.lhs

    local accepted = engine.advance(transition.checkpoint, {
      now_ms = 3000,
      observations = {},
      feedback = { feedback_item("accepted", pattern, 3000, accepted_key) },
      inventory = empty_inventory(),
    })
    eq({}, accepted.recommendations)
    eq({}, accepted.adoptions)

    local adopted = engine.advance(accepted.checkpoint, {
      now_ms = 6000,
      observations = later_actions("workspace.find_files", { 4, 5 }, 1, 4000, "mapping", accepted_key),
      feedback = {},
      inventory = empty_inventory(),
    })
    eq({ { pattern_id = pattern, lhs = accepted_key } }, adopted.adoptions)
    eq({}, adopted.recommendations)

    -- Adoption is recorded once, then stays retired.
    local settled = engine.advance(adopted.checkpoint, {
      now_ms = 7000,
      observations = {},
      feedback = {},
      inventory = empty_inventory(),
    })
    eq({}, settled.adoptions)
    eq({}, settled.recommendations)
  end)

  it("expires detailed Observations after the retention window", function()
    local engine, transition = triggered_transition()
    eq(10, #transition.checkpoint.details)

    local month_ms = 31 * 86400000
    local pruned = engine.advance(transition.checkpoint, {
      now_ms = 2000 + month_ms,
      observations = later_actions("workspace.find_files", { 4 }, 2, 1000 + month_ms),
      feedback = {},
      inventory = empty_inventory(),
    })
    eq(2, #pruned.checkpoint.details)
    -- Compact aggregate evidence remains.
    local aggregate_occurrences = 0
    for _, aggregate in pairs(pruned.checkpoint.actions) do
      aggregate_occurrences = aggregate_occurrences + aggregate.occurrences
    end
    eq(12, aggregate_occurrences)
  end)

  it("applies feedback idempotently and rejects id reuse for different data", function()
    local engine, transition, recommendation = triggered_transition()
    local pattern = recommendation.pattern_id
    local item = feedback_item("excluded", pattern, 3000)

    local first = engine.advance(transition.checkpoint, {
      now_ms = 3000,
      observations = {},
      feedback = { item, item },
      inventory = empty_inventory(),
    })
    eq(1, #first.exclusions)

    local reused = {
      id = item.id,
      at_ms = 3000,
      kind = "snoozed",
      pattern_id = pattern,
    }
    local retried, problem = engine.advance(first.checkpoint, {
      now_ms = 4000,
      observations = {},
      feedback = { reused },
      inventory = empty_inventory(),
    })
    eq(nil, retried)
    eq("id_collision", problem.code)
  end)
end)
