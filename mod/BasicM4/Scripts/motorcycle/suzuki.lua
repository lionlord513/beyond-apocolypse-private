-- Mini-bike presentation only. The native carrier and rider remain unit scale.
local scale=.52
local function v(x,y,z)return {X=x*scale,Y=y*scale,Z=z*scale}end
return {
 dir='suzuki',visualScale=scale,frameOffsetZ=(1-scale)*(-16.80253-32.944965625),tireRadius=32.944965625*scale,
 pivots={front=v(78.94016,0,-16.80253),rear=v(-77.94617,0,-16.80253),steer=v(48.38945,0,48.68875),frontpaint=v(48.38945,0,48.68875),rearpaint=v(0,0,0),body=v(0,0,0),paint=v(0,0,0)},
 -- Native seat socket puts the pelvis 15.889 cm above this connector.
 -- Seat surface is frame Z26-33; Z24 places the pelvis at frame Z39.889.
 -- Only the invisible native saddle moves; visible geometry is unchanged.
 seat={X=-20,Y=0,Z=24},
 slots={CarSeatDriver={X=-20,Y=0,Z=24},CarMotorV2={X=1,Y=0,Z=7.5},CarBatteryV2={X=-7,Y=-10.5,Z=1},CarRadiatorV2={X=1,Y=10.5,Z=7},CarTankGasV2=v(24,0,51),CarStarterV2=v(26,0,58),CarSteeringWheelV2=v(23,0,106)},
 service={CarMotorV2={class='CarItemMotor',at={X=1,Y=0,Z=7.5},size={X=32,Y=10,Z=26},axisFit=true,rotation={Pitch=90,Yaw=0,Roll=0}},CarBatteryV2={class='CarItemBattery',at={X=-7,Y=-10.5,Z=1},size={X=15,Y=4,Z=11},axisFit=true,rotation={Pitch=0,Yaw=0,Roll=0}},CarRadiatorV2={class='CarItemTankRadiator',at={X=1,Y=10.5,Z=7},size={X=26,Y=3,Z=20},axisFit=true,rotation={Pitch=0,Yaw=90,Roll=0}}},
 -- Grip island centres (72 left, 122 right), in unscaled steering-component coordinates.
 hands={left={X=-25.50833,Y=-38.64177,Z=57.82138},right={X=-25.50833,Y=38.64184,Z=57.82135}},
 -- Authored targets mark the rubber grips, not the wrist bones. Native curled
 -- finger/thumb measurements put the grasp centre 8.25 cm ahead and 3.1 cm
 -- below the wrist. These steering-local offsets account for mesh scale once.
 wristOffsets={left={X=-8.25/scale,Y=-2.5/scale,Z=3.1/scale},right={X=-8.25/scale,Y=2.5/scale,Z=3.1/scale}},
 feet={left={X=-7,Y=-17,Z=-3},right={X=-7,Y=17,Z=-3},leftBall={X=5,Y=-17,Z=-6},rightBall={X=5,Y=17,Z=-6}},
}
