local root=assert(arg[1]);local P=dofile(root..'/apocalypse_policy.lua')
local cfg={MaxSpawnsPerPass=2,ModCapDay=30,ModCapNight=40,TotalNearbyCap=64,MinSpawnMeters=100,MaxLoadMeters=1250,BaseLoadMeters=850,LeadSeconds=8}
for live=0,70 do for total=0,70 do for _,night in ipairs({false,true})do
 local n=P.budget(live,total,night,cfg);assert(n>=0 and n<=2)
 if live>= (night and 40 or 30)or total>=64 then assert(n==0)end
end end end
local players={{pos={X=0,Y=0,Z=0},velocity={X=1000,Y=0,Z=0},speed=10}}
assert(not P.safePoint({X=6000,Y=0,Z=0},players,cfg),'unsafe movement corridor')
assert(P.safePoint({X=20000,Y=10000,Z=0},players,cfg),'safe spawn rejected')
assert(P.night(0)and P.night(1900)and not P.night(600))
assert(P.loadDistance({speed=200},cfg)==1250,'unbounded streaming radius')
local defaults=dofile(root..'/default_config.lua').Apocalypse
local infestation
for i=1,1000 do local key='Building_'..i;if P.infested(key,defaults)then infestation=key;break end end
assert(infestation and not P.infested('L_SpawnHouse',defaults))
assert(P.locationTarget(infestation,false,defaults,10)==10,'infestation default is not ten')
for limit=2,40 do for _,night in ipairs({false,true})do
 local n=P.locationTarget(infestation,night,defaults,limit);assert(n>=1 and n<=limit,'location bypassed ceiling')
end end
assert(P.locationTarget(infestation,false,defaults,2)==2)
local R=dofile(root..'/stop_encounters.lua')(P,defaults,function(a,b)return a or 0 end)
local stopped={{pos={X=0,Y=0,Z=0},speed=0,roadMeters=5,nearBuilding=false}}
assert(#R.update(stopped,0,{},false)==0 and #R.update(stopped,179,{},false)==0)
assert(#R.update(stopped,180,{},false)==1,'day roadside delay changed')
R.reset();assert(#R.update(stopped,0,{},true)==0 and #R.update(stopped,44,{},true)==0)
assert(#R.update(stopped,45,{},true)==1,'night breakdown delay not applied')
assert(#R.update({},46,{},true)==0,'leaving did not cancel pending encounter')
local valid=function(o)return type(o)=='table'and not o.dead end
local F=dofile(root..'/firing.lua')(valid);local shots=0
local a={NbBullet=30,IsAttacking=0,GetAddress=function()return 1 end}
function a:TriggerAttack()shots=shots+1;self.NbBullet=self.NbBullet-1 end
local d={Mode='burst',FireRate=.1}
F.tick(a,d,0,true,false);a.NbBullet=29;F.tick(a,d,.1,true,false);F.tick(a,d,.3,true,false)
assert(shots==0,'remote ammunition acknowledgement started a burst')
F.tick(a,d,.4,true,true);a.NbBullet=28;F.tick(a,d,.45,true,true)
F.tick(a,d,.56,true,true);F.tick(a,d,.67,true,true);F.tick(a,d,1,true,true)
assert(shots==2,'three-round burst did not stop after two follow-up shots')
F.tick(a,d,1.1,true,false);F.tick(a,d,1.2,true,true);a.NbBullet=a.NbBullet-1;F.tick(a,d,1.25,true,true)
F.tick(a,d,1.3,false,true);F.tick(a,d,1.5,true,true);assert(shots==2,'death did not cancel queued shots')
local I=dofile(root..'/backpack/policy.lua')
assert(not I.decode(string.rep('x',300)),'oversized inventory request accepted')
assert(not I.slot(-1,6)and not I.slot(6,6)and not I.slot(.5,6)and I.slot(5,6))
assert(not I.actor('n:0')and not I.actor('n:2147483648')and I.actor('n:12'))
print('PASS: shared zombie caps/clearance, remote burst guard, three-round/death behavior, inventory bounds')
