local M = {}

local function centered(width, height)
  return {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = width,
    height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height) / 2)),
  }
end

local function open_step(title, lines, mappings)
  local buffer = vim.api.nvim_create_buf(false, true)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(math.max(width + 4, 46), math.max(20, vim.o.columns - 4))
  local height = math.min(#lines, math.max(8, vim.o.lines - vim.o.cmdheight - 4))

  local config = centered(width, height)
  config.title = " " .. title .. " "
  config.title_pos = "center"
  local window = vim.api.nvim_open_win(buffer, true, config)

  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buffer })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buffer })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buffer })
  vim.api.nvim_set_option_value("filetype", "keycoach", { buf = buffer })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buffer })

  local function close()
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end

  for lhs, callback in pairs(mappings) do
    vim.keymap.set("n", lhs, function()
      close()
      callback()
    end, { buffer = buffer, nowait = true, silent = true })
  end

  return close
end

local BOUNDARY_LINES = {
  "",
  "  KeyCoach observes how you work and recommends mappings.",
  "",
  "  What is observed",
  "    - Exact keys in Normal, Visual, Select, Operator-pending modes",
  "    - Counts and categories only in Insert/Replace/Search/Cmdline",
  "    - Mouse buttons, scrolling, mode changes, command identities",
  "",
  "  Never stored",
  "    - Inserted text, search or command arguments, clipboard data",
  "    - File contents, paths, project names",
  "    - Anything typed in terminal or prompt buffers",
  "",
  "  All analysis happens on this machine. No account, no telemetry.",
  "",
  "  <CR> continue    q quit",
}

local FILE_LINES = {
  "",
  "  When you accept a recommendation, KeyCoach appends one readable",
  "  vim.keymap.set(...) line to a Lua file you own.",
  "",
  "  It never rewrites or removes anything in that file.",
  "",
  "  After accepting, require that file from your config to activate it.",
  "",
  "  <CR> choose file    q quit",
}

local function consent_lines(mapping_file, data_directory)
  return {
    "",
    "  Ready to start.",
    "",
    "    Observe:   this Neovim, within the boundary from step 1",
    "    Analyze:   locally, during idle moments",
    "    Append to: " .. vim.fn.fnamemodify(mapping_file, ":~"),
    "    Store:     " .. vim.fn.fnamemodify(data_directory, ":~") .. "  (30-day detail expiry)",
    "",
    "    Pause any time:      :KeyCoachPause",
    "    Delete everything:   :KeyCoachClear",
    "",
    "  y start tracking    q not now",
  }
end

--- Runs the three-step walkthrough from docs/design/onboarding-ux.md.
--- options.default_mapping_file: prefill for the file prompt
--- options.preset_mapping_file: setup()-provided path; step 2 confirms it
--- options.data_directory: shown in the consent summary
--- options.on_complete(mapping_file): called only after explicit consent
function M.run(options)
  local function step_three(mapping_file)
    open_step("KeyCoach Setup (3/3)", consent_lines(mapping_file, options.data_directory), {
      ["y"] = function()
        options.on_complete(mapping_file)
      end,
      ["q"] = function() end,
      ["<Esc>"] = function() end,
    })
  end

  local function step_two()
    if options.preset_mapping_file then
      step_three(options.preset_mapping_file)
      return
    end
    open_step("KeyCoach Setup (2/3)", FILE_LINES, {
      ["<CR>"] = function()
        vim.ui.input({
          prompt = "Mappings file: ",
          default = options.default_mapping_file,
          completion = "file",
        }, function(chosen)
          if chosen and chosen ~= "" then
            step_three(vim.fn.fnamemodify(vim.fn.expand(chosen), ":p"))
          end
        end)
      end,
      ["q"] = function() end,
      ["<Esc>"] = function() end,
    })
  end

  open_step("KeyCoach Setup (1/3)", BOUNDARY_LINES, {
    ["<CR>"] = step_two,
    ["q"] = function() end,
    ["<Esc>"] = function() end,
  })
end

return M
