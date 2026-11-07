local C=dofile(arg[1]..'/computer_target.lua')
local guest={X=-1200050,Y=500000,Z=80}
local terminal={X=-1200000,Y=500090,Z=30}
local host={X=950,Y=-200,Z=80}
local message,legacy=C.encode(terminal,guest);assert(message)
assert(legacy=='BAHC1|-1200000|500090|30','Updated guest lost the older-host hint')
assert(C.decode(legacy,guest),'Older host at the same origin cannot use the compatibility hint')
local at,tolerance=C.decode(message,host)
assert(at.X==1000 and at.Y==-110 and at.Z==30 and tolerance==100,'Guest origin selected the wrong host terminal')
at=C.decode(message,{X=955,Y=-200,Z=80});assert(at.X==1005,'Small movement during network transit must remain resolvable')
at,tolerance=C.decode('BAHC1|1000|-110|30',host);assert(at.X==1000 and tolerance==2,'Existing clients remain supported')
assert(not C.decode('BAHC1|-1200000|500090|30',host),'Out-of-range old-origin coordinates accepted')
for _,bad in ipairs({'BAHC2|999999|0|0','BAHC2|nan|0|0','BAHC2|1..1|0|0','BAHC2|1|2|3|4','BAHC3|1|2|3'})do assert(not C.decode(bad,host))end
assert(not C.encode({X=0/0,Y=0,Z=0},host))
assert(not C.encode({X=host.X+500,Y=host.Y,Z=host.Z},host))
return 'Rebased origins, transit movement, legacy clients, reach limits and malformed messages'
