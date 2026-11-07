return function(M,H,valid,log)
 local F={nextAt=0,gameplayMode=false}
 -- Client-local preference; transient engine settings are never written to
 -- native graphics config or sent to another player.
 -- Native distance culling stays intact. Decoration uses a bounded startup
 -- pass and construction/change events, without a recurring world scan.
 local preference=M.statePath and M.statePath('performance-mode.txt')or M.root..'/state/performance-mode.txt'
 do local f=io.open(preference,'r');if f then F.requested=f:read('*a'):match('^enabled=1%s*$')~=nil;f:close()end end
 local modeVars={{name='r.StaticMeshLODDistanceScale',target=function(n)return math.max(n,8)end,required=true},
  {name='foliage.LODDistanceScale',target=function(n)return math.min(n,.25)end,required=true},
  {name='grass.DensityScale',target=function()return 0 end,required=true,allowZero=true},
  {name='sg.PostProcessQuality',target=function()return 0 end,required=true,allowZero=true},
  {name='r.Shadow.MaxResolution',target=function(n)return math.min(n,512)end,maximum=16384,allowZero=true},
  {name='r.Shadow.MaxCSMResolution',target=function(n)return math.min(n,512)end,maximum=16384,allowZero=true},
  {name='r.Shadow.CSM.MaxCascades',target=function(n)return math.min(n,1)end,allowZero=true},
  {name='r.SkeletalMeshLODBias',target=function(n)return math.max(n,1)end,allowZero=true},
  {name='r.ParticleLODBias',target=function(n)return math.max(n,1)end,allowZero=true}}
 for _,name in ipairs({'r.ShadowQuality','r.VolumetricFog','r.VolumetricCloud','r.SSR.Quality','r.RefractionQuality','r.AmbientOcclusionLevels',
  'r.MotionBlurQuality','r.DepthOfFieldQuality','r.BloomQuality','r.LensFlareQuality','r.SkyAtmosphere.MultiScatteringLUT.HighQuality'})do
  modeVars[#modeVars+1]={name=name,target=function()return 0 end,allowZero=true,minimum=name=='r.AmbientOcclusionLevels'and -1 or 0}
 end
 for _,name in ipairs({'r.SkyAtmosphere.SampleCountMin','r.SkyAtmosphere.FastSkyLUT.SampleCountMin'})do
  modeVars[#modeVars+1]={name=name,target=function(n)return math.min(n,4)end,maximum=4096,allowZero=true}
 end
 for _,name in ipairs({'r.SkyAtmosphere.SampleCountMax','r.SkyAtmosphere.FastSkyLUT.SampleCountMax'})do
  modeVars[#modeVars+1]={name=name,target=function(n)return math.min(n,16)end,maximum=4096,allowZero=true}
 end
 local enabledStatus='Extreme Performance Mode on. Decorative foliage and clouds removed; sky, trees and effects simplified.'
 local function scene()
  if not F.scene then F.scene=dofile(M.root..'/Scripts/performance_scene.lua')(valid)end
  return F.scene
 end
 local function sky()
  if not F.sky then F.sky=dofile(M.root..'/Scripts/performance_sky.lua')(valid)end
  return F.sky
 end
 local function modeSystem()return StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')end
 local function setCvar(sys,pc,name,value)sys:ExecuteConsoleCommand(pc,name..' '..tostring(value),pc)end
 local function persist(enabled)
  local f=assert(io.open(preference..'.tmp','w'),'Cannot save Performance Mode preference')
  assert(f:write(enabled and 'enabled=1\n'or 'enabled=0\n'));assert(f:close())
  os.remove(preference..'.bak');local old=io.open(preference,'r');if old then old:close();assert(os.rename(preference,preference..'.bak'))end
  local ok,e=os.rename(preference..'.tmp',preference);if not ok then os.rename(preference..'.bak',preference);error(e)end
  F.requested=enabled
 end
 local function restoreMode(pc)
  if not F.modePrevious then return true end
  local sys=modeSystem();if not valid(pc)or not valid(sys)then return false end
  local worked=true
  local owned={}
  -- Restoring a scalability group can change several leaf variables. Decide
  -- ownership before any writes, then restore every still-owned leaf snapshot.
  for _,item in ipairs(modeVars)do local value=F.modePrevious[item.name]
   owned[item.name]=math.abs(sys:GetConsoleVariableFloatValue(item.name)-item.target(value))<.01
  end
  for _,item in ipairs(modeVars)do
   local name=item.name;local value=F.modePrevious[name]
   if owned[name]then
    local ok=pcall(setCvar,sys,pc,name,value)
    if not ok or math.abs(sys:GetConsoleVariableFloatValue(name)-value)>.01 then worked=false end
   end
  end
  if worked then F.modePrevious=nil end
  return worked
 end
 function F.setGameplayMode(enabled,automatic)
  enabled=enabled==true
  local pc,sys=H.GetPlayerController(),modeSystem()
  if not enabled then
   if F.sky and not F.sky.restore()then return false,'Some cloud settings could not be restored; retry.'end
   if F.scene and not F.scene.restore()then return false,'Some foliage could not be restored; retry.'end
   if not restoreMode(pc)then return false,'Some prior render settings could not be restored; retry.'end
   if not automatic then persist(false)end
   F.gameplayMode=false;return true,'Performance Mode off; previous render settings restored.'
  end
  if F.gameplayMode then return true,F.status end
  if not valid(pc)or not valid(sys)or not valid(pc.PlayerControlled)or not pc.PlayerControlled.IsLoaded then return false,'Join a game first.'end
  local previous={}
  for _,item in ipairs(modeVars)do
   local value=sys:GetConsoleVariableFloatValue(item.name)
   if type(value)~='number'or value~=value or value<(item.minimum or 0)or value>=(item.maximum or 100)or not item.allowZero and value==0 then return false,'Unsupported render setting: '..item.name end
   previous[item.name]=value
  end
  F.modePrevious=previous
  local ok,why=pcall(function()
   for _,item in ipairs(modeVars)do
    local target=item.target(previous[item.name]);if math.abs(previous[item.name]-target)>.01 then setCvar(sys,pc,item.name,target)end
    assert(math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)<.01,'Render setting was rejected: '..item.name)
   end
   scene().begin();sky().begin()
   if not automatic then persist(true)end
  end)
  if not ok then if F.sky then F.sky.restore()end;if F.scene then F.scene.restore()end;restoreMode(pc);return false,tostring(why)end
  F.gameplayMode=true
  F.status=enabledStatus
  log(F.status);return true,F.status
 end
 local function maintainMode(pc)
  if not F.gameplayMode then
   if F.requested then local ok,message=F.setGameplayMode(true,true);if not ok then F.status=message end end
   return
  end
  local sys=modeSystem();if not valid(sys)then return end
  local rejected={}
  for _,item in ipairs(modeVars)do if F.modePrevious and F.modePrevious[item.name]~=nil then
   local target=item.target(F.modePrevious[item.name])
   local current=sys:GetConsoleVariableFloatValue(item.name)
   if math.abs(current-target)>.01 then
    -- A native preset changed while Performance Mode was active.
    F.modePrevious[item.name]=current
    target=item.target(current)
    setCvar(sys,pc,item.name,target)
    if math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)>.01 then rejected[#rejected+1]=item.name end
   end
  end end
  local status=#rejected>0 and ('Performance Mode partly rejected: '..table.concat(rejected,', '))or
   enabledStatus
  if status~=F.status and #rejected>0 then log(status)end
  F.status=status
 end
 function F.tick()
  if F.gameplayMode and F.sky then F.sky.tick()end
  if F.gameplayMode and F.scene then F.scene.tick()end
  if not F.requested and not F.gameplayMode or os.clock()<F.nextAt then return end
  F.nextAt=os.clock()+3
  local pc=H.GetPlayerController();if valid(pc)then maintainMode(pc)end
 end
 function F.reset()if F.sky then F.sky.restore()end;if F.scene then F.scene.restore()end;restoreMode(H.GetPlayerController());F.gameplayMode=false;F.nextAt=0 end
 return F
end
