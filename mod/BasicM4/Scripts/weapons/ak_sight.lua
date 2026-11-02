-- The native AK points along local +Y. Camera presentation rotates it -90 Z.
-- Align its authored sight socket, rather than the old six-centimetre guess.
return function(point,scale)
 return {height=point.Z*scale,lateral=-point.X*scale}
end
