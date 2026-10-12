--
-- CameraMotionOffset
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

CameraMotionOffset = {}

local CameraMotionOffset_mt = Class(CameraMotionOffset)

---Creates a new CameraMotionOffset instance
-- @return table New instance of CameraMotionOffset
-- @includeCode
function CameraMotionOffset.new()
  local self = setmetatable({}, CameraMotionOffset_mt)

  self.state = {}

  return self
end

---Gets the current camera from state
-- @return any Current camera or nil
-- @includeCode
function CameraMotionOffset:getCamera()
  return self.state.camera
end

---Gets the camera node from the current camera
-- @return any Camera node or nil
-- @includeCode
function CameraMotionOffset:getCameraNode()
  local camera = self.state.camera

  return camera ~= nil and camera.cameraNode or nil
end

---Restores the camera to its previous state
-- @includeCode
function CameraMotionOffset:restore()
  local state = self.state

  if state.camera ~= nil then
    if state.node ~= nil and entityExists(state.node) then
      setTranslation(state.node, state.x, state.y, state.z)
    end

    if state.rotX ~= nil and entityExists(state.camera.cameraNode) then
      setRotation(state.camera.cameraNode, state.rotX, state.rotY, state.rotZ)
    end

    state.camera = nil
    state.node = nil
    state.rotX = nil
  end
end

---Applies pitch offset to the camera
-- @param any camera Camera object
-- @param table offset Offset data
-- @includeCode
function CameraMotionOffset:applyPitch(camera, offset)
  if offset.pitch ~= 0 then
    local state = self.state
    state.camera = camera
    state.rotX, state.rotY, state.rotZ = getRotation(camera.cameraNode)

    setWorldRotation(camera.cameraNode, localRotationToWorld(camera.cameraNode, math.rad(offset.pitch), 0, 0))
  end
end

---Applies camera offset adjustments
-- @param table camera Camera object
-- @param table offset Offset values
-- @param boolean initialize Whether native camera smoothing should be synchronized
-- @includeCode
function CameraMotionOffset:apply(camera, offset, initialize)
  local hasOffset = offset.x ~= 0 or offset.y ~= 0 or offset.z ~= 0

  if hasOffset then
    local isCameraNodeOffset = camera.isInside or camera.rotateNode == camera.cameraPositionNode
    local node = camera.rotateNode
    local x, y, z = -offset.x, offset.y, offset.z

    if isCameraNodeOffset then
      node = camera.cameraNode
      x, y, z = localDirectionToLocal(getParent(camera.rotateNode), getParent(node), x, y, z)
    end

    local baseX, baseY, baseZ = getTranslation(node)
    local state = self.state
    state.camera, state.node = camera, node
    state.x, state.y, state.z = baseX, baseY, baseZ
    setTranslation(node, baseX + x, baseY + y, baseZ + z)

    if initialize and not isCameraNodeOffset then
      self:synchronizeCameraPose(camera)
    end
  end
end

---Initializes native camera smoothing from the current pose, same as VehicleCamera:onActivate
-- @param table camera Camera object to synchronize
-- @includeCode
function CameraMotionOffset:synchronizeCameraPose(camera)
  if camera.positionSmoothingParameter > 0 then
    local x, y, z = getWorldTranslation(camera.cameraPositionNode)
    camera.position[1], camera.position[2], camera.position[3] = x, y, z
    camera.lastTargetPosition[1], camera.lastTargetPosition[2], camera.lastTargetPosition[3] = x, y, z

    x, y, z = getWorldTranslation(camera.rotateNode)
    x, y, z = x + (camera.offsetX or 0), y + (camera.offsetY or 0), z + (camera.offsetZ or 0)
    camera.lookAtPosition[1], camera.lookAtPosition[2], camera.lookAtPosition[3] = x, y, z
    camera.lookAtLastTargetPosition[1], camera.lookAtLastTargetPosition[2], camera.lookAtLastTargetPosition[3] = x, y, z

    x, y, z = localDirectionToWorld(camera.rotateNode, camera:getTiltDirectionOffset(), 1, 0)
    camera.upVector[1], camera.upVector[2], camera.upVector[3] = x, y, z
    camera.lastUpVector[1], camera.lastUpVector[2], camera.lastUpVector[3] = x, y, z

    camera:setSeparateCameraPose()
  end
end
