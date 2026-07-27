local M = {}

local OBSERVATION_FIELDS = {
  schema_version = true,
  id = true,
  session = true,
  ordinal = true,
  at_ms = true,
  kind = true,
  action_id = true,
  mode = true,
  source = true,
  bindable = true,
  cost = true,
  context = true,
  lhs = true,
}

local CYCLE_FIELDS = {
  now_ms = true,
  observations = true,
  feedback = true,
  inventory = true,
  retention_days = true,
}

local FEEDBACK_FIELDS = {
  id = true,
  at_ms = true,
  kind = true,
  pattern_id = true,
  lhs = true,
}

local FEEDBACK_KINDS = {
  accepted = true,
  acknowledged = true,
  rejected_key = true,
  snoozed = true,
  excluded = true,
  restored = true,
}

local CONTEXT_FIELDS = {
  filetype = true,
  buffer_kind = true,
  plugin_context = true,
}

local INVENTORY_FIELDS = {
  revision = true,
  complete = true,
  conventions = true,
  mappings = true,
}

local CONVENTION_FIELDS = {
  leader = true,
  localleader = true,
  prefixes = true,
}

local MAPPING_FIELDS = {
  mode = true,
  lhs = true,
  action_id = true,
  desc = true,
  buffer = true,
}

local CHECKPOINT_FIELDS = {
  version = true,
  last_now_ms = true,
  last_session = true,
  seen_observations = true,
  seen_feedback = true,
  details = true,
  actions = true,
  sequences = true,
  session_tails = true,
  native_actions = true,
  native_tails = true,
  session_order = true,
  suppressions = true,
  accepted = true,
}

local COUNTABLE_MOTIONS = {
  ["cursor.down"] = "j",
  ["cursor.left"] = "h",
  ["cursor.right"] = "l",
  ["cursor.up"] = "k",
  ["key:b"] = "b",
  ["key:B"] = "B",
  ["key:e"] = "e",
  ["key:E"] = "E",
  ["key:h"] = "h",
  ["key:j"] = "j",
  ["key:k"] = "k",
  ["key:l"] = "l",
  ["key:w"] = "w",
  ["key:W"] = "W",
}

local MIN_MOTION_RUN_LENGTH = 5
local MIN_MOTION_RUNS = 6
local MIN_MOTION_SESSIONS = 3
local MAX_RUN_GAP_MS = 2000
local SNOOZE_MS = 30 * 86400000
local DEFAULT_RETENTION_DAYS = 30
local MIN_ADOPTION_SESSIONS = 2

local function problem(code, message, path)
  return {
    code = code,
    message = message,
    path = path,
  }
end

local function is_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value % 1 == 0
end

local function is_non_empty_string(value)
  return type(value) == "string" and value ~= ""
end

local function validate_closed(value, fields, code, path)
  if type(value) ~= "table" then
    return problem(code, "Expected a table", path)
  end
  for field in pairs(value) do
    if not fields[field] then
      return problem(code, "Value contains an unsupported field", path .. "." .. tostring(field))
    end
  end
  return nil
end

local function validate_array(value, code, path)
  if type(value) ~= "table" then
    return problem(code, "Expected an array", path)
  end

  local size = 0
  for index in pairs(value) do
    if not is_integer(index) or index < 1 then
      return problem(code, "Expected a dense array", path)
    end
    size = math.max(size, index)
  end
  for index = 1, size do
    if value[index] == nil then
      return problem(code, "Expected a dense array", path)
    end
  end
  return nil
end

local function validate_context(context, path)
  local context_problem = validate_closed(context, CONTEXT_FIELDS, "invalid_observation", path)
  if context_problem then
    return context_problem
  end
  for _, field in ipairs({ "filetype", "buffer_kind", "plugin_context" }) do
    if type(context[field]) ~= "string" then
      return problem("invalid_observation", "Observation context field must be a string", path .. "." .. field)
    end
  end
  return nil
end

local function validate_observation(observation, index)
  local path = string.format("cycle.observations[%d]", index)
  local observation_problem = validate_closed(observation, OBSERVATION_FIELDS, "invalid_observation", path)
  if observation_problem then
    return observation_problem
  end

  if observation.schema_version ~= nil and observation.schema_version ~= 1 then
    return problem("invalid_observation", "Unsupported Observation schema version", path .. ".schema_version")
  end
  if not is_non_empty_string(observation.id) then
    return problem("invalid_observation", "Observation id is required", path .. ".id")
  end
  if not is_integer(observation.session) or observation.session < 1 then
    return problem("invalid_observation", "Observation Session must be a positive integer", path .. ".session")
  end
  if not is_integer(observation.ordinal) or observation.ordinal < 1 then
    return problem("invalid_observation", "Observation ordinal must be a positive integer", path .. ".ordinal")
  end
  if not is_integer(observation.at_ms) or observation.at_ms < 0 then
    return problem("invalid_observation", "Observation time must be a non-negative integer", path .. ".at_ms")
  end
  if observation.kind ~= "action" then
    return problem("invalid_observation", "Observation kind must be action", path .. ".kind")
  end
  if not is_non_empty_string(observation.action_id) then
    return problem("invalid_observation", "Observation Action is required", path .. ".action_id")
  end
  if not is_non_empty_string(observation.mode) then
    return problem("invalid_observation", "Observation mode is required", path .. ".mode")
  end
  if not is_non_empty_string(observation.source) then
    return problem("invalid_observation", "Observation source is required", path .. ".source")
  end
  if type(observation.bindable) ~= "boolean" then
    return problem("invalid_observation", "Observation bindable must be boolean", path .. ".bindable")
  end
  if not is_integer(observation.cost) or observation.cost < 0 then
    return problem("invalid_observation", "Observation cost must be a non-negative integer", path .. ".cost")
  end
  if observation.lhs ~= nil and not is_non_empty_string(observation.lhs) then
    return problem("invalid_observation", "Observation lhs must be a non-empty string", path .. ".lhs")
  end
  return validate_context(observation.context, path .. ".context")
end

local function validate_inventory(inventory)
  local inventory_problem = validate_closed(inventory, INVENTORY_FIELDS, "invalid_inventory", "cycle.inventory")
  if inventory_problem then
    return inventory_problem
  end
  if not is_non_empty_string(inventory.revision) then
    return problem("invalid_inventory", "Inventory revision is required", "cycle.inventory.revision")
  end
  if type(inventory.complete) ~= "boolean" then
    return problem("invalid_inventory", "Inventory completeness must be boolean", "cycle.inventory.complete")
  end

  local conventions_problem = validate_closed(
    inventory.conventions,
    CONVENTION_FIELDS,
    "invalid_inventory",
    "cycle.inventory.conventions"
  )
  if conventions_problem then
    return conventions_problem
  end
  for _, field in ipairs({ "leader", "localleader" }) do
    if not is_non_empty_string(inventory.conventions[field]) then
      return problem(
        "invalid_inventory",
        "Inventory convention must be a non-empty string",
        "cycle.inventory.conventions." .. field
      )
    end
  end
  local prefixes_problem = validate_array(
    inventory.conventions.prefixes,
    "invalid_inventory",
    "cycle.inventory.conventions.prefixes"
  )
  if prefixes_problem then
    return prefixes_problem
  end
  for index, prefix in ipairs(inventory.conventions.prefixes) do
    if not is_non_empty_string(prefix) then
      return problem(
        "invalid_inventory",
        "Inventory prefix must be a non-empty string",
        string.format("cycle.inventory.conventions.prefixes[%d]", index)
      )
    end
  end

  local mappings_problem = validate_array(inventory.mappings, "invalid_inventory", "cycle.inventory.mappings")
  if mappings_problem then
    return mappings_problem
  end
  for index, mapping in ipairs(inventory.mappings) do
    local path = string.format("cycle.inventory.mappings[%d]", index)
    local mapping_problem = validate_closed(mapping, MAPPING_FIELDS, "invalid_inventory", path)
    if mapping_problem then
      return mapping_problem
    end
    for _, field in ipairs({ "mode", "lhs", "action_id" }) do
      if not is_non_empty_string(mapping[field]) then
        return problem("invalid_inventory", "Mapping field is required", path .. "." .. field)
      end
    end
    if mapping.desc ~= nil and type(mapping.desc) ~= "string" then
      return problem("invalid_inventory", "Mapping description must be a string", path .. ".desc")
    end
    if type(mapping.buffer) ~= "boolean"
      and (not is_integer(mapping.buffer) or mapping.buffer < 1)
    then
      return problem("invalid_inventory", "Mapping buffer must be false or a positive integer", path .. ".buffer")
    end
  end
  return nil
end

local function validate_feedback_item(item, index)
  local path = string.format("cycle.feedback[%d]", index)
  local item_problem = validate_closed(item, FEEDBACK_FIELDS, "invalid_feedback", path)
  if item_problem then
    return item_problem
  end
  if not is_non_empty_string(item.id) then
    return problem("invalid_feedback", "Feedback id is required", path .. ".id")
  end
  if not is_integer(item.at_ms) or item.at_ms < 0 then
    return problem("invalid_feedback", "Feedback time must be a non-negative integer", path .. ".at_ms")
  end
  if not FEEDBACK_KINDS[item.kind] then
    return problem("invalid_feedback", "Unsupported feedback kind", path .. ".kind")
  end
  if not is_non_empty_string(item.pattern_id) then
    return problem("invalid_feedback", "Feedback Workflow Pattern is required", path .. ".pattern_id")
  end
  if (item.kind == "accepted" or item.kind == "rejected_key") and not is_non_empty_string(item.lhs) then
    return problem("invalid_feedback", "Feedback lhs is required for this kind", path .. ".lhs")
  end
  if item.lhs ~= nil and not is_non_empty_string(item.lhs) then
    return problem("invalid_feedback", "Feedback lhs must be a non-empty string", path .. ".lhs")
  end
  return nil
end

local function validate_cycle(cycle)
  local cycle_problem = validate_closed(cycle, CYCLE_FIELDS, "invalid_cycle", "cycle")
  if cycle_problem then
    return cycle_problem
  end
  if not is_integer(cycle.now_ms) or cycle.now_ms < 0 then
    return problem("invalid_cycle", "Cycle time must be a non-negative integer", "cycle.now_ms")
  end
  if cycle.retention_days ~= nil
    and (not is_integer(cycle.retention_days) or cycle.retention_days < 1)
  then
    return problem("invalid_cycle", "Retention days must be a positive integer", "cycle.retention_days")
  end
  local observations_problem = validate_array(cycle.observations, "invalid_cycle", "cycle.observations")
  if observations_problem then
    return observations_problem
  end
  local feedback_problem = validate_array(cycle.feedback, "invalid_cycle", "cycle.feedback")
  if feedback_problem then
    return feedback_problem
  end
  for index, item in ipairs(cycle.feedback) do
    local item_problem = validate_feedback_item(item, index)
    if item_problem then
      return item_problem
    end
  end
  return validate_inventory(cycle.inventory)
end

local function validate_checkpoint(checkpoint)
  if checkpoint == nil then
    return nil
  end
  if type(checkpoint) ~= "table" then
    return problem("invalid_checkpoint", "Checkpoint must be a table", "checkpoint")
  end
  if checkpoint.version ~= 1 then
    return problem("invalid_checkpoint", "Unsupported checkpoint version", "checkpoint.version")
  end
  local checkpoint_problem = validate_closed(checkpoint, CHECKPOINT_FIELDS, "invalid_checkpoint", "checkpoint")
  if checkpoint_problem then
    return checkpoint_problem
  end
  if not is_integer(checkpoint.last_now_ms) or checkpoint.last_now_ms < 0 then
    return problem("invalid_checkpoint", "Checkpoint time is invalid", "checkpoint.last_now_ms")
  end
  if not is_integer(checkpoint.last_session) or checkpoint.last_session < 0 then
    return problem("invalid_checkpoint", "Checkpoint Session is invalid", "checkpoint.last_session")
  end
  for _, field in ipairs({
    "seen_observations",
    "seen_feedback",
    "details",
    "actions",
    "sequences",
    "session_tails",
    "native_actions",
    "native_tails",
    "session_order",
    "suppressions",
    "accepted",
  }) do
    if type(checkpoint[field]) ~= "table" then
      return problem("invalid_checkpoint", "Checkpoint field must be a table", "checkpoint." .. field)
    end
  end
  return validate_array(checkpoint.details, "invalid_checkpoint", "checkpoint.details")
end

local function copy(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for key, item in pairs(value) do
    result[copy(key)] = copy(item)
  end
  return result
end

local function token(value)
  return (value:gsub("([^%w%._%-])", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

local function fingerprint_value(value)
  if value == nil then
    return "nil"
  end
  if type(value) == "boolean" then
    return value and "bool:1" or "bool:0"
  end
  local rendered = tostring(value)
  return type(value) .. ":" .. #rendered .. ":" .. rendered
end

local function observation_fingerprint(observation)
  return table.concat({
    fingerprint_value(observation.schema_version),
    fingerprint_value(observation.session),
    fingerprint_value(observation.ordinal),
    fingerprint_value(observation.at_ms),
    fingerprint_value(observation.kind),
    fingerprint_value(observation.action_id),
    fingerprint_value(observation.mode),
    fingerprint_value(observation.source),
    fingerprint_value(observation.bindable),
    fingerprint_value(observation.cost),
    fingerprint_value(observation.lhs),
    fingerprint_value(observation.context.filetype),
    fingerprint_value(observation.context.buffer_kind),
    fingerprint_value(observation.context.plugin_context),
  }, "|")
end

local function context_key(context)
  return table.concat({ context.filetype, context.buffer_kind, context.plugin_context }, "|")
end

local function action_key(observation)
  return table.concat({ observation.mode, observation.action_id, context_key(observation.context) }, "|")
end

local function sequence_key(first, second)
  return table.concat({ first.mode, first.action_id, second.action_id, context_key(first.context) }, "|")
end

local function native_action_key(observation)
  return table.concat({
    observation.mode,
    observation.action_id,
    observation.lhs,
    context_key(observation.context),
  }, "|")
end

local function pattern_id(aggregate)
  return table.concat({
    "action",
    token(aggregate.mode),
    token(aggregate.action_id),
    token(context_key(aggregate.context)),
  }, ":")
end

local function sequence_pattern_id(aggregate)
  return table.concat({
    "sequence",
    token(aggregate.mode),
    token(aggregate.actions[1]),
    token(aggregate.actions[2]),
    token(context_key(aggregate.context)),
  }, ":")
end

local function native_pattern_id(aggregate)
  return table.concat({
    "native",
    token(aggregate.mode),
    token(aggregate.action_id),
    token(aggregate.lhs),
    token(context_key(aggregate.context)),
  }, ":")
end

local function table_size(values)
  local size = 0
  for _ in pairs(values) do
    size = size + 1
  end
  return size
end

local function initial_checkpoint(now_ms)
  return {
    version = 1,
    last_now_ms = now_ms,
    last_session = 0,
    seen_observations = {},
    seen_feedback = {},
    details = {},
    actions = {},
    sequences = {},
    session_tails = {},
    native_actions = {},
    native_tails = {},
    session_order = {},
    suppressions = {},
    accepted = {},
  }
end

local function counted_motion(observation)
  local lhs = COUNTABLE_MOTIONS[observation.action_id]
  if not lhs or observation.source ~= "keys" or observation.lhs ~= lhs then
    return nil
  end
  return "{count}" .. lhs
end

local function aggregate_native_action(checkpoint, tail, observation)
  local aggregate = checkpoint.native_actions[tail.key]
  if not aggregate then
    aggregate = {
      action_id = observation.action_id,
      mode = observation.mode,
      lhs = observation.lhs,
      context = copy(observation.context),
      native_keys = tail.native_keys,
      occurrences = 0,
      total_cost = 0,
      sessions = {},
    }
    checkpoint.native_actions[tail.key] = aggregate
  end

  aggregate.occurrences = aggregate.occurrences + 1
  aggregate.total_cost = aggregate.total_cost + tail.total_cost
  aggregate.sessions[tostring(observation.session)] = true
end

local function observe_native_action(checkpoint, observation)
  local session_key = tostring(observation.session)
  local native_keys = counted_motion(observation)
  if not native_keys then
    checkpoint.native_tails[session_key] = nil
    return
  end

  local key = native_action_key(observation)
  local previous = checkpoint.native_tails[session_key]
  local continues_run = previous
    and previous.key == key
    and observation.at_ms >= previous.at_ms
    and observation.at_ms - previous.at_ms <= MAX_RUN_GAP_MS

  local tail
  if continues_run then
    tail = previous
    tail.length = tail.length + 1
    tail.total_cost = tail.total_cost + observation.cost
  else
    tail = {
      key = key,
      native_keys = native_keys,
      at_ms = observation.at_ms,
      length = 1,
      total_cost = observation.cost,
    }
    checkpoint.native_tails[session_key] = tail
  end
  tail.at_ms = observation.at_ms

  if tail.length == MIN_MOTION_RUN_LENGTH then
    aggregate_native_action(checkpoint, tail, observation)
  elseif tail.length > MIN_MOTION_RUN_LENGTH then
    checkpoint.native_actions[key].total_cost = checkpoint.native_actions[key].total_cost + observation.cost
  end
end

local function feedback_fingerprint(item)
  return table.concat({
    fingerprint_value(item.at_ms),
    fingerprint_value(item.kind),
    fingerprint_value(item.pattern_id),
    fingerprint_value(item.lhs),
  }, "|")
end

local function pattern_evidence(checkpoint, target_pattern_id)
  for _, collection in ipairs({ checkpoint.actions, checkpoint.native_actions }) do
    for _, aggregate in pairs(collection) do
      local id = collection == checkpoint.actions and pattern_id(aggregate) or native_pattern_id(aggregate)
      if id == target_pattern_id then
        return aggregate.occurrences
      end
    end
  end
  for _, aggregate in pairs(checkpoint.sequences) do
    if sequence_pattern_id(aggregate) == target_pattern_id then
      return aggregate.occurrences
    end
  end
  return 0
end

local function apply_feedback(checkpoint, cycle)
  for _, item in ipairs(cycle.feedback) do
    local fingerprint = feedback_fingerprint(item)
    local seen = checkpoint.seen_feedback[item.id]
    if seen and seen ~= fingerprint then
      return problem("id_collision", "Feedback id was reused for different data", "cycle.feedback")
    end

    if not seen then
      checkpoint.seen_feedback[item.id] = fingerprint
      local suppression = checkpoint.suppressions[item.pattern_id] or {}

      if item.kind == "accepted" then
        checkpoint.accepted[item.pattern_id] = {
          lhs = item.lhs,
          at_ms = item.at_ms,
          adopted = false,
          sessions_with_mapping = {},
          sessions_without_mapping = {},
        }
        checkpoint.suppressions[item.pattern_id] = nil
      elseif item.kind == "acknowledged" then
        checkpoint.accepted[item.pattern_id] = checkpoint.accepted[item.pattern_id] or {
          lhs = item.lhs,
          at_ms = item.at_ms,
          adopted = false,
          sessions_with_mapping = {},
          sessions_without_mapping = {},
        }
      elseif item.kind == "rejected_key" then
        suppression.rejected_keys = suppression.rejected_keys or {}
        suppression.rejected_keys[item.lhs] = true
        checkpoint.suppressions[item.pattern_id] = suppression
      elseif item.kind == "snoozed" then
        suppression.snoozed_until_ms = item.at_ms + SNOOZE_MS
        suppression.snooze_evidence = pattern_evidence(checkpoint, item.pattern_id)
        checkpoint.suppressions[item.pattern_id] = suppression
      elseif item.kind == "excluded" then
        suppression.excluded = true
        checkpoint.suppressions[item.pattern_id] = suppression
      elseif item.kind == "restored" then
        suppression.excluded = nil
        suppression.snoozed_until_ms = nil
        suppression.snooze_evidence = nil
        if not next(suppression) then
          checkpoint.suppressions[item.pattern_id] = nil
        else
          checkpoint.suppressions[item.pattern_id] = suppression
        end
      end
    end
  end
  return nil
end

local function suppressed(checkpoint, recommendation, now_ms)
  local accepted = checkpoint.accepted[recommendation.pattern_id]
  if accepted then
    if accepted.adopted then
      return true
    end
    if table_size(accepted.sessions_with_mapping) > 0 then
      return true
    end
    -- An accepted Recommendation stays out of the list while adoption is
    -- plausible; it becomes available again once later Sessions show the
    -- Workflow Pattern continuing without the accepted mapping.
    if table_size(accepted.sessions_without_mapping) < MIN_ADOPTION_SESSIONS then
      return true
    end
  end

  local suppression = checkpoint.suppressions[recommendation.pattern_id]
  if not suppression then
    return false
  end
  if suppression.excluded then
    return true
  end
  if suppression.snoozed_until_ms then
    if now_ms < suppression.snoozed_until_ms then
      return true
    end
    -- The spec requires materially stronger evidence after a Snooze
    -- expires: recurrence since the Snooze must exceed the evidence that
    -- originally triggered the Recommendation, not merely add to it.
    local baseline = suppression.snooze_evidence or 0
    local evidence = pattern_evidence(checkpoint, recommendation.pattern_id)
    if evidence - baseline <= baseline then
      return true
    end
  end
  if suppression.rejected_keys
    and recommendation.kind == "mapping_candidate"
    and suppression.rejected_keys[recommendation.mapping.lhs]
  then
    return true
  end
  return false
end

local function rejected_keys_for(checkpoint, target_pattern_id)
  local suppression = checkpoint.suppressions[target_pattern_id]
  return suppression and suppression.rejected_keys or nil
end

local function find_existing_mapping(inventory, aggregate)
  local matches = {}
  for _, mapping in ipairs(inventory.mappings) do
    if mapping.mode == aggregate.mode and mapping.action_id == aggregate.action_id then
      table.insert(matches, mapping)
    end
  end
  table.sort(matches, function(left, right)
    return left.lhs < right.lhs
  end)
  return matches[1]
end

local function candidate_keys(inventory, action_id)
  local result = {}
  local seen = {}

  local function add(lhs)
    if lhs and lhs ~= "" and not seen[lhs] then
      seen[lhs] = true
      table.insert(result, lhs)
    end
  end

  local tail = action_id:match("([^%.:]+)$") or action_id
  local tail_initials = ""
  for word in tail:gmatch("[%w]+") do
    tail_initials = tail_initials .. word:sub(1, 1):lower()
  end
  if tail_initials == "" then
    tail_initials = "a"
  end

  local all_initials = ""
  for word in action_id:gmatch("[%w]+") do
    all_initials = all_initials .. word:sub(1, 1):lower()
  end

  local conventions = inventory.conventions
  for _, prefix in ipairs(conventions.prefixes) do
    add(prefix .. tail_initials:sub(1, 1))
  end
  add(conventions.leader .. tail_initials)
  add(conventions.leader .. all_initials)

  for first = string.byte("a"), string.byte("z") do
    for second = string.byte("a"), string.byte("z") do
      add(conventions.leader .. string.char(first, second))
    end
  end

  return result
end

local function common_prefix_length(left, right)
  local limit = math.min(#left, #right)
  local length = 0
  while length < limit and left:byte(length + 1) == right:byte(length + 1) do
    length = length + 1
  end
  return length
end

-- A candidate may share an established convention prefix (or the bare
-- leader/localleader) with existing mappings; any deeper shared prefix
-- is treated as a conflict so proposed keys never crowd an existing
-- mapping family the user did not set up as a namespace.
local function allowed_shared_prefix(conventions, lhs)
  local allowed = 0
  local bases = { conventions.leader, conventions.localleader }
  for _, prefix in ipairs(conventions.prefixes) do
    table.insert(bases, prefix)
  end
  for _, base in ipairs(bases) do
    if #base > allowed and lhs:sub(1, #base) == base then
      allowed = #base
    end
  end
  return allowed
end

local function candidate_is_free(inventory, mode, lhs)
  local allowed = allowed_shared_prefix(inventory.conventions, lhs)
  for _, mapping in ipairs(inventory.mappings) do
    local modes_overlap = mapping.mode == mode
      or mapping.mode == "v" and (mode == "x" or mode == "s")
      or mode == "v" and (mapping.mode == "x" or mapping.mode == "s")
    local keys_overlap = mapping.lhs == lhs
      or mapping.lhs:sub(1, #lhs) == lhs
      or lhs:sub(1, #mapping.lhs) == mapping.lhs
      or common_prefix_length(mapping.lhs, lhs) > allowed
    if modes_overlap and keys_overlap then
      return false
    end
  end
  return true
end

local function allocate_candidate(inventory, aggregate, rejected)
  if not inventory.complete then
    return nil
  end

  for _, lhs in ipairs(candidate_keys(inventory, aggregate.action_id)) do
    if not (rejected and rejected[lhs]) and candidate_is_free(inventory, aggregate.mode, lhs) then
      return lhs
    end
  end
  return nil
end

local function recommendations_for_actions(checkpoint, inventory)
  local recommendations = {}
  for _, aggregate in pairs(checkpoint.actions) do
    local sessions = table_size(aggregate.sessions)
    if aggregate.occurrences >= 10 and sessions >= 3 and aggregate.mapping_uses == 0 then
      local mapping = find_existing_mapping(inventory, aggregate)
      local workflow_id = pattern_id(aggregate)
      if mapping then
        table.insert(recommendations, {
          id = workflow_id .. ":existing:" .. token(mapping.lhs),
          pattern_id = workflow_id,
          kind = "existing_mapping",
          action_id = aggregate.action_id,
          mode = aggregate.mode,
          context = copy(aggregate.context),
          mapping = copy(mapping),
          evidence = {
            occurrences = aggregate.occurrences,
            sessions = sessions,
            estimated_keystrokes_saved = math.max(0, aggregate.total_cost - aggregate.occurrences),
          },
        })
      elseif aggregate.bindable then
        local lhs = allocate_candidate(inventory, aggregate, rejected_keys_for(checkpoint, workflow_id))
        if lhs then
          table.insert(recommendations, {
            id = workflow_id .. ":candidate:" .. token(lhs),
            pattern_id = workflow_id,
            kind = "mapping_candidate",
            action_id = aggregate.action_id,
            mode = aggregate.mode,
            context = copy(aggregate.context),
            inventory_revision = inventory.revision,
            mapping = {
              mode = aggregate.mode,
              lhs = lhs,
              action_id = aggregate.action_id,
              desc = "KeyCoach: " .. aggregate.action_id,
            },
            evidence = {
              occurrences = aggregate.occurrences,
              sessions = sessions,
              estimated_keystrokes_saved = math.max(0, aggregate.total_cost - aggregate.occurrences),
            },
          })
        end
      end
    end
  end
  return recommendations
end

local function recommendations_for_sequences(checkpoint, inventory)
  local recommendations = {}
  for _, aggregate in pairs(checkpoint.sequences) do
    local sessions = table_size(aggregate.sessions)
    if aggregate.occurrences >= 6 and sessions >= 3 then
      local workflow_id = sequence_pattern_id(aggregate)
      local allocation_input = {
        action_id = "sequence." .. aggregate.actions[1] .. "." .. aggregate.actions[2],
        mode = aggregate.mode,
      }
      local lhs = allocate_candidate(inventory, allocation_input, rejected_keys_for(checkpoint, workflow_id))
      if lhs then
        table.insert(recommendations, {
          id = workflow_id .. ":candidate:" .. token(lhs),
          pattern_id = workflow_id,
          kind = "mapping_candidate",
          mode = aggregate.mode,
          context = copy(aggregate.context),
          inventory_revision = inventory.revision,
          workflow = {
            actions = copy(aggregate.actions),
          },
          mapping = {
            mode = aggregate.mode,
            lhs = lhs,
            actions = copy(aggregate.actions),
            desc = "KeyCoach: repeated action sequence",
          },
          evidence = {
            occurrences = aggregate.occurrences,
            sessions = sessions,
            estimated_keystrokes_saved = math.max(0, aggregate.total_cost - aggregate.occurrences),
          },
        })
      end
    end
  end
  return recommendations
end

local function recommendations_for_native_actions(checkpoint)
  local recommendations = {}
  for _, aggregate in pairs(checkpoint.native_actions) do
    local sessions = table_size(aggregate.sessions)
    if aggregate.occurrences >= MIN_MOTION_RUNS and sessions >= MIN_MOTION_SESSIONS then
      local workflow_id = native_pattern_id(aggregate)
      table.insert(recommendations, {
        id = workflow_id .. ":" .. token(aggregate.native_keys),
        pattern_id = workflow_id,
        kind = "native_action",
        action_id = aggregate.action_id,
        mode = aggregate.mode,
        context = copy(aggregate.context),
        native_action = {
          keys = aggregate.native_keys,
        },
        evidence = {
          occurrences = aggregate.occurrences,
          sessions = sessions,
          estimated_keystrokes_saved = math.max(0, aggregate.total_cost - aggregate.occurrences * 2),
        },
      })
    end
  end
  return recommendations
end

local function ranked_recommendations(checkpoint, inventory, now_ms)
  local candidates = recommendations_for_actions(checkpoint, inventory)
  for _, recommendation in ipairs(recommendations_for_native_actions(checkpoint)) do
    table.insert(candidates, recommendation)
  end
  for _, recommendation in ipairs(recommendations_for_sequences(checkpoint, inventory)) do
    table.insert(candidates, recommendation)
  end

  local recommendations = {}
  for _, recommendation in ipairs(candidates) do
    if not suppressed(checkpoint, recommendation, now_ms) then
      table.insert(recommendations, recommendation)
    end
  end

  table.sort(recommendations, function(left, right)
    local priority = { existing_mapping = 1, native_action = 2, mapping_candidate = 3 }
    if priority[left.kind] ~= priority[right.kind] then
      return priority[left.kind] < priority[right.kind]
    end
    if left.evidence.occurrences ~= right.evidence.occurrences then
      return left.evidence.occurrences > right.evidence.occurrences
    end
    return left.id < right.id
  end)
  return recommendations
end

function M.advance(previous, cycle)
  local cycle_problem = validate_cycle(cycle)
  if cycle_problem then
    return nil, cycle_problem
  end

  local checkpoint_problem = validate_checkpoint(previous)
  if checkpoint_problem then
    return nil, checkpoint_problem
  end

  for index, observation in ipairs(cycle.observations) do
    local observation_problem = validate_observation(observation, index)
    if observation_problem then
      return nil, observation_problem
    end
  end

  local checkpoint = previous and copy(previous) or initial_checkpoint(cycle.now_ms)
  if previous and cycle.now_ms < previous.last_now_ms then
    return nil, problem("time_regression", "Cycle time cannot regress", "cycle.now_ms")
  end
  checkpoint.last_now_ms = cycle.now_ms
  checkpoint.native_actions = checkpoint.native_actions or {}
  checkpoint.native_tails = checkpoint.native_tails or {}
  checkpoint.session_order = checkpoint.session_order or {}

  local feedback_problem = apply_feedback(checkpoint, cycle)
  if feedback_problem then
    return nil, feedback_problem
  end

  for index, observation in ipairs(cycle.observations) do
    local path = string.format("cycle.observations[%d]", index)
    if observation.at_ms > cycle.now_ms then
      return nil, problem("time_regression", "Observation time cannot exceed cycle time", path .. ".at_ms")
    end

    local fingerprint = observation_fingerprint(observation)
    local seen = checkpoint.seen_observations[observation.id]
    if seen and seen ~= true and seen ~= fingerprint then
      return nil, problem("id_collision", "Observation id was reused for different data", path .. ".id")
    end

    if not seen then
      if previous and observation.at_ms < previous.last_now_ms then
        return nil, problem("time_regression", "New Observation time cannot precede the last cycle", path .. ".at_ms")
      end
      local session_key = tostring(observation.session)
      local order = checkpoint.session_order[session_key]
      if order and observation.ordinal <= order.ordinal then
        return nil, problem("observation_order", "Session ordinal must increase", path .. ".ordinal")
      end
      if order and observation.at_ms < order.at_ms then
        return nil, problem("time_regression", "Observation time cannot regress within a Session", path .. ".at_ms")
      end

      checkpoint.seen_observations[observation.id] = fingerprint
      checkpoint.session_order[session_key] = {
        ordinal = observation.ordinal,
        at_ms = observation.at_ms,
      }
      checkpoint.last_session = math.max(checkpoint.last_session, observation.session)
      table.insert(checkpoint.details, copy(observation))

      local key = action_key(observation)
      local aggregate = checkpoint.actions[key]
      if not aggregate then
        aggregate = {
          action_id = observation.action_id,
          mode = observation.mode,
          context = copy(observation.context),
          bindable = observation.bindable,
          occurrences = 0,
          mapping_uses = 0,
          total_cost = 0,
          sessions = {},
        }
      checkpoint.actions[key] = aggregate
      end
      aggregate.occurrences = aggregate.occurrences + 1
      aggregate.total_cost = aggregate.total_cost + observation.cost
      aggregate.sessions[tostring(observation.session)] = true
      if observation.source == "mapping" then
        aggregate.mapping_uses = aggregate.mapping_uses + 1
      end

      if observation.source == "mapping" and observation.lhs then
        for _, entry in pairs(checkpoint.accepted) do
          if not entry.adopted and entry.lhs == observation.lhs then
            entry.sessions_with_mapping = entry.sessions_with_mapping or {}
            entry.sessions_with_mapping[session_key] = true
          end
        end
      else
        local accepted_entry = checkpoint.accepted[pattern_id(aggregate)]
        if accepted_entry and not accepted_entry.adopted then
          accepted_entry.sessions_without_mapping = accepted_entry.sessions_without_mapping or {}
          accepted_entry.sessions_without_mapping[session_key] = true
        end
      end

      observe_native_action(checkpoint, observation)

      local previous_observation = checkpoint.session_tails[session_key]
      if previous_observation
        and observation.at_ms >= previous_observation.at_ms
        and observation.at_ms - previous_observation.at_ms <= 2000
        and observation.mode == previous_observation.mode
        and context_key(observation.context) == context_key(previous_observation.context)
        and observation.action_id ~= previous_observation.action_id
        and observation.bindable
        and previous_observation.bindable
      then
        local key_for_sequence = sequence_key(previous_observation, observation)
        local sequence = checkpoint.sequences[key_for_sequence]
        if not sequence then
          sequence = {
            actions = { previous_observation.action_id, observation.action_id },
            mode = observation.mode,
            context = copy(observation.context),
            occurrences = 0,
            total_cost = 0,
            sessions = {},
          }
          checkpoint.sequences[key_for_sequence] = sequence
        end
        sequence.occurrences = sequence.occurrences + 1
        sequence.total_cost = sequence.total_cost + previous_observation.cost + observation.cost
        sequence.sessions[session_key] = true

        local sequence_entry = checkpoint.accepted[sequence_pattern_id(sequence)]
        if sequence_entry and not sequence_entry.adopted then
          sequence_entry.sessions_without_mapping = sequence_entry.sessions_without_mapping or {}
          sequence_entry.sessions_without_mapping[session_key] = true
        end
      end
      checkpoint.session_tails[session_key] = copy(observation)
    end
  end

  local adoptions = {}
  for pattern_key, entry in pairs(checkpoint.accepted) do
    if not entry.adopted and table_size(entry.sessions_with_mapping or {}) >= MIN_ADOPTION_SESSIONS then
      entry.adopted = true
      table.insert(adoptions, { pattern_id = pattern_key, lhs = entry.lhs })
    end
  end
  table.sort(adoptions, function(left, right)
    return left.pattern_id < right.pattern_id
  end)

  local horizon = cycle.now_ms - (cycle.retention_days or DEFAULT_RETENTION_DAYS) * 86400000
  if horizon > 0 then
    local retained = {}
    local retained_seen = {}
    for _, detail in ipairs(checkpoint.details) do
      if detail.at_ms >= horizon then
        table.insert(retained, detail)
        retained_seen[detail.id] = checkpoint.seen_observations[detail.id]
      end
    end
    checkpoint.details = retained
    checkpoint.seen_observations = retained_seen
  end

  local exclusions = {}
  for pattern_key, suppression in pairs(checkpoint.suppressions) do
    if suppression.excluded then
      table.insert(exclusions, { pattern_id = pattern_key })
    end
  end
  table.sort(exclusions, function(left, right)
    return left.pattern_id < right.pattern_id
  end)

  return {
    checkpoint = checkpoint,
    recommendations = ranked_recommendations(checkpoint, cycle.inventory, cycle.now_ms),
    exclusions = exclusions,
    adoptions = adoptions,
    notices = {},
  }, nil
end

return M
