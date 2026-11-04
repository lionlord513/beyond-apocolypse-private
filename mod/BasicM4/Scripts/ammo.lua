-- All counts, spawning and save records are host-owned. Native AkBullet keeps
-- its ammunition type, pickup, inventory, replication and save implementation.
return function(M,root,H,valid,enqueue,log)
 local A={items={},dead={},identities={},visualErrors={},nextScan=0,nextAmbient=0};local none=FName('None')
 local game=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 local color={R=0,G=0,B=0,A=1};local pmc=StaticFindObject('/Script/ProceduralMeshComponent.ProceduralMeshComponent')
 local rendering=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
 local function texture(a,file)return rendering:ImportFileAsTexture2D(a,root..'/assets/'..file)end
 A.journal=dofile(root..'/Scripts/ammo_journal.lua')(root,M.gyrocopter.transport.journal,valid,log,M.statePath)
 A.reserves=dofile(root..'/Scripts/ammo_reserves.lua')(M,valid,log)
 local function distance(a,b)return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2 end
 function A.spawn(context,at,count)
  assert(valid(context)and context:HasAuthority(),'Ammo spawning requires authority')
  assert(count>=1 and count<=30 and count%1==0,'Invalid ammo count')
  local tr={Translation=at,Rotation=identity.Rotation,Scale3D=identity.Scale3D}
  local a=game:BeginDeferredActorSpawnFromClass(context,LoadAsset('/Game/BP/Items/Movable/Bullets/AkBullet.AkBullet_C'),tr,1,nil,0)
  assert(valid(a),'Native ammunition unavailable')
  local ok,e=pcall(function()a.Min=count;a.Max=count;a.NbBullet=count;game:FinishSpawningActor(a,tr,0);a.NbBullet=count;a:FlushNetDormancy();a:ForceNetUpdate()end)
  if not ok then a:K2_DestroyActor();error(e)end;return a
 end
 local material;local geometry
 local function appearance(a)
  if not valid(a.cube)then return end
  local key=a:GetFullName();local r=A.items[key]
  if r and valid(r.visual)then a.cube:SetVisibility(false,false);r.visual:SetVisibility(a.NbBullet>0,false);return end
  if not valid(material)then
   material=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary'):CreateDynamicMaterialInstance(a,LoadAsset('/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47'),FName('BA_AmmoCarton'),0)
   local diffuse=texture(a,'ammo/carton.png');assert(valid(diffuse),'Ammo carton PNG unavailable')
   material:SetTextureParameterValue(FName('Diffuse'),diffuse)
   material:SetTextureParameterValue(FName('NormalMap'),texture(a,'gyrocopter/plastic-normal.png'))
   material:SetTextureParameterValue(FName('AOMap'),texture(a,'gyrocopter/clean-ao.png'))
   material:SetTextureParameterValue(FName('RoughnessMap'),texture(a,'gyrocopter/roughness.png'))
   material:SetTextureParameterValue(FName('MetalMap'),texture(a,'gyrocopter/metal.png'))
   material:SetScalarParameterValue(FName('DiffuseBrightness'),1);material:SetScalarParameterValue(FName('RoughnessBrightness'),1)
  end
  geometry=geometry or dofile(root..'/assets/ammo/carton.lua')
  local c=a:AddComponentByClass(pmc,true,identity,false);assert(valid(c),'Ammo carton visual unavailable')
  c:K2_AttachToComponent(a.cube,none,0,0,0,false);c:SetAbsolute(false,false,true);c:SetIsReplicated(false);c:SetCollisionEnabled(0)
  c:CreateMeshSection(0,geometry.vertices,geometry.triangles,geometry.normals,geometry.uv,{},geometry.tangents,false);c:SetMaterial(0,material);c:SetCullDistance(18000)
  local visible=a.cube:IsVisible();a.cube:SetVisibility(false,false);c:SetVisibility(a.NbBullet>0,false);A.items[key]={actor=a,visual=c,originalVisible=visible}
 end
 A.appearance=appearance
 local function identityOf(z)
  local previous=A.identities[z:GetAddress()]
  if previous and valid(previous.actor)and previous.actor:GetAddress()==z:GetAddress()then return previous.key end
  -- The native saver has a persistent GUID even for actors without GuidUnique.
  -- Use its map instead of names, positions, seeds or a synthetic identity.
  for _,s in ipairs(FindAllOf('ItemSaverState')or{})do if valid(s)then
   local result;s.MapActorGuid:ForEach(function(k,v)local a=v:get();if valid(a)and a:GetAddress()==z:GetAddress()then result=M.gyrocopter.transport.journal.guid(k:get())end end)
   if result and result~='00000000:00000000:00000000:00000000'then return result end
  end end
 end
 function A.cacheIdentities()
  if not valid(A.zombieClass)then return end
  for _,s in ipairs(FindAllOf('ItemSaverState')or{})do if valid(s)then
   s.MapActorGuid:ForEach(function(k,v)local a=v:get()
    if valid(a)and a:IsA(A.zombieClass)then local key=M.gyrocopter.transport.journal.guid(k:get())
     if key~='00000000:00000000:00000000:00000000'then A.identities[a:GetAddress()]={actor=a,key=key}end
    end
   end)
  end end
  for address,r in pairs(A.identities)do if not valid(r.actor)then A.identities[address]=nil end end
 end
 function A.drop(z)
  if not valid(z)or not z:HasAuthority()then return true end
  if not z.IsDead then return false end
  local key=identityOf(z);if not key then return false end
  local J=A.journal;if J.state.kill[key]then return true end;J.writable()
  if game:GetGameInstance(z).IsSaving then return false end
  local p=z:K2_GetActorLocation();local at={X=p.X+28,Y=p.Y,Z=p.Z+15}
  A.spawn(z,at,3);J.state.kill[key]=true;return true
 end
 function A.install()
  if A.killHook then return end
  local cls=FindObject('BlueprintGeneratedClass','BP_Zombie_C');if not valid(cls)then return end
  A.zombieClass=cls
  local path=cls:GetFullName():gsub('^%S+ ','')..':KillZombie';if not valid(StaticFindObject(path))then return end
  A.killHook={RegisterHook(path,function(ctx)
   -- Like other Blueprint post-hooks, defer actor work to the shared game tick.
   local z=ctx:get();enqueue(function()if M.features~=false and valid(z)and z:HasAuthority()then A.dead[z:GetAddress()]={actor=z,untilTime=os.clock()+15}end end)
  end)}
 end
 local function roll(key)
  local h=5381;for i=1,#key do h=(h*33+key:byte(i))&0xffffffff end;return h%100<20
 end
 function A.ambient(p,now,ammo)
  if now<A.nextAmbient or not p:HasAuthority()or game:GetGameInstance(p).IsSaving then return end;A.nextAmbient=now+10
  local J=A.journal;if not J.ready or J.error then return end
  local gs=game:GetGameState(p);if not valid(gs)then return end
  local weapons=FindAllOf('AkWeapon_C')or{};local work=0
  for _,site in ipairs(M.apocalypse.locations or{})do
   local key=site.key
   if not J.state.site[key]and roll(tostring(gs.Seed)..'|'..key)then
    for _,w in ipairs(weapons)do if valid(w)then
     local at=w:K2_GetActorLocation();local ground={};w:CanBePickedUpFromGround(ground)
     if ground.Can and distance(at,site.pos)<3000^2 and distance(at,p:K2_GetActorLocation())>500^2 then
      -- Native ammunition nearby satisfies this site. Supplement only when absent.
      local present=false;for _,a in ipairs(ammo)do if valid(a)and distance(a:K2_GetActorLocation(),at)<500^2 then present=true;break end end
      J.writable()
      if present then J.state.site[key]=true;break end
      local hit={};work=work+1
      local start={X=at.X+35,Y=at.Y,Z=at.Z+70};local finish={X=start.X,Y=start.Y,Z=at.Z-100}
      if sys:LineTraceSingle(p,start,finish,0,false,{w},0,hit,true,color,color,0)then
       local q=hit.ImpactPoint;local box={};local center={X=q.X,Y=q.Y,Z=q.Z+8}
       if not sys:BoxTraceSingle(p,center,{X=center.X,Y=center.Y,Z=center.Z+.1},{X=10,Y=5,Z=4},{Pitch=0,Yaw=0,Roll=0},0,false,{w},0,box,true,color,color,0)then
        local a=A.spawn(p,center,6);ammo[#ammo+1]=a;J.state.site[key]=true;return
       end
      end
      if work>=2 then return end
     end
    end end
   end
  end
 end
 function A.tick(p,now)
  if M.features==false then return end;A.install()
  if p:HasAuthority()then
   if not A.journal.ready then A.journal.load(game:GetGameInstance(p).MainSaveGame)end
   if not A.journal.error then for key,d in pairs(A.dead)do
   if now>=(d.nextAt or 0)then d.nextAt=now+1
    local ok,done=pcall(A.drop,d.actor)
    if ok and done then A.dead[key]=nil
    elseif os.clock()>d.untilTime then A.dead[key]=nil;log('Zombie ammo retained no drop: '..(ok and 'native saver identity unavailable'or tostring(done)))end
   end end end
  end
  if now<A.nextScan then return end;A.nextScan=now+1
  if p:HasAuthority()then A.reserves.load(game:GetGameInstance(p).MainSaveGame);A.reserves.update()end
  if p:HasAuthority()then A.cacheIdentities()end
  local ammo=FindAllOf('AkBullet_C')or{}
  local alive={}
  for _,a in ipairs(ammo)do if valid(a)then
   local key=a:GetFullName();alive[key]=true;local ok,e=pcall(appearance,a)
   if ok then A.visualErrors[key]=nil else local message=tostring(e)
    if A.visualErrors[key]~=message then A.visualErrors[key]=message;log('Ammo carton: '..message)end
   end
  end end
  for key in pairs(A.visualErrors)do if not alive[key]then A.visualErrors[key]=nil end end
  for key,r in pairs(A.items)do if not valid(r.actor)then A.items[key]=nil end end
  A.ambient(p,now,ammo)
 end
 function A.reset()
  A.reserves.reset()
  for _,r in pairs(A.items)do if valid(r.visual)then r.visual:K2_DestroyComponent(r.actor)end;if valid(r.actor)and valid(r.actor.cube)then r.actor.cube:SetVisibility(r.originalVisible,false)end end
  A.items={};A.dead={};A.identities={};A.visualErrors={};A.nextScan=0;A.nextAmbient=0;material=nil;A.journal.reset()
 end
 return A
end
