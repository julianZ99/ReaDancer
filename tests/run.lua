-- Test runner. Run from the repo root: `lua5.4 tests/run.lua`
-- Exits non-zero if any test fails (for CI).

local suites = { 'test_loader', 'test_engine' }

local total_pass, total_fail = 0, 0
for _, name in ipairs(suites) do
  print('== ' .. name .. ' ==')
  local pass, fail = dofile('tests/' .. name .. '.lua')
  print(('   %d passed, %d failed'):format(pass, fail))
  total_pass = total_pass + pass
  total_fail = total_fail + fail
end

print(('\nTOTAL: %d passed, %d failed'):format(total_pass, total_fail))
os.exit(total_fail == 0 and 0 or 1)
