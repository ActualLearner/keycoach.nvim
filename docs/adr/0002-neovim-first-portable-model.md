# Ship Neovim first behind a portable domain model

The first implementation is a pure Lua Neovim plugin with no required external runtime, while Observation and Recommendation fixtures remain runtime-neutral so later VS Code and Vim adapters can reproduce the same behavior. A shared native process could reduce future porting, but its installation and packaging cost would weaken the Neovim-first release.
