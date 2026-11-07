local source=assert(arg[1]);local clock=0;local scans=0;local objects={};local writes=0
local observers,hooks={},{}
NotifyOnNewObject=function(kind,fn)assert(not observers[kind]);observers[kind]=fn end
RegisterHook=function(path,pre,post)assert(not hooks[path]);hooks[path]=post end
StaticFindObject=function(path)return path:match('%.([^%.]+)$')end
os.clock=function()return clock end
FindAllOf=function(kind)assert(kind=='StaticMeshComponent');scans=scans+1;return{table.unpack(objects)}end
local function valid(o)return o~=nil and (type(o)~='table'or not o.dead)end
local function cls(name)return{GetFName=function()return{ToString=function()return name end}end}end
local function component(id,ownerClass,meshName,collision)
 local c={bVisible=true,LDMaxDrawDistance=12345,bNeverDistanceCull=false,collision=collision or 0}
 c.owner={GetClass=function()return cls(ownerClass)end}
 function c:GetAddress()return id end;function c:GetFullName()return 'component '..id end
 function c:GetOwner()return self.owner end;function c:IsA()return not self.reused end
 function c:GetCollisionEnabled()return self.collision end
 function c:SetVisibility(v)self.bVisible=v;writes=writes+1 end
 c.StaticMesh={GetFullName=function()return meshName end}
 return c
end
for i=1,1000 do objects[i]=component(i,'SLLandscapePCG','/Game/Environments/Vegetation/SM_Grass')end
local tree=component(2001,'InstancedFoliageActor','/Game/Environments/Vegetation/SM_Tree_Pine')
local road=component(2002,'StaticMeshActor','/GrassPack/SM_GrassRoad.SM_GrassRoad')
local moving=component(2003,'Vehicle_C','grass')
local obstacle=component(2004,'SLLandscapePCG','SM_Bush',3)
local priorHidden=component(2005,'StaticMeshActor','SM_Bush');priorHidden.bVisible=false
for _,c in ipairs({tree,road,moving,obstacle,priorHidden})do objects[#objects+1]=c end
local S=dofile(source)(valid)
local function drain(n)for _=1,n or 100 do local before=writes;clock=clock+.05;S.tick();assert(writes-before<=64,'Unbounded work')end end
S.begin();drain()
assert(S.hidden==1001 and scans==1)
assert(tree.bVisible and road.bVisible and moving.bVisible and obstacle.bVisible)
assert(road.LDMaxDrawDistance==12345 and not road.bNeverDistanceCull,'Native culling changed')
local examined=S.metrics.examined;drain(400)
assert(scans==1 and S.metrics.examined==examined,'Settled scene was rescanned')
local streamed=component(3001,'InstancedFoliageActor','SM_Bush')
local notify=observers['/Script/Engine.StaticMeshComponent'];notify(streamed);notify(streamed);drain()
assert(not streamed.bVisible and S.hidden==1002)
local unfinished=component(3002,'SLLandscapePCG','SM_Grass');local owner=unfinished.owner;unfinished.owner=nil
notify(unfinished);drain(10);assert(unfinished.bVisible);unfinished.owner=owner;drain();assert(not unfinished.bVisible)
local function event(path,c,value)hooks[path]({get=function()return c end},{get=function()return value end})end
streamed.collision=3;event('/Script/Engine.PrimitiveComponent:SetCollisionEnabled',streamed);drain()
assert(streamed.bVisible,'Collision obstacle became invisible')
unfinished.StaticMesh={GetFullName=function()return 'SM_Tree_Oak'end}
event('/Script/Engine.StaticMeshComponent:SetStaticMesh',unfinished);drain();assert(unfinished.bVisible,'Repurposed mesh stayed hidden')
local changed=objects[1];changed.bVisible=true;event('/Script/Engine.SceneComponent:SetVisibility',changed,true);drain();assert(not changed.bVisible)
-- A gameplay actor deliberately hides its own decorative child while enabled.
event('/Script/Engine.SceneComponent:SetVisibility',objects[2],false);drain()
local stale=objects[3];stale.reused=true;stale.bVisible=true
stale.SetVisibility=function()error('Recycled object was modified')end
assert(S.restore());assert(changed.bVisible and not objects[2].bVisible and not priorHidden.bVisible)
assert(not next(S.saved)and #S.order==0 and S.last==0)
local old=scans;notify(component(4001,'StaticMeshActor','grass'));drain();assert(scans==old,'Disabled observer did work')
S.begin();drain();assert(scans==old+1,'Re-enable did not rediscover restored scene');assert(S.restore())
return 'Placed/PCG decoration, tree and collision preservation, streaming, idle work, native visibility changes, restore and address reuse'
