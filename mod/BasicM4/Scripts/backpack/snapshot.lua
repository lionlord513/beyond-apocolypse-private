-- Native save-data fingerprints for stale-request rejection. ByteData is never reconstructed in Lua.
local S={}
function S.token(d)
 if not d then return '-'end
 if type(d)=='table'and d._token then return d._token end
 local a,b,c,n=2166136261,5381,0,0
 local function byte(v)n=n+1;a=((a~v)*16777619)&0xffffffff;b=((b*33)~v)&0xffffffff;c=(c+v*n)&0xffffffff end
 local s=d.ActorName:ToString()..d.Class:GetFullName();for j=1,#s do byte(s:byte(j))end
 d.ByteData:ForEach(function(_,v)byte(v:get())end)
 return ('%08x:%08x:%08x:%08x'):format(a,b,c,n)
end
return S
