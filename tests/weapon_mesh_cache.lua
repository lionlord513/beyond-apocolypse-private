local scripts=assert(arg[1]);local nextId=0;local actors,assets,meshes={},{},{}
local function valid(o)return type(o)=='table'and o.alive~=false end
local function object()
 nextId=nextId+1;local id=nextId
 return {GetAddress=function()return id end,GetFullName=function()return 'Fixture.'..id end}
end
local function component(owner)
 local c=object();c.owner=owner;c.visibilityChanges=0
 function c:SetCollisionEnabled(n)self.collision=n end
 function c:SetGenerateOverlapEvents(n)self.overlap=n end
 function c:SetComponentTickEnabled(n)self.tick=n end
 function c:SetIsReplicated(n)self.rep=n end
 function c:SetVisibility(n)self.visible=n;self.visibilityChanges=self.visibilityChanges+1 end
 function c:SetCastShadow(n)self.shadow=n end
 function c:SetStaticMesh(mesh)self.StaticMesh=mesh;return not self.reject end
 function c:SetMaterial(_,m)self.material=m end
 function c:K2_AttachToComponent(parent)self.parent=parent end
 function c:K2_SetRelativeTransform(tr)self.transform=tr end
 function c:K2_DestroyComponent(a)assert(a==self.owner);self.alive=false end
 owner.components[#owner.components+1]=c;return c
end
local function actor()
 local a=object();a.components={};function a:AddComponentByClass()return component(self)end
 actors[#actors+1]=a;return a
end
local pc=actor();local H={GetPlayerController=function()return pc end}
local fields={'LoaderConfig','ReturnValue','SceneScale','TransformBaseType','StaticMeshConfig','bBuildSimpleCollision','bBuildComplexCollision'}
StaticFindObject=function()
 local o=object();function o:ForEachProperty(fn)
  for i,name in ipairs(fields)do fn({GetFName=function()return {ToString=function()return name end}end,GetOffset_Internal=function()return i end})end
 end;return o
end
FName=function(s)return s end
FindAllOf=function(name)return name=='StaticMesh'and meshes or assets end
local imports,builds=0,0
package.loadlib=function(_,name)
 if name=='ba_load_asset'then return function(...)
  assert(select('#',...)==7,'Native asset ABI changed');imports=imports+1
  local a=object();assets[#assets+1]=a;return a:GetAddress()
 end end
 assert(name=='ba_load_chassis');return function(...)
  assert(select('#',...)==6,'Native mesh ABI changed');builds=builds+1
  local m=object();meshes[#meshes+1]=m;return m:GetAddress()
 end
end
local C=dofile(scripts..'/weapons/mesh_cache.lua')({root='fixture'},H,valid)
local material=object();local a=actor();local body=component(a)
C.fill(a,body,'m4','body',material)
assert(imports==2 and builds==2,'Body and separate iron sight must load once')
local iron=C.irons[body:GetFullName()].component
assert(iron.parent==body and iron.transform.Scale3D.X==1,'Iron sight inherited an extra weapon transform')
for _,entry in pairs(C.entries)do
 assert(entry.holder.StaticMesh==entry.mesh and entry.holder.material==material,'Stored rifle lost its native GC references')
 assert(entry.holder.visible==false and entry.holder.tick==false and entry.holder.rep==false and entry.holder.collision==0 and entry.holder.overlap==false)
end
for i=1,100 do C.showIrons(body,false)end
assert(iron.visibilityChanges==1 and iron.visible==false,'Unchanged optic state did repeated native work')
C.showIrons(body,true);assert(iron.visible and iron.visibilityChanges==2)
C.remove(body);body:K2_DestroyComponent(a);assert(not valid(iron))
local replacement=actor();local nextBody=component(replacement)
C.fill(replacement,nextBody,'m4','body',material)
assert(imports==2 and builds==2,'Hotbar restoration rebuilt cached geometry')
local mag=component(replacement);C.fill(replacement,mag,'m4','magazine',material)
assert(imports==3 and not C.irons[mag:GetFullName()],'Magazine acquired an iron sight')
local orphan=C.irons[nextBody:GetFullName()].component;nextBody.alive=false;C.prune()
assert(not valid(orphan),'Deleted body left an orphan iron sight')
local oldHolder=C.entries['m4-body'].holder;pc=actor()
C.mesh('m4','body',material)
assert(imports==4 and not valid(oldHolder),'New controller reused old-world retention components')
local finalBody=component(replacement);C.fill(replacement,finalBody,'m4','body',material)
local finalIron=C.irons[finalBody:GetFullName()].component;C.reset()
assert(not next(C.entries)and not next(C.irons)and not valid(finalIron),'Travel retained native mesh references')
for _,owner in ipairs(actors)do
 if owner==a or owner==replacement then -- Actor-owned bodies are removed by normal item teardown.
 else for _,c in ipairs(owner.components)do assert(not valid(c),'Cache holder leaked on reset')end end
end
pc.alive=false;local ok=pcall(C.mesh,'m4','body',material);assert(not ok,'Loading world accepted an expired controller')
return 'Native ABI, geometry reuse, rooted materials, optic visibility, orphan cleanup and controller/world lifetime'
