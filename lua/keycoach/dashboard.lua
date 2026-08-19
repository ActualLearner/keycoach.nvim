local M = {}

local format = require("keycoach.format")

local HEADER_LINES = 4
local RECOMMENDATION_STRIDE = 3

local function dimensions()
  local available_width = math.max(20, vim.o.columns - 4)
  local available_height = math.max(8, vim.o.lines - vim.o.cmdheight - 4)
  local width = math.min(84, available_width)
  local height = math.min(24, available_height)

  return {
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height) / 2)),
  }
end

local function tracking_label(tracking)
  if tracking == "tracking" then
    return "Tracking active"
  end
  if tracking == "paused" then
    return "Tracking paused"
  end
  if tracking == "pending" then
    return "Setup pending"
  end
  return "Tracking disabled"
end

local function recommendation_action_label(recommendation)
  if recommendation.action_id then
    return recommendation.action_id
  end
  if recommendation.mapping and recommendation.mapping.action_id then
    return recommendation.mapping.action_id
  end
  if recommendation.native_action then
    return recommendation.native_action.keys
  end
  return "repeated pattern"
end

local function recommendation_lines(recommendations)
  local lines = {}
  for index, recommendation in ipairs(recommendations) do
    local evidence = recommendation.evidence
    table.insert(lines, string.format("%d  %s", index, format.recommendation_title(recommendation)))
    table.insert(
      lines,
      string.format(
        "   %s · %s",
        recommendation_action_label(recommendation),
        format.evidence_summary(evidence)
      )
    )
    table.insert(lines, "")
  end
  return lines
end

local function render(buffer, model)
  local recommendations = model.recommendations or {}
  local lines = {
    "KeyCoach",
    "",
    tracking_label(model.tracking),
    "",
  }

  if #recommendations == 0 then
    table.insert(lines, "No recommendations yet")
    table.insert(lines, "")
    table.insert(lines, "  KeyCoach recommends only patterns seen across several sessions.")
  else
    for _, line in ipairs(recommendation_lines(recommendations)) do
      table.insert(lines, line)
    end
  end

  table.insert(lines, "")
  table.insert(lines, "<CR> apply/got it · o options · r refresh · q close")

  vim.api.nvim_set_option_value("modifiable", true, { buf = buffer })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
  vim.api.nvim_buf_clear_namespace(buffer, model.namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, model.namespace, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, model.namespace, "Comment", 2, 0, -1)
end

local function recommendation_at_row(recommendations, row)
  if #recommendations == 0 then
    return nil
  end
  local index = math.floor((row - HEADER_LINES) / RECOMMENDATION_STRIDE) + 1
  if index >= 1 and index <= #recommendations then
    return recommendations[index]
  end
  return nil
end

local function apply_at_cursor(window, model)
  local row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local recommendation = recommendation_at_row(model.recommendations or {}, row)
  if recommendation and model.on_apply then
    model.on_apply(recommendation)
  end
end

local function menu_at_cursor(window, model)
  local row = vim.api.nvim_win_get_cursor(window)[1] - 1
  local recommendation = recommendation_at_row(model.recommendations or {}, row)
  if recommendation and model.on_menu then
    model.on_menu(recommendation)
  end
end

function M.open(model)
  model = model or {}
  model.namespace = vim.api.nvim_create_namespace("keycoach-dashboard")
  local size = dimensions()
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = size.width,
    height = size.height,
    col = size.col,
    row = size.row,
    title = " KeyCoach ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "keycoach", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
  vim.api.nvim_set_option_value("cursorline", true, { win = window })
  vim.api.nvim_set_option_value("wrap", false, { win = window })

  local function close()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end

  local function cursor_to_first_recommendation()
    if model.recommendations and #model.recommendations > 0 then
      vim.api.nvim_win_set_cursor(window, { HEADER_LINES + 1, 0 })
    end
  end

  model.render = function()
    render(buffer, model)
  end

  vim.keymap.set("n", "q", close, { buffer = buffer, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buffer, nowait = true, silent = true })
  vim.keymap.set("n", "<CR>", function()
    apply_at_cursor(window, model)
  end, { buffer = buffer, silent = true })
  vim.keymap.set("n", "o", function()
    menu_at_cursor(window, model)
  end, { buffer = buffer, silent = true })
  vim.keymap.set("n", "<Tab>", function()
    menu_at_cursor(window, model)
  end, { buffer = buffer, silent = true })
  if model.refresh then
    vim.keymap.set("n", "r", function()
      local refreshed = model.refresh()
      if refreshed then
        model.tracking = refreshed.tracking or model.tracking
        model.recommendations = refreshed.recommendations or model.recommendations
        model.render()
      end
    end, { buffer = buffer, silent = true })
  end

  render(buffer, model)
  cursor_to_first_recommendation()
  return window
end

return M
