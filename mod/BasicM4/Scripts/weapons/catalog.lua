local folder=debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/[^/]+$')
local m4=dofile(folder..'/m4.lua')
local defs={m4=m4}
for _,entry in ipairs({{'hunting','Hunting Rifle','semi',0.4},{'enfield','Lee-Enfield','bolt',1.35}}) do
    local id=entry[1]
    defs[id]={Id=id,Name=entry[2],Mode=entry[3],FireRate=entry[4],Parts={'body'},
        BaseClass=m4.BaseClass,ActorClass=m4.ActorClass,Geometry='assets/'..id..'.lua',
        MaterialParent=m4.MaterialParent,MaterialName='BWP_'..id,
        BodySocket='BWP_'..id,Transform=m4.Transform,
        Textures={Diffuse='assets/'..id..'-diffuse.png',NormalMap='assets/'..id..'-normal.png',
            MetalMap='assets/rifle-metal.png',RoughnessMap='assets/rifle-rough.png'}}
end
return defs
