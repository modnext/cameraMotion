--
-- CameraMotionHeadMovement
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

CameraMotionHeadMovement = {}

local CameraMotionHeadMovement_mt = Class(CameraMotionHeadMovement)

---Creates a new CameraMotionHeadMovement instance
-- @return CameraMotionHeadMovement New instance of CameraMotionHeadMovement
-- @includeCode
function CameraMotionHeadMovement.new()
  local self = setmetatable({}, CameraMotionHeadMovement_mt)

  self:reset()

  return self
end

---Resets the camera head movement state
-- @includeCode
function CameraMotionHeadMovement:reset()
  self.state = nil
  self.limitedCamera = nil
  self.leanCameraNode = nil
end

---Checks if head tracking is enabled
-- @param table camera Camera object
-- @return boolean True if head tracking is enabled
-- @includeCode
function CameraMotionHeadMovement:getIsHeadTracking(camera)
  local hasHeadTracking = camera.vehicle ~= nil and camera.allowHeadTracking and camera.headTrackingNode ~= nil

  return hasHeadTracking and g_gameSettings:getValue(GameSettings.SETTING.IS_HEAD_TRACKING_ENABLED) and isHeadTrackingAvailable()
end

---Toggles the lean camera node
-- @param table cameraNode Camera node to toggle
-- @includeCode
function CameraMotionHeadMovement:toggleLean(cameraNode)
  self.leanCameraNode = self.leanCameraNode ~= cameraNode and cameraNode or nil
end

---Sets the lean camera node
-- @param table cameraNode Camera node to set
-- @includeCode
function CameraMotionHeadMovement:setLean(cameraNode)
  self.leanCameraNode = cameraNode
end

---Limits the camera's rotation angles
-- @param table camera Camera object to limit rotation
-- @includeCode
function CameraMotionHeadMovement:limitRotation(camera)
  local maxYaw = math.rad(165)
  local maxPitch = math.rad(65)
  local yaw = camera.rotY - camera.origRotY

  if self.limitedCamera ~= camera then
    yaw = MathUtil.getValidLimit(yaw)
    self.limitedCamera = camera
  end

  camera.rotY = camera.origRotY + math.clamp(yaw, -maxYaw, maxYaw)
  camera.rotX = math.clamp(camera.rotX, camera.origRotX - maxPitch, camera.origRotX + maxPitch)
end

---Smoothly interpolates a value towards a target
-- @param number value Current value to smooth
-- @param number velocity Current velocity of the value
-- @param number target Target value to reach
-- @param number response Response rate for smoothing
-- @param number dt Delta time in seconds
-- @return number New smoothed value
-- @return number New velocity
-- @includeCode
function CameraMotionHeadMovement.smooth(value, velocity, target, response, dt)
  local offset = value - target
  local change = velocity + response * offset
  local decay = math.exp(-response * dt)

  return target + (offset + change * dt) * decay, (velocity - response * change * dt) * decay
end

---Softly limits a value so it approaches but never exceeds the limit
-- @param number value Value to limit
-- @param number limit Maximum absolute result
-- @return number Limited value
-- @includeCode
function CameraMotionHeadMovement.softLimit(value, limit)
  return math.atan(value / limit) * limit * 2 / math.pi
end

---Updates camera head movement based on motion
-- @param table motion Motion data for the camera
-- @param table profile Profile settings for head movement
-- @param number dt Delta time since last update
-- @param boolean useHeadTracking Whether head tracking controls the camera
-- @return table Updated camera position and rotation, nil if head movement is inactive
-- @includeCode
function CameraMotionHeadMovement:update(motion, profile, dt, useHeadTracking)
  local camera = motion.camera
  local isVehicle = camera.vehicle ~= nil
  local isInside = isVehicle and camera.isInside or not isVehicle and camera.isFirstPerson

  if not isInside or useHeadTracking then
    self:reset()
    return nil
  end

  local yaw, pitch, strength = 0, 0, 0

  if isVehicle then
    yaw = camera.rotY - camera.origRotY
    pitch = camera.rotX - camera.origRotX
    strength = profile.headLook
  end

  local head = self.state
  local isNewState = head == nil

  if isNewState then
    head = {
      yaw = yaw,
      pitch = pitch,
      yawVelocity = 0,
      pitchVelocity = 0,
      yawLag = 0,
      pitchLag = 0,
      yawLagVelocity = 0,
      pitchLagVelocity = 0,
      lean = 0,
      leanVelocity = 0,
      x = 0,
      y = 0,
      z = 0,
      velocityX = 0,
      velocityY = 0,
      velocityZ = 0,
      roll = 0,
      rollVelocity = 0,
      strength = strength,
      pose = {},
    }
    self.state = head
  end

  local canLean = profile.lean > 0 and (not profile.leanHold or not g_gui:getIsGuiVisible())

  if not isVehicle then
    local mover = camera.player.mover
    canLean = canLean and mover.isGrounded and not mover.isInWater and not mover.isOnLadder
  end

  if not canLean then
    self.leanCameraNode = nil
  end

  local leanTarget = self.leanCameraNode == motion.cameraNode and profile.lean or 0
  local dtSeconds = dt * 0.001
  head.lean, head.leanVelocity = self.smooth(head.lean, head.leanVelocity, leanTarget, 10, dtSeconds)

  if strength == 0 or head.strength == 0 then
    head.yaw, head.pitch = yaw, pitch
    head.yawVelocity, head.pitchVelocity = 0, 0
    head.yawLag, head.pitchLag = 0, 0
    head.yawLagVelocity, head.pitchLagVelocity = 0, 0

    if strength == 0 then
      self.limitedCamera = nil
    end
  else
    local lookResponse = 18
    head.yaw, head.yawVelocity = self.smooth(head.yaw, head.yawVelocity, yaw, lookResponse, dtSeconds)
    head.pitch, head.pitchVelocity = self.smooth(head.pitch, head.pitchVelocity, pitch, lookResponse, dtSeconds)
  end

  head.strength = strength

  local isBodyActive = isVehicle and strength > 0
  local referenceNode = isVehicle and motion.mountNode or getRootNode()
  local lookX, _, lookZ = localDirectionToLocal(motion.cameraNode, referenceNode, 0, 0, -1)
  local heading = math.atan2(lookX, lookZ)
  local leanDistance = 0.48 * head.lean
  local targetX = math.sin(heading) * leanDistance
  local targetY = -0.05 * head.lean
  local targetZ = math.cos(heading) * leanDistance
  local targetRoll = 0

  if isBodyActive then
    local sinYaw, cosYaw = math.sin(yaw), math.cos(yaw)
    local shoulder = MathUtil.smoothstep(math.rad(65), math.rad(150), math.abs(yaw))
    local side = sinYaw * 0.09 + (yaw < 0 and -1 or 1) * shoulder * 0.12
    local forward = (cosYaw - 1) * 0.09 + shoulder * 0.035

    local bodyStrength = strength / (0.4 + 0.6 * strength)
    local seatHeading = heading - yaw
    local sinHeading, cosHeading = math.sin(seatHeading), math.cos(seatHeading)
    targetX = targetX + (cosHeading * side + sinHeading * forward) * bodyStrength
    targetY = targetY + ((math.cos(pitch) - 1) * 0.08 - shoulder * 0.025) * bodyStrength
    targetZ = targetZ + (-sinHeading * side + cosHeading * forward) * bodyStrength
    targetRoll = -sinYaw * math.rad(1) * bodyStrength
  end

  targetX, targetY, targetZ = MathUtil.vector3Clamp(targetX, targetY, targetZ, 0, 0.4 * math.max(1, head.lean))

  if isNewState then
    head.x, head.y, head.z = targetX, targetY, targetZ
    head.roll = targetRoll
  end

  local bodyResponse = 12
  head.x, head.velocityX = self.smooth(head.x, head.velocityX, targetX, bodyResponse, dtSeconds)
  head.y, head.velocityY = self.smooth(head.y, head.velocityY, targetY, bodyResponse, dtSeconds)
  head.z, head.velocityZ = self.smooth(head.z, head.velocityZ, targetZ, bodyResponse, dtSeconds)
  head.roll, head.rollVelocity = self.smooth(head.roll, head.rollVelocity, targetRoll, bodyResponse, dtSeconds)

  local rotX, rotY, rotZ = 0, 0, 0

  if isBodyActive then
    local lagResponse = 24
    local yawLag = self.softLimit((head.yaw - yaw) * 0.35 * strength, math.rad(3))
    local pitchLag = self.softLimit((head.pitch - pitch) * 0.35 * strength, math.rad(2))
    head.yawLag, head.yawLagVelocity = self.smooth(head.yawLag, head.yawLagVelocity, yawLag, lagResponse, dtSeconds)
    head.pitchLag, head.pitchLagVelocity = self.smooth(head.pitchLag, head.pitchLagVelocity, pitchLag, lagResponse, dtSeconds)

    local yawRotX, yawRotY, yawRotZ = localDirectionToLocal(referenceNode, motion.cameraNode, 0, head.yawLag, 0)
    local pitchRotX, pitchRotY, pitchRotZ = localDirectionToLocal(camera.rotateNode, motion.cameraNode, head.pitchLag, 0, 0)
    rotX, rotY, rotZ = yawRotX + pitchRotX, yawRotY + pitchRotY, yawRotZ + pitchRotZ
  end

  local pose = head.pose
  pose.x, pose.y, pose.z = localDirectionToLocal(referenceNode, motion.cameraNode, head.x, head.y, head.z)
  pose.rotX, pose.rotY, pose.rotZ = rotX, rotY, rotZ + head.roll

  return pose
end
