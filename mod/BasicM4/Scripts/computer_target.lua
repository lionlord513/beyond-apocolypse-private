-- Coordinates sent by a guest must be relative to its replicated pawn.
-- Different players can have different native world-origin offsets.
local C={}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<2147483647 end
function C.encode(terminal,pawn)
 local v={};for _,k in ipairs({'X','Y','Z'})do
  if not finite(terminal[k])or not finite(pawn[k])then return end
  v[k]=terminal[k]-pawn[k]
 end
 if v.X*v.X+v.Y*v.Y+v.Z*v.Z>=500^2 then return end
 return ('BAHC2|%.2f|%.2f|%.2f'):format(v.X,v.Y,v.Z),('BAHC1|%.0f|%.0f|%.0f'):format(terminal.X,terminal.Y,terminal.Z)
end
function C.decode(text,pawn)
 if type(text)~='string'or #text>80 then return end
 local protocol,x,y,z=text:match('^(BAHC[12])|([%d.%-]+)|([%d.%-]+)|([%d.%-]+)$')
 x,y,z=tonumber(x),tonumber(y),tonumber(z)
 if not protocol or not finite(x)or not finite(y)or not finite(z)then return end
 local at={X=x,Y=y,Z=z}
 if protocol=='BAHC2'then
  if x*x+y*y+z*z>=500^2 then return end
  at={X=pawn.X+x,Y=pawn.Y+y,Z=pawn.Z+z}
 end
 if not finite(at.X)or not finite(at.Y)or not finite(at.Z)then return end
 if (at.X-pawn.X)^2+(at.Y-pawn.Y)^2+(at.Z-pawn.Z)^2>=500^2 then return end
 return at,protocol=='BAHC2'and 100 or 2
end
return C
