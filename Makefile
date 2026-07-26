.PHONY: test check

test:
	nvim --headless -u NONE -l tests/run.lua

check: test
	nvim --headless -u NONE \
		-c "set runtimepath^=." \
		-c "lua require('keycoach')" \
		-c "qa!"
