local root = vim.fn.getcwd()

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  package.path,
}, ";")

vim.opt.runtimepath:prepend(root)

local spec_pattern = vim.env.SPEC or "*_spec.lua"
local specs = vim.fn.globpath(root .. "/tests", spec_pattern, false, true)
table.sort(specs)

for _, spec in ipairs(specs) do
  dofile(spec)
end

require("tests.harness").run()
