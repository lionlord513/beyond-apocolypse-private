Beyond Apocolypse 0.11.7 beta - multiplayer stabilization candidate

Native-owner-only flight; replicated scene identity markers; delayed vehicle
setup; host-validated guest blade eligibility; immediate query-only blade and
docked-body protection during native refitting. Backpack saving/dormancy guards.
RPGs are single-use: native rocket launch followed by host launcher disposal.
Both players MUST update to 0.11.7 and reconnect.

Native checks passed: two aircraft with distinct identities; both original
blades fitted while docked with physics still disabled; stationary trailer
retains 350 kg mass; backpack store/move/take retains GUID and ammunition;
RPG emits one projectile and the original launcher is removed.
Real two-PC acceptance is pending with the user and friend. This is not a
guarantee of perfect synchronization or verified high-speed towing.
Details: source/AUDIT-0.11.7.md. No new DLL or assets; flight tuning and saves
unchanged. Backup: backups/before-stability-0117.

Beyond Apocolypse 0.11.6 beta - multiplayer transport audit

Client docking now disables collision/suspension before snapping into place.
Native attachment arriving before the host snapshot freezes safely; stale
undocked state cannot leave an attached Hornet simulating flight. Late native
collision resets are repaired while docked. Undocking restores the actual
pre-dock physics state instead of forcing every client to simulate physics.
Clients now apply the host trailer mass already supplied in network state.
A bounded visual check hides reappearing donor chassis, preserves service
parts and blades, and recreates missing local Hornet rendering if needed.
Both players: close the game, update to 0.11.6, then reconnect.

Beyond Apocolypse 0.11.5 beta - restore landing-pad construction

Fixes the missing heli-trailer pad introduced in 0.11.4. UE4SS LoadAsset
returns the asset plus two status values; the collision mesh setter must
receive only the asset. This prevented setup from reaching the visual pad.
Retains the replicated pad collision and client left-click blade changes.
Carrier setup failures now log their error once instead of silently retrying.
Both players: update to 0.11.5 and restart Drive Beyond Horizons.

Beyond Apocolypse 0.11.4 beta - client blade attachment and landing-pad movement

Remote players use the normal left-click Attach prompt. The host receives
stable aircraft/blade identities, checks the held original part, matching
mount, reach and parked state, and performs the native fitting operation.
Duplicate requests and races with native fitting do not install twice.
Landing-pad collision is created once by the host and replicated. Clients
wait for that shared movement base instead of making unrelated local copies.
Query-only collision preserves the weightless pad and towing behavior.
Both players must close the game and update to 0.11.4 before reconnecting.
Launcher: Check updates > Update / repair. Offline: extract and run Install.cmd.

# Beyond Apocolypse 0.11.3 beta - multiplayer Hornet synchronization

Unique host-created replicated identity markers replace ambiguous native part
IDs (new vehicle parts can all have ID zero). Host snapshots synchronize each
aircraft's fitted blade mask, blade identities and dock target. Clients wait
for authoritative state instead of inventing fitted blades. Changed state is
checked four times per second; a two-second refresh supports late joins and
late actor replication. Old/out-of-order snapshots are ignored.
Docked aircraft keep native interaction queries, with rigid-body collision,
suspension and free-flight network smoothing suspended until release.
Both players MUST close the game and update to 0.11.3 before reconnecting.
Launcher: Check updates > Update / repair. Offline: extract full ZIP and run
Install.cmd. Existing saves/settings retained. No new DLL or asset changes.


# Hornet blades and Heli trailer - 0.11.1 beta

The Car spawner tab contains separate **Trailer** and **Heli trailer** entries.
World basic trailers have a saved 50/50 normal/heli choice. The heli variant
arrives with its textured landing pad and mounting frame fitted. Occupied saved
normal trailers are preserved. Remorque 2000 is unchanged. Existing carriers
receive the new deck, H marking, braces and paired blade rack automatically.
The 4.8 x 2.4 metre pad uses 732 triangles and one shared 1024 texture atlas.

0.10.1 fixes loose blades: their imported model follows the native simulated
pickup mesh, so the normal Take prompt targets the blade you can see. Existing
saved blade actors are repaired when loaded; no replacement items are created.

## Controls

- Hover low over a parked trailer and press J from the pilot seat. The Hornet
  snaps into alignment, stops its engine and automatically stows fitted blades.
  You may approach from either direction; small drift and tilt are accepted.
  The capture area spans most of the pad and reaches about 1.5 metres above
  the secured position, comfortably including a one-foot hover.
- Press J again in the pilot seat, or while looking directly at the aircraft with empty hands, to
  release it. The engine stays off and the blades remain in the rack.
- Look directly at a stopped fitted or racked blade and right-click **Remove**.
  The same part goes into your hands. No J blade-removal prompt remains. Approach the matching side of its Hornet rotor mast, look up at
  the highlighted mount and left-click **Attach**, including while docked.
  Repeat from the other side for the second blade. Land and stop the rotor first.
- Carry a blade and look at the carrier to secure it individually in its rack.
- Change Gyrocopter.TransportKey in Scripts/config.lua to another free letter.
  J is the default even with an older configuration. Flight/menu keys are excluded.
  Chat, pause, developer menu and backpack UI suppress this interaction.

New Hornets get exactly two matching physical main blades nearby once. They
still need a native engine. Existing saved Hornets retain their fitted blades.
Both blades are required for lift, including autorotation. The hub stays fitted;
the rear propeller, wheels and body geometry are unchanged. Each blade takes one
inventory cell under the existing backpack rules. Native loose-part names may
still show the donor headlight name; the imported blade identifies it.

## Transport and saves

Docking accepts low hover within local X -240..180 cm, Y +/-135 cm, Z 45..245 cm.
Heading is corrected automatically; relative speed below 5 m/s and tilt below
45 degrees are accepted. Trailer motion below 1 m/s tolerates suspension settling.
Occupied racks, another helicopter, people/cargo in the footprint and unsafe
departure clearance still block the relevant operation.
The pad adds no rigid-body collision, welded mass or inertia; its query surfaces
ignore native suspension trace channels. A secured aircraft and its parts have
collision and wheel suspension disabled, with original settings restored on
release. Helicopter mass is not added to the trailer. The original native hitch,
trailer body, suspension and ordinary cargo remain in control.
Service parts removed while docked regain their normal collision.

The same aircraft and part actors are retained. The aircraft is never inserted
into the native item-cargo save list; that causes duplicate vehicles. Blades and
ordinary supplies use native cargo. A plain-text record keyed to the exact
native save revision preserves the aircraft/trailer link, blade identities and
original trailer body mass. Selecting an older save selects its own record.
Invalid records block changes rather than replacing originals. A missing or
far-away trailer never teleports a remote aircraft into place.

Keep the mod's state folder with your saves when moving a host world between
computers. The installer/launcher retains it and custom settings. Clients receive
native item IDs and replicated variant/attachment markers; host save GUIDs are
never used as network IDs. Both players must run 0.11.1.

## Validation boundary

See TEST-RESULTS.txt for the measured native tests and remaining acceptance.
No real second computer was available during this build. Host validation,
request sequencing and client attach/detach logic are implemented and tested
locally; live co-op, disconnect/late join and prolonged rough-road hauling are
not certified by those tests.

Implementation: gyrocopter/{transport,blades,journal,transport_controls}.lua,
blade_mounts.lua, controller.lua, visuals.lua and the split original blade geometry. No new DLL.
The existing update loop owns all operations. New native hooks observe
/Script/DriveBeyondHorizons.DBHHelper:SaveGameToSlotAsyncReal,
/Script/Engine.PlayerController:ServerExecRPC and ClientMessage; engine-owned
strings are read without rewriting them. Native part detach/refit and
AttachActorOn handlers preserve actor identity and existing part condition.

0.10.1 native selection/attachment hooks are scoped to blade actors and Hornet
mounts. Wrong-side/aircraft and unsafe fitting requests retain the original part.

0.11.0 keeps CheckNeedShape hover eligibility cached (no disk IO or ground
traces). Fresh authoritative checks remain on mutations. Native scoped hooks
add CarEquipableV2:CheckCanBeRemoved and CarItemEquipableActor:
ExecuteSecondaryAction / GetSecondaryActionName. Racked blades use the native
secondary-input RPC followed by native cargo detach and SetItemInHand.
Clean AO replaces the inherited weapon-shaped shading on aircraft and carrier
materials. Both clients must update; live two-PC acceptance is still required.
