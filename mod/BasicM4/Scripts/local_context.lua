-- UEHelpers in the pinned loader can select the first remote controller.
-- Select the actual local controller, retaining the human while driving.
return function(valid)
 local H={};local controller
 function H.GetPlayerController()
  if valid(controller)and controller:IsLocalPlayerController()then return controller end
  controller=nil
  for _,pc in ipairs(FindAllOf('PlayerController')or{})do
   if valid(pc)and pc:IsLocalPlayerController()then controller=pc;return pc end
  end
 end
 function H.GetPlayer()
  local pc=H.GetPlayerController();if not pc then return end
  if valid(pc.PlayerControlled)then return pc.PlayerControlled end
  return pc.Pawn
 end
 function H.GetWorld()
  local pc=H.GetPlayerController();return pc and pc:GetWorld()
 end
 -- Alpha 25781648 creates the component at runtime and renamed its player
 -- property. The main-menu controller and legacy builds keep the old name.
 -- Both references point to the same native menu implementation; never cache
 -- a missing component across loading or replace its multiplayer pause logic.
 function H.GetMenuComponent(pc)
  pc=pc or H.GetPlayerController();if not valid(pc)then return end
  local menu=pc['BP Menu Component'];if valid(menu)then return menu end
  menu=pc.BP_MenuComponent;if valid(menu)then return menu end
 end
 function H.IsPauseMenu(pc)
  local menu=H.GetMenuComponent(pc)
  if not menu then return true end
  return menu:GetIsPauseMenu()
 end
 function H.reset()controller=nil end
 return H
end
