local source=assert(arg[1]);local clock=0;local discoveries={};local objects={};local applies=0
local observers={};NotifyOnNewObject=function(kind,fn)assert(not observers[kind],'duplicate observer');observers[kind]=fn end
StaticFindObject=function(path)return path:match('%.([^%.]+)$')end
os.clock=function()return clock end
FindAllOf=function(kind)discoveries[#discoveries+1]=kind;return kind=='StaticMeshComponent'and{table.unpack(objects)}or{}end
local function valid(o)return type(o)=='table'and not o.dead end
local function cls(name)return{GetFName=function()return{ToString=function()return name end}end}end
local function component(id,ownerName,ownerClass,meshName,componentClass)
 local owner={GetFullName=function()return ownerName end,GetClass=function()return cls(ownerClass)end,GetAddress=function()return id+100000 end}
 local c={LDMaxDrawDistance=12345,bVisible=true,bNeverDistanceCull=false,owner=owner}
 function c:GetAddress()return id end;function c:GetFullName()return 'component '..id end
 function c:GetOwner()return self.owner end;function c:GetClass()return cls(componentClass or'StaticMeshComponent')end
 function c:IsA(kind)return not self.reusedActor and kind==(componentClass or'StaticMeshComponent')end
 function c:GetCollisionEnabled()return 0 end
 function c:SetVisibility(v)self.bVisible=v;applies=applies+1 end
 function c:SetCullDistance(v)self.LDMaxDrawDistance=v;applies=applies+1 end
 if meshName then c.StaticMesh={GetFullName=function()return meshName end}end
 return c
end
local S=dofile(source)(valid)
for i=1,1000 do objects[i]=component(i,'decoration '..i,'StaticMeshActor','grass')end
local road=component(2001,'road','StaticMeshActor','asphalt');objects[#objects+1]=road
local movable=component(2002,'dynamic actor','Actor','grass');objects[#objects+1]=movable
local procedural=component(2003,'procedural','Actor',nil,'ProceduralMeshComponent')
setmetatable(procedural,{__index=function(_,k)if k=='StaticMesh'then error('invalid property access')end end})
objects[#objects+1]=procedural
S.begin()
for i=1,100 do
 local before=applies;local scans=#discoveries;S.tick(.25)
 assert(applies-before<=128,'unbounded classification batch')
 assert(#discoveries-scans<=1,'multiple discoveries in one tick')
 if S.metrics.cycles>0 and S.hidden==1000 then break end
 clock=clock+.05
end
assert(S.metrics.cycles==1 and S.hidden==1000 and S.protected==1,'classification mismatch')
assert(road.bVisible and road.bNeverDistanceCull,'road protection lost')
assert(movable.bVisible and procedural.bVisible,'dynamic actor changed')
assert(S.ignored[2002]and S.ignored[2003],'ineligible cache missing')
local n=applies;S.apply(objects[1],.25);assert(applies==n,'repeat snapshot overwritten')
local scans=#discoveries
for _=1,400 do clock=clock+.05;S.tick(.25)end
assert(#discoveries==scans,'periodic full-world discovery returned')
local streamed=component(3001,'streamed decoration','StaticMeshActor','grass')
local notify=assert(observers['/Script/Engine.StaticMeshComponent'])
notify(streamed);notify(streamed)
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(not streamed.bVisible and S.hidden==1001,'streamed decoration missed/duplicated')
local unfinished=component(3002,'late decoration','StaticMeshActor','grass');local owner=unfinished.owner;unfinished.owner=nil
notify(unfinished)
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(unfinished.bVisible,'unfinished component changed')
unfinished.owner=owner
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(not unfinished.bVisible,'late owner assignment missed')
streamed.dead=true
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(not S.known[3001]and not S.saved[3001],'unloaded component retained')
assert(#discoveries==scans,'streaming triggered full-world search')
-- Streaming may recycle a still-valid native address for a different object.
local recycled=component(3004,'old decoration','StaticMeshActor','grass');notify(recycled)
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(not recycled.bVisible)
recycled.reusedActor=true;recycled.bVisible=true
recycled.SetCullDistance=function()error('Recycled actor treated as a component')end
recycled.SetVisibility=function()error('Recycled actor visibility changed')end
for _=1,100 do clock=clock+.05;S.tick(.25)end
assert(not S.known[3004]and not S.saved[3004],'Recycled object was retained')
local renamed=component(3005,'old decoration','StaticMeshActor','grass');notify(renamed)
for _=1,100 do clock=clock+.05;S.tick(.25)end
renamed.GetFullName=function()return 'replacement component'end
renamed.SetVisibility=function()error('Replacement component restored from old snapshot')end
S.begin();S.tick(.25);assert(S.restore(),'restore failed');local scanCount=#discoveries
notify(component(3003,'disabled decoration','StaticMeshActor','grass'))
S.tick(.25);assert(#discoveries==scanCount and not S.pending,'work continued after disabling')
assert(objects[1].bVisible and objects[1].LDMaxDrawDistance==12345,'original values not restored')
assert(not road.bNeverDistanceCull,'road override not restored')
assert(not next(S.saved)and not next(S.ignored),'caches not cleared')
assert(#S.registry==0 and S.incomingLast==0,'disabled observer retained work')
print('PASS: bounded work, no recurring world scans, streamed/late/deleted components, dynamic/road protection, snapshot reuse, restore/cancel')
