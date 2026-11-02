-- Remove only our old local rendering, after replacement succeeds.
return function(valid)
 return function(a,keep,carrier)
  local live,stale={},{}
  for _,c in ipairs(keep)do if valid(c)then live[c:GetAddress()]=true end end
  local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
  local prefix=carrier and 'BA_HeliTrailer' or 'BA_Hornet'
  for _,v in ipairs(a:K2_GetComponentsByClass(pmc))do
   local c=v:get()
   if valid(c)and not live[c:GetAddress()]and not c.bReplicates then
    local m=c:GetMaterial(0)
    if valid(m)and (m:GetFullName():match('[./]'..prefix..'[_%d]*$')or not carrier and m:GetFullName():match('[./]BA_Plastic[_%d]*$'))then stale[c:GetAddress()]=c end
   end
  end
  if not next(stale)then return end
  for _,v in ipairs(a:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.RotatingMovementComponent')))do
   local c=v:get()
   if valid(c)and not live[c:GetAddress()]and not c.bReplicates and valid(c.UpdatedComponent)and stale[c.UpdatedComponent:GetAddress()]then c:K2_DestroyComponent(a)end
  end
  for _,c in pairs(stale)do c:K2_DestroyComponent(a)end
 end
end


