local result = {}
local GameState = require('Base.GameState')
local weapon_mesh = GameState:GetEquippedWeapon()
if not weapon_mesh then return 'NO WEAPON' end
result[#result+1] = 'weapon: ' .. weapon_mesh:get_fname():to_string()
local all_scope_meshes = GameState:get_all_scope_meshes(weapon_mesh)
if all_scope_meshes then
  for i, mesh in ipairs(all_scope_meshes) do
    local fname = mesh:get_fname():to_string()
    local nm = mesh:GetNumMaterials()
    result[#result+1] = 'mesh[' .. i .. ']: ' .. fname .. ' mats=' .. nm
    for slot = 0, nm-1 do
      local mat = mesh:GetMaterial(slot)
      if mat then
        local ok, parent = pcall(function() return mat.Parent end)
        local pname = (ok and parent) and parent:get_fname():to_string() or '(no parent)'
        result[#result+1] = '  slot' .. slot .. ': ' .. mat:get_fname():to_string() .. ' parent=' .. pname
      end
    end
  end
else
  result[#result+1] = 'no scope meshes'
end
return table.concat(result, '\n')
