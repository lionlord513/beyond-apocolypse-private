local C={}
for tier=1,2 do for size,litres in ipairs({2,5,10})do
 local id=(tier-1)*3+size
 C[id]={id=id,tier=tier,litres=litres,height=({26,38,52})[size],dryMass=({.9,1.8,3.0})[size],
  name=('Nitrous Stage %s / %d L'):format(tier==1 and 'I'or 'II',litres),
  price=({600,1200,2200})[size]*tier,color=tier==1 and 'blue'or 'purple'}
end end
return C
