return function(g)
  if g.tangents then return g.tangents end
  local out={};for i=1,#g.vertices do out[i]={TangentX={X=1,Y=0,Z=0},bFlipTangentY=false}end
  for k=1,#g.triangles,3 do
   local ia,ib,ic=g.triangles[k]+1,g.triangles[k+1]+1,g.triangles[k+2]+1
   local a,b,c=g.vertices[ia],g.vertices[ib],g.vertices[ic];local u,v,w=g.uv[ia],g.uv[ib],g.uv[ic]
   local e={X=b.X-a.X,Y=b.Y-a.Y,Z=b.Z-a.Z};local f={X=c.X-a.X,Y=c.Y-a.Y,Z=c.Z-a.Z}
   local du,dv=v.X-u.X,v.Y-u.Y;local eu,ev=w.X-u.X,w.Y-u.Y;local determinant=du*ev-eu*dv
   if math.abs(determinant)>1e-8 then
    local t={X=(e.X*ev-f.X*dv)/determinant,Y=(e.Y*ev-f.Y*dv)/determinant,Z=(e.Z*ev-f.Z*dv)/determinant}
    local bit={X=(f.X*du-e.X*eu)/determinant,Y=(f.Y*du-e.Y*eu)/determinant,Z=(f.Z*du-e.Z*eu)/determinant}
    for _,i in ipairs({ia,ib,ic})do local n=g.normals[i];local dot=t.X*n.X+t.Y*n.Y+t.Z*n.Z
     local x,y,z=t.X-dot*n.X,t.Y-dot*n.Y,t.Z-dot*n.Z;local length=math.sqrt(x*x+y*y+z*z)
     if length>1e-8 then x,y,z=x/length,y/length,z/length
      local cross={X=n.Y*z-n.Z*y,Y=n.Z*x-n.X*z,Z=n.X*y-n.Y*x}
      out[i]={TangentX={X=x,Y=y,Z=z},bFlipTangentY=(cross.X*bit.X+cross.Y*bit.Y+cross.Z*bit.Z)<0}
     end
    end
   end
  end
  g.tangents=out;return out
end
