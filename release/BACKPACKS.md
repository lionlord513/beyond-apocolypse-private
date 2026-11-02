Current multiplayer update: 0.7.2 uses replicated game item IDs, not local
save GUIDs. Update BOTH players, close/restart the game, then test remote RMB
pickup with empty hands and a worn backpack. The host now returns real errors;
requests remain pending until the native inventory update or timeout.

# Native backpack grid — 0.7.1 beta

Uses the game's existing small, medium and large bags, models, hotbar and loot.
No new bag models or separate bag loot pool are added.

| Bag | Native hotbar | Total cells |
| --- | ---: | ---: |
| Small | 2 | 6 |
| Medium | 4 | 12 |
| Large | 6 | 18 |

The large bag is 6 columns by 3 rows. The first gold cells are the actual native
hotbar slots. Each pickupable item uses one cell, including fuel cans and other items
which cannot normally enter the hotbar. Quantities and contents remain native.
Backpacks cannot be nested. Attached car parts and fixed scenery are excluded.

## Controls

- Drag the title bar to move the translucent window; position is remembered
  until restarting the game. It stays inside the screen. Smaller bags have
  fewer rows. Hover over a cell to see its full item name.
- With a bag worn and hands empty, look at a loose item within 2 metres and
  right-click to store it. The prompt appears immediately below Take. Storage
  cells fill first, then free hotbar cells. Full bags leave the item untouched.
  Native right-click aiming and dropping return outside this context.

- Holding a bag: left mouse equips it; right mouse drops it with contents.
- Tab: close the grid, or open the targeted ground bag within 2 metres;
  otherwise open your equipped bag. Another player's held/worn bag is unavailable.
- Drag hands to an empty cell to store. Drag a cell to hands to retrieve.
- Drag between cells to move or swap; releasing outside a cell cancels.
- B: remove the equipped bag to empty hands, on foot. Occupied hands block it.
  If native pickup cannot complete, a message identifies the intact bag nearby.
  Driving retains the game's B autopilot binding.
- Caps Lock: native melee toggle. Tab is removed from the active melee mapping
  for this session; saved key settings are not rewritten.
- Escape or Tab closes. Inventory controls are suppressed during chat/pause or
  Field Command. The grid closes on death, map change, lost bag or lost reach.

The world keeps running while the grid is open. UI mode and disabled pawn input
prevent grid mouse clicks from firing or punching. Original move/look/cursor
and pause-menu permissions are restored when it closes.

A native hotbar weapon can retain a saved snapshot while equipped. Moving its
active hotbar cell is blocked until you store the actual held item. This avoids
creating a second weapon from that snapshot. Rifles keep native names/icons;
AK-based variants can appear as Rifle / AK family in the grid.

## Storage and co-op

Contents live in each bag's existing BP_InventoryComponent.Slots save data.
The host reads authoritative Slots (SlotsList can be empty after loading).
Clients read replicated SlotsList, including extended indices. Native
NbSlot stays 2/4/6; it is expanded only during a validated store call and restored
in that same game-thread operation, so the ordinary hotbar is unchanged.

Moves copy native FActorSaveData into a temporary native component, then swap or
move it, verify both fingerprints and roll back on failure. ByteData is never
reconstructed as Lua arrays: a development probe found that loses native data.
Native removal handles the held weapon's existing quick-slot snapshot before
storing its current state. Original held actors are destroyed only after native
storage reports success. No nested bag storage is allowed through this grid.

Direct pickup uses native AddItemToSlot serialization. A validated transfer
temporarily enables CanBeInBackpack and restores it in the same operation,
including on error. Force=true does not bypass native eligibility. The restored
fuel can retained its GUID, 3.2 litres, petrol composition and original false
eligibility flag. No independent item save format is introduced.

Only the host changes items. Client requests use a bounded BAINV1 protocol on
PlayerController.ServerExecRPC; a read-only post-hook observes this prefix after
native dispatch. Engine-owned FString parameters are never rewritten. The
shipped 25172482 ServerExecRPC implementation is a no-op, verified using its
PDB and executable. Unrelated commands are not intercepted. The actual
RPC controller supplies identity; requests cannot nominate another player.
Every operation checks life, ownership, distance/line of sight, capacity, held
item and expected source/destination fingerprints. Direct pickup additionally
resolves the requested GUID from host world actors for remote controllers,
then checks reach, visibility and pickup rules. Local selection traces are not
called on remote controller proxies. Held/attached objects are rejected. Requests are rate limited.
The host applies each transfer without yielding; a simultaneous stale request
is rejected. Clients wait for native replication and never create local copies.

The first two-PC 0.7.0 test crashed the host during client RMB storage.
Symbols show allocator corruption surfacing in AItemSaverState::LoadItem; the
original corrupting write is not proven. 0.7.1 removes incoming string mutation
and fixes remote item resolution. A new two-PC test, late join, reconnect and
death/recovery acceptance are still required. Use matching builds for private beta testing.
Restart the game when updating or disabling the pack. Before removing the mod,
retrieve extended-storage contents through the grid: native hotbar alone cannot
reach cells beyond its original size.

## Verified API locations

- /Game/BP/Components/BP_InventoryComponent.BP_InventoryComponent_C:
  AddItemToSlot, GetItemFromSlot, RemoveItem, CanAddItemToSlot,
  ItemCanBeInBackpack, InventoryChange_Event; Slots and SlotsList properties.
- Native PlayerBase GetBackpack/RemoveEquipedItem and controller
  GetItemInHand/RemoveItemInHand. Native ItemWearable Unequip and primary action.
- /Script/Engine.PlayerController:ServerExecRPC, authority-side request hook.
- /Game/Inputs/PIE/IMC_Player.IMC_Player with FistMode input action;
  InputMappingContext.UnmapKey/MapKey and EnhancedInputLibrary rebuild.
- /Game/BP/Garage/PaintStation/UI/ColorElement.ColorElement_C:
  OnMouseButtonDown/OnMouseButtonUp, restricted to our own transparent instance.
  Its original widget tree is retained to receive Slate mouse events. Pointer
  event coordinates go through SlateBlueprintLibrary.AbsoluteToViewport; polling
  mouse position after an event is too late for quick drags. No native art ships.
- HUD ActionBox parent VerticalBox: a prompt is inserted directly after Take,
  retaining existing children and their layout settings. No HUD tick hook.
- InteractSecondary mapping temporarily borrows RightMouseButton for direct
  pickup, then restores it when the context ends or on reset.
- ItemBaseMaster CanBePickedUp/CanBePickedUpFromGround, GetAttachParentActor;
  controller ItemTargeted/GetItemSelected validate direct pickup on the host.
- Existing queued game-thread loop; no additional timer/thread loop.

UE4SS native map operations are documented at
https://docs.ue4ss.com/dev/lua-api/classes/tmap.html and object construction at
https://docs.ue4ss.com/lua-api/global-functions/staticconstructobject.html.
See TEST-RESULTS.txt for actual live evidence and outstanding checks.

1.0.3 update: Melee bindings are editable in F9 Controls. Hangar rifle ammo is
30 rounds for $300. Small zombie drops contain 3 rifle rounds; uncommon loot-site
cartons contain 6. Native ammo type, pickup and saved counts remain in use.
