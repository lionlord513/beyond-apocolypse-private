-- Render-only component changes; never remove actors/instances or touch
-- collision, simulation, navigation, native streaming or gameplay distance.
return function(valid)
 local S={saved={},hidden=0,culled=0,protected=0}
 local function class(o)return o:GetClass():GetFName():ToString()end
 local function vegetation(name)
  for _,word in ipairs({'grass','bush','shrub','fern','flower','weed','foliage'})do if name:find(word,1,true)then return true end end
  return false
 end
 local function preserve(name)
  for _,word in ipairs({'road','landscape','terrain','bridge','guardrail','barrier','sign','door','loot','item','vehicle','car','player','zombie','interactive','lamp','light','water','fence'})do if name:find(word,1,true)then return true end end
  return false
 end
 function S.apply(c,scale)
  if not valid(c)then return end
  local key=c:GetAddress();local name=c:GetFullName();local prior=S.saved[key]
  -- UE4SS creates fresh Lua wrappers for the same native component. Preserve
  -- its first snapshot; wrapper equality re-applied work and lost restoration.
  if prior and valid(prior.component)and prior.identity==name then return end
  local owner=c:GetOwner();if not valid(owner)then return end
  local ownerName=owner:GetFullName():lower();local cls=class(c)
  local generated=cls=='FoliageInstancedStaticMeshComponent'or cls=='HierarchicalInstancedStaticMeshComponent'or cls=='InstancedStaticMeshComponent'
  local function save()local v={component=c,identity=c:GetFullName(),cull=c.LDMaxDrawDistance,visible=c.bVisible,never=c.bNeverDistanceCull};S.saved[key]=v;return v end
  -- Counter global scenery scaling for roads and dynamic/interactive actors.
  if preserve(ownerName)and(not generated or not ownerName:find('landscapepcg',1,true))then save();c.bNeverDistanceCull=true;c:SetCullDistance(c.LDMaxDrawDistance);S.protected=S.protected+1;return end
  local mesh=c.StaticMesh;if not valid(mesh)then return end
  local name=mesh:GetFullName():lower()
  local ownerClass=class(owner);local isStatic=ownerClass=='StaticMeshActor'
  local isVegetation=vegetation(mesh:GetFullName():lower())
  local collision=c:GetCollisionEnabled()
  -- Only authored static decoration and PCG/instanced foliage are candidates.
  -- Interactive subclasses, movable components, collision vegetation stay.
  if not isStatic and not generated then return end
  if preserve(name)then save();c.bNeverDistanceCull=true;c:SetCullDistance(c.LDMaxDrawDistance);S.protected=S.protected+1;return end
  local saved={component=c,identity=c:GetFullName(),cull=c.LDMaxDrawDistance,visible=c.bVisible,never=c.bNeverDistanceCull}
  local clutter=name:find('clutter',1,true)or name:find('debris',1,true)or name:find('litter',1,true)
  if (isVegetation or clutter)and collision==0 then
   S.saved[key]=saved;c:SetVisibility(false,false);S.hidden=S.hidden+1
  elseif isStatic or generated then
   -- 160 m leaves ~5 seconds at 110 km/h. Colliding scenery remains visible
   -- nearby; roads, signs and all functional actors retain native visibility.
   local target=16000/math.max(.01,scale)
   if saved.cull>0 then target=math.min(saved.cull,target)end
   S.saved[key]=saved;c.bNeverDistanceCull=false;c:SetCullDistance(target);S.culled=S.culled+1
  end
 end
 function S.tick(scale)
  for key,v in pairs(S.saved)do if not valid(v.component)then S.saved[key]=nil end end
  local seen={}
  for _,kind in ipairs({'StaticMeshComponent','ProceduralMeshComponent'})do
   for _,c in ipairs(FindAllOf(kind)or{})do if valid(c)then local key=c:GetAddress();if not seen[key]then seen[key]=true;S.apply(c,scale)end end end
  end
 end
 function S.restore()
  local failed=0
  for _,v in pairs(S.saved)do if valid(v.component)then local ok=pcall(function()
   v.component.bNeverDistanceCull=v.never;v.component:SetCullDistance(v.cull);v.component:SetVisibility(v.visible,false)
  end);if not ok then failed=failed+1 end end end
  if failed==0 then S.saved={};S.hidden=0;S.culled=0;S.protected=0 end
  return failed==0
 end
 return S
end
