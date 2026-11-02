-- Native zombie provider. Future imported variants plug in here; no mesh swap yet.
local Z={}
function Z.classes(spawner,valid)
 local out={};spawner.ArrayClass:ForEach(function(_,v)local c=v:get();if valid(c)then out[#out+1]=c end end);return out
end
function Z.configure(z,c,valid)
 z:SetReplicates(true);z:SetReplicateMovement(true)
 z.bAlwaysRelevant=false;z.NetCullDistanceSquared=(c.DrawMeters*100)^2
 -- Every clothing piece must use the same distance as the body.
 local cls=StaticFindObject('/Script/Engine.SkinnedMeshComponent')
 for _,v in ipairs(z:K2_GetComponentsByClass(cls))do
  local mesh=v:get();mesh:SetCullDistance(c.DrawMeters*100)
  mesh.VisibilityBasedAnimTickOption=3
 end
end
return Z
