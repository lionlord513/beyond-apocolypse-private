-- Render-only component changes; never remove actors/instances or touch
-- collision, simulation, navigation, native streaming or gameplay distance.
return function(valid)
 local staticMesh=StaticFindObject('/Script/Engine.StaticMeshComponent')
 local proceduralMesh=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local function component(c)return valid(c)and(c:IsA(staticMesh)or c:IsA(proceduralMesh))end
 local S={saved={},ignored={},hidden=0,culled=0,protected=0,suspended=true,
  registry={},known={},incoming={},incomingFirst=1,incomingLast=0,cursor=1,
  metrics={discoveries=0,discoveryMs=0,maxDiscoveryMs=0,batches=0,applyMs=0,maxApplyMs=0,examined=0,ignoredHits=0,cycles=0}}
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
  if not component(c)then return end
  local key=c:GetAddress();local name=c:GetFullName();local prior=S.saved[key]
  -- UE4SS creates fresh Lua wrappers for the same native component. Preserve
  -- its first snapshot; wrapper equality re-applied work and lost restoration.
  if prior and valid(prior.component)and prior.identity==name then return end
  local owner=c:GetOwner();if not valid(owner)then return end
  local ownerIdentity=owner:GetFullName();local ignored=S.ignored[key]
  if ignored and valid(ignored.component)and valid(ignored.owner)and ignored.identity==name and ignored.ownerIdentity==ownerIdentity and ignored.owner:GetAddress()==owner:GetAddress()then
   S.metrics.ignoredHits=S.metrics.ignoredHits+1;return
  end
  if ignored then S.ignored[key]=nil end
  local ownerName=ownerIdentity:lower();local cls=class(c)
  local generated=cls=='FoliageInstancedStaticMeshComponent'or cls=='HierarchicalInstancedStaticMeshComponent'or cls=='InstancedStaticMeshComponent'
  local function save()local v={component=c,identity=c:GetFullName(),cull=c.LDMaxDrawDistance,visible=c.bVisible,never=c.bNeverDistanceCull};S.saved[key]=v;return v end
  -- Counter global scenery scaling for roads and dynamic/interactive actors.
  if preserve(ownerName)and(not generated or not ownerName:find('landscapepcg',1,true))then save();c.bNeverDistanceCull=true;c:SetCullDistance(c.LDMaxDrawDistance);S.protected=S.protected+1;return end
  local ownerClass=class(owner);local isStatic=ownerClass=='StaticMeshActor'
  -- Only authored static decoration and PCG/instanced foliage are candidates.
  -- Interactive subclasses, movable components, collision vegetation stay.
  if not isStatic and not generated then
   -- Owner/component classes cannot become static/instanced in place. Validate
   -- both native identities on reuse; a new owner must be classified again.
   S.ignored[key]={component=c,identity=name,owner=owner,ownerIdentity=ownerIdentity};return
  end
  local mesh=c.StaticMesh;if not valid(mesh)then return end
  local name=mesh:GetFullName():lower()
  local isVegetation=vegetation(name)
  local collision=c:GetCollisionEnabled()
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
 function S.observe(c)
  -- The pinned loader dispatches construction notifications on the game thread.
  -- Only queue here: streamed components may not yet have an owner or mesh.
  if S.suspended then return end
  S.incomingLast=S.incomingLast+1;S.incoming[S.incomingLast]=c
 end
 function S.begin()
  S.suspended=false;S.seedKind=1;S.pending=nil
  if not S.listening then
   NotifyOnNewObject('/Script/Engine.StaticMeshComponent',S.observe)
   NotifyOnNewObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent',S.observe)
   S.listening=true
  end
 end
 local function remember(c)
  if not component(c)then return end
  local key,name=c:GetAddress(),c:GetFullName();local old=S.known[key]
  if old then
   if old.identity~=name then
    S.saved[key]=nil;S.ignored[key]=nil;old.component=c;old.identity=name;old.settled=nil
   end
   return
  end
  local r={component=c,identity=name,key=key};S.known[key]=r;S.registry[#S.registry+1]=r
 end
 local function remove(index,r)
  S.known[r.key]=nil;S.saved[r.key]=nil;S.ignored[r.key]=nil
  local last=#S.registry;S.registry[index]=S.registry[last];S.registry[last]=nil
 end
 function S.tick(scale)
  if S.suspended then return end
  local now=os.clock()
  -- Discover existing components once per enable/map. New ones arrive through
  -- notifications; never rebuild a world-sized Lua array every few seconds.
  if S.seedKind and not S.pending then
   local kind=({'StaticMeshComponent','ProceduralMeshComponent'})[S.seedKind]
   if not kind then S.seedKind=nil;S.metrics.cycles=S.metrics.cycles+1
   else
    S.pending={items=FindAllOf(kind)or{},index=1};S.pending.total=#S.pending.items
    local ms=(os.clock()-now)*1000;local m=S.metrics
    m.discoveries=m.discoveries+1;m.discoveryMs=m.discoveryMs+ms;m.maxDiscoveryMs=math.max(m.maxDiscoveryMs,ms)
    return
   end
  end
  local count=0;local deadline=now+.001
  if S.pending then
   local p=S.pending
   while p.index<=p.total and count<64 and os.clock()<deadline do
    local c=p.items[p.index];p.items[p.index]=false;p.index=p.index+1;count=count+1;remember(c)
   end
   if p.index>p.total then S.pending=nil;S.seedKind=S.seedKind+1 end
   return
  end
  -- Share one small budget between arriving components and existing records.
  while S.incomingFirst<=S.incomingLast and count<32 and os.clock()<deadline do
   local i=S.incomingFirst;local c=S.incoming[i];S.incoming[i]=nil;S.incomingFirst=i+1
   remember(c);count=count+1
  end
  if S.incomingFirst>S.incomingLast then S.incomingFirst=1;S.incomingLast=0 end
  local remaining=math.min(64-count,#S.registry)
  while remaining>0 and os.clock()<deadline do
   if S.cursor>#S.registry then S.cursor=1 end
   local r=S.registry[S.cursor];local c=r.component;count=count+1;remaining=remaining-1
   -- Native addresses can be reused after streaming unloads an object. A
   -- valid pointer alone does not mean this is still the recorded component.
   if not component(c)or c:GetFullName()~=r.identity then remove(S.cursor,r)
   else
    -- Classify each unchanged component only once, within the shared budget.
    if not r.settled then S.apply(c,scale);r.settled=S.saved[r.key]or S.ignored[r.key]end
    S.cursor=S.cursor+1
   end
  end
  local ms=(os.clock()-now)*1000;local m=S.metrics
  m.batches=m.batches+1;m.applyMs=m.applyMs+ms;m.maxApplyMs=math.max(m.maxApplyMs,ms);m.examined=m.examined+count
 end
 function S.restore()
  -- A toggle/reset must cancel queued discoveries before restoring snapshots.
  S.pending=nil;S.seedKind=nil;S.suspended=true
  S.registry={};S.known={};S.incoming={};S.incomingFirst=1;S.incomingLast=0;S.cursor=1
  local failed=0
  for _,v in pairs(S.saved)do if component(v.component)and v.component:GetFullName()==v.identity then local ok=pcall(function()
   v.component.bNeverDistanceCull=v.never;v.component:SetCullDistance(v.cull);v.component:SetVisibility(v.visible,false)
  end);if not ok then failed=failed+1 end end end
  if failed==0 then S.saved={};S.ignored={};S.hidden=0;S.culled=0;S.protected=0 end
  return failed==0
 end
 return S
end
