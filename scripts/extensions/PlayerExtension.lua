--
-- PlayerExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

PlayerExtension = {}

---Overwrites game functions for player and camera
-- @param any system System for function overwriting
-- @includeCode
function PlayerExtension:overwriteGameFunctions(system)
  system:overwriteGameFunction(PlayerCamera, "updatePosition", function(superFunc, camera, dt)
    system.motion:restore(camera)
    superFunc(camera, dt)
    system:updatePlayerCamera(camera, dt)
  end)

  system:overwriteGameFunction(Player, "getLookRay", function(superFunc, player)
    return system:getPlayerLookRay(player, superFunc(player))
  end)
end

---
PlayerCamera.delete = Utils.prependedFunction(PlayerCamera.delete, function(camera)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:onCameraReleased(camera)
  end
end)

---
PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function(playerInputComponent, contextName)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:registerGlobalPlayerActionEvents(playerInputComponent, contextName)
  end
end)
