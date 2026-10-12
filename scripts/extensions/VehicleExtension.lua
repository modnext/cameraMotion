--
-- VehicleExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

VehicleExtension = {}

---Overwrites game functions for vehicle camera
-- @param any system System to manage camera functions
-- @includeCode
function VehicleExtension:overwriteGameFunctions(system)
  system:overwriteGameFunction(VehicleCamera, "update", function(superFunc, camera, dt)
    if not camera.vehicle:isa(Vehicle) then
      return superFunc(camera, dt)
    end

    system.motion:restore(camera)
    system:restoreVehicleCameraOffset(camera)

    local hasSeparatePivot = not camera.isInside and camera.rotateNode ~= camera.cameraPositionNode
    if hasSeparatePivot then
      system:applyVehicleCameraOffset(camera)
    end

    superFunc(camera, dt)

    if not hasSeparatePivot then
      system:applyVehicleCameraOffset(camera)
    end

    system:updateVehicleCamera(camera, dt)
  end)
end

---
VehicleCamera.updateRotateNodeRotation = Utils.prependedFunction(VehicleCamera.updateRotateNodeRotation, function(camera)
  if g_modIsLoaded[modName] and camera.vehicle:isa(Vehicle) then
    g_cameraMotionSystem:limitVehicleHeadRotation(camera)
  end
end)

---
VehicleCamera.onActivate = Utils.appendedFunction(VehicleCamera.onActivate, function(camera)
  if g_modIsLoaded[modName] and camera.vehicle:isa(Vehicle) then
    local system = g_cameraMotionSystem
    local profile = system.settings:getProfile(CameraMotionSystem.getCameraProfileKey(camera))
    local canSynchronize = profile.enabled and not system.headMovement:getIsHeadTracking(camera)

    if canSynchronize then
      camera:updateRotateNodeRotation()
      system.offset:synchronizeCameraPose(camera)
    end

    system:applyVehicleCameraOffset(camera, true)
    system:updateVehicleCamera(camera, 0)
  end
end)

---
VehicleCamera.onDeactivate = Utils.prependedFunction(VehicleCamera.onDeactivate, function(camera)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:onCameraReleased(camera, true)
  end
end)

---
VehicleCamera.resetCamera = Utils.prependedFunction(VehicleCamera.resetCamera, function(camera)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:onCameraReleased(camera)
  end
end)

---
VehicleCamera.delete = Utils.prependedFunction(VehicleCamera.delete, function(camera)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:onCameraReleased(camera)
  end
end)
