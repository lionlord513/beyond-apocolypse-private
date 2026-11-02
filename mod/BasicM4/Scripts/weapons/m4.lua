-- Content definition for the first weapon in Basic Weapon Pack.
-- Keep this identity/registry stable so existing M4 saves keep their appearance.
return {
    Id = 'm4',
    Mode = 'burst', FireRate = 0.085,
    Parts = {'body','magazine'}, BodySocket = 'None',
    Name = 'M4A1',
    BaseClass = '/Game/BP/Items/Movable/Weapons/AK/AkWeapon.AkWeapon_C',
    ActorClass = 'AkWeapon_C',
    Registry = 'forced-m4.txt',
    Geometry = 'assets/model.lua',
    MaterialParent = '/MasterWeapon/Materials/Weapons/MAT_ArK47.MAT_ArK47',
    MaterialName = 'BasicM4Material',
    Textures = {
        Diffuse = 'assets/M4A1_Base_Color.png',
        MetalMap = 'assets/M4A1_Metallic.png',
        NormalMap = 'assets/M4A1_Normal.png',
        RoughnessMap = 'assets/M4A1_Roughness.png',
    },
    MagazineSocket = 'magazine_joint',
    Transform = function()
        return {Translation={X=-0.7,Y=5.57,Z=3.61},Rotation={X=0,Y=0,Z=0.70710678118655,W=0.70710678118655},Scale3D={X=1.06,Y=1.06,Z=1.06}}
    end,
}
