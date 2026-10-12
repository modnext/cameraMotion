--
-- CameraMotion
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

CameraMotion = {}

local CameraMotion_mt = Class(CameraMotion)

---Creates a new CameraMotion instance
-- @param any headMovement Head movement settings
-- @return CameraMotion New instance of CameraMotion
-- @includeCode
function CameraMotion.new(headMovement)
  local self = setmetatable({}, CameraMotion_mt)

  self.state = nil
  self.vehicleMotion = nil
  self.headMovement = headMovement

  return self
end

---Gets the current camera from motion
-- @return any Current camera or nil
-- @includeCode
function CameraMotion:getCamera()
  local motion = self.state or self.vehicleMotion

  return motion ~= nil and motion.camera or nil
end

---Gets the camera node from motion
-- @return any Camera node or nil
-- @includeCode
function CameraMotion:getCameraNode()
  local motion = self.state or self.vehicleMotion

  return motion ~= nil and motion.cameraNode or nil
end

---Gets the profile key from motion
-- @return any Profile key or nil
-- @includeCode
function CameraMotion:getProfileKey()
  local motion = self.state or self.vehicleMotion

  return motion ~= nil and motion.profileKey or nil
end

---Gets applied camera node if conditions met
-- @param any camera Camera to check
-- @return any Applied camera node or nil
-- @includeCode
function CameraMotion:getAppliedCameraNode(camera)
  local motion = self.state
  local isApplied = motion ~= nil and motion.camera == camera and motion.isApplied

  return isApplied and motion.cameraNode or nil
end

---Restores the camera to its base position
-- @param any camera The camera to restore, nil restores any camera
-- @includeCode
function CameraMotion:restore(camera)
  local motion = self.state
  local canRestore = motion ~= nil and motion.isApplied and (camera == nil or motion.camera == camera)

  if canRestore then
    if entityExists(motion.cameraNode) then
      setTranslation(motion.cameraNode, motion.baseX, motion.baseY, motion.baseZ)
      setRotation(motion.cameraNode, motion.baseRotX, motion.baseRotY, motion.baseRotZ)
    end

    motion.isApplied = false
  end
end

---Resets the camera motion state
-- @param boolean preserveVehicleMotion Whether to keep vehicle motion
-- @includeCode
function CameraMotion:reset(preserveVehicleMotion)
  self:restore()

  if not preserveVehicleMotion then
    self.vehicleMotion = nil
  elseif self.state ~= nil then
    self.vehicleMotion = self.state.camera.vehicle ~= nil and self.state or nil
  end

  self.state = nil

  self.headMovement:reset()
end

---Gets the nodes and world position the camera motion is measured from
-- @param any camera Vehicle or player camera
-- @return any Reference node defining the forward direction
-- @return any Node the camera is mounted to
-- @return any Node used to measure the look rotation
-- @return number World X, Y and Z position of the mount
-- @includeCode
function CameraMotion.getMountTransform(camera)
  if camera.vehicle ~= nil then
    local referenceNode = camera.vehicle.directionReferenceNode or camera.vehicle.rootNode
    local mountNode = getParent(camera.rotateNode)

    if mountNode == 0 then
      mountNode = referenceNode
    end

    return referenceNode, mountNode, mountNode, getWorldTranslation(mountNode)
  else
    return camera.yawNode, camera.player.mover.movementDirectionNode, getRootNode(), camera.player:getGraphicalPosition()
  end
end

---Gets the target cab pitch and roll from the mount orientation
-- @param number forwardX World X of the mount forward direction
-- @param number forwardY World Y of the mount forward direction
-- @param number forwardZ World Z of the mount forward direction
-- @param number upX World X of the mount up direction
-- @param number upY World Y of the mount up direction
-- @param number upZ World Z of the mount up direction
-- @return number Target pitch or nil if the mount points straight up or down
-- @return number Target roll or nil if the mount points straight up or down
-- @includeCode
function CameraMotion.getCabTiltTarget(forwardX, forwardY, forwardZ, upX, upY, upZ)
  local horizontalForward = MathUtil.vector2Length(forwardX, forwardZ)

  if horizontalForward > 0.001 then
    local maxTilt = math.rad(60)
    local headingX, headingZ = forwardX / horizontalForward, forwardZ / horizontalForward
    local pitch = math.clamp(math.atan2(forwardY, horizontalForward), -maxTilt, maxTilt)

    local sinPitch, cosPitch = math.sin(pitch), math.cos(pitch)
    local rollSin = upZ * headingX - upX * headingZ
    local rollCos = upY * cosPitch - (upX * headingX + upZ * headingZ) * sinPitch

    return pitch, math.clamp(math.atan2(rollSin, rollCos), -maxTilt, maxTilt)
  else
    return nil, nil
  end
end

---Checks if the player mover allows camera bobbing
-- @param PlayerMover mover Player mover
-- @return boolean True if bobbing can be applied
-- @includeCode
function CameraMotion.getCanApplyBobbing(mover)
  return mover.isGrounded and not mover.isInWater and not mover.isOnLadder and g_gameSettings:getValue(GameSettings.SETTING.CAMERA_BOBBING)
end

---Gets the target idle sway strength
-- @param any camera The camera to update
-- @param table motion Current motion state
-- @param table profile Motion profile data
-- @param boolean useHeadTracking Whether head tracking controls the camera
-- @return number Target idle sway strength
-- @includeCode
function CameraMotion.getIdleSwayTarget(camera, motion, profile, useHeadTracking)
  local isVehicle = camera.vehicle ~= nil
  local canSway = profile.idleSway > 0 and not useHeadTracking and (isVehicle or CameraMotion.getCanApplyBobbing(camera.player.mover))

  if not canSway then
    return 0
  elseif profile.idleWhileMoving then
    return profile.idleSway * profile.intensity
  else
    local speed = isVehicle and camera.vehicle:getLastSpeed() / 3.6 or MathUtil.vector3Length(motion.velocityX or 0, motion.velocityY or 0, motion.velocityZ or 0)

    return profile.idleSway * profile.intensity * (1 - MathUtil.smoothstep(0.05, 0.8, speed))
  end
end

---Updates camera motion based on input
-- @param any camera The camera to update
-- @param any cameraNode Node associated with the camera
-- @param string profileKey Key for the motion profile
-- @param table profile Motion profile data
-- @param number dt Delta time since last update
-- @includeCode
function CameraMotion:update(camera, cameraNode, profileKey, profile, dt)
  local maxFrameTime = 250
  local isVehicle = camera.vehicle ~= nil
  local isVehicleClient = isVehicle and g_server == nil
  local isInvalidFrame = dt < 0 or dt > maxFrameTime

  if isInvalidFrame or not profile.enabled and not isVehicle then
    self:reset()
    return
  end

  local referenceNode, mountNode, lookReferenceNode, x, y, z = CameraMotion.getMountTransform(camera)
  local dtSeconds = dt * 0.001
  local movementDt = dtSeconds

  if isVehicle and g_server ~= nil and dt > 0 then
    local physicsDt = camera.vehicle.spec_rideable ~= nil and camera.vehicle.spec_rideable.interpolationDt or g_physicsDt
    movementDt = physicsDt > 0.001 and physicsDt * 0.001 or 0
  end

  if not MathUtil.getIsValidTransformationValue(x, y, z) or movementDt > maxFrameTime * 0.001 then
    self:reset()
    return
  end

  local isInside = isVehicle and camera.isInside or not isVehicle and camera.isFirstPerson
  local useHeadTracking = self.headMovement:getIsHeadTracking(camera)
  local lookX, lookY, lookZ = localDirectionToLocal(cameraNode, lookReferenceNode, 0, 0, -1)
  local motion = self.state

  if motion == nil and not profile.enabled then
    motion = self.vehicleMotion
  end

  if motion ~= nil then
    local hasChangedCamera = motion.camera ~= camera or motion.cameraNode ~= cameraNode or motion.mountNode ~= mountNode

    if hasChangedCamera or g_time - motion.lastTime > maxFrameTime then
      self:reset(motion.camera ~= camera)
      motion = nil
    end
  end

  local sample = motion
  local sampleX, sampleY, sampleZ = x, y, z
  local sampleDt = movementDt

  if motion == nil then
    local previous = self.vehicleMotion
    self.vehicleMotion = nil

    local hasPreviousMotion = isVehicle and previous ~= nil and previous.camera.vehicle == camera.vehicle
    local canReuseMotion = hasPreviousMotion and previous.velocityX ~= nil and entityExists(previous.mountNode) and g_time - previous.lastTime <= maxFrameTime

    if canReuseMotion then
      sample = previous
      sampleX, sampleY, sampleZ = getWorldTranslation(previous.mountNode)
      local elapsed = (g_time - previous.lastTime) * 0.001
      sampleDt = g_server ~= nil and elapsed > 0 and movementDt or elapsed
    end
  end

  if sample ~= nil then
    if dt == 0 or sample.lastUpdateTime == g_time then
      dt, dtSeconds = 0, 0
      movementDt, sampleDt = 0, 0
    end

    local distance = MathUtil.vector3Length(sampleX - sample.lastX, sampleY - sample.lastY, sampleZ - sample.lastZ)
    local speed = MathUtil.vector3Length(sample.velocityX or 0, sample.velocityY or 0, sample.velocityZ or 0)

    if sampleDt < 0 or distance > 2 + speed * sampleDt * 2 then
      self:reset()
      motion, sample = nil, nil
    end
  end

  local initialize = motion == nil
  local forwardX, forwardY, forwardZ, upX, upY, upZ

  if initialize or movementDt > 0 then
    forwardX, forwardY, forwardZ = localDirectionToWorld(mountNode, 0, 0, 1)
    upX, upY, upZ = localDirectionToWorld(mountNode, 0, 1, 0)
  else
    forwardX, forwardY, forwardZ = motion.forwardX, motion.forwardY, motion.forwardZ
    upX, upY, upZ = motion.upX, motion.upY, motion.upZ
  end

  local useWorldRotation = camera.useWorldXZRotation == nil and g_gameSettings:getValue(GameSettings.SETTING.USE_WORLD_CAMERA) or camera.useWorldXZRotation
  local followCabTilt = profile.enabled and isVehicle and isInside and not useHeadTracking and useWorldRotation
  local targetCabPitch, targetCabRoll

  if followCabTilt then
    targetCabPitch, targetCabRoll = CameraMotion.getCabTiltTarget(forwardX, forwardY, forwardZ, upX, upY, upZ)
  end

  if initialize then
    local moverVelocityX, _, moverVelocityZ

    if not isVehicle then
      moverVelocityX, _, moverVelocityZ = camera.player.mover:getVelocity()
    end

    self.state = {
      camera = camera,
      cameraNode = cameraNode,
      profileKey = profileKey,
      mountNode = mountNode,
      lastX = sample ~= nil and x - sampleX + sample.lastX or x,
      lastY = sample ~= nil and y - sampleY + sample.lastY or y,
      lastZ = sample ~= nil and z - sampleZ + sample.lastZ or z,
      lookX = lookX,
      lookY = lookY,
      lookZ = lookZ,
      forwardX = forwardX,
      forwardY = forwardY,
      forwardZ = forwardZ,
      upX = upX,
      upY = upY,
      upZ = upZ,
      lastTime = g_time,
      lastUpdateTime = sample ~= nil and sample.lastUpdateTime or g_time,
      idleTime = math.random() * 60,
      idleBlend = 0,
      moverVelocityX = moverVelocityX,
      moverVelocityZ = moverVelocityZ,
      x = 0,
      y = 0,
      z = 0,
      rotX = 0,
      rotY = 0,
      rotZ = 0,
      cabPitch = targetCabPitch,
      cabRoll = targetCabRoll,
    }

    motion = self.state

    if sample == nil then
      if not profile.enabled then
        self.vehicleMotion = motion
        self.state = nil
      else
        local headPose = self.headMovement:update(motion, profile, dt, useHeadTracking)

        if headPose ~= nil then
          self:applyPose(motion, headPose)
        end
      end

      return
    end
  end

  local velocityX, velocityY, velocityZ
  local accelerationX, accelerationY, accelerationZ

  if sampleDt > 0 then
    velocityX = (sampleX - sample.lastX) / sampleDt
    velocityY = (sampleY - sample.lastY) / sampleDt
    velocityZ = (sampleZ - sample.lastZ) / sampleDt
    local previousVelocityX = sample.velocityX or velocityX
    local previousVelocityY = sample.velocityY or velocityY
    local previousVelocityZ = sample.velocityZ or velocityZ
    local velocityAlpha = 1 - math.exp(-14 * sampleDt)

    motion.velocityX, motion.velocityY, motion.velocityZ = MathUtil.vector3Lerp(previousVelocityX, previousVelocityY, previousVelocityZ, velocityX, velocityY, velocityZ, velocityAlpha)

    accelerationX = (motion.velocityX - previousVelocityX) / sampleDt
    accelerationY = (motion.velocityY - previousVelocityY) / sampleDt
    accelerationZ = (motion.velocityZ - previousVelocityZ) / sampleDt
  else
    velocityX, velocityZ = sample.velocityX or 0, sample.velocityZ or 0
    motion.velocityX, motion.velocityY, motion.velocityZ = sample.velocityX, sample.velocityY, sample.velocityZ
    accelerationX, accelerationY, accelerationZ = sample.accelerationX or 0, sample.accelerationY or 0, sample.accelerationZ or 0
  end

  motion.accelerationX, motion.accelerationY, motion.accelerationZ = accelerationX, accelerationY, accelerationZ

  if isVehicle and movementDt > 0 then
    local _, previousForwardY, previousForwardZ = worldDirectionToLocal(mountNode, motion.forwardX, motion.forwardY, motion.forwardZ)
    local previousUpX, previousUpY, _ = worldDirectionToLocal(mountNode, motion.upX, motion.upY, motion.upZ)
    local pitchRate, rollRate = 0, 0

    if previousForwardZ > 0 and previousUpY > 0 then
      pitchRate = math.asin(math.clamp(previousForwardY, -1, 1)) / movementDt
      rollRate = math.atan2(previousUpX, previousUpY) / movementDt
    end

    if isVehicleClient then
      pitchRate = math.clamp(pitchRate, -2, 2)
      rollRate = math.clamp(rollRate, -2, 2)
      motion.pitchRate, motion.pitchFilterVelocity = CameraMotionHeadMovement.smooth(motion.pitchRate or pitchRate, motion.pitchFilterVelocity or 0, pitchRate, 10, movementDt)
      motion.rollRate, motion.rollFilterVelocity = CameraMotionHeadMovement.smooth(motion.rollRate or rollRate, motion.rollFilterVelocity or 0, rollRate, 10, movementDt)
    else
      motion.pitchRate, motion.rollRate = pitchRate, rollRate
    end
  end

  if movementDt > 0 then
    motion.lastX, motion.lastY, motion.lastZ = x, y, z
    motion.forwardX, motion.forwardY, motion.forwardZ = forwardX, forwardY, forwardZ
    motion.upX, motion.upY, motion.upZ = upX, upY, upZ
  end

  if dtSeconds > 0 then
    motion.lastUpdateTime = g_time
  end

  motion.lastTime = g_time

  if not profile.enabled then
    self.vehicleMotion = motion
    self.state = nil
    return
  end

  accelerationX, accelerationY, accelerationZ = worldDirectionToLocal(referenceNode, accelerationX, accelerationY, accelerationZ)
  accelerationX, accelerationY, accelerationZ = MathUtil.vector3Clamp(accelerationX, accelerationY, accelerationZ, 0, 25)
  local targetInertiaAcceleration = accelerationZ

  if isVehicleClient then
    local signedSpeed = camera.vehicle.lastSignedSpeedReal * 1000
    motion.networkSpeed = motion.networkSpeed or signedSpeed
    motion.networkAccelerationX = motion.networkAccelerationX or accelerationX
    motion.networkAccelerationY = motion.networkAccelerationY or accelerationY
    targetInertiaAcceleration = motion.inertiaAccelerationZ or 0

    if dtSeconds > 0 then
      motion.networkAccelerationX, motion.networkFilterVelocityX = CameraMotionHeadMovement.smooth(motion.networkAccelerationX, motion.networkFilterVelocityX or 0, accelerationX, 10, dtSeconds)
      motion.networkAccelerationY, motion.networkFilterVelocityY = CameraMotionHeadMovement.smooth(motion.networkAccelerationY, motion.networkFilterVelocityY or 0, accelerationY, 10, dtSeconds)

      local previousSpeed = motion.networkSpeed
      motion.networkSpeed = MathUtil.lerp(previousSpeed, signedSpeed, 1 - math.exp(-8 * dtSeconds))
      targetInertiaAcceleration = (motion.networkSpeed - previousSpeed) / dtSeconds
    end

    accelerationX, accelerationY = motion.networkAccelerationX, motion.networkAccelerationY
  elseif isVehicle then
    local nativeAcceleration = camera.vehicle.lastSpeedAcceleration

    if MathUtil.isFinite(nativeAcceleration) then
      targetInertiaAcceleration = nativeAcceleration * 1000000
    end
  else
    local mover = camera.player.mover
    local moverVelocityX, _, moverVelocityZ = mover:getVelocity()

    if dtSeconds > 0 then
      local moverAccelerationX = (moverVelocityX - motion.moverVelocityX) / dtSeconds
      local moverAccelerationZ = (moverVelocityZ - motion.moverVelocityZ) / dtSeconds
      local _, _, longitudinalAcceleration = worldDirectionToLocal(referenceNode, moverAccelerationX, 0, moverAccelerationZ)
      targetInertiaAcceleration = longitudinalAcceleration
    end

    motion.moverVelocityX, motion.moverVelocityZ = moverVelocityX, moverVelocityZ

    if not mover.isGrounded and not motion.wasGrounded then
      accelerationY = 0
    end

    motion.wasGrounded = mover.isGrounded
  end

  targetInertiaAcceleration = math.clamp(targetInertiaAcceleration, -12, 12)
  local currentInertiaAcceleration = motion.inertiaAccelerationZ or targetInertiaAcceleration
  local filterVelocity = motion.inertiaFilterVelocity or 0
  motion.inertiaAccelerationZ, motion.inertiaFilterVelocity = CameraMotionHeadMovement.smooth(currentInertiaAcceleration, filterVelocity, targetInertiaAcceleration, 18, dtSeconds)

  local targetX = -accelerationX * 0.008 * profile.cornering
  local targetY = -accelerationY * 0.004 * profile.terrain
  local targetZ = -motion.inertiaAccelerationZ * 0.006 * profile.inertia
  local targetRotX = -motion.inertiaAccelerationZ * 0.002 * profile.inertia
  local targetRotZ = accelerationX * 0.0025 * profile.cornering
  local targetRotY

  targetX, targetY, targetZ = localDirectionToLocal(referenceNode, cameraNode, targetX, targetY, targetZ)
  targetRotX, targetRotY, targetRotZ = localDirectionToLocal(referenceNode, cameraNode, targetRotX, 0, targetRotZ)

  if isVehicle then
    local rx = -math.clamp(motion.pitchRate or 0, -2, 2) * 0.025 * profile.terrain
    local rz = -math.clamp(motion.rollRate or 0, -2, 2) * 0.035 * profile.terrain
    local terrainX, terrainY, terrainZ = localDirectionToLocal(mountNode, cameraNode, rx, 0, rz)

    targetRotX = targetRotX + terrainX
    targetRotY = targetRotY + terrainY
    targetRotZ = targetRotZ + terrainZ
  else
    local walkX, walkY, walkZ = self:getWalkingOffset(camera.player, motion, dtSeconds, velocityX, velocityZ)
    local walkingRotX, walkingRotY, walkingRotZ = localDirectionToLocal(referenceNode, cameraNode, 0, 0, -walkX * 0.2)
    walkX, walkY, walkZ = localDirectionToLocal(referenceNode, cameraNode, walkX, walkY, walkZ)

    targetX = targetX + walkX * profile.walking
    targetY = targetY + walkY * profile.walking
    targetZ = targetZ + walkZ * profile.walking
    targetRotX = targetRotX + walkingRotX * profile.walking
    targetRotY = targetRotY + walkingRotY * profile.walking
    targetRotZ = targetRotZ + walkingRotZ * profile.walking
  end

  local useNaturalHeadMovement = isVehicle and isInside and profile.headLook > 0

  if dtSeconds > 0 and not useHeadTracking and not useNaturalHeadMovement then
    local previousLookX, previousLookY, previousLookZ = localDirectionToLocal(lookReferenceNode, cameraNode, motion.lookX, motion.lookY, motion.lookZ)

    if previousLookZ < 0 then
      local pitchRate = math.asin(math.clamp(previousLookY, -1, 1)) / dtSeconds
      local yawRate = -math.atan2(previousLookX, -previousLookZ) / dtSeconds

      targetRotX = targetRotX + math.clamp(pitchRate, -6, 6) * 0.018 * profile.headMovement
      targetRotY = targetRotY + math.clamp(yawRate, -6, 6) * 0.012 * profile.headMovement
      targetRotZ = targetRotZ + math.clamp(yawRate, -6, 6) * 0.006 * profile.headMovement
    end
  end

  targetX, targetY, targetZ = targetX * profile.intensity, targetY * profile.intensity, targetZ * profile.intensity
  targetRotX, targetRotY, targetRotZ = targetRotX * profile.intensity, targetRotY * profile.intensity, targetRotZ * profile.intensity

  local idleTarget = CameraMotion.getIdleSwayTarget(camera, motion, profile, useHeadTracking)

  motion.idleTime = motion.idleTime + dtSeconds
  motion.idleBlend = MathUtil.lerp(motion.idleBlend, idleTarget, 1 - math.exp(-3 * dtSeconds))

  local time = motion.idleTime
  local swayX = (math.sin(time * 0.9) * 0.7 + math.sin(time * 1.7) * 0.3) * motion.idleBlend
  local swayY = math.sin(time * 1.4) * motion.idleBlend
  local swayRoll = math.sin(time * 0.73 + 0.6) * motion.idleBlend

  targetX = targetX + swayX * 0.003
  targetY = targetY + swayY * 0.004
  targetRotX = targetRotX + swayY * 0.0032
  targetRotY = targetRotY + swayX * 0.0044
  targetRotZ = targetRotZ + swayRoll * 0.0024

  local maxTranslation = isInside and (isVehicle and 0.06 or 0.04) or 0
  targetX, targetY, targetZ = MathUtil.vector3Clamp(targetX, targetY, targetZ, 0, maxTranslation)
  targetRotX, targetRotY, targetRotZ = MathUtil.vector3Clamp(targetRotX, targetRotY, targetRotZ, 0, math.rad(isInside and 4 or 1.5))

  local poseAlpha = initialize and 1 or 1 - math.exp(-12 * dtSeconds)
  motion.x, motion.y, motion.z = MathUtil.vector3Lerp(motion.x, motion.y, motion.z, targetX, targetY, targetZ, poseAlpha)
  motion.rotX, motion.rotY, motion.rotZ = MathUtil.vector3Lerp(motion.rotX, motion.rotY, motion.rotZ, targetRotX, targetRotY, targetRotZ, poseAlpha)

  if targetCabPitch ~= nil then
    motion.cabPitch, motion.cabRoll = MathUtil.vector2Lerp(motion.cabPitch or targetCabPitch, motion.cabRoll or targetCabRoll, targetCabPitch, targetCabRoll, poseAlpha)
  else
    motion.cabPitch, motion.cabRoll = nil, nil
  end

  motion.lookX, motion.lookY, motion.lookZ = lookX, lookY, lookZ

  local headPose = self.headMovement:update(motion, profile, dt, useHeadTracking)
  self:applyPose(motion, headPose)
end

---Calculates walking offset for the player
-- @param any player The player object
-- @param table motion Current motion state
-- @param number dtSeconds Delta time in seconds
-- @param number velocityX Velocity in X direction
-- @param number velocityZ Velocity in Z direction
-- @return number Offset in X, Y and Z direction relative to the camera yaw node
-- @includeCode
function CameraMotion:getWalkingOffset(player, motion, dtSeconds, velocityX, velocityZ)
  local model = player.graphicsComponent ~= nil and player.graphicsComponent.model or nil
  local headNode = model ~= nil and model.thirdPersonHeadNode or nil

  if headNode == nil or not entityExists(headNode) then
    motion.headNode = nil
    return 0, 0, 0
  end

  local x, y = localToLocal(headNode, model.rootNode, 0, 0, 0)

  if motion.headNode ~= headNode then
    motion.headNode = headNode
    motion.headX, motion.headY = x, y
  end

  motion.headX, motion.headY = MathUtil.vector2Lerp(motion.headX, motion.headY, x, y, 1 - math.exp(-2 * dtSeconds))

  if CameraMotion.getCanApplyBobbing(player.mover) then
    local speedFactor = math.clamp(MathUtil.vector2Length(velocityX, velocityZ) / 1.5, 0, 1)
    local offsetX = math.clamp(x - motion.headX, -0.025, 0.025) * speedFactor
    local offsetY = math.clamp(y - motion.headY, -0.035, 0.035) * speedFactor

    return localDirectionToLocal(model.rootNode, player.camera.yawNode, offsetX, offsetY, 0)
  else
    return 0, 0, 0
  end
end

---Applies cab pitch and roll while preserving the camera's look direction
-- @param table motion Contains pitch and roll values
-- @param any node Node to apply the tilt to
-- @includeCode
function CameraMotion:applyCabTilt(motion, node)
  local pitch, roll = motion.cabPitch, motion.cabRoll
  local hasTilt = pitch ~= nil and math.abs(pitch) + math.abs(roll) >= 0.0001
  local horizontalForward = hasTilt and MathUtil.vector2Length(motion.forwardX, motion.forwardZ) or 0

  if horizontalForward > 0.001 then
    local headingX, headingZ = motion.forwardX / horizontalForward, motion.forwardZ / horizontalForward
    local rightX, rightZ = headingZ, -headingX
    local sinPitch, cosPitch = math.sin(pitch), math.cos(pitch)
    local sinRoll, cosRoll = math.sin(roll), math.cos(roll)

    local pitchedUpX, pitchedUpY, pitchedUpZ = -headingX * sinPitch, cosPitch, -headingZ * sinPitch
    local cabinForwardX, cabinForwardY, cabinForwardZ = headingX * cosPitch, sinPitch, headingZ * cosPitch
    local cabinRightX, cabinRightY, cabinRightZ = rightX * cosRoll + pitchedUpX * sinRoll, pitchedUpY * sinRoll, rightZ * cosRoll + pitchedUpZ * sinRoll
    local cabinUpX, cabinUpY, cabinUpZ = pitchedUpX * cosRoll - rightX * sinRoll, pitchedUpY * cosRoll, pitchedUpZ * cosRoll - rightZ * sinRoll

    local dx, dy, dz = localDirectionToWorld(node, 0, 0, 1)
    local upX, upY, upZ = localDirectionToWorld(node, 0, 1, 0)
    local forwardRight = dx * rightX + dz * rightZ
    local forwardHeading = dx * headingX + dz * headingZ
    local upRight = upX * rightX + upZ * rightZ
    local upHeading = upX * headingX + upZ * headingZ

    dx, dy, dz = MathUtil.vector3Transformation(forwardRight, dy, forwardHeading, cabinRightX, cabinRightY, cabinRightZ, cabinUpX, cabinUpY, cabinUpZ, cabinForwardX, cabinForwardY, cabinForwardZ)
    upX, upY, upZ = MathUtil.vector3Transformation(upRight, upY, upHeading, cabinRightX, cabinRightY, cabinRightZ, cabinUpX, cabinUpY, cabinUpZ, cabinForwardX, cabinForwardY, cabinForwardZ)
    setWorldDirection(node, dx, dy, dz, upX, upY, upZ)
  end
end

---Checks if a raycast hit belongs to the camera's own vehicle
-- @param any camera Inside vehicle camera
-- @param any hitId Node hit by the raycast
-- @return boolean True if the hit node is part of the camera's vehicle
-- @includeCode
function CameraMotion.getIsOwnVehicleHit(camera, hitId)
  local object = g_currentMission:getNodeObject(hitId)
  local isVehicleObject = object ~= nil and (object == camera.vehicle or object.rootVehicle == camera.vehicle.rootVehicle)

  return isVehicleObject or table.hasElement(camera.collisionNodes, hitId)
end

---Applies the calculated pose to the camera
-- @param table motion Current motion state
-- @param table headPose Pose data for head movement
-- @includeCode
function CameraMotion:applyPose(motion, headPose)
  local node = motion.cameraNode
  motion.baseX, motion.baseY, motion.baseZ = getTranslation(node)
  motion.baseRotX, motion.baseRotY, motion.baseRotZ = getRotation(node)

  local offsetX, offsetY, offsetZ = motion.x, motion.y, motion.z
  local rotX, rotY, rotZ = motion.rotX, motion.rotY, motion.rotZ

  if headPose ~= nil then
    offsetX, offsetY, offsetZ = offsetX + headPose.x, offsetY + headPose.y, offsetZ + headPose.z
    rotX, rotY, rotZ = rotX + headPose.rotX, rotY + headPose.rotY, rotZ + headPose.rotZ
  end

  if offsetX ~= 0 or offsetY ~= 0 or offsetZ ~= 0 then
    local x, y, z = localToWorld(node, offsetX, offsetY, offsetZ)
    local originX, originY, originZ = getWorldTranslation(node)
    local dx, dy, dz = x - originX, y - originY, z - originZ
    local distance = MathUtil.vector3Length(dx, dy, dz)

    if distance > 0.02 then
      dx, dy, dz = dx / distance, dy / distance, dz / distance
      local collisionMask = CollisionFlag.TERRAIN + CollisionFlag.CAMERA_BLOCKING + CollisionFlag.VEHICLE
      local hitId, _, _, _, hitDistance = RaycastUtil.raycastClosest(originX, originY, originZ, dx, dy, dz, distance + 0.1, collisionMask)
      local camera = motion.camera
      local isOwnVehicleHit = hitId ~= nil and camera.vehicle ~= nil and camera.isInside and CameraMotion.getIsOwnVehicleHit(camera, hitId)

      if hitId ~= nil and not isOwnVehicleHit then
        local alpha = math.clamp((hitDistance - 0.1) / distance, 0, 1)
        x, y, z = MathUtil.vector3Lerp(originX, originY, originZ, x, y, z, alpha)
      end
    end

    setWorldTranslation(node, x, y, z)
  end

  self:applyCabTilt(motion, node)

  if rotX ~= 0 or rotY ~= 0 or rotZ ~= 0 then
    local qx, qy, qz, qw = getWorldQuaternion(node)
    local offsetQx, offsetQy, offsetQz, offsetQw = mathEulerToQuaternion(rotX, rotY, rotZ)
    setWorldQuaternion(node, MathUtil.quaternionMult(qx, qy, qz, qw, offsetQx, offsetQy, offsetQz, offsetQw))
  end

  motion.isApplied = true
end
