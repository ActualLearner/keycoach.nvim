local uv = vim.uv or vim.loop

local M = {}

local function problem(code, message, path)
  return {
    code = code,
    message = message,
    path = path,
  }
end

local function valid_path(path)
  return type(path) == "string" and path ~= ""
end

local function parent_directory(path)
  return vim.fn.fnamemodify(path, ":h")
end

local function remove_quietly(path)
  pcall(uv.fs_unlink, path)
end

local function atomic_write(path, contents)
  local parent = parent_directory(path)
  local made_parent, mkdir_result = pcall(vim.fn.mkdir, parent, "p")
  if not made_parent or mkdir_result == 0 and not uv.fs_stat(parent) then
    return nil, problem("write_failed", "could not create checkpoint directory", path)
  end

  local temporary = string.format("%s.tmp.%s.%s", path, uv.os_getpid(), uv.hrtime())
  local file, open_message = io.open(temporary, "wb")
  if not file then
    return nil, problem("write_failed", open_message or "could not open temporary checkpoint", path)
  end

  local wrote, write_message = file:write(contents)
  local closed, close_message = file:close()
  if not wrote or not closed then
    remove_quietly(temporary)
    return nil, problem("write_failed", write_message or close_message or "could not write checkpoint", path)
  end

  local renamed, rename_message = uv.fs_rename(temporary, path)
  if not renamed then
    remove_quietly(temporary)
    return nil, problem("write_failed", rename_message or "could not replace checkpoint", path)
  end

  return true, nil
end

function M.load(path)
  if not valid_path(path) then
    return nil, problem("invalid_path", "checkpoint path must be a non-empty string", path)
  end

  local stat, message, code = uv.fs_stat(path)
  if not stat then
    if code == "ENOENT" then
      return nil, nil
    end

    return nil, problem("read_failed", message or "could not inspect checkpoint", path)
  end

  if stat.type ~= "file" then
    return nil, problem("read_failed", "checkpoint path is not a regular file", path)
  end

  local file, open_message = io.open(path, "rb")
  if not file then
    return nil, problem("read_failed", open_message or "could not open checkpoint", path)
  end

  local contents = file:read("*a")
  local closed, close_message = file:close()
  if not contents or not closed then
    return nil, problem("read_failed", close_message or "could not read checkpoint", path)
  end

  local decoded, checkpoint = pcall(vim.json.decode, contents)
  if not decoded then
    return nil, problem("invalid_json", checkpoint, path)
  end
  if type(checkpoint) ~= "table" then
    return nil, problem("invalid_checkpoint", "stored checkpoint must be a JSON-compatible table", path)
  end

  return checkpoint, nil
end

function M.save(path, checkpoint)
  if not valid_path(path) then
    return nil, problem("invalid_path", "checkpoint path must be a non-empty string", path)
  end

  if type(checkpoint) ~= "table" then
    return nil, problem("invalid_checkpoint", "checkpoint must be a JSON-compatible table", path)
  end

  local encoded, json = pcall(vim.json.encode, checkpoint)
  if not encoded then
    return nil, problem("invalid_checkpoint", json, path)
  end

  return atomic_write(path, json .. "\n")
end

function M.export(path)
  local checkpoint, load_problem = M.load(path)
  if load_problem or checkpoint == nil then
    return nil, load_problem
  end

  local encoded, json = pcall(vim.json.encode, checkpoint)
  if not encoded then
    return nil, problem("invalid_checkpoint", json, path)
  end

  return json, nil
end

function M.delete(path)
  if not valid_path(path) then
    return nil, problem("invalid_path", "checkpoint path must be a non-empty string", path)
  end

  local deleted, message, code = uv.fs_unlink(path)
  if deleted or code == "ENOENT" then
    return true, nil
  end

  return nil, problem("delete_failed", message or "could not delete checkpoint", path)
end

return M
