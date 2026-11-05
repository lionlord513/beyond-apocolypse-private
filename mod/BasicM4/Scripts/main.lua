-- Beyond Apocalypse. Legacy local records migrate without changing saved IDs.
local root=debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/Scripts/[^/]+$')
assert(root,'Install as Mods/BeyondApocalypse/Scripts/main.lua')
local storage=dofile(root..'/Scripts/storage.lua')(root)
local configPath=storage.config()
local config=dofile(configPath)
-- A player upgrade may retain a config from before a feature existed.
local function inherit(settings,defaults)
 for key,value in pairs(defaults)do
  if settings[key]==nil then settings[key]=value
  elseif type(value)=='table'and type(settings[key])=='table'then inherit(settings[key],value)end
 end
end
inherit(config,dofile(root..'/Scripts/default_config.lua'))
local release=dofile(root..'/Scripts/release.lua')
local defs=dofile(root..'/Scripts/weapons/catalog.lua')
local M={version=release.Version,release=release,active=true,definitions=defs,config=config,statePath=storage.state}
local forced,chosen,tracked,filled,errors={},{},{},{},{}
local geometry,materials={},{ }
local refreshRetry={}
local akClass,pmcClass,game
local function log(s)print('[Beyond Apocolypse] '..s..'\n') end
local function valid(o)return o and o:IsValid()end
local H=dofile(root..'/Scripts/local_context.lua')(valid)
M.root=root
local performance=dofile(root..'/Scripts/performance.lua')(M,H,valid,log);M.performance=performance
local branding=dofile(root..'/Scripts/menu_branding.lua')(root,release,H,valid)
M.branding=branding
local playerClass
local function player()
 local p=H.GetPlayer();if not valid(p)then return end
 if not valid(playerClass)then playerClass=StaticFindObject('/Game/BP/Player/PlayerBase.PlayerBase_C')end
 if not valid(playerClass)or not p:IsA(playerClass)then return end
 if p.IsInitialized and p.IsLoaded then return p end
end
local function guid(a)
 local g=a.GuidUnique
 if g.A==0 and g.B==0 and g.C==0 and g.D==0 then return end
 return string.format('%08x:%08x:%08x:%08x',g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)
end
local function readState(file,fn)
 local f=io.open(M.statePath(file),'r');if f then for line in f:lines()do fn(line)end;f:close()end
end
readState('forced-m4.txt',function(k)if k:match('^%x+:%x+:%x+:%x+$')then forced[k]=true end end)
readState('rifles.txt',function(line)local k,id=line:match('^(%x+:%x+:%x+:%x+) (%w+)$');if k and (defs[id]or id=='ak')then chosen[k]=id end end)
local function saveChoice(key,id)
 if chosen[key]==id then return end
 local f=assert(io.open(M.statePath('rifles.txt'),'a'),'Cannot save rifle identity')
 f:write(key..' '..id..'\n');f:close();chosen[key]=id
end
local function selected(a)
 local k=guid(a);if not k then return end
 if chosen[k]then return defs[chosen[k]]end
 local id='ak'
 if forced[k]then id='m4' else
  local h=5381;for i=1,#k do h=(h*33+k:byte(i))&0xffffffff end
  local roll=h%100;local m=math.max(0,math.min(100,config.LootPercent))
  local s=math.max(0,math.min(100-m,config.HuntingPercent));local b=math.max(0,math.min(100-m-s,config.EnfieldPercent))
  if roll<m then id='m4' elseif roll<m+s then id='hunting' elseif roll<m+s+b then id='enfield' end
 end
 saveChoice(k,id);return defs[id]
end
local function components(a)
 local out={}
 for _,v in ipairs(a:K2_GetComponentsByClass(pmcClass))do
  local c=v:get()
  if valid(c) and valid(c.AttachParent) and c.AttachParent:GetAddress()==a.SkeletalMesh:GetAddress()then
   local s=c.AttachSocketName:ToString()
   if s=='None' or s=='magazine_joint' or s=='BWP_hunting' or s=='BWP_enfield'then out[#out+1]=c end
  end
 end
 return out
end
local function identify(meshes)
 local body,mag
 for _,c in ipairs(meshes)do
  local s=c.AttachSocketName:ToString()
  if s=='BWP_hunting'then return defs.hunting end
  if s=='BWP_enfield'then return defs.enfield end
  if s=='None'then body=true elseif s=='magazine_joint'then mag=true end
 end
 if body and mag then return defs.m4 end
end
local loadPbrImages=dofile(root..'/Scripts/weapons/pbr_images.lua')(root,valid)
local function getMaterial(a,d)
 if valid(materials[d.Id])then return materials[d.Id]end
 local parent=LoadAsset(d.MaterialParent)
 local lib=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
 local mat=lib:CreateDynamicMaterialInstance(a,parent,FName(d.MaterialName),0)
 assert(valid(mat),'Cannot create '..d.Id..' material')
 local images=loadPbrImages('assets/'..d.Id..'-textures.gltf')
 for param,tex in pairs(images)do mat:SetTextureParameterValue(FName(param),tex)end
 -- White AO must stay white: zero was suppressing indirect light in shade.
 mat:SetScalarParameterValue(FName('AODarkness'),1)
 mat:SetScalarParameterValue(FName('DiffuseBrightness'),1.35)
 mat:SetScalarParameterValue(FName('RoughnessBrightness'),1)
 materials[d.Id]=mat;return mat
end
local function fill(a,c,d)
 local key=c:GetFullName()
 if valid(filled[key]) and filled[key]:GetAddress()==c:GetAddress()and c:GetNumSections()>0 then return end
 geometry[d.Id]=geometry[d.Id]or dofile(root..'/'..d.Geometry)
 local part=c.AttachSocketName:ToString()==d.MagazineSocket and 'magazine' or 'body'
 local data=assert(geometry[d.Id][part]);c:SetCollisionEnabled(0)

 c:CreateMeshSection(0,data.vertices,data.triangles,data.normals,data.uv,{},data.tangents or {},false)
 c:SetMaterial(0,getMaterial(a,d))
 if data.ironTriangles then c:CreateMeshSection(1,data.vertices,data.ironTriangles,data.normals,data.uv,{},data.tangents or{},false);c:SetMaterial(1,getMaterial(a,d))end
 do
  local tr=d.Transform()
  if part=='magazine'then tr=StaticFindObject('/Script/Engine.Default__KismetMathLibrary'):MakeRelativeTransform(tr,a.SkeletalMesh:GetSocketTransform(FName(d.MagazineSocket),2))end
  c:K2_SetRelativeTransform(tr,false,{},true)
 end
 filled[key]=c
end
local function create(a,d)
 local made={};local mesh=a.SkeletalMesh
 local ok,e=pcall(function()
  for _,part in ipairs(d.Parts)do
   local tr=d.Transform();local socket=part=='magazine'and d.MagazineSocket or d.BodySocket
   if part=='magazine'then tr=StaticFindObject('/Script/Engine.Default__KismetMathLibrary'):MakeRelativeTransform(tr,mesh:GetSocketTransform(FName(socket),2))end
   local c=a:AddComponentByClass(pmcClass,true,tr,false);assert(valid(c),'Mesh creation failed')
   made[#made+1]=c;c:K2_AttachToComponent(mesh,FName(socket),0,0,0,false);c:K2_SetRelativeTransform(tr,false,{},true)
   fill(a,c,d)
  end
  if a:HasAuthority()then a:FlushNetDormancy();a:ForceNetUpdate()end
 end)
 if not ok then for _,c in ipairs(made)do if valid(c)then c:K2_DestroyComponent(a)end end;error(e)end
 return made
end
local identitySockets={ba_nativeak='ak',ba_rifle_m4='m4',ba_rifle_hunting='hunting',ba_rifle_enfield='enfield'}
local function rifleMarker(a)
 local scene=StaticFindObject('/Script/Engine.SceneComponent')
 for _,entry in ipairs(a:K2_GetComponentsByClass(scene))do
  local c=entry:get()
  if valid(c)then
   local id=identitySockets[c.AttachSocketName:ToString():lower()]
   if id then return c,id end
  end
 end
end
local function setMarker(a,marker,id)
 if not valid(marker)then
  local tr={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
  marker=a:AddComponentByClass(StaticFindObject('/Script/Engine.SceneComponent'),true,tr,false)
  assert(valid(marker),'Rifle identity component unavailable')
 end
 local socket=id=='ak' and 'BA_NativeAK' or ('BA_Rifle_'..id)
 marker:K2_AttachToComponent(a.SkeletalMesh,FName(socket),0,0,0,false)
 marker:SetIsReplicated(true);a:FlushNetDormancy();a:ForceNetUpdate()
end
local function update(a)
 if not valid(a)or not valid(a.SkeletalMesh)then return end
 local meshes=components(a);local rendered=identify(meshes)
 local marker,id=rifleMarker(a)
 if a:HasAuthority()then
  local key=guid(a)
  if not key then return end
  -- Preserve previously saved models when upgrading an existing world.
  if not chosen[key]and rendered then saveChoice(key,rendered.Id)end
  selected(a)
  if id~=chosen[key]then id=chosen[key];setMarker(a,marker,id)end
 elseif not id then
  -- Identity may arrive after the actor. Keep a visible donor in the meantime.
  if not rendered then a.SkeletalMesh:SetVisibility(true,false);return end
  id=rendered.Id
 end
 local d=defs[id]
 if #meshes>0 and rendered~=d then
  for _,c in ipairs(meshes)do c:K2_DestroyComponent(a)end
  meshes={};tracked[a:GetFullName()]=nil
 end
 if d and #meshes==0 then a.SkeletalMesh:SetVisibility(true,false);meshes=create(a,d)end
 if d then
  for _,c in ipairs(meshes)do fill(a,c,d)end
  a.SkeletalMesh.VisibilityBasedAnimTickOption=0;a.SkeletalMesh:SetVisibility(false,false)
  a.IsAutomatic=false;a.CanBeAutomatic=false;a.FireRate=d.FireRate
  if M.ballistics and M.ballistics.installed then M.ballistics.prepare(a,d)end
  if M.rail then M.rail.update(a,d)end
  local scope=M.rail and M.rail.optic.has(a)
  for _,c in ipairs(meshes)do if c:GetNumSections()>1 then c:SetMeshSectionVisible(1,not scope)end end
  tracked[a:GetFullName()]={actor=a,def=d}
 else
  a.SkeletalMesh:SetVisibility(true,false)
  if a:HasAuthority()then a.IsAutomatic=true;a.CanBeAutomatic=true end
  if M.rail then M.rail.update(a,M.nativeRifle)end
 end
end
local function guardedUpdate(a)
 local key=a:GetFullName();local now=os.time()
 if now<(refreshRetry[key]or 0)then return end
 local ok,e=pcall(update,a)
 if ok then refreshRetry[key]=nil;return end
 refreshRetry[key]=now+2
 local message=tostring(e)
 if not errors[message]then errors[message]=true;log(message)end
end
local function initialize()
 if valid(akClass)and valid(pmcClass)then return true end
 akClass=LoadAsset(defs.m4.BaseClass);pmcClass=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 return valid(akClass)and valid(pmcClass)
end
function M.force(a,id)
 id=id or 'm4';local d=assert(defs[id],'Unknown rifle')
 assert(initialize()and valid(a)and a:IsA(akClass),'Hold a rifle first')
 assert(a:HasAuthority(),'Host only');local k=assert(guid(a),'Item identity not ready')
 saveChoice(k,id)
 for _,c in ipairs(components(a))do c:K2_DestroyComponent(a)end
 tracked[a:GetFullName()]=nil;update(a);log(d.Name..' selected: '..k)
end
function M.spawn(id)
 assert(initialize());local p=player();assert(valid(p)and p:HasAuthority(),'Spawn requires host game')
 local l,v=p:K2_GetActorLocation(),p:GetActorForwardVector()
 local tr={Translation={X=l.X+v.X*120,Y=l.Y+v.Y*120,Z=l.Z+30},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local a=game:BeginDeferredActorSpawnFromClass(p,akClass,tr,1,nil,0);assert(valid(a),'Native AK spawn failed')
 game:FinishSpawningActor(a,tr,0)
 if id=='ak'then saveChoice(assert(guid(a),'Item identity not ready'),'ak')else M.force(a,id)end
 return a
end
function M.scan()
 if M.features==false or not player()or not initialize()then return end
 local world=H.GetWorld();if not valid(world)then return end
 local seen={}
 for _,a in ipairs(FindAllOf('AkWeapon_C')or{})do if valid(a)and a:GetWorld():GetAddress()==world:GetAddress()then seen[a:GetFullName()]=true;guardedUpdate(a)end end
 for k,t in pairs(tracked)do if not valid(t.actor)then tracked[k]=nil end end
 for k,c in pairs(filled)do if not valid(c)then filled[k]=nil end end
 for k in pairs(refreshRetry)do if not seen[k]then refreshRetry[k]=nil end end
end
local firing=dofile(root..'/Scripts/firing.lua')(valid)
local hazmat=dofile(root..'/Scripts/hazmat.lua')(root,config.Apocalypse,valid,log)
M.hazmat=hazmat
local apocalypse=dofile(root..'/Scripts/apocalypse.lua')(root,config.Apocalypse,valid,log,hazmat,M.statePath)
M.apocalypse=apocalypse
local mechanic=dofile(root..'/Scripts/night_hunter.lua')(root,config.Apocalypse,valid,log);M.mechanic=mechanic
local actions,scanElapsed={},config.PollMilliseconds
local function shortcut(fn)if not M.travelling then actions[#actions+1]=fn end end
local session=dofile(root..'/Scripts/session.lua')(M,H,valid,shortcut);M.session=session
M.dashboard=dofile(root..'/Scripts/dashboard.lua')(M,H,valid)
M.hudFrame=M.dashboard.frame
local companion
function M.overlayCapturesInput()return companion and companion.ui.opened or false end
local function companionCall(method)
 if not companion then return end
 local ok,err=pcall(companion[method])
 if not ok and not errors[err]then errors[err]=true;log('Test menu: '..tostring(err))end
end
M.guid=guid
local backpack=dofile(root..'/Scripts/backpack/controller.lua')(M,root,H,valid,shortcut,log)
M.backpack=backpack
local weaponHandling=dofile(root..'/Scripts/weapons/handling.lua')(M,root,H,valid,shortcut,log);M.weaponHandling=weaponHandling
local rail=dofile(root..'/Scripts/weapons/rail.lua')(M,root,H,valid,shortcut,log);M.rail=rail
M.ballistics=dofile(root..'/Scripts/weapons/ballistics.lua')(M,root,valid,log,H)
local rpg=dofile(root..'/Scripts/rpg.lua')(M,root,H,valid,shortcut,log);M.rpg=rpg
M.controls=dofile(root..'/Scripts/controls.lua')(M,root,H,valid)
local gyrocopter=dofile(root..'/Scripts/gyrocopter/controller.lua')(M,root,H,valid,log)
M.gyrocopter=gyrocopter
local motorcycle=dofile(root..'/Scripts/motorcycle/controller.lua')(M,root,H,valid,log);M.motorcycle=motorcycle
M.playerModels=dofile(root..'/Scripts/player_models/controller.lua')(M,root,H,valid,shortcut,log)
M.utility=dofile(root..'/Scripts/utility.lua')(M,root,H,valid,shortcut,log)
local hangar=dofile(root..'/Scripts/hangar.lua')(M,root,H,valid,shortcut,log);M.hangar=hangar
local towing=dofile(root..'/Scripts/towing.lua')(M,valid,shortcut,log);M.towing=towing
M.ammo=dofile(root..'/Scripts/ammo.lua')(M,root,H,valid,shortcut,log)
local roaming=dofile(root..'/Scripts/zombie_roaming.lua')(M,valid,log);M.roaming=roaming
M.population=dofile(root..'/Scripts/zombie_population.lua')(M,root,H,valid,log)
apocalypse.population=M.population;mechanic.population=M.population
dofile(root..'/Scripts/game_loop.lua')(function()return M.active end,function()
  local ok,e=pcall(function()
   if M.travelling then return end
   session.tick()
   local pending=actions;actions={};for _,fn in ipairs(pending)do local worked,err=pcall(fn);if not worked then log(tostring(err))end end
   scanElapsed=scanElapsed+50
   if scanElapsed>=config.PollMilliseconds then scanElapsed=0;M.scan();branding.tick();local hp=player();if hp and M.features~=false then hazmat.tick(hp)end end
   local perfOK,perfError=pcall(performance.tick)
   if not perfOK and not errors[tostring(perfError)]then errors[tostring(perfError)]=true;log('Graphics settings: '..tostring(perfError))end
   M.utility.tick()
   local modelsOK,modelsError=pcall(M.playerModels.tick)
   if not modelsOK and not errors[tostring(modelsError)]then errors[tostring(modelsError)]=true;log('Player models: '..tostring(modelsError))end
   M.dashboard.tick(valid(game)and game:GetTimeSeconds(H.GetPlayerController())or 0)
   if M.features==false then firing.reset();return end
   companionCall('tick');backpack.tick()
   local p=player()
   if p and valid(game)then
    rpg.install();M.ballistics.install();M.ballistics.tick();hangar.tick();towing.tick();weaponHandling.tick();rail.tick(p);M.ammo.tick(p,game:GetTimeSeconds(p))
    local a=p.ItemEquiped;local t=valid(a)and tracked[a:GetFullName()]
    local now=game:GetTimeSeconds(p)
    if not game:IsGamePaused(p)then
     firing.tick(a,t and t.def,now,not M.utility.opened and not M.overlayCapturesInput() and not backpack.ui.opened and valid(p.BP_PlayerStats) and not p.BP_PlayerStats.IsDead and not p.BP_PlayerStats.IsDying,H.GetPlayerController():IsInputKeyDown({KeyName=FName('LeftMouseButton')}))
     M.population.tick(p)
     if not M.population.disabled then
      apocalypse.tick(p,game,now)
      mechanic.tick(p,game,now)
      roaming.tick(p,game,now)
     end
     gyrocopter.tick(p,now)
     motorcycle.tick(p,now)
    end
   else firing.reset()end
  end)
  if not ok and not errors[tostring(e)]then errors[tostring(e)]=true;log(tostring(e))end
end,log)
RegisterKeyBind(Key.ESCAPE,function()shortcut(function()if M.utility.opened then if M.utility.capture then M.utility.capture=nil;M.utility.render()else M.utility.close()end end;if M.overlayCapturesInput()then companion.ui.close()end;if backpack.ui.opened then backpack.ui.close()end end)end)
RegisterKeyBind(Key.MIDDLE_MOUSE_BUTTON,function()shortcut(function()rail.request('drop')end)end)
RegisterKeyBind(Key.L,function()shortcut(function()rail.request('light')end)end)
RegisterKeyBind(Key.TAB,function()shortcut(function()backpack.toggle()end)end)
RegisterKeyBind(Key.B,function()shortcut(function()backpack.unequip()end)end)
RegisterKeyBind(Key.RIGHT_MOUSE_BUTTON,function()if M.overlayCapturesInput()and companion.ui.rightClick then shortcut(function()companion.ui.rightClick()end);return end;local intended=backpack.storeTarget;shortcut(function()backpack.store(intended)end)end)
M.guid=guid;M.components=components;M.identify=identify;M.firing=firing
M.nativeRifle={Id='ak',Name='AK-47',Mode='auto',Transform=function()return {Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=.70710678118655,W=.70710678118655},Scale3D={X=1,Y=1,Z=1}}end}
function M.weaponDefinition(a)
 if M.features==false or not valid(a)or not a:GetFullName():match('^AkWeapon_C ')then return end
 initialize();return identify(components(a))or M.nativeRifle
end
function M.refreshWeapon(a)if M.features~=false and valid(a)and a:GetFullName():match('^AkWeapon_C ')and initialize()then guardedUpdate(a)end end
function M.itemName(a)
 if not valid(a)then return 'Item'end
 if M.gyrocopter and M.gyrocopter.transport.blades.info(a)then return 'Universal rotor blade'end
 if M.rail and M.rail.optic.item(a)then return '2x Sight'end
 if a:GetFullName():match('^AkWeapon_C ')then
  local d=identify(components(a));if not d and a:HasAuthority()then d=selected(a)end
  return d and d.Name or 'AK-47'
 end
 return (a:GetFullName():match('^(%S+)')or'Item'):gsub('_C$',''):gsub('(%l)(%u)','%1 %2'):gsub('_',' ')
end
M.akClass=function()initialize();return akClass end
-- The private launcher test package alone supplies this limited host fixture kit.
-- Public packages have no spawn-test key bindings.
RegisterLoadMapPreHook(function()
 M.travelling=true;M.features=false
 M.population.reset();actions={};tracked={};filled={};materials={};refreshRetry={};akClass=nil;pmcClass=nil;game=nil
    M.playerModels.reset();M.dashboard.reset();motorcycle.reset();M.utility.reset();H.reset();session.reset();performance.reset();firing.reset();apocalypse.reset();hazmat.reset();mechanic.reset();branding.reset();companionCall('reset');backpack.reset();gyrocopter.reset();weaponHandling.reset();weaponHandling.slots.reset();weaponHandling.equipCache=nil;rail.reset();roaming.reset();hangar.reset();towing.reset();M.ammo.reset();M.ballistics.reset()
end)
RegisterLoadMapPostHook(function()actions={};M.travelling=false end)
companion=dofile(root..'/Scripts/optional_interface.lua')(M,root,H,valid,shortcut,log)
M.devmenu=companion -- Compatibility for separately installed test tools.
_G.BeyondApocalypse=M
-- Compatibility for separately installed tools; these aliases do not load code.
_G.BasicM4=M;_G.BasicWeaponPack=M;_G.BeyondApocolypse=M
log(release.Version..' '..release.Channel..' loaded: M4 burst, hunting semi-auto, Enfield bolt cadence; additive apocalypse enabled='..tostring(config.Apocalypse.Enabled))
-- BEGIN BEYOND TUNING BACKPACK BRIDGE
do
 local ok,err=pcall(function()
  local scripts=debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/[^/]+$')
  local mods=scripts..'/../..';local tuning=mods..'/BeyondTuning'
  local enabled=io.open(tuning..'/enabled.txt','r');local active=enabled~=nil;if enabled then enabled:close()end
  local list=io.open(mods..'/mods.txt','r');if list then for line in list:lines()do local v=line:match('^%s*BeyondTuning%s*:%s*(%d)');if v then active=v=='1'end end;list:close()end
  if not active then return end
  local path=tuning..'/Scripts/backpack_bridge.lua';local file=io.open(path,'r');if not file then return end;file:close()
  dofile(path)(_G.BeyondApocalypse,tuning)
 end)
 if not ok then print('[Beyond Tuning] Backpack bridge: '..tostring(err)..'\n')end
end
-- END BEYOND TUNING BACKPACK BRIDGE
return M
