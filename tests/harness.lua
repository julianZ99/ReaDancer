-- Test harness: load ReaDancer.lua with a mock `reaper` and mock `.txt` files,
-- returning the module table it exposes (engine, loader, ...).
--
-- ReaDancer is one ReaScript that runs on load, so we stub just enough of the
-- REAPER API for its top-level code to run, then use the modules it returns.
-- Run the suite from the repo root: `lua5.4 tests/run.lua`.

local M = {}

local realopen = io.open

-- Load ReaDancer with the given options and return its module table.
--   opts.imgW, opts.imgH : dimensions ImGui_Image_GetSize reports (default 96x48)
--   opts.txt             : array of `.txt` lines, or nil for "no .txt file"
function M.load(opts)
  opts = opts or {}
  local imgW, imgH = opts.imgW or 96, opts.imgH or 48
  local txt = opts.txt

  _G.reaper = {
    ImGui_CreateContext       = function() return {} end,
    ImGui_CreateImage         = function() return {} end,
    ImGui_Image_GetSize       = function() return imgW, imgH end,
    ImGui_WindowFlags_TopMost = function() return 0 end,
    GetExtState               = function() return '' end,
    SetExtState               = function() end,
    atexit                    = function() end,
    defer                     = function() end,
    time_precise              = function() return 0 end,
    MB                        = function() end,
  }

  -- serve opts.txt for any `*.txt` open; real files (the .lua) go to realopen
  io.open = function(path, mode)
    if path:match('%.txt$') then
      if not txt then return nil end
      local i = 0
      return {
        lines = function() return function() i = i + 1; return txt[i] end end,
        close = function() end,
      }
    end
    return realopen(path, mode)
  end

  local src = realopen('ReaDancer.lua', 'r'):read('*a')
  return assert(load(src, 'ReaDancer'))()
end

-- Tiny assertion helper. Returns a table with :eq and :ok plus pass/fail counts.
function M.tester()
  local t = { pass = 0, fail = 0 }
  function t:eq(name, got, want)
    if got == want then self.pass = self.pass + 1
    else self.fail = self.fail + 1
      print(('  FAIL %s: got %s want %s'):format(name, tostring(got), tostring(want)))
    end
  end
  function t:ok(name, cond)
    if cond then self.pass = self.pass + 1
    else self.fail = self.fail + 1; print('  FAIL ' .. name) end
  end
  return t
end

return M
