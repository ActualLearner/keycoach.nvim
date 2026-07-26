local M = {}

local state = {
  tracking = "disabled",
  ready_count = 0,
}

local function notify_status()
  vim.notify(M.statusline(), vim.log.levels.INFO, { title = "KeyCoach" })
end

local function register_commands()
  local commands = {
    KeyCoach = {
      callback = function()
        return M.open()
      end,
      description = "Open KeyCoach recommendations",
    },
    KeyCoachClear = {
      callback = function()
        return M.clear()
      end,
      description = "Delete local KeyCoach observations and recommendations",
    },
    KeyCoachEnable = {
      callback = function()
        return M.enable()
      end,
      description = "Enable KeyCoach tracking",
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
  }

  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command.callback, {
      desc = command.description,
      force = true,
    })
  end
end

function M.setup(options)
  options = options or {}

  if options.enabled == true then
    state.tracking = "tracking"
  elseif options.enabled == nil then
    state.tracking = "pending"
  else
    state.tracking = "disabled"
  end

  state.ready_count = 0
  register_commands()
  return M
end

function M.status()
  return {
    tracking = state.tracking,
    ready_count = state.ready_count,
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
    state.tracking = "paused"
  end

  return state.tracking == "paused"
end

function M.resume()
  if state.tracking == "paused" then
    state.tracking = "tracking"
  end

  return state.tracking == "tracking"
end

function M.open()
  return require("keycoach.dashboard").open({
    tracking = state.tracking,
    recommendations = {},
  })
end

return M
