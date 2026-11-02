-- Pure policy: positions are centimetres, distances exposed to users are metres.
local P={}
function P.distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)/100 end
function P.nearest(q,players)local best=math.huge;for _,p in ipairs(players)do best=math.min(best,P.distance(q,p.pos))end;return best end
function P.night(t)return t>=1900 or t<600 end
function P.loadDistance(p,c)return math.min(c.MaxLoadMeters,math.max(c.BaseLoadMeters,200+p.speed*c.LeadSeconds))end
function P.nearLocation(q,players,c)
 for _,p in ipairs(players)do if P.distance(q,p.pos)<=P.loadDistance(p,c)then return true end end
 return false
end
function P.safePoint(q,players,c,minimum)
 for _,p in ipairs(players)do
  if P.distance(q,p.pos)<(minimum or c.MinSpawnMeters)then return false end
  -- Keep all spawns clear of the next 8 seconds of each player's movement.
  local vx,vy=p.velocity.X,p.velocity.Y;local vv=vx*vx+vy*vy
  if vv>10000 then
   local t=math.max(0,math.min(8,((q.X-p.pos.X)*vx+(q.Y-p.pos.Y)*vy)/vv))
   local dx,dy=q.X-p.pos.X-vx*t,q.Y-p.pos.Y-vy*t
   if dx*dx+dy*dy<(3500)^2 then return false end
  end
 end
 return true
end
function P.budget(live,total,night,c)return math.max(0,math.min(c.MaxSpawnsPerPass,(night and c.ModCapNight or c.ModCapDay)-live,c.TotalNearbyCap-total))end
function P.locationHash(key)local h=5381;for i=1,#key do h=(h*33+key:byte(i))&0xffffffff end;return h end
function P.infested(key,c)
 -- Keep the starter house out of the random infestation pool.
 return not key:lower():find('spawn',1,true)and P.locationHash(key)%100<(c.InfestedBuildingPercent or 15)
end
function P.locationTarget(key,night,c,ceiling)
 local hash=P.locationHash(key);local lo,hi=night and c.NightMin or c.DayMin,night and c.NightMax or c.DayMax
 local base=not night and P.infested(key,c)and(c.InfestedBuildingMax or 10)or lo+hash%(hi-lo+1)
 return math.max(1,math.min(ceiling,math.floor(base*ceiling/10+.5)))
end
return P
