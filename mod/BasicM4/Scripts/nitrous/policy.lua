-- Pure, bounded boost policy. Extra bottles extend duration; they do not stack force.
local P={}
function P.clamp(x,a,b)return math.max(a,math.min(b,x))end
function P.output(s,dt)
 dt=P.clamp(dt or 0,0,.15)
 if not s.held or not s.driver or not s.running or not s.ground or s.brake>.05 or s.handbrake or s.reverse or s.up<.65 or s.litres<=.0001 or s.paused then return 0,0 end
 if s.throttle<=.05 and s.speed<1 then return 0,0 end
 local tier=s.tier==2 and 2 or 1
 local taper=P.clamp((55.56-math.max(0,s.speed))/19.45,0,1)
 local turning=1-.7*P.clamp(math.abs(s.steering or 0),0,1)
 local rate=tier==1 and .20 or .35
 local used=math.min(s.litres,rate*dt)
 if dt<=0 then return 0,0 end
 return (tier==1 and 3.6 or 5.4)*taper*turning*used/(rate*dt),taper>0 and used or 0
end
function P.hash(s)local h=5381;for i=1,#s do h=(h*33+s:byte(i))&0xffffffff end;return h end
return P
