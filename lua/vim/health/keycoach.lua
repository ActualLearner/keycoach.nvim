local M = {}

local function data_directory()
  return vim.g.keycoach_data_dir or (vim.fn.stdpath("data") .. "/keycoach")
end

local function path_is_writable(path)
  if vim.fn.isdirectory(path) == 1 then
    return vim.fn.filewritable(path) == 2
  end
  return vim.fn.filewritable(vim.fs.dirname(path)) == 2
end

local function read_settings()
  local file = io.open(data_directory() .. "/settings.json", "r")
  if not file then
    return {}
  end
  local contents = file:read("*a")
  file:close()
  local ok, decoded = pcall(vim.json.decode, contents)
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

M.check = function()
  vim.health.start("keycoach")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok(
      ("Neovim %d.%d.%d"):format(vim.version().major, vim.version().minor, vim.version().patch)
    )
  else
    vim.health.error("Neovim 0.10 or newer is required", "Update Neovim")
  end

  local directory = data_directory()
  if path_is_writable(directory) then
    vim.health.ok(("Data directory is writable: %s"):format(directory))
  else
    vim.health.error(
      ("Data directory is not writable: %s"):format(directory),
      "Check permissions under stdpath('data')"
    )
  end

  local current = read_settings()
  local mapping_file = current.mapping_file
  if type(mapping_file) == "string" and mapping_file ~= "" then
    if path_is_writable(mapping_file) then
      vim.health.ok(("Mappings file location is writable: %s"):format(mapping_file))
    else
      vim.health.warn(
        ("Mappings file location is not writable: %s"):format(mapping_file),
        "Pick a writable mappings file in setup()"
      )
    end
  else
    vim.health.info("No mappings file chosen yet - :KeyCoach onboarding will ask for one")
  end

  if current.consent == true then
    vim.health.ok("Consent recorded; KeyCoach observes while you edit")
  elseif current.consent == false then
    vim.health.info("Consent declined - run :KeyCoachEnable to reconsider")
  else
    vim.health.info("Not set up yet - run :KeyCoach to walk through setup")
  end

  vim.health.ok("Observations stay on this machine; nothing is ever sent anywhere")
end

return M
