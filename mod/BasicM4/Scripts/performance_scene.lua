-- Local rendering only. Never remove foliage instances, change collision,
-- extend draw distance, or modify gameplay actors. PCG and placed foliage do
-- not obey grass.DensityScale, so hide their non-colliding ground cover here.
return function(valid)
 local meshClass=StaticFindObject('/Script/Engine.StaticMeshComponent')
 local S={saved={},order={},pending={},queue={},first=1,last=0,suspended=true,hidden=0,
  metrics={discoveries=0,examined=0,batches=0,maxBatchMs=0},pruneAt=0,cursor=1}
 local function component(c)return valid(c)and c:IsA(meshClass)end
 local function current(r)return component(r.component)and r.component:GetFullName()==r.identity end
 local function class(a)return a:GetClass():GetFName():ToString()end
 local function decoration(c)
  local owner=c:GetOwner();if not valid(owner)then return nil end
  local kind=class(owner)
  if kind~='StaticMeshActor'and kind~='InstancedFoliageActor'and kind~='SLLandscapePCG'then return false end
  local mesh=c.StaticMesh;if not valid(mesh)then return nil end
  if c:GetCollisionEnabled()~=0 then return false end
  local path=mesh:GetFullName():lower();local name=path:match('%.([^%.]+)$')or path:match('/([^/]+)$')or path
  for _,word in ipairs({'road','terrain','bridge','guardrail','barrier','sign','door','loot','vehicle','water','fence'})do
   if name:find(word,1,true)then return false end
  end
  -- Trees/cacti can acquire collision as their PCG cell approaches the player.
  -- Keep their silhouette even while their distant component has no collision.
  if name:find('tree',1,true)and not name:find('bush',1,true)then return false end
  for _,word in ipairs({'grass','bush','shrub','fern','flower','weed','marigold','naturaltrash','rockspebbles'})do
   if name:find(word,1,true)then return true end
  end
  return path:find('/trash/',1,true)~=nil and kind=='InstancedFoliageActor'
 end
 local function visibility(c,value)
  S.writing=true;local ok,e=pcall(c.SetVisibility,c,value,false);S.writing=false
  if not ok then error(e)end
 end
 local function forget(r,restore)
  if restore and current(r)then visibility(r.component,r.visible)end
  if S.saved[r.key]==r then S.saved[r.key]=nil;S.hidden=S.hidden-1 end
 end
 function S.apply(c)
  if not component(c)then return true end
  local key=c:GetAddress();local name=c:GetFullName();local old=S.saved[key]
  if old and (not current(old)or old.identity~=name)then forget(old,false);old=nil end
  local eligible=decoration(c)
  if eligible==nil then return false end
  if not eligible then if old then forget(old,true)end;return true end
  if not old then
   old={key=key,component=c,identity=name,visible=c.bVisible};S.saved[key]=old;S.order[#S.order+1]=old;S.hidden=S.hidden+1
  end
  if c.bVisible then visibility(c,false)end
  return true
 end
 function S.observe(c)
  if S.suspended or not component(c)then return end
  local key=c:GetAddress();if S.pending[key]then return end
  S.pending[key]=true;S.last=S.last+1;S.queue[S.last]={component=c,key=key,expires=os.clock()+10}
 end
 function S.begin()
  if not S.suspended then return end
  S.suspended=false;S.seed=true
  if S.listening then return end
  NotifyOnNewObject('/Script/Engine.StaticMeshComponent',S.observe)
  local function hook(path,fn)if valid(StaticFindObject(path))then RegisterHook(path,function()end,fn)end end
  -- Asset assignment catches PCG components that finish construction later.
  hook('/Script/Engine.StaticMeshComponent:SetStaticMesh',function(ctx)if not S.suspended then S.observe(ctx:get())end end)
  hook('/Script/Engine.PrimitiveComponent:SetCollisionEnabled',function(ctx)
   if not S.suspended then local c=ctx:get();if valid(c)and S.saved[c:GetAddress()]then S.observe(c)end end
  end)
  hook('/Script/Engine.SceneComponent:SetVisibility',function(ctx,value)
   if S.suspended or S.writing then return end
   local c=ctx:get();local r=valid(c)and S.saved[c:GetAddress()]
   if r and current(r)then r.visible=value:get();S.observe(c)end
  end)
  S.listening=true
 end
 function S.tick()
  if S.suspended then return end
  local start=os.clock();local count=0
  if S.seed then
   S.seed=false;S.seedItems=FindAllOf('StaticMeshComponent')or{};S.seedIndex=1
   S.metrics.discoveries=S.metrics.discoveries+1;return
  end
  local deadline=start+.001
  if S.seedItems then
   while S.seedIndex<=#S.seedItems and count<64 and os.clock()<deadline do
    local i=S.seedIndex;local c=S.seedItems[i];S.seedItems[i]=false;S.seedIndex=i+1;count=count+1
    if not S.apply(c)then S.observe(c)end
   end
   if S.seedIndex>#S.seedItems then S.seedItems=nil end
  end
  -- Process only new/changed objects. Settled objects have no polling loop.
  local last=S.last
  while S.first<=last and count<64 and os.clock()<deadline do
   local i=S.first;local r=S.queue[i];S.queue[i]=nil;S.first=i+1;count=count+1
   S.pending[r.key]=nil
   if not S.apply(r.component)and os.clock()<r.expires then
    S.pending[r.key]=true;S.last=S.last+1;S.queue[S.last]=r
   end
  end
  if S.first>S.last then S.queue={};S.first=1;S.last=0 end
  if start>=S.pruneAt then
   S.pruneAt=start+3
   for _=1,math.min(32,#S.order)do
    if S.cursor>#S.order then S.cursor=1 end
    local r=S.order[S.cursor]
    if S.saved[r.key]~=r or not current(r)then
     forget(r,false);S.order[S.cursor]=S.order[#S.order];S.order[#S.order]=nil
    else S.cursor=S.cursor+1 end
   end
  end
  if count>0 then local m=S.metrics;m.examined=m.examined+count;m.batches=m.batches+1;m.maxBatchMs=math.max(m.maxBatchMs,(os.clock()-start)*1000)end
 end
 function S.restore()
  S.suspended=true;S.seed=nil;S.seedItems=nil;S.pending={};S.queue={};S.first=1;S.last=0
  local failed=0
  for _,r in pairs(S.saved)do local ok=pcall(forget,r,true);if not ok then failed=failed+1 end end
  if failed==0 then S.saved={};S.order={};S.hidden=0;S.cursor=1 end
  return failed==0
 end
 return S
end
