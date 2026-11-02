-- Native firing still owns replication, attenuation and damage delivery.
return function(M,root,valid,log,H)
 local B={pools={},bytes={},damage={m4=1.1,hunting=1.7,enfield=2.8}}
 local function sample(id)
  if B.bytes[id]then return B.bytes[id]end
  local f=assert(io.open(root..'/assets/audio/'..id..'.wav','rb'));local raw=f:read('*a');f:close()
  local bytes={};for i=1,#raw do bytes[i]=raw:byte(i)end;B.bytes[id]=bytes;return bytes
 end
 -- Pool ownership follows the local world, never a boxed/dropped weapon.
 function B.reset()
  for _,pool in pairs(B.pools)do if valid(pool.anchor)then for _,c in ipairs(pool.holders)do if valid(c)then c:K2_DestroyComponent(pool.anchor)end end end end
  B.pools={};B.nextVoice=0
 end
 function B.prepare(a,d)
  if not B.damage[d.Id]then return end
  local anchor=H.GetPlayerController();if not valid(anchor)then return end
  local pool=B.pools[d.Id]
  if not pool or not valid(pool.anchor)or pool.anchor:GetAddress()~=anchor:GetAddress()then
   -- World/boxed rifles do not need decoded shot voices. First equip starts
   -- the existing gradual import; native audio covers the initial shot.
   if not valid(a.IsEquipedOn)then return end
   pool={original=LoadAsset('/Game/Sound/Player/Combat/Ak47/Ak_Shot.Ak_Shot'),anchor=anchor,index=0,waves={},holders={},reserved={},selected={}}
   B.pools[d.Id]=pool
  end
  local key=a:GetAddress()
  if not valid(a.IsEquipedOn)then
   local old=pool.selected[key];if old then pool.reserved[old]=nil;pool.selected[key]=nil end
   a.SoundToPlay=pool.original;return
  end
  if not pool.selected[key]then B.shot(a)end
 end
 function B.tick()
  if os.clock()<(B.nextVoice or 0)then return end
  B.nextVoice=os.clock()+.1
  for id,pool in pairs(B.pools)do
   if valid(pool.anchor)and #pool.waves<12 then
    local factory=StaticFindObject('/Script/RuntimeAudioImporter.Default__StreamingSoundWave')
    local w=factory:CreateStreamingSoundWave();assert(valid(w),'Gun sound unavailable')
    local holder=pool.anchor:AddComponentByClass(StaticFindObject('/Script/Engine.AudioComponent'),true,{Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}},false)
    assert(valid(holder),'Gun sound holder unavailable')
    holder:SetAutoActivate(false);holder:SetComponentTickEnabled(false);holder:SetIsReplicated(false);holder:SetSound(w)
    w.SoundClassObject=pool.original.SoundClassObject;w.AttenuationSettings=pool.original.AttenuationSettings;w.SoundSubmixObject=pool.original.SoundSubmixObject
    w:SetStopSoundOnPlaybackFinish(true);w:SetLooping(false);w:SetPitch(1);w:SetVolume(1.2)
    w:AppendAudioDataFromEncoded(sample(id),2)
    pool.holders[#pool.holders+1]=holder;pool.waves[#pool.waves+1]=w
    return -- At most one voice import per update, regardless of weapon count.
   end
  end
 end
 function B.shot(a)
  if M.features==false or not valid(a)then return end
  local d=M.weaponDefinition(a);local pool=d and B.pools[d.Id];if not pool then return end
  local key=a:GetAddress();local old=pool.selected[key];if old then pool.reserved[old]=nil;pool.selected[key]=nil end
  for n=1,#pool.waves do
   pool.index=pool.index%#pool.waves+1;local w=pool.waves[pool.index]
   if valid(w)and not valid(pool.reserved[w:GetAddress()])and w:GetDurationConst()>0 and not w:IsPlaying(a)then
    w:RewindPlaybackTime(0);a.SoundToPlay=w;pool.reserved[w:GetAddress()]=a;pool.selected[key]=w:GetAddress();return
   end
  end
  -- Heavy simultaneous fire falls back to the native sound rather than cutting tails.
  a.SoundToPlay=pool.original
 end
 function B.install()
  if B.installed then return end
  local fire='/Game/BP/Items/Master/BulletWeaponMasterItem.BulletWeaponMasterItem_C:TriggerAttack'
  local damage='/Game/BP/Items/Master/WeaponMasterItem.WeaponMasterItem_C:ServerDealDamage'
  if not valid(StaticFindObject(fire))or not valid(StaticFindObject(damage))then return end
  B.fireHook={RegisterHook(fire,function(ctx)local ok,e=pcall(B.shot,ctx:get());if not ok and not B.error then B.error=true;log('Rifle audio: '..tostring(e))end end)}
  B.damageHook={RegisterHook(damage,function(ctx,target,amount,instigator,physical,location,normal,component,bone)
   local a=ctx:get();if M.features==false or not valid(a)or not a:HasAuthority()then return end
   if B.bonus then return end
   local d=M.weaponDefinition(a);local multiplier=d and B.damage[d.Id];local value=amount:get()
   -- Blueprint hooks run after the original hit. Apply only its bounded bonus,
   -- through the same authority damage function, with a recursion guard.
   if multiplier and type(value)=='number'and value>0 and value<10000 and valid(target:get())then
    B.bonus=true
    local ok,e=pcall(function()a:ServerDealDamage(target:get(),value*(multiplier-1),instigator:get(),physical:get(),location:get(),normal:get(),component:get(),bone:get())end)
    B.bonus=false;if not ok then log('Rifle damage: '..tostring(e))end
   end
  end)}
  B.installed=true
 end
 return B
end

