local h = require("tests.harness")

local root = vim.fn.getcwd()
local DOC_PATH = root .. "/doc/keycoach.txt"

local function read_doc()
  local file = assert(io.open(DOC_PATH, "rb"), "doc/keycoach.txt does not exist")
  local contents = assert(file:read("*a"))
  assert(file:close())
  return contents
end

local function lines(contents)
  local result = {}
  for line in contents:gmatch("[^\n]+") do
    result[#result + 1] = line
  end
  return result
end

local function tags_from_tags_file(dir)
  local file = io.open(dir .. "/tags", "rb")
  if not file then
    return {}
  end
  local contents = assert(file:read("*a"))
  assert(file:close())
  local tags = {}
  for _, line in ipairs(lines(contents)) do
    local tag = line:match("^([^\t]+)\t")
    if tag then
      tags[#tags + 1] = tag
    end
  end
  return tags
end

local function generated_tags()
  local temp = vim.fn.tempname()
  vim.fn.mkdir(temp, "p")
  vim.fn.writefile(vim.fn.readfile(DOC_PATH), temp .. "/keycoach.txt")
  vim.cmd("helptags " .. vim.fn.fnameescape(temp))
  return tags_from_tags_file(temp)
end

local function defined_tags(contents)
  local tags = {}
  for _, line in ipairs(lines(contents)) do
    for tag in line:gmatch("%*([^%*]+)%*") do
      tags[#tags + 1] = tag
    end
  end
  return tags
end

local function referenced_tags(contents)
  local tags = {}
  for tag in contents:gmatch("%|([^%|]+)%|") do
    tags[#tags + 1] = tag
  end
  return tags
end

local function builtin_tags()
  local runtime = vim.env.VIMRUNTIME
  if runtime == "" then
    return {}
  end
  return tags_from_tags_file(runtime .. "/doc")
end

h.describe("Vim help doc (doc/keycoach.txt)", function()
  h.it("exists as a regular file", function()
    local stat = vim.uv.fs_stat(DOC_PATH)
    h.truthy(stat, "doc/keycoach.txt should exist")
    h.eq("file", stat.type)
  end)

  h.it("resolves through :help keycoach after helptags generation", function()
    local tags = generated_tags()
    h.truthy(
      vim.tbl_contains(tags, "keycoach.txt"),
      ":help keycoach must resolve to a generated tag"
    )
    h.truthy(vim.tbl_contains(tags, "keycoach"), "the *keycoach* alias tag should resolve")
  end)

  h.it("documents every KeyCoach user command registered by the plugin", function()
    package.loaded["keycoach"] = nil
    require("keycoach").setup({ enabled = false })

    local contents = read_doc()
    local commands = vim.api.nvim_get_commands({ builtin = false })
    for name, _ in pairs(commands) do
      if name:match("^KeyCoach") then
        h.truthy(contents:find(":" .. name, 1, true), "help doc must document :" .. name)
      end
    end
  end)

  h.it("documents the statusline function", function()
    local contents = read_doc()
    h.truthy(contents:find("statusline", 1, true), "help doc must mention statusline")
  end)

  h.it("documents the capture boundary and that content is never stored", function()
    local contents = read_doc()
    for _, phrase in ipairs({
      "Normal",
      "Visual",
      "Operator-pending",
      "never",
    }) do
      h.truthy(
        contents:find(phrase, 1, true),
        "help doc must cover the capture boundary (" .. phrase .. ")"
      )
    end
  end)

  h.it("documents setup, commands, statusline, privacy, and data sections", function()
    local contents = read_doc()
    local section_topics = {
      "setup",
      "command",
      "statusline",
      "privacy",
      "data",
    }
    local lower = contents:lower()
    for _, topic in ipairs(section_topics) do
      h.truthy(lower:find(topic, 1, true), "help doc must cover the " .. topic .. " topic")
    end
  end)

  h.it("defines no duplicate tags", function()
    local tags = defined_tags(read_doc())
    local seen = {}
    for _, tag in ipairs(tags) do
      h.falsy(seen[tag], "duplicate tag *" .. tag .. "*")
      seen[tag] = true
    end
  end)

  h.it("resolves every |xref| to a defined tag", function()
    local contents = read_doc()
    local local_tags = {}
    for _, tag in ipairs(defined_tags(contents)) do
      local_tags[tag] = true
    end
    local builtin = builtin_tags()
    local known = {}
    for _, tag in ipairs(builtin) do
      known[tag] = true
    end

    for _, xref in ipairs(referenced_tags(contents)) do
      local ok = local_tags[xref] or known[xref]
      h.truthy(ok, "xref |" .. xref .. "| must resolve to a defined tag")
    end
  end)
end)
