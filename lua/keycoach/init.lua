local engine = require("keycoach.engine")
local store = require("keycoach.store")
local appender = require("keycoach.appender")
local dashboard = require("keycoach.dashboard")
local format = require("keycoach.format")
local inventory_module = require("keycoach.nvim.inventory")

local uv = vim.uv or vim.loop

local M = {}

local active_timer
local collector_emit
local start_tracking
local apply_hint_shown = false

local DEFAULT_RETENTION_DAYS = 30
local DEFAULT_SESSION_IDLE_MINUTES = 30
local CYCLE_MIN_INTERVAL_MS = 30000
local FAILSAFE_TIMER_MS = 5 * 60 * 1000
local MAX_BUFFERED_OBSERVATIONS = 10000

local state = {
  options = {},
  tracking = "disabled",
  ready_count = 0,
  checkpoint = nil,
  recommendations = {},
  feedback = {},
  feedback_seq = 0,
  pending = {},
  collector = nil,
  session = 0,
  session_initialized = false,
  consent = false,
  mapping_file = nil,
  data_dir = nil,
  settings_path = nil,
  state_path = nil,
  last_observation_ms = nil,
  last_cycle_ms = nil,
  now_fn = nil,
  wall_anchor_ms = 0,
  wall_anchor_hrtime = 0,
  inventory = nil,
  active_model = nil,
}

local function monotonic_ms()
  return math.floor(uv.hrtime() / 1000000)
end

local function now_ms()
  if state.now_fn then
    return state.now_fn()
  end
  local now = state.wall_anchor_ms + (monotonic_ms() - state.wall_anchor_hrtime)
  if state.checkpoint and state.checkpoint.last_now_ms then
    now = math.max(now, state.checkpoint.last_now_ms)
  end
  return now
end

local function load_settings()
  local settings, problem = store.load(state.settings_path)
  if problem or type(settings) ~= "table" then
    return {}
  end
  return settings
end

local function save_settings()
  store.save(state.settings_path, {
    consent = state.consent,
    mapping_file = state.mapping_file,
  })
end

local function schedule_setup_hint()
  vim.schedule(function()
    vim.notify(
      "KeyCoach is installed but not set up. Run :KeyCoach to begin.",
      vim.log.levels.INFO,
      {
        title = "KeyCoach",
      }
    )
  end)
end

local function current_session()
  local checkpoint_session = state.checkpoint and state.checkpoint.last_session or 0
  if
    state.session_initialized
    and state.last_observation_ms
    and (now_ms() - state.last_observation_ms) <= state.session_idle_ms
    and state.session > checkpoint_session
  then
    return state.session
  end
  state.session_initialized = true
  state.session = math.max(state.session or 0, checkpoint_session) + 1
  return state.session
end

local function snapshot_inventory()
  if
    type(state.options.inventory) == "table"
    and type(state.options.inventory.snapshot) == "function"
  then
    return state.options.inventory.snapshot()
  end
  return inventory_module.snapshot()
end

local function refresh_inventory()
  local inventory, problem = snapshot_inventory()
  if not problem then
    state.inventory = inventory
  end
  return inventory, problem
end

local function expand_leader(lhs)
  local leader = vim.g.mapleader or "\\"
  local localleader = vim.g.maplocalleader or "\\"
  return lhs
    :gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return leader
    end)
    :gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return localleader
    end)
end

local function canonical_lhs(lhs)
  local ok, result = pcall(vim.api.nvim_replace_termcodes, expand_leader(lhs), true, true, true)
  return ok and result or expand_leader(lhs)
end

local function inventory_mode_for(raw_mode)
  if type(raw_mode) ~= "string" then
    return nil
  end
  if raw_mode == "no" or raw_mode:sub(1, 2) == "no" then
    return "o"
  end
  local first = raw_mode:sub(1, 1)
  if first == "n" then
    return "n"
  end
  if first == "v" then
    return "v"
  end
  if first == "s" then
    return "s"
  end
  return nil
end

local function mapping_mode_overlaps(left, right)
  if left == right then
    return true
  end
  return left == "v" and (right == "x" or right == "s")
    or right == "v" and (left == "x" or left == "s")
end

local function resolve_mapping(lhs, context)
  local snapshot = state.inventory
  if type(snapshot) ~= "table" or type(snapshot.mappings) ~= "table" then
    return nil
  end

  local mode = inventory_mode_for(context and context.mode)
  if not mode then
    return nil
  end

  local typed = canonical_lhs(lhs)
  if typed == "" then
    return nil
  end

  local exact
  local pending = false
  for _, mapping in ipairs(snapshot.mappings) do
    if type(mapping.lhs) == "string" and mapping_mode_overlaps(mapping.mode, mode) then
      local target = canonical_lhs(mapping.lhs)
      if target == typed then
        if not exact or #mapping.lhs > #exact.lhs then
          exact = mapping
        end
      elseif target:sub(1, #typed) == typed and #target > #typed then
        pending = true
      end
    end
  end

  if exact then
    return {
      action_id = exact.action_id,
      category = "command",
      bindable = true,
    }
  end
  if pending then
    return { pending = true }
  end
  return nil
end

local function record_feedback(kind, pattern_id, lhs)
  state.feedback_seq = state.feedback_seq + 1
  table.insert(state.feedback, {
    id = string.format("f%d:%d", state.session or 0, state.feedback_seq),
    at_ms = now_ms(),
    kind = kind,
    pattern_id = pattern_id,
    lhs = lhs,
  })
end

local function stop_tracking()
  if state.collector then
    pcall(state.collector.stop)
    state.collector = nil
  end
end

local function start_tracking()
  stop_tracking()
  refresh_inventory()

  local collector_module = state.options.collector or require("keycoach.nvim.collector")
  local collector_options = {
    session = current_session(),
    emit = collector_emit,
    now_ms = now_ms,
  }
  if state.options.resolve_mapping ~= false then
    collector_options.resolve_mapping = resolve_mapping
  end

  local ok, handle = pcall(collector_module.start, collector_options)
  if ok and handle then
    state.collector = handle
  else
    vim.notify("KeyCoach could not start observing: " .. tostring(handle), vim.log.levels.WARN, {
      title = "KeyCoach",
    })
  end
end

collector_emit = function(observation)
  if type(observation) ~= "table" then
    return
  end

  local at_ms = observation.at_ms
  if
    state.last_observation_ms
    and at_ms
    and at_ms - state.last_observation_ms > state.session_idle_ms
  then
    start_tracking()
    state.last_observation_ms = at_ms
    if #state.pending < state.max_pending then
      table.insert(state.pending, observation)
    end
    return
  end
  if at_ms then
    state.last_observation_ms = at_ms
  end

  if #state.pending < state.max_pending then
    table.insert(state.pending, observation)
  end
end

function M.flush(force)
  if state.tracking ~= "tracking" and state.tracking ~= "paused" then
    return nil, { code = "not_tracking", message = "KeyCoach is not tracking" }
  end

  local now = now_ms()
  if state.last_cycle_ms and not force and now - state.last_cycle_ms < state.cycle_interval_ms then
    return nil, { code = "too_soon", message = "cycle spacing has not elapsed" }
  end

  local observations = state.pending
  local feedback = state.feedback
  state.pending = {}
  state.feedback = {}

  local inventory, inventory_problem = snapshot_inventory()
  if inventory_problem then
    state.pending = observations
    state.feedback = feedback
    return nil, inventory_problem
  end
  state.inventory = inventory

  local transition, problem = engine.advance(state.checkpoint, {
    now_ms = now,
    observations = observations,
    feedback = feedback,
    inventory = inventory,
    retention_days = state.options.retention_days or DEFAULT_RETENTION_DAYS,
  })
  if problem then
    state.pending = observations
    state.feedback = feedback
    return nil, problem
  end

  local saved, save_problem = store.save(state.state_path, transition.checkpoint)
  if save_problem then
    return nil, save_problem
  end

  state.checkpoint = transition.checkpoint
  state.last_cycle_ms = now
  state.recommendations = transition.recommendations
  state.ready_count = #transition.recommendations
  return transition, nil
end

local function cycle()
  if state.tracking ~= "tracking" then
    return nil
  end
  local ok, transition, problem = pcall(M.flush)
  if not ok then
    return nil
  end
  return transition, problem
end

local function stop_failsafe_timer()
  if active_timer then
    pcall(active_timer.stop, active_timer)
    active_timer = nil
  end
end

local function setup_cycle_triggers()
  stop_failsafe_timer()

  local group = vim.api.nvim_create_augroup("KeyCoachCycle", { clear = true })
  state.cycle_group = group

  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "FocusLost" }, {
    group = group,
    callback = function()
      pcall(cycle)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      stop_failsafe_timer()
      pcall(function()
        M.flush(true)
      end)
    end,
  })

  if uv.new_timer then
    local timer = uv.new_timer()
    timer:start(
      FAILSAFE_TIMER_MS,
      FAILSAFE_TIMER_MS,
      vim.schedule_wrap(function()
        pcall(cycle)
      end)
    )
    active_timer = timer
  end
end

local function notify_status()
  vim.notify(M.statusline(), vim.log.levels.INFO, { title = "KeyCoach" })
end

local function run_onboarding()
  local onboarding_module = state.options.onboarding or require("keycoach.nvim.onboarding")
  onboarding_module.run({
    default_mapping_file = state.options.mapping_file
      or (vim.fn.stdpath("config") .. "/lua/keycoach_mappings.lua"),
    preset_mapping_file = state.options.mapping_file,
    data_directory = state.data_dir,
    on_complete = function(mapping_file)
      state.consent = true
      state.mapping_file = mapping_file
      save_settings()
      state.tracking = "tracking"
      start_tracking()
      notify_status()
      vim.notify(
        "KeyCoach is tracking. Open :KeyCoach any time.",
        vim.log.levels.INFO,
        { title = "KeyCoach" }
      )
    end,
  })
end

local function register_commands()
  local commands = {
    KeyCoach = {
      callback = function()
        return M.open()
      end,
      description = "Open KeyCoach recommendations or start first-run setup",
    },
    KeyCoachClear = {
      callback = function()
        return M.clear()
      end,
      description = "Delete local KeyCoach evidence after confirmation",
    },
    KeyCoachEnable = {
      callback = function()
        M.enable()
        notify_status()
      end,
      description = "Complete setup and enable KeyCoach tracking",
    },
    KeyCoachMappings = {
      callback = function()
        return M.open_mappings()
      end,
      description = "Open the configured KeyCoach mappings file",
    },
    KeyCoachPause = {
      callback = function()
        M.pause()
        notify_status()
      end,
      description = "Pause KeyCoach tracking",
    },
    KeyCoachResume = {
      callback = function()
        M.resume()
        notify_status()
      end,
      description = "Resume KeyCoach tracking",
    },
    KeyCoachStatus = {
      callback = notify_status,
      description = "Show KeyCoach tracking status",
    },
    KeyCoachData = {
      callback = function()
        return M.data()
      end,
      description = "Inspect, export, or manage local KeyCoach data",
    },
  }

  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command.callback, {
      desc = command.description,
      force = true,
    })
  end
end

local function refresh_active_dashboard()
  local model = state.active_model
  if not model or not model.refresh then
    return
  end
  local fresh = model.refresh()
  if not fresh then
    return
  end
  model.tracking = fresh.tracking
  model.recommendations = fresh.recommendations
  if model.render then
    model.render()
  end
end

local function rhs_for(action_id)
  local command = type(action_id) == "string" and action_id:match("^command:(.+)$")
  if command and command ~= "" then
    return "<Cmd>" .. command .. "<CR>"
  end
  return nil
end

local function keymap_set_line(candidate)
  return string.format(
    "vim.keymap.set(%q, %q, %q, { desc = %q })",
    candidate.mode,
    candidate.lhs,
    candidate.rhs,
    candidate.opts and candidate.opts.desc or ""
  )
end

local function require_name(path)
  local config = vim.fn.stdpath("config")
  local prefix = config .. "/lua/"
  local expanded = vim.fn.expand(path)
  if expanded:sub(1, #prefix) ~= prefix then
    return nil
  end
  local name = expanded:sub(#prefix + 1):gsub("%.lua$", ""):gsub("/", ".")
  if name == "" then
    return nil
  end
  return name
end

local function appender_inventory(snapshot)
  return {
    revision = snapshot.revision,
    complete = snapshot.complete,
    mappings = snapshot.mappings,
    leader = vim.g.mapleader or "\\",
    localleader = vim.g.maplocalleader or "\\",
  }
end

local function apply_mapping_candidate(recommendation, options)
  options = options or {}
  if type(state.mapping_file) ~= "string" or state.mapping_file == "" then
    return nil,
      {
        code = "no_mapping_file",
        message = "No mappings file configured. Run :KeyCoach to set one.",
      }
  end

  local target = recommendation.mapping or {}
  local candidate = {
    mode = target.mode,
    lhs = target.lhs,
    rhs = rhs_for(target.action_id),
    opts = { desc = target.desc },
  }
  if not candidate.rhs then
    record_feedback("acknowledged", recommendation.pattern_id, target.lhs)
    M.flush(true)
    return { acknowledged = true }, nil
  end

  if not options.confirmed then
    local ok, choice = pcall(
      vim.fn.confirm,
      string.format(
        "Append %s to %s?",
        keymap_set_line(candidate),
        vim.fn.fnamemodify(state.mapping_file, ":~")
      ),
      "&Yes\n&No"
    )
    if not ok or choice ~= 1 then
      return nil, { code = "declined", message = "apply declined" }
    end
  end

  local snapshot, snapshot_problem = snapshot_inventory()
  if snapshot_problem then
    return nil, snapshot_problem
  end

  local result, problem = appender.append(state.mapping_file, candidate, {
    expected_revision = recommendation.inventory_revision,
    current_inventory = function()
      return appender_inventory(snapshot)
    end,
  })
  if problem then
    if problem.code == "mapping_conflict" or problem.code == "stale_inventory" then
      record_feedback("rejected_key", recommendation.pattern_id, target.lhs)
      M.flush(true)
      return { regenerated = true }, nil
    end
    return nil, problem
  end

  record_feedback("accepted", recommendation.pattern_id, target.lhs)
  M.flush(true)
  local message = "Appended " .. result.line
  if not apply_hint_shown then
    apply_hint_shown = true
    local module = require_name(state.mapping_file)
    local load_snippet = module and ("require(" .. vim.inspect(module) .. ")")
      or ("dofile(" .. vim.inspect(vim.fn.expand(state.mapping_file)) .. ")")
    message = message .. "  Add " .. load_snippet .. " to your config to activate it."
  end
  vim.notify(message, vim.log.levels.INFO, { title = "KeyCoach" })
  return { applied = true, line = result.line }, nil
end

function M.apply(recommendation, options)
  options = options or {}
  if type(recommendation) ~= "table" then
    return nil, { code = "invalid_recommendation", message = "recommendation must be a table" }
  end

  if recommendation.kind == "mapping_candidate" then
    return apply_mapping_candidate(recommendation, options)
  end

  local lhs
  if recommendation.kind == "existing_mapping" then
    lhs = recommendation.mapping and recommendation.mapping.lhs
  end
  record_feedback("acknowledged", recommendation.pattern_id, lhs)
  M.flush(true)
  return { acknowledged = true }, nil
end

local function handle_menu_action(action, recommendation)
  if action == "why" then
    local evidence = recommendation.evidence
    vim.notify(
      string.format("%s · %s", recommendation.pattern_id, format.evidence_summary(evidence)),
      vim.log.levels.INFO,
      { title = "KeyCoach" }
    )
    return
  end

  if action == "another_key" then
    record_feedback(
      "rejected_key",
      recommendation.pattern_id,
      recommendation.mapping and recommendation.mapping.lhs
    )
  elseif action == "snooze" then
    record_feedback("snoozed", recommendation.pattern_id)
  elseif action == "exclude" then
    record_feedback("excluded", recommendation.pattern_id)
  end
  M.flush(true)
  refresh_active_dashboard()
end

local function menu_for(recommendation)
  if type(recommendation) ~= "table" then
    return
  end

  local items = {
    { action = "why", label = "Why am I seeing this?" },
    { action = "snooze", label = "Snooze 30 days" },
    { action = "exclude", label = "Never suggest this" },
  }
  if recommendation.kind == "mapping_candidate" then
    table.insert(items, 1, { action = "another_key", label = "Another key" })
  end

  local labels = {}
  for _, item in ipairs(items) do
    table.insert(labels, item.label)
  end

  vim.ui.select(labels, {
    prompt = "KeyCoach: " .. format.recommendation_title(recommendation),
  }, function(choice)
    if not choice then
      return
    end
    for _, item in ipairs(items) do
      if item.label == choice then
        handle_menu_action(item.action, recommendation)
        return
      end
    end
  end)
end

function M.data_inspect()
  local buffer = vim.api.nvim_create_buf(false, true)
  local contents = format.pretty_json(state.checkpoint or {})
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(contents, "\n", { plain = true }))
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "json", { buf = buffer })
  local window = vim.api.nvim_win_set_buf(0, buffer)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end, { buffer = buffer, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end, { buffer = buffer, nowait = true, silent = true })
end

local function write_export(path)
  local json, problem = store.export(state.state_path)
  if problem then
    vim.notify(
      "KeyCoach export failed: " .. tostring(problem.message or problem.code),
      vim.log.levels.ERROR,
      {
        title = "KeyCoach",
      }
    )
    return
  end
  local expanded = vim.fn.expand(path)
  pcall(vim.fn.mkdir, vim.fn.fnamemodify(expanded, ":h"), "p")
  local file = io.open(expanded, "wb")
  if not file then
    vim.notify(
      "KeyCoach export could not open the chosen path",
      vim.log.levels.ERROR,
      { title = "KeyCoach" }
    )
    return
  end
  file:write(json)
  file:close()
  vim.notify("KeyCoach data exported to " .. path, vim.log.levels.INFO, { title = "KeyCoach" })
end

function M.data_export(path)
  if type(path) ~= "string" or path == "" then
    vim.ui.input(
      { prompt = "Export path: ", default = vim.fn.expand("~/keycoach-export.json") },
      function(chosen)
        if chosen and chosen ~= "" then
          write_export(chosen)
        end
      end
    )
    return
  end
  write_export(path)
end

function M.data_restore(pattern_id)
  if type(pattern_id) ~= "string" or pattern_id == "" then
    local exclusions = {}
    if state.checkpoint then
      for id, suppression in pairs(state.checkpoint.suppressions or {}) do
        if suppression and suppression.excluded then
          table.insert(exclusions, id)
        end
      end
    end
    table.sort(exclusions)
    if #exclusions == 0 then
      vim.notify(
        "KeyCoach has no exclusions to restore.",
        vim.log.levels.INFO,
        { title = "KeyCoach" }
      )
      return
    end
    vim.ui.select(exclusions, { prompt = "Restore an exclusion" }, function(choice)
      if choice then
        record_feedback("restored", choice)
        M.flush(true)
        vim.notify("Exclusion restored for " .. choice, vim.log.levels.INFO, { title = "KeyCoach" })
      end
    end)
    return
  end
  record_feedback("restored", pattern_id)
  M.flush(true)
end

local function data_menu()
  vim.ui.select({
    "Inspect",
    "Export",
    "Restore an exclusion",
    "Delete everything",
  }, { prompt = "KeyCoach data" }, function(choice)
    if choice == "Inspect" then
      M.data_inspect()
    elseif choice == "Export" then
      M.data_export()
    elseif choice == "Restore an exclusion" then
      M.data_restore()
    elseif choice == "Delete everything" then
      M.clear()
    end
  end)
end

function M.data(options)
  options = options or {}
  if options.action then
    if options.action == "inspect" then
      M.data_inspect()
    elseif options.action == "export" then
      M.data_export(options.path)
    elseif options.action == "restore" then
      M.data_restore(options.pattern_id)
    elseif options.action == "delete" then
      M.clear({ confirmed = true })
    end
    return
  end
  data_menu()
end

function M.setup(options)
  options = options or {}
  state.options = options

  local data_dir = options.data_dir
    or (options.state_path and vim.fn.fnamemodify(options.state_path, ":h"))
    or (vim.fn.stdpath("data") .. "/keycoach")
  state.data_dir = data_dir
  vim.g.keycoach_data_dir = data_dir
  state.settings_path = options.settings_path or (data_dir .. "/settings.json")
  state.state_path = options.state_path or (data_dir .. "/checkpoint.json")
  state.mapping_file = options.mapping_file

  state.retention_days = options.retention_days or DEFAULT_RETENTION_DAYS
  state.session_idle_ms = (options.session_idle_minutes or DEFAULT_SESSION_IDLE_MINUTES) * 60000
  state.cycle_interval_ms = options.cycle_interval_ms or CYCLE_MIN_INTERVAL_MS
  state.max_pending = options.max_pending or MAX_BUFFERED_OBSERVATIONS

  if type(options.now_ms) == "function" then
    state.now_fn = options.now_ms
  else
    state.now_fn = nil
    local sec, usec = uv.gettimeofday()
    state.wall_anchor_ms = sec * 1000 + math.floor(usec / 1000)
    state.wall_anchor_hrtime = monotonic_ms()
  end

  local checkpoint, checkpoint_problem = store.load(state.state_path)
  if checkpoint_problem then
    vim.notify(
      "KeyCoach could not read its data: " .. tostring(checkpoint_problem.message),
      vim.log.levels.WARN,
      { title = "KeyCoach" }
    )
  end
  state.checkpoint = checkpoint or nil
  state.recommendations = {}
  state.ready_count = 0
  state.pending = {}
  state.feedback = {}
  state.feedback_seq = 0
  state.session = 0
  state.session_initialized = false
  state.last_observation_ms = nil
  state.last_cycle_ms = nil
  state.active_model = nil

  local settings = load_settings()
  if type(settings.consent) == "boolean" then
    state.consent = settings.consent
  end
  if type(settings.mapping_file) == "string" and not state.mapping_file then
    state.mapping_file = settings.mapping_file
  end

  register_commands()
  setup_cycle_triggers()

  if options.enabled == true then
    state.consent = true
    state.tracking = "tracking"
    save_settings()
    start_tracking()
  elseif options.enabled == false then
    state.tracking = "disabled"
  elseif state.consent then
    state.tracking = "tracking"
    start_tracking()
  else
    state.tracking = "pending"
    schedule_setup_hint()
  end

  return M
end

function M.status()
  return {
    tracking = state.tracking,
    ready_count = state.ready_count,
    pending_count = #state.pending,
  }
end

function M.statusline()
  if state.tracking == "tracking" then
    return state.ready_count > 0 and ("KC " .. state.ready_count) or "KC on"
  end

  if state.tracking == "paused" then
    return "KC paused"
  end

  if state.tracking == "pending" then
    return "KC setup"
  end

  return "KC off"
end

function M.pause()
  if state.tracking == "tracking" then
    stop_tracking()
    state.tracking = "paused"
  end

  return state.tracking == "paused"
end

function M.resume()
  if state.tracking == "paused" then
    state.tracking = "tracking"
    start_tracking()
  end

  return state.tracking == "tracking"
end

function M.enable()
  if state.tracking == "tracking" then
    return true
  end

  if not state.consent then
    run_onboarding()
    return false
  end

  state.tracking = "tracking"
  start_tracking()
  notify_status()
  return true
end

function M.open()
  if state.tracking == "pending" then
    run_onboarding()
    return nil
  end

  if state.tracking == "tracking" then
    M.flush(true)
  end

  local model = {
    tracking = state.tracking,
    recommendations = state.recommendations or {},
    refresh = function()
      if state.tracking == "tracking" then
        M.flush(true)
      end
      return {
        tracking = state.tracking,
        recommendations = state.recommendations or {},
      }
    end,
    on_apply = function(recommendation)
      local _, problem = M.apply(recommendation)
      if problem and problem.code ~= "declined" then
        vim.notify(
          "KeyCoach: " .. tostring(problem.message or problem.code),
          vim.log.levels.WARN,
          { title = "KeyCoach" }
        )
      end
      refresh_active_dashboard()
    end,
    on_menu = function(recommendation)
      menu_for(recommendation)
    end,
  }
  state.active_model = model
  return dashboard.open(model)
end

function M.open_mappings()
  if type(state.mapping_file) ~= "string" or state.mapping_file == "" then
    vim.notify(
      "No KeyCoach mappings file configured. Run :KeyCoach to set one.",
      vim.log.levels.WARN,
      {
        title = "KeyCoach",
      }
    )
    return nil
  end
  vim.cmd("edit " .. vim.fn.fnameescape(state.mapping_file))
end

function M.clear(options)
  options = options or {}
  if not options.confirmed then
    local ok, choice = pcall(vim.fn.confirm, "Delete all KeyCoach evidence?", "&Yes\n&No")
    if not ok or choice ~= 1 then
      return false
    end
  end

  local deleted, problem = store.delete(state.state_path)
  if not deleted or problem then
    return false
  end

  state.checkpoint = nil
  state.recommendations = {}
  state.ready_count = 0
  state.pending = {}
  state.feedback = {}
  state.session = 0
  state.session_initialized = false
  state.last_observation_ms = nil
  state.last_cycle_ms = nil

  vim.notify("KeyCoach evidence deleted.", vim.log.levels.INFO, { title = "KeyCoach" })
  return true
end

function M.inspect()
  return {
    checkpoint = state.checkpoint,
    recommendations = state.recommendations or {},
    settings = {
      consent = state.consent,
      mapping_file = state.mapping_file,
    },
    status = M.status(),
  }
end

return M
