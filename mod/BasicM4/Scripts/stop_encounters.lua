-- Pure encounter scheduling. Time is supplied by the host's pause-aware clock.
return function(P,c,random)
 local R={groups={},serial=0,stats={triggered=0,buildingSkipped=0}}
 random=random or math.random
 local function copy(v)return {X=v.X,Y=v.Y,Z=v.Z}end
 local function delay(mode)
  return mode=='building' and random(c.BuildingStopMinSeconds,c.BuildingStopMaxSeconds)
   or random(c.RoadsideStopMinSeconds,c.RoadsideStopMaxSeconds)
 end
 local function mode(p)
  if p.speed>c.StopMaxSpeed then return end
  if p.nearBuilding then return 'building' end
  if p.roadMeters and p.roadMeters<=c.RoadsideNearRoadMeters then return 'roadside' end
 end
 function R.reset()R.groups={};R.serial=0 end
 function R.update(ps,now,alive)
  if not c.StopEncountersEnabled then R.reset();return {} end
  local groups,claimed={},{}
  -- Nearby co-op players share one timer. Walking around to repair is allowed.
  for _,p in ipairs(ps)do
   local m=mode(p)
   if m then
    local group
    for _,g in ipairs(groups)do if P.distance(p.pos,g.anchor)<=c.StopRadiusMeters then group=g;break end end
    if not group then
     for _,g in ipairs(R.groups)do
      if not claimed[g] and P.distance(p.pos,g.anchor)<=c.StopRadiusMeters then group=g;break end
     end
     if not group then R.serial=R.serial+1;group={id=R.serial,anchor=copy(p.pos)}end
     claimed[group]=true;group.members={};group.nextMode='roadside';groups[#groups+1]=group
    end
    group.members[#group.members+1]=p
    if m=='building'then group.nextMode='building' end
   end
  end
  R.groups=groups -- leaving cancels unspawned encounters, never existing hunters
  local requests={}
  for _,g in ipairs(groups)do
   if g.mode~=g.nextMode then
    g.mode=g.nextMode;g.wave=nil;g.due=now+delay(g.mode)
   end
   local count=alive[g.id]or 0
   if g.wave and (now>=g.wave.expires or g.wave.spawned>=c.StopMaxHunters)then g.wave=nil;g.due=nil end
   if not g.wave and not g.due and count==0 then g.due=now+delay(g.mode)end
   if g.due and now>=g.due then
    if count>0 then g.due=nil
    elseif g.mode=='building' and random()>c.BuildingStopChance then
     g.due=now+delay(g.mode);R.stats.buildingSkipped=R.stats.buildingSkipped+1
    else
     g.due=nil;g.wave={expires=now+c.StopSpawnWindowSeconds,nextAttempt=now,
      angle=random()*math.pi*2,used={},positions={},cursor=1,spawned=0}
     R.stats.triggered=R.stats.triggered+1
    end
   end
   local w=g.wave
   if w and now>=w.nextAttempt then
    for offset=0,c.StopMaxHunters-1 do
     local slot=(w.cursor+offset-1)%c.StopMaxHunters+1
     if not w.used[slot]then
      requests[#requests+1]={group=g,wave=w,slot=slot,origin=g.members[1].pos,
       angle=w.angle+(slot-1)*2*math.pi/c.StopMaxHunters,prior=w.positions}
      break
     end
    end
   end
  end
  return requests
 end
 function R.result(request,position,now)
  local w=request.wave;if request.group.wave~=w then return end
  w.nextAttempt=now+c.StopSpawnGapSeconds;w.cursor=request.slot%c.StopMaxHunters+1
  if position then
   w.used[request.slot]=true;w.spawned=w.spawned+1;w.positions[#w.positions+1]=copy(position)
  end
 end
 return R
end
