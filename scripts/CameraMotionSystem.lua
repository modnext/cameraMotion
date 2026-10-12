--
-- CameraMotionSystem
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName
local modDirectory = g_currentModDirectory

CameraMotionSystem = {}

source(modDirectory .. "scripts/misc/CameraMotionSettings.lua")
source(modDirectory .. "scripts/camera/CameraMotionHeadMovement.lua")
source(modDirectory .. "scripts/camera/CameraMotion.lua")
source(modDirectory .. "scripts/camera/CameraMotionOffset.lua")
source(modDirectory .. "scripts/extensions/VehicleExtension.lua")
source(modDirectory .. "scripts/extensions/PlayerExtension.lua")
source(modDirectory .. "scripts/gui/CameraMotionDialog.lua")

local CameraMotionSystem_mt = Class(CameraMotionSystem)

---Creates a new CameraMotionSystem instance
-- @return CameraMotionSystem The new instance
-- @includeCode
function CameraMotionSystem.new()
  local self = setmetatable({}, CameraMotionSystem_mt)

  self.isClient = false
  self.isInitialized = false
  self.overwrittenGameFunctions = {}

  self.headMovement = CameraMotionHeadMovement.new()
  self.motion = CameraMotion.new(self.headMovement)
  self.offset = CameraMotionOffset.new()

  self.settings = CameraMotionSettings.new(self)

  return self
end

---Initializes the CameraMotionSystem
-- @includeCode
function CameraMotionSystem:initialize()
  if self.isInitialized then
    return
  end

  VehicleExtension:overwriteGameFunctions(self)
  PlayerExtension:overwriteGameFunctions(self)

  self.isInitialized = true
end

---Loads the map for the CameraMotionSystem
-- @includeCode
function CameraMotionSystem:loadMap()
  if not g_modIsLoaded[modName] then
    return
  end

  self.isClient = g_currentMission:getIsClient()
  self:resetMotion()
  self:restoreVehicleCameraOffset()

  if self.isClient then
    self.settings:load()
  end
end

---Updates the camera system each frame
-- @param number dt Delta time
-- @includeCode
function CameraMotionSystem:update(dt)
  if not g_modIsLoaded[modName] then
    return
  end

  local motionCameraNode = self.motion:getCameraNode()

  if motionCameraNode ~= nil and not self:getCanUpdateCamera(motionCameraNode) then
    self:resetMotion()
  end

  local offsetCameraNode = self.offset:getCameraNode()

  if offsetCameraNode ~= nil and not self:getIsActiveCameraNode(offsetCameraNode) then
    self:restoreVehicleCameraOffset()
  end
end

---Cleans up the CameraMotionSystem resources
-- @includeCode
function CameraMotionSystem:deleteMap()
  if self.isClient then
    self.settings:saveIfDirty()
  end

  self:resetMotion()
  self:restoreVehicleCameraOffset()
  self:unregisterActionEvents()

  for i = #self.overwrittenGameFunctions, 1, -1 do
    local reference = self.overwrittenGameFunctions[i]
    reference.object[reference.funcName] = reference.oldFunc
    self.overwrittenGameFunctions[i] = nil
  end

  self.isInitialized = false
  self.isClient = false
end

---Restores the vehicle camera offset
-- @param any camera The camera to restore, nil restores any camera
-- @includeCode
function CameraMotionSystem:restoreVehicleCameraOffset(camera)
  local offsetCamera = self.offset:getCamera()
  local canRestore = offsetCamera ~= nil and (camera == nil or offsetCamera == camera)

  if canRestore then
    self.motion:restore(offsetCamera)
    self.offset:restore()
  end
end

---Applies the vehicle camera offset
-- @param any camera The camera to apply offset to
-- @param boolean initialize Whether to initialize the offset
-- @includeCode
function CameraMotionSystem:applyVehicleCameraOffset(camera, initialize)
  if camera ~= g_activeVehicleCamera or not camera.isActivated or not self:getIsActiveCameraNode(camera.cameraNode) then
    return
  end

  self:restoreVehicleCameraOffset()

  local profileKey = CameraMotionSystem.getCameraProfileKey(camera)
  local profile = self.settings:getProfile(profileKey)

  if profile.enabled then
    self.offset:apply(camera, self.settings:getCameraOffset(camera.vehicle, profileKey), initialize)
  end
end

---Gets the profile key for a camera's current perspective
-- @param any camera Vehicle or player camera
-- @return string Camera profile key
-- @includeCode
function CameraMotionSystem.getCameraProfileKey(camera)
  if camera.vehicle ~= nil then
    return camera.isInside and CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON or CameraMotionSettings.PROFILE.VEHICLE_THIRD_PERSON
  else
    return camera.isFirstPerson and CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON or CameraMotionSettings.PROFILE.PLAYER_THIRD_PERSON
  end
end

---Gets the active camera profile key
-- @return string The active profile key or nil
-- @includeCode
function CameraMotionSystem:getActiveProfileKey()
  local cameraNode = g_cameraManager ~= nil and g_cameraManager.activeCameraNode or nil

  if cameraNode == nil then
    return nil
  end

  local vehicleCamera = g_activeVehicleCamera

  if vehicleCamera ~= nil and vehicleCamera.cameraNode == cameraNode and vehicleCamera.vehicle:isa(Vehicle) then
    return CameraMotionSystem.getCameraProfileKey(vehicleCamera)
  elseif g_localPlayer ~= nil and g_localPlayer.camera ~= nil then
    local camera = g_localPlayer.camera

    if cameraNode == camera.firstPersonCamera then
      return CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON
    elseif cameraNode == camera.thirdPersonCamera then
      return CameraMotionSettings.PROFILE.PLAYER_THIRD_PERSON
    end
  end

  return nil
end

---Gets the first vehicle camera matching the requested perspective
-- @param Vehicle vehicle Vehicle whose cameras should be searched
-- @param boolean isInside Whether an inside camera is requested
-- @return integer Camera index or nil if no matching camera is available
-- @includeCode
function CameraMotionSystem.getVehicleCameraIndex(vehicle, isInside)
  local spec = vehicle ~= nil and vehicle.spec_enterable or nil

  if spec == nil then
    return nil
  end

  for index, camera in ipairs(spec.cameras) do
    if camera.isInside == isInside then
      return index
    end
  end

  return nil
end

---Checks if the player camera is free from target overrides, conversation and flight control
-- @param PlayerCamera camera Player camera
-- @return boolean True if camera effects and perspective changes are allowed
-- @includeCode
function CameraMotionSystem.getCanUsePlayerCamera(camera)
  return not camera:getHasOverriddenTarget() and not camera.isInConversation and not camera.player.mover.isFlightActive
end

---Switches camera based on profile key
-- @param string profileKey The profile key to switch to
-- @includeCode
function CameraMotionSystem:switchCameraForProfile(profileKey)
  local activeProfileKey = self:getActiveProfileKey()

  if not self.isClient or activeProfileKey == nil or activeProfileKey == profileKey then
    return
  end

  local isVehicleProfile = profileKey == CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON or profileKey == CameraMotionSettings.PROFILE.VEHICLE_THIRD_PERSON
  local isPlayerProfile = profileKey == CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON or profileKey == CameraMotionSettings.PROFILE.PLAYER_THIRD_PERSON

  if isVehicleProfile then
    if table.hasElement(CameraMotionSettings.VEHICLE_PROFILE_ORDER, activeProfileKey) then
      local vehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or g_activeVehicleCamera.vehicle
      local index = CameraMotionSystem.getVehicleCameraIndex(vehicle, profileKey == CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON)

      if index ~= nil then
        vehicle:setActiveCameraIndex(index)
      end
    end
  elseif isPlayerProfile then
    local isPlayerCamera = activeProfileKey == CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON or activeProfileKey == CameraMotionSettings.PROFILE.PLAYER_THIRD_PERSON

    if isPlayerCamera then
      local player = g_localPlayer
      local camera = player.camera
      local canSwitchCamera = player.isOwner and CameraMotionSystem.getCanUsePlayerCamera(camera)

      if canSwitchCamera then
        camera:switchToPerspective(profileKey == CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON)
      end
    end
  end
end

---Resets the camera motion if profile matches
-- @param string profileKey Key for camera profile
-- @includeCode
function CameraMotionSystem:resetMotion(profileKey)
  if profileKey == nil or self.motion:getProfileKey() == profileKey then
    self.motion:reset()
  end
end

---Handles camera release and resets motion
-- @param any camera The camera being released
-- @param boolean preserveVehicleMotion Whether to keep vehicle motion
-- @includeCode
function CameraMotionSystem:onCameraReleased(camera, preserveVehicleMotion)
  if self.motion:getCamera() == camera then
    self.motion:reset(preserveVehicleMotion)
  end

  self:restoreVehicleCameraOffset(camera)
end

---Sets the active camera and resets if changed
-- @param any cameraNode Node of the camera
-- @includeCode
function CameraMotionSystem:onSetActiveCamera(cameraNode)
  if self.motion:getCameraNode() ~= cameraNode then
    self.motion:reset(true)
  end

  if self.offset:getCameraNode() ~= cameraNode then
    self:restoreVehicleCameraOffset()
  end
end

---Gets the player's look ray from the camera
-- @param any player The player object
-- @param number x X position
-- @param number y Y position
-- @param number z Z position
-- @param number dx Direction X
-- @param number dy Direction Y
-- @param number dz Direction Z
-- @return number Updated x, y, z, dx, dy, dz values
-- @includeCode
function CameraMotionSystem:getPlayerLookRay(player, x, y, z, dx, dy, dz)
  if player ~= g_localPlayer then
    return x, y, z, dx, dy, dz
  end

  local cameraNode = self.motion:getAppliedCameraNode(player.camera)

  if cameraNode ~= nil then
    if player.camera.isFirstPerson then
      x, y, z = getWorldTranslation(cameraNode)
    end

    dx, dy, dz = localDirectionToWorld(cameraNode, 0, 0, -1)
  end

  return x, y, z, dx, dy, dz
end

---Checks if the given camera node is active
-- @param any cameraNode The camera node to check
-- @return boolean True if active, else false
-- @includeCode
function CameraMotionSystem:getIsActiveCameraNode(cameraNode)
  local isAvailable = self.isClient and g_currentMission ~= nil and g_cameraManager ~= nil and cameraNode ~= nil

  return isAvailable and g_cameraManager.activeCameraNode == cameraNode and entityExists(cameraNode)
end

---Checks if the camera can be updated
-- @param any cameraNode Node of the camera
-- @return boolean True if camera can update
-- @includeCode
function CameraMotionSystem:getCanUpdateCamera(cameraNode)
  if not self:getIsActiveCameraNode(cameraNode) then
    return false
  end

  local isCabCamera = g_activeVehicleCamera ~= nil and g_activeVehicleCamera.isInside and g_activeVehicleCamera.cameraNode == cameraNode

  if isCabCamera and g_gui:getIsDialogVisible() then
    return true
  else
    local isMissionRunning = g_currentMission.isRunning and not g_currentMission.paused and not g_currentMission.isPlayerFrozen
    local isGuiReady = not g_gui:getIsGuiVisible()

    if isMissionRunning and not isGuiReady then
      local isSettingsDialog = g_gui.currentListener ~= nil and g_gui.currentListener == g_gui.guis.CameraMotionDialog
      isGuiReady = isSettingsDialog and not g_gui:getIsMenuVisible()
    end

    return isMissionRunning and isGuiReady
  end
end

---Updates the vehicle camera based on state
-- @param Camera camera The camera to update
-- @param number dt Delta time
-- @includeCode
function CameraMotionSystem:updateVehicleCamera(camera, dt)
  if camera ~= g_activeVehicleCamera or not camera.isActivated then
    return
  end

  local profileKey = CameraMotionSystem.getCameraProfileKey(camera)
  local profile = self.settings:getProfile(profileKey)

  if profile.enabled and self:getIsActiveCameraNode(camera.cameraNode) then
    self.offset:applyPitch(camera, self.settings:getCameraOffset(camera.vehicle, profileKey))
  end

  self:updateCamera(camera, camera.cameraNode, profileKey, profile, dt)
end

---Limits head rotation for vehicle camera
-- @param Camera camera The camera to limit
-- @includeCode
function CameraMotionSystem:limitVehicleHeadRotation(camera)
  if camera ~= g_activeVehicleCamera or not camera.isActivated or not camera.isInside then
    return
  end

  local profile = self.settings:getProfile(CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON)

  local canMoveHead = profile.enabled and profile.headLook > 0 and self:getCanUpdateCamera(camera.cameraNode) and not self.headMovement:getIsHeadTracking(camera)

  if canMoveHead then
    self.headMovement:limitRotation(camera)
  end
end

---Updates the player camera based on state
-- @param Camera camera The camera to update
-- @param number dt Delta time
-- @includeCode
function CameraMotionSystem:updatePlayerCamera(camera, dt)
  if camera.player ~= g_localPlayer or not camera.player.isOwner then
    return
  end

  if CameraMotionSystem.getCanUsePlayerCamera(camera) then
    local profileKey = CameraMotionSystem.getCameraProfileKey(camera)
    local profile = self.settings:getProfile(profileKey)
    self:updateCamera(camera, camera:getCurrentCameraNode(), profileKey, profile, dt)
  elseif self.motion:getCamera() == camera then
    self:resetMotion()
  end
end

---Updates the camera with given parameters
-- @param Camera camera The camera to update
-- @param Node cameraNode The camera node
-- @param string profileKey Profile key for settings
-- @param table profile Profile settings
-- @param number dt Delta time
-- @includeCode
function CameraMotionSystem:updateCamera(camera, cameraNode, profileKey, profile, dt)
  if self:getCanUpdateCamera(cameraNode) then
    self.motion:update(camera, cameraNode, profileKey, profile, dt)
  else
    self:resetMotion()
  end
end

---Registers global player action events
-- @param PlayerInputComponent playerInputComponent Input component for player
-- @param string contextName Context name for actions
-- @includeCode
function CameraMotionSystem:registerGlobalPlayerActionEvents(playerInputComponent, contextName)
  if not playerInputComponent.player.isOwner then
    return
  end

  local inputBinding = g_inputBinding
  local currentContextName = inputBinding:getContextName()
  local targetContextName = contextName or currentContextName
  local isDifferentContext = currentContextName ~= targetContextName

  if isDifferentContext then
    inputBinding:beginActionEventsModification(targetContextName)
  end

  local _, leanEventId = inputBinding:registerActionEvent(InputAction.CAMERA_MOTION_LEAN_TOGGLE, self, self.onLeanAction, true, true, false, true)
  inputBinding:setActionEventTextVisibility(leanEventId, false)

  local _, actionEventId = inputBinding:registerActionEvent(InputAction.CAMERA_MOTION_SETTINGS, self, self.onOpenSettingsAction, false, true, false, true)
  inputBinding:setActionEventTextVisibility(actionEventId, false)

  if isDifferentContext then
    inputBinding:beginActionEventsModification(currentContextName)
  end
end

---Handles lean action for camera movement
-- @param any _ Unused parameter
-- @param number inputValue Input value for lean action
-- @includeCode
function CameraMotionSystem:onLeanAction(_, inputValue)
  local profileKey = self:getActiveProfileKey()
  local isFirstPersonProfile = profileKey == CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON or profileKey == CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON

  if not isFirstPersonProfile then
    return
  end

  local profile = self.settings:getProfile(profileKey)

  if inputValue == 1 then
    local cameraNode = self.motion:getCameraNode()
    local camera = self.motion:getCamera()
    local canLean = profile.enabled and profile.lean > 0 and self:getCanUpdateCamera(cameraNode) and not g_gui:getIsGuiVisible()

    if canLean and not self.headMovement:getIsHeadTracking(camera) then
      if profile.leanHold then
        self.headMovement:setLean(cameraNode)
      else
        self.headMovement:toggleLean(cameraNode)
      end
    end
  elseif profile.leanHold then
    self.headMovement:setLean(nil)
  end
end

---Opens the camera settings dialog
-- @includeCode
function CameraMotionSystem:onOpenSettingsAction()
  if self.isClient and not g_gui:getIsGuiVisible() then
    CameraMotionDialog.show(self:getActiveProfileKey())
  end
end

---Unregisters action events for the system
-- @includeCode
function CameraMotionSystem:unregisterActionEvents()
  if g_inputBinding ~= nil then
    g_inputBinding:removeActionEventsByTarget(self)
  end
end

---Overwrites a game function with a new one
-- @param table object Class or object whose function is overwritten
-- @param string funcName Name of the function to overwrite
-- @param function newFunc Replacement receiving the original function followed by its arguments
-- @includeCode
function CameraMotionSystem:overwriteGameFunction(object, funcName, newFunc)
  if object == nil then
    Logging.error("Failed to overwrite '%s'", funcName)
    printCallstack()
  else
    local oldFunc = object[funcName]

    if oldFunc ~= nil then
      object[funcName] = function(...)
        return newFunc(oldFunc, ...)
      end
    end

    table.insert(self.overwrittenGameFunctions, {
      object = object,
      funcName = funcName,
      oldFunc = oldFunc,
    })
  end
end

---Global instance of CameraMotionSystem
g_cameraMotionSystem = CameraMotionSystem.new()
addModEventListener(g_cameraMotionSystem)

---
CameraManager.setActiveCamera = Utils.appendedFunction(CameraManager.setActiveCamera, function(_, cameraNode)
  if g_modIsLoaded[modName] then
    g_cameraMotionSystem:onSetActiveCamera(cameraNode)
  end
end)

---
TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, function(typeManager)
  if typeManager.typeName == "vehicle" and g_modIsLoaded[modName] and g_iconGenerator == nil then
    g_cameraMotionSystem:initialize()
  end
end)
