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
function P.safePoint(q,players,c)
 for _,p in ipairs(players)do
  if P.distance(q,p.pos)<c.MinSpawnMeters then return false end
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
return P
