return {
    -- Host only. Reuse a fraction of existing AK loot; no extra ammo or weapons.
    LootPercent = 25, HuntingPercent=15, EnfieldPercent=10,
    PollMilliseconds = 750,
    -- Ctrl+F6: convert held AK. Ctrl+F7: spawn one M4 at the host.
    EnableHostShortcuts = true,
    Gyrocopter={Enabled=true,WorldSpawns=true,SpawnPercent=3,ShowHUD=true,TransportKey='J'},
    Apocalypse={
        Enabled=true,DayMin=3,DayMax=5,NightMin=5,NightMax=8,
        ModCapDay=5,ModCapNight=10,TotalNearbyCap=10,
        InfestedBuildingPercent=15,InfestedBuildingMax=10,
        BaseLoadMeters=850,MaxLoadMeters=950,LeadSeconds=12,
        DespawnMeters=1250,DespawnGraceSeconds=25,
        MinSpawnMeters=100,RoadClearanceMeters=15,
        DrawMeters=700,MaxSpawnsPerPass=1,
        NightMinSpawnMeters=45,NightStopSpawnMinMeters=55,NightStopSpawnMaxMeters=95,
        NightRoadsideStopMinSeconds=45,NightRoadsideStopMaxSeconds=100,
        RoamerMinSeconds=180,RoamerMaxSeconds=360,
        SwarmMinSeconds=7200,SwarmMaxSeconds=10800,
        SwarmMin=6,SwarmMax=10,SwarmChaseSeconds=300,
        NightSpeedMultiplier=1.3,RunnerSpeed=520,
        HazmatPercent=20, -- Share of added zombies; native spawns are untouched.
        LocationRespawnSeconds=21600,
        -- Staying nearby while repairing/looting counts as a stop.
        StopEncountersEnabled=true,
        RoadsideStopMinSeconds=180,RoadsideStopMaxSeconds=600,
        BuildingStopMinSeconds=1200,BuildingStopMaxSeconds=2100,BuildingStopChance=0.5,
        BuildingRadiusMeters=180,RoadsideNearRoadMeters=120,
        StopRadiusMeters=70,StopMaxSpeed=8,
        StopSpawnMinMeters=160,StopSpawnMaxMeters=230,StopMaxHunters=5,
        StopSpawnGapSeconds=4,StopSpawnWindowSeconds=90,StopSpawnSeparationMeters=40,
    },
}
