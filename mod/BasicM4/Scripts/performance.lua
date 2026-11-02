-- All quality keys below were resolved from the game's DA_Qual asset.
-- Apply the user's existing choices through Unreal's own scalability profiles.
return function(M,H,valid,log)
 local F={nextAt=0,terrain={},sky={},dirty=true,hooks={},gameplayMode=false}
 -- Client-local preference; transient engine settings are never written to
 -- native graphics config or sent to another player.
 local scene=dofile(M.root..'/Scripts/performance_scene.lua')(valid);F.scene=scene
 local preference=M.statePath and M.statePath('performance-mode.txt')or M.root..'/state/performance-mode.txt'
 do local f=io.open(preference,'r');if f then F.requested=f:read('*a'):match('^enabled=1%s*$')~=nil;f:close()end end
 local modeVars={{name='r.ViewDistanceScale',target=function(n)return math.min(n,.25)end,required=true},
  {name='r.StaticMeshLODDistanceScale',target=function(n)return math.max(n,4)end,required=true},
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
  if not F.modePrevious then return scene.restore()end
  local sys=modeSystem();if not valid(pc)or not valid(sys)then return false end
  local worked=true
  for name,value in pairs(F.modePrevious)do
   local ok=pcall(setCvar,sys,pc,name,value)
   if not ok or math.abs(sys:GetConsoleVariableFloatValue(name)-value)>.01 then worked=false end
  end
  if not scene.restore()then worked=false end
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
    local target=item.target(previous[item.name]);setCvar(sys,pc,item.name,target)
    assert(math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)<.01,'Render setting was rejected: '..item.name)
   end
   F.sceneScale=sys:GetConsoleVariableFloatValue('r.ViewDistanceScale');scene.begin();scene.tick(F.sceneScale)
   if not automatic then persist(true)end
  end)
  if not ok then restoreMode(pc);return false,tostring(why)end
  F.gameplayMode=true
  F.status='Performance Mode on. Scenery target 160 m; updating scenery. Saved locally.'
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
   if math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)>.01 then
    setCvar(sys,pc,item.name,target)
    if math.abs(sys:GetConsoleVariableFloatValue(item.name)-target)>.01 then F.status='Performance Mode partly rejected by the engine.';log(F.status)end
   end
  end end
  F.sceneScale=sys:GetConsoleVariableFloatValue('r.ViewDistanceScale')
  F.status=('Performance Mode on. Scenery target 160 m; %d decorative components hidden. Saved locally.'):format(scene.hidden)
 end
 local groups={[0]='GlobalIllumination',[1]='Texture',[4]='Reflection',[5]='AntiAliasing',[6]='Foliage',[9]='ViewDistance',[10]='Shadow',[11]='VisualEffect',[12]='Shading'}
 function F.values(menu)
  local values={};menu.CurrentGraphicsSettings:ForEach(function(k,v)local n=v:get();if type(n)=='number'and n%1==0 and n>=0 and n<=4 then values[k:get()]=n end end);return values
 end
 function F.apply(menu,pc,values)
  local settings=StaticFindObject('/Script/Engine.Default__GameUserSettings'):GetGameUserSettings()
  if not valid(settings)then return false end
  for key,name in pairs(groups)do if values[key]~=nil then settings['Set'..name..'Quality'](settings,values[key])end end
  -- Post-processing has no separate visible quality row in this build.
  -- Use the selected overall tier; custom mode retains its current value.
  if menu.Preset>=0 and menu.Preset<=4 then settings:SetPostProcessingQuality(menu.Preset)end
  settings:ApplyNonResolutionSettings()
  local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
  for key,name in pairs(groups)do if values[key]~=nil then
   local group=name=='VisualEffect'and'Effects'or name=='PostProcessing'and'PostProcess'or name
   local cvar='sg.'..group..'Quality'
   if sys:GetConsoleVariableIntValue(cvar)~=values[key]then sys:ExecuteConsoleCommand(pc,cvar..' '..values[key],pc)end
  end end
  -- These two menu controls have no corresponding GameUserSettings setter.
  if values[2]~=nil then sys:ExecuteConsoleCommand(pc,'r.ContactShadows '..(values[2]==0 and '0'or'1'),pc)end
  if values[3]~=nil then sys:ExecuteConsoleCommand(pc,'r.BloomQuality '..values[3],pc)end
  settings:SaveSettings()
  if F.gameplayMode then maintainMode(pc)end
  F.terrain={};F.sky={};F.valuesApplied=values
  return true
 end
 function F.matches(values)
  local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
  for key,name in pairs(groups)do
   local group=name=='VisualEffect'and'Effects'or name=='PostProcessing'and'PostProcess'or name
   if values[key]~=nil and sys:GetConsoleVariableIntValue('sg.'..group..'Quality')~=values[key]then return false end
  end
  return true
 end
 function F.install(menu)
  local base=menu:GetClass():GetFullName():gsub('^%S+ ','')..':'
  for _,event in ipairs({'SetPreset','Set Quality','LoadUserSettings'})do
   local path=base..event
   if not F.hooks[path]and valid(StaticFindObject(path))then
    F.hooks[path]={RegisterHook(path,function()F.dirty=true end)}
   end
  end
 end
 function F.tick()
  -- Apply a bounded scenery batch on the existing timer, not the entire world
  -- in a single three-second maintenance burst.
  if F.gameplayMode and F.sceneScale then scene.tick(F.sceneScale)end
  if os.clock()<F.nextAt then return end;F.nextAt=os.clock()+.5
  local pc=H.GetPlayerController();if not valid(pc)then return end
  if os.clock()>=(F.modeAt or 0)then maintainMode(pc);F.modeAt=os.clock()+3 end
  if M.config.PerformancePatch==false then return end
  local menu=H.GetMenuComponent(pc);if not valid(menu)then return end
  local address=menu:GetAddress()
  local verify=os.clock()>=(F.verifyAt or 0)
  if F.dirty or F.menuAddress~=address or verify then
   F.install(menu)
   local values=F.values(menu);if values[0]==nil or values[10]==nil then return end
   local sig={tostring(address),tostring(menu.Preset)};for i=0,13 do sig[#sig+1]=tostring(values[i])end;sig=table.concat(sig,':')
   if F.signature~=sig or verify and not F.matches(values)then
    if not F.apply(menu,pc,values)then return end
    F.signature=sig;log('Graphics settings applied: preset '..tostring(menu.Preset))
   end
   F.valuesApplied=values;F.menuAddress=address;F.dirty=false;F.verifyAt=os.clock()+3
  end
  local values=F.valuesApplied;if not values then return end
  -- Newly streamed custom terrain/sky also receive the current local quality.
  if os.clock()<(F.sceneAt or 0)then return end;F.sceneAt=os.clock()+3
  if values[7]~=nil then
   local live={};for _,o in ipairs(FindAllOf('SLLandscapeGenerator')or{})do if valid(o)then
    local id=o:GetAddress();live[id]=o;if not valid(F.terrain[id])then o:SetScalability(values[7])end
   end end;F.terrain=live
  end
  local live={};for _,o in ipairs(FindAllOf('Ultra_Dynamic_Sky_C')or{})do if valid(o)then
   local id=o:GetAddress();live[id]=o;if not valid(F.sky[id])then
    -- The game's sky quality table was disabled. Use its authored modes,
    -- including its cheaper Potato sky, through the supported runtime switch.
    local quality=menu.Preset>=0 and menu.Preset<=4 and menu.Preset or values[11]
    local modes=o['Sky Mode Scalability Map']
    if quality and modes:Contains(quality)then local mode=modes:Find(quality):get();if o['Sky Mode']~=mode then o['Change Sky Mode at Runtime'](o,mode)end end
    o['Update Settings Based on Platform and Scalability'](o)
   end
  end end;F.sky=live
 end
 function F.reset()restoreMode(H.GetPlayerController());F.gameplayMode=false;F.dirty=true;F.menuAddress=nil;F.valuesApplied=nil;F.signature=nil;F.nextAt=0;F.verifyAt=0;F.sceneAt=0;F.modeAt=0;F.terrain={};F.sky={}end
 return F
end
