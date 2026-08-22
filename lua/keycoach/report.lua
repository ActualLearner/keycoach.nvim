local M = {}

local WEEK_MS = 7 * 86400000

M.lines = function(checkpoint, now_ms)
  checkpoint = checkpoint or {}
  local details = checkpoint.details or {}
  local horizon = (now_ms or 0) - WEEK_MS

  local lines = {
    "KeyCoach weekly report",
    "",
  }

  local total = 0
  local sessions = {}
  local counts = {}
  for _, detail in ipairs(details) do
    if detail.at_ms and detail.at_ms >= horizon then
      total = total + 1
      sessions[tostring(detail.session)] = true
      counts[detail.action_id] = (counts[detail.action_id] or 0) + 1
    end
  end

  lines[#lines + 1] =
    string.format("Observations this week: %d across %d session(s)", total, #vim.tbl_keys(sessions))
  lines[#lines + 1] = ""

  local top = vim.tbl_keys(counts)
  table.sort(top, function(left, right)
    if counts[left] ~= counts[right] then
      return counts[left] > counts[right]
    end
    return left < right
  end)
  lines[#lines + 1] = "Top actions:"
  for index = 1, math.min(5, #top) do
    lines[#lines + 1] = string.format("  %d. %s - %d", index, top[index], counts[top[index]])
  end
  if #top == 0 then
    lines[#lines + 1] = "  nothing observed yet"
  end
  lines[#lines + 1] = ""

  local accepted = 0
  local adopted = 0
  for _ in pairs(checkpoint.accepted or {}) do
    accepted = accepted + 1
  end
  for _, entry in pairs(checkpoint.accepted or {}) do
    if entry.adopted then
      adopted = adopted + 1
    end
  end
  lines[#lines + 1] =
    string.format("Applied mappings: %d (%d still in regular use)", accepted, adopted)

  local excluded = 0
  for _, suppression in pairs(checkpoint.suppressions or {}) do
    if suppression.excluded then
      excluded = excluded + 1
    end
  end
  if excluded > 0 then
    lines[#lines + 1] = string.format("Excluded patterns: %d (:KeyCoachData to review)", excluded)
  end

  return lines, nil
end

M.open = function(lines)
  local buffer = vim.api.nvim_create_buf(false, true)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(math.max(width + 4, 50), math.max(20, vim.o.columns - 4))
  local height = math.min(#lines + 2, math.max(8, vim.o.lines - vim.o.cmdheight - 4))

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    title = " KeyCoach Report ",
    title_pos = "center",
  })

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "keycoach-report", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })
  vim.api.nvim_buf_add_highlight(buffer, -1, "Title", 0, 0, -1)

  local function close()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buffer, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buffer, silent = true })

  return window
end

return M
