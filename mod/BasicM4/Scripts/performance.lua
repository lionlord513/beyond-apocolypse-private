return function(M,H,valid,log)
 local F={nextAt=0,gameplayMode=false}
 -- Client-local preference; transient engine settings are never written to
 -- native graphics config or sent to another player.
 -- Let Unreal select LODs and cull its own objects. The old component sweep
 -- cost CPU time and its protection overrides disabled native distance culling.
 local preference=M.statePath and M.statePath('performance-mode.txt')or M.root..'/state/performance-mode.txt'
 do local f=io.open(preference,'r');if f then F.requested=f:read('*a'):match('^enabled=1%s*$')~=nil;f:close()end end
 local modeVars={{name='r.StaticMeshLODDistanceScale',target=function(n)return math.max(n,4)end,required=true},
  {name='grass.DensityScale',target=function()return 0 end,required=true,allowZero=true},
  {name='sg.PostProcessQuality',target=function()return 0 end,required=true,allowZero=true}}
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
  for _,item in ipairs(modeVars)do
   local name=item.name;local value=F.modePrevious[name]
   if math.abs(sys:GetConsoleVariableFloatValue(name)-item.target(value))<.01 then
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
   if not restoreMode(pc)then return false,'Some prior render settings could not be restored; retry.'end
   if not automatic then persist(false)end
   F.gameplayMode=false;return true,'Performance Mode off; previous render settings restored.'
  end
  if F.gameplayMode then return true,F.status end
  if not valid(pc)or not valid(sys)then return false,'Join a game first.'end
  local previous={}
  for _,item in ipairs(modeVars)do
   local value=sys:GetConsoleVariableFloatValue(item.name)
   if type(value)~='number'or value<0 or value>=100 or not item.allowZero and value==0 then return false,'Unsupported render setting: '..item.name end
   previous[item.name]=value
  end
  F.modePrevious=previous
  local ok,why=pcall(function()
   for _,item in ipairs(modeVars)do
    local target=item.target(previous[item.name]);if math.abs(previous[item.name]-target)>.01 then setCvar(sys,pc,item.name,target)end
    assert(math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)<.01,'Render setting was rejected: '..item.name)
   end
   if not automatic then persist(true)end
  end)
  if not ok then restoreMode(pc);return false,tostring(why)end
  F.gameplayMode=true
  F.status='Performance Mode on. Native LOD, grass and post-processing reductions. Saved locally.'
  log(F.status);return true,F.status
 end
 local function maintainMode(pc)
  if not F.gameplayMode then
   if F.requested then local ok,message=F.setGameplayMode(true,true);if not ok then F.status=message end end
   return
  end
  local sys=modeSystem();if not valid(sys)then return end
  for _,item in ipairs(modeVars)do if F.modePrevious and F.modePrevious[item.name]~=nil then
   local target=item.target(F.modePrevious[item.name])
   local current=sys:GetConsoleVariableFloatValue(item.name)
   if math.abs(current-target)>.01 then
    -- A native preset changed while Performance Mode was active.
    F.modePrevious[item.name]=current
    target=item.target(current)
    setCvar(sys,pc,item.name,target)
    if math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)>.01 then F.status='Performance Mode partly rejected by the engine.';log(F.status)end
   end
  end end
  F.status='Performance Mode on. Native LOD, grass and post-processing reductions. Saved locally.'
 end
 function F.tick()
  if not F.requested and not F.gameplayMode or os.clock()<F.nextAt then return end
  F.nextAt=os.clock()+3
  local pc=H.GetPlayerController();if valid(pc)then maintainMode(pc)end
 end
 function F.reset()restoreMode(H.GetPlayerController());F.gameplayMode=false;F.nextAt=0 end
 return F
end
