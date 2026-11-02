return function(G,valid,remember,config)
 local W={nextAt=0,seen={}}
 local function guid(a)
  local key
  a.Seats:ForEach(function(_,v)
   local s=v:get();if not key and valid(s)and s.IsDriverSeat and valid(s.AttachedCarEquipableActor)then
    local g=s.AttachedCarEquipableActor.GuidUnique
    if g.A~=0 or g.B~=0 or g.C~=0 or g.D~=0 then key=('%08x:%08x:%08x:%08x'):format(g.A&0xffffffff,g.B&0xffffffff,g.C&0xffffffff,g.D&0xffffffff)end
   end
  end)
  return key
 end
 function W.tick(p,now)
  if config.WorldSpawns~=true or not p:HasAuthority()or now<W.nextAt then return end
  W.nextAt=now+5
  local count=0;for _ in pairs(G.tracked)do count=count+1 end
  if count>=3 or #G.pending>0 then return end
  local players={p:K2_GetActorLocation()}
  for _,pc in ipairs(FindAllOf('PlayerControllerBase_C')or{})do
   if valid(pc)and valid(pc.PlayerControlled)then players[#players+1]=pc.PlayerControlled:K2_GetActorLocation()end
  end
  for _,a in ipairs(FindAllOf('AVS_Template_Vehicle_C')or{})do if valid(a)and a:HasAuthority()and a['From Level Spawn']==true and not valid(a.Driver)then
   local at=a:K2_GetActorLocation();local d2=math.huge
   for _,q in ipairs(players)do local dx,dy=at.X-q.X,at.Y-q.Y;d2=math.min(d2,dx*dx+dy*dy)end
   if d2>14000^2 and d2<50000^2 then
    local key=guid(a)
    if key and not G.known[key]and not G.sites[key]and not W.seen[key]then
     local h=5381;for i=1,#key do h=(h*33+key:byte(i))&0xffffffff end
     local chance=math.max(0,math.min(10,(config.SpawnPercent or 3)+1))
     if h%100<chance then
      for i=0,5 do
       local angle=(h%360)*math.pi/180+i*math.pi/3
       local pos=G.clearance(p,{X=at.X+math.cos(angle)*2400,Y=at.Y+math.sin(angle)*2400,Z=at.Z})
       local nearby=false
       if pos then for _,r in pairs(G.tracked)do if valid(r.actor)then
        local q=r.actor:K2_GetActorLocation();if (q.X-pos.X)^2+(q.Y-pos.Y)^2<10000^2 then nearby=true;break end
       end end end
       if pos and not nearby then
        G.spawn(true,pos,true);remember('site',key,G.sites);W.seen[key]=true;return
       end
      end
     end
     W.seen[key]=true
    end
   end
  end end
 end
 function W.reset()W.nextAt=0;W.seen={}end
 return W
end
