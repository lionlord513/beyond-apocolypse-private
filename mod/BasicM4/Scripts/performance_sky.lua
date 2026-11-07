-- UDS owns time, weather and lighting. Suppress only its local cloud renderers
-- and cloud particle simulation; keep the sky actor and gameplay clock running.
return function(valid)
 local S={active=false,saved={},pending={},wake={}}
 local fields={'VolumetricCloud','StaticCloudsSphere','Overcast_Turbulence','Inside_Cloud_Fog','VolumetricCloud_LightRays'}
 local niagara=StaticFindObject('/Script/Niagara.NiagaraComponent')
 local function current(r)return valid(r.component)and r.component:GetFullName()==r.name end
 local function write(fn)
  S.writing=true;local ok,e=pcall(fn);S.writing=false;if not ok then error(e)end
 end
 local function adopt(a)
  if not valid(a)then return true end
  local complete=true
  for _,name in ipairs(fields)do local c=a[name]
   if valid(c)then
    local key=c:GetAddress();local old=S.saved[key]
    if not old or not current(old)then
     local r={component=c,name=c:GetFullName(),visible=c.bVisible}
     if valid(niagara)and c:IsA(niagara)then r.paused=c:IsPaused();r.tick=c:IsComponentTickEnabled()end
     S.saved[key]=r
     write(function()c:SetVisibility(false,false);if r.paused~=nil then c:SetPaused(true);c:SetComponentTickEnabled(false)end end)
    end
   else complete=false end
  end
  return complete
 end
 function S.observe(a)if S.active then S.pending[#S.pending+1]={actor=a,untilAt=os.clock()+10}end end
 function S.begin()
  if S.active then return end;S.active=true
  if not S.listening then
   NotifyOnNewObject('/Game/UltraDynamicSky/Blueprints/Ultra_Dynamic_Sky_Nory.Ultra_Dynamic_Sky_Nory_C',S.observe)
   local function intercept(path,key,value)
    if not valid(StaticFindObject(path))then return end
    RegisterHook(path,function(ctx,arg)
     if not S.active or S.writing then return end
     local c=ctx:get();local r=valid(c)and S.saved[c:GetAddress()]
     if r and current(r)and (key=='visible'or r.paused~=nil)then
      -- Remember the latest native intent, including night/weather changes,
      -- so disabling this preset restores what UDS currently wants.
      r[key]=arg:get();arg:set(value)
     end
    end)
   end
   intercept('/Script/Engine.SceneComponent:SetVisibility','visible',false)
   intercept('/Script/Niagara.NiagaraComponent:SetPaused','paused',true)
   intercept('/Script/Engine.ActorComponent:SetComponentTickEnabled','tick',false)
   local activate='/Script/Engine.ActorComponent:Activate'
   if valid(StaticFindObject(activate))then RegisterHook(activate,function()end,function(ctx)
    if not S.active or S.writing then return end
    local c=ctx:get();local r=valid(c)and S.saved[c:GetAddress()]
    if r and r.paused~=nil and current(r)then
     -- The prehooks already recorded native intent. Reading the component
     -- here would replace it with our forced pause/tick values.
     S.wake[c:GetAddress()]=r
    end
   end)end
   S.listening=true
  end
  for _,a in ipairs(FindAllOf('Ultra_Dynamic_Sky_Nory_C')or{})do S.observe(a)end
  S.tick()
 end
 function S.tick()
  if not S.active then return end
  for key,r in pairs(S.wake)do
   S.wake[key]=nil
   if current(r)then write(function()r.component:SetPaused(true);r.component:SetComponentTickEnabled(false)end)end
  end
  if #S.pending==0 then return end
  local q=S.pending;S.pending={}
  for i,r in ipairs(q)do
   if i>2 then S.pending[#S.pending+1]=r
   elseif not adopt(r.actor)and os.clock()<r.untilAt then S.pending[#S.pending+1]=r end
  end
 end
 function S.restore()
  S.active=false;S.pending={};S.wake={};local failed=0
  for key,r in pairs(S.saved)do
   local ok=pcall(function()if current(r)then write(function()
    local c=r.component;c:SetVisibility(r.visible,false)
    if r.paused~=nil then c:SetPaused(r.paused);c:SetComponentTickEnabled(r.tick)end
   end)end end)
   if ok then S.saved[key]=nil else failed=failed+1 end
  end
  return failed==0
 end
 return S
end
