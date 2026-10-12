--
-- CameraMotionSettings
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modSettingsDirectory = g_currentModSettingsDirectory

CameraMotionSettings = {}

---
CameraMotionSettings.PROFILE = {
  VEHICLE_FIRST_PERSON = "vehicleFirstPerson",
  VEHICLE_THIRD_PERSON = "vehicleThirdPerson",
  PLAYER_FIRST_PERSON = "playerFirstPerson",
  PLAYER_THIRD_PERSON = "playerThirdPerson",
}

---
CameraMotionSettings.PROFILE_ORDER = {
  CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON,
  CameraMotionSettings.PROFILE.VEHICLE_THIRD_PERSON,
  CameraMotionSettings.PROFILE.PLAYER_FIRST_PERSON,
  CameraMotionSettings.PROFILE.PLAYER_THIRD_PERSON,
}

---
CameraMotionSettings.VEHICLE_PROFILE_ORDER = {
  CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON,
  CameraMotionSettings.PROFILE.VEHICLE_THIRD_PERSON,
}

---
CameraMotionSettings.INTENSITY_SETTINGS = {
  "intensity",
  "idleSway",
  "headLook",
  "lean",
  "inertia",
  "cornering",
  "terrain",
  "headMovement",
  "walking",
}

---
CameraMotionSettings.INTENSITY_XML_KEYS = {
  intensity = "movement#intensity",
  idleSway = "movement#idle",
  headLook = "head#look",
  lean = "head#lean",
  inertia = "movement#inertia",
  cornering = "movement#cornering",
  terrain = "movement#terrain",
  headMovement = "head#movement",
  walking = "movement#walking",
}

---
CameraMotionSettings.DEFAULT_PROFILES = {
  vehicleFirstPerson = {
    enabled = true,
    intensity = 1,
    idleSway = 1,
    idleWhileMoving = false,
    inertia = 1,
    cornering = 0.75,
    terrain = 0.8,
    headMovement = 0,
    headLook = 1,
    lean = 1,
    leanHold = false,
  },
  vehicleThirdPerson = {
    enabled = true,
    intensity = 1,
    idleSway = 1,
    idleWhileMoving = false,
    inertia = 0.4,
    cornering = 0.35,
    terrain = 0.3,
    headMovement = 0.3,
  },
  playerFirstPerson = {
    enabled = true,
    intensity = 1,
    idleSway = 1,
    idleWhileMoving = false,
    inertia = 0.55,
    cornering = 0.5,
    terrain = 0.6,
    headMovement = 0.65,
    walking = 0.6,
    lean = 1,
    leanHold = false,
  },
  playerThirdPerson = {
    enabled = true,
    intensity = 1,
    idleSway = 1,
    idleWhileMoving = false,
    inertia = 0.3,
    cornering = 0.3,
    terrain = 0.25,
    headMovement = 0.25,
    walking = 0.2,
  },
}

---
CameraMotionSettings.INTENSITY_STEP = 0.1
CameraMotionSettings.INTENSITY_MAX = 2
CameraMotionSettings.CAMERA_PITCH_MAX = 30
CameraMotionSettings.CAMERA_PITCH_STEP = 1

CameraMotionSettings.CAMERA_OFFSET_MAX = {
  vehicleFirstPerson = 0.35,
  vehicleThirdPerson = 5,
}

CameraMotionSettings.CAMERA_OFFSET_STEP = {
  vehicleFirstPerson = 0.01,
  vehicleThirdPerson = 0.05,
}

CameraMotionSettings.OFFSET_AXES = { "x", "y", "z", "pitch" }

local CameraMotionSettings_mt = Class(CameraMotionSettings)

---Creates a new CameraMotionSettings instance
-- @param CameraMotionSystem system The system reference
-- @return CameraMotionSettings New instance of CameraMotionSettings
-- @includeCode
function CameraMotionSettings.new(system)
  local self = setmetatable({}, CameraMotionSettings_mt)

  self.system = system
  self.profiles = {}
  self.vehicleCameraOffsets = {}
  self.savedCameraOffsets = {}
  self.cameraOffsetsDirty = false
  self:resetToDefaults()

  return self
end

---Resets camera settings to defaults
-- @includeCode
function CameraMotionSettings:resetToDefaults()
  self.advancedMode = false
  self.cameraOffsetSettings = {}

  for _, profileKey in ipairs(CameraMotionSettings.PROFILE_ORDER) do
    self:resetProfile(profileKey)

    if CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey] ~= nil then
      self.cameraOffsetSettings[profileKey] = { x = 0, y = 0, z = 0, pitch = 0 }
    end
  end

  self.isDirty = false
end

---Resets camera settings to defaults
-- @includeCode
function CameraMotionSettings:resetAll()
  if not self.system.isClient then
    return
  end

  self:resetToDefaults()
  self.vehicleCameraOffsets = {}
  self.savedCameraOffsets = {}
  self.cameraOffsetsDirty = false

  for _, name in ipairs({ "settings.xml", "vehicles.xml" }) do
    local filename = modSettingsDirectory .. name

    if fileExists(filename) then
      deleteFile(filename)
    end
  end
end

---Sets the advanced mode for camera settings
-- @param boolean enabled Enable advanced mode
-- @includeCode
function CameraMotionSettings:setAdvancedMode(enabled)
  enabled = enabled == true

  if self.advancedMode ~= enabled then
    self.advancedMode = enabled
    self.isDirty = true
  end
end

---Gets the camera profile by key
-- @param string profileKey Key of the profile
-- @return table Camera profile data
-- @includeCode
function CameraMotionSettings:getProfile(profileKey)
  return self.profiles[profileKey]
end

---Gets the custom vehicle offset or global profile offset
-- @param Vehicle vehicle Vehicle object, nil uses the global offset
-- @param string profileKey Profile key for offset
-- @return table Camera offset settings or nil if the profile has no offsets
-- @includeCode
function CameraMotionSettings:getCameraOffset(vehicle, profileKey)
  local settings = self.cameraOffsetSettings[profileKey]

  if settings ~= nil and vehicle ~= nil and vehicle.configFileName ~= nil then
    local entry = self.vehicleCameraOffsets[string.lower(vehicle.configFileName)]
    local offset = entry ~= nil and entry[profileKey] or nil

    if offset ~= nil and offset.custom then
      return offset
    end
  end

  return settings
end

---Sets the camera offset mode for a vehicle
-- @param Vehicle vehicle Vehicle object
-- @param string profileKey Profile key for offset
-- @param boolean custom Custom mode flag
-- @includeCode
function CameraMotionSettings:setCameraOffsetMode(vehicle, profileKey, custom)
  local hasValidVehicle = self.system.isClient and vehicle ~= nil and vehicle.configFileName ~= nil

  if not hasValidVehicle or self.cameraOffsetSettings[profileKey] == nil then
    return
  end

  custom = custom == true
  local filename = vehicle.configFileName
  local key = string.lower(filename)
  local entry = self.vehicleCameraOffsets[key]
  local offset = entry ~= nil and entry[profileKey] or nil

  if (offset ~= nil and offset.custom == true) == custom then
    return
  end

  if entry == nil then
    entry = { filename = filename, modName = vehicle.customEnvironment }
    self.vehicleCameraOffsets[key] = entry
  end

  if offset == nil then
    offset = { x = 0, y = 0, z = 0, pitch = 0 }
    entry[profileKey] = offset
  end

  offset.custom = custom

  local savedEntry = self.savedCameraOffsets[key]
  local isDefaultOffset = offset.x == 0 and offset.y == 0 and offset.z == 0 and offset.pitch == 0

  if not custom and isDefaultOffset and (savedEntry == nil or savedEntry[profileKey] == nil) then
    entry[profileKey] = nil

    if entry.vehicleFirstPerson == nil and entry.vehicleThirdPerson == nil then
      self.vehicleCameraOffsets[key] = nil
    end
  end

  self.cameraOffsetsDirty = true
end

---Sets a specific camera offset value
-- @param Vehicle vehicle Vehicle object
-- @param string profileKey Profile key for offset
-- @param string axis Axis to modify
-- @param number value Position in meters or pitch in degrees
-- @includeCode
function CameraMotionSettings:setCameraOffset(vehicle, profileKey, axis, value)
  local limit = CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey]

  if not self.system.isClient or limit == nil then
    return
  end

  value = tonumber(value)

  local isValidAxis = axis == "x" or axis == "y" or axis == "z" or axis == "pitch"
  if not isValidAxis or value == nil or not MathUtil.isFinite(value) then
    return
  end

  limit = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_MAX or limit
  value = math.clamp(value, -limit, limit)

  local offset = self:getCameraOffset(vehicle, profileKey)

  if offset[axis] ~= value then
    offset[axis] = value

    if offset.custom then
      self.cameraOffsetsDirty = true
    else
      self.isDirty = true
    end
  end
end

---Sets a profile value for the camera settings
-- @param string profileKey Key of the profile
-- @param string name Name of the setting
-- @param any value Value to set
-- @includeCode
function CameraMotionSettings:setProfileValue(profileKey, name, value)
  local profile = self.profiles[profileKey]

  if profile == nil or profile[name] == nil then
    return
  end

  local currentValue = profile[name]
  if type(currentValue) == "boolean" then
    value = value == true
  else
    value = tonumber(value)

    if value == nil or not MathUtil.isFinite(value) then
      return
    end

    value = math.clamp(value, 0, CameraMotionSettings.INTENSITY_MAX)
  end

  if currentValue ~= value then
    profile[name] = value

    self.isDirty = true

    if name == "enabled" and not value then
      self.system:resetMotion(profileKey)
    elseif name == "leanHold" and self.system.motion:getProfileKey() == profileKey then
      self.system.headMovement:setLean(nil)
    end
  end
end

---Resets a profile to its default values
-- @param string profileKey Key of the profile
-- @includeCode
function CameraMotionSettings:resetProfile(profileKey)
  local defaults = CameraMotionSettings.DEFAULT_PROFILES[profileKey]

  if defaults ~= nil then
    if self.system.motion:getProfileKey() == profileKey then
      self.system.headMovement:setLean(nil)
    end

    self.profiles[profileKey] = table.clone(defaults)
    self.isDirty = true
  end
end

---Loads camera settings from defaults and XML
-- @includeCode
function CameraMotionSettings:load()
  self:resetToDefaults()
  self:loadFromXMLFile()
  self:loadCameraOffsets()
end

---Loads and validates camera offset values from XML
-- @param XMLFile xmlFile XML file to read
-- @param string key Path to the cameraOffset element
-- @param string profileKey Profile key defining the position limits
-- @param table offset Position in meters and pitch in degrees to update
-- @return boolean True if invalid or out of range values were corrected
-- @includeCode
function CameraMotionSettings.loadCameraOffsetFromXMLFile(xmlFile, key, profileKey, offset)
  local changed = false
  local positionLimit = CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey]

  for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
    local limit = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_MAX or positionLimit
    local value = xmlFile:getFloat(key .. "#" .. axis, 0)

    if not MathUtil.isFinite(value) then
      value = 0
      changed = true
    end

    offset[axis] = math.clamp(value, -limit, limit)
    changed = changed or value ~= offset[axis]
  end

  return changed
end

---Loads camera settings from an XML file
-- @includeCode
function CameraMotionSettings:loadFromXMLFile()
  self.isDirty = false
  local xmlFile = XMLFile.loadIfExists("CameraMotionXML", modSettingsDirectory .. "settings.xml")

  if xmlFile == nil then
    return
  end

  self.advancedMode = xmlFile:getBool("settings.global#advancedMode", false)

  for _, profileKey in ipairs(CameraMotionSettings.PROFILE_ORDER) do
    local profile = self.profiles[profileKey]
    local key = "settings." .. profileKey

    profile.enabled = xmlFile:getBool(key .. "#enabled", profile.enabled)
    profile.idleWhileMoving = xmlFile:getBool(key .. ".movement#idleWhileMoving", profile.idleWhileMoving)

    if profile.leanHold ~= nil then
      profile.leanHold = xmlFile:getBool(key .. ".head#leanHold", profile.leanHold)
    end

    for _, name in ipairs(CameraMotionSettings.INTENSITY_SETTINGS) do
      if profile[name] ~= nil then
        local valueKey = key .. "." .. CameraMotionSettings.INTENSITY_XML_KEYS[name]
        local value = xmlFile:getFloat(valueKey, profile[name])

        if not MathUtil.isFinite(value) then
          value = CameraMotionSettings.DEFAULT_PROFILES[profileKey][name]
          self.isDirty = true
        end

        profile[name] = math.clamp(value, 0, CameraMotionSettings.INTENSITY_MAX)
        self.isDirty = self.isDirty or value ~= profile[name]
      end
    end

    local settings = self.cameraOffsetSettings[profileKey]

    if settings ~= nil then
      local changed = CameraMotionSettings.loadCameraOffsetFromXMLFile(xmlFile, key .. ".cameraOffset", profileKey, settings)
      self.isDirty = self.isDirty or changed
    end
  end

  xmlFile:delete()
end

---Saves settings if they have changed
-- @includeCode
function CameraMotionSettings:saveIfDirty()
  self:saveCameraOffsets()

  if not self.system.isClient or not self.isDirty then
    return
  end

  createFolder(modSettingsDirectory)
  local xmlFile = XMLFile.create("CameraMotionXML", modSettingsDirectory .. "settings.xml", "settings")

  if xmlFile == nil then
    return
  end

  xmlFile:setBool("settings.global#advancedMode", self.advancedMode)

  for _, profileKey in ipairs(CameraMotionSettings.PROFILE_ORDER) do
    local profile = self.profiles[profileKey]
    local key = "settings." .. profileKey

    xmlFile:setBool(key .. "#enabled", profile.enabled)
    xmlFile:setBool(key .. ".movement#idleWhileMoving", profile.idleWhileMoving)

    if profile.leanHold ~= nil then
      xmlFile:setBool(key .. ".head#leanHold", profile.leanHold)
    end

    for _, name in ipairs(CameraMotionSettings.INTENSITY_SETTINGS) do
      if profile[name] ~= nil then
        xmlFile:setFloat(key .. "." .. CameraMotionSettings.INTENSITY_XML_KEYS[name], profile[name])
      end
    end

    local settings = self.cameraOffsetSettings[profileKey]

    if settings ~= nil then
      for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
        xmlFile:setFloat(key .. ".cameraOffset#" .. axis, settings[axis])
      end
    end
  end

  if xmlFile:save() then
    self.isDirty = false
  end

  xmlFile:delete()
end

---Loads camera offsets from XML file
-- @includeCode
function CameraMotionSettings:loadCameraOffsets()
  self.vehicleCameraOffsets = {}
  self.savedCameraOffsets = {}
  self.cameraOffsetsDirty = false

  local xmlFile = XMLFile.loadIfExists("CameraMotionOffsetsXML", modSettingsDirectory .. "vehicles.xml")

  if xmlFile == nil then
    return
  end

  for _, key in xmlFile:iterator("vehicles.vehicle") do
    local filename = xmlFile:getString(key .. "#filename")

    if filename ~= nil and filename ~= "" then
      filename = HTMLUtil.decodeFromHTML(filename)
      local modName = xmlFile:getString(key .. "#modName")
      local resolvedFilename = filename
      local isModAvailable = modName ~= nil and g_modNameToDirectory[modName] ~= nil

      if not string.startsWith(filename, "$moddir$") or isModAvailable then
        resolvedFilename = NetworkUtil.convertFromNetworkFilename(filename)
      end

      local entry = { filename = filename, modName = modName }

      for _, profileKey in ipairs(CameraMotionSettings.VEHICLE_PROFILE_ORDER) do
        local profilePath = key .. "." .. profileKey

        if xmlFile:hasProperty(profilePath) then
          local offset = { custom = xmlFile:getBool(profilePath .. "#custom", true) }
          local changed = CameraMotionSettings.loadCameraOffsetFromXMLFile(xmlFile, profilePath .. ".cameraOffset", profileKey, offset)
          self.cameraOffsetsDirty = self.cameraOffsetsDirty or changed

          entry[profileKey] = offset
        end
      end

      self.vehicleCameraOffsets[string.lower(resolvedFilename)] = entry
    end
  end

  xmlFile:delete()

  if not self.cameraOffsetsDirty then
    self:rememberCameraOffsets()
  end
end

---Checks if two offsets are equal
-- @param table first First offset
-- @param table second Second offset
-- @return boolean True if equal
-- @includeCode
function CameraMotionSettings.getOffsetsEqual(first, second)
  if first == nil or second == nil then
    return first == second
  end

  local hasSameMode = first.custom == second.custom
  local hasSamePosition = hasSameMode and first.x == second.x and first.y == second.y and first.z == second.z

  return hasSamePosition and first.pitch == second.pitch
end

---Remembers current camera offsets
-- @includeCode
function CameraMotionSettings:rememberCameraOffsets()
  self.savedCameraOffsets = {}

  for key, entry in pairs(self.vehicleCameraOffsets) do
    local savedEntry = {}

    for _, profileKey in ipairs(CameraMotionSettings.VEHICLE_PROFILE_ORDER) do
      if entry[profileKey] ~= nil then
        savedEntry[profileKey] = table.clone(entry[profileKey])
      end
    end

    self.savedCameraOffsets[key] = savedEntry
  end
end

---Checks if camera offsets have changed
-- @return boolean True if changed
-- @includeCode
function CameraMotionSettings:getHaveCameraOffsetsChanged()
  for key, entry in pairs(self.vehicleCameraOffsets) do
    local savedEntry = self.savedCameraOffsets[key]

    for _, profileKey in ipairs(CameraMotionSettings.VEHICLE_PROFILE_ORDER) do
      if not CameraMotionSettings.getOffsetsEqual(entry[profileKey], savedEntry ~= nil and savedEntry[profileKey] or nil) then
        return true
      end
    end
  end

  for key in pairs(self.savedCameraOffsets) do
    if self.vehicleCameraOffsets[key] == nil then
      return true
    end
  end

  return false
end

---Saves camera offsets to an XML file
-- @includeCode
function CameraMotionSettings:saveCameraOffsets()
  if not self.system.isClient or not self.cameraOffsetsDirty then
    return
  end

  if not self:getHaveCameraOffsetsChanged() then
    self.cameraOffsetsDirty = false
    return
  end

  createFolder(modSettingsDirectory)
  local xmlFile = XMLFile.create("CameraMotionOffsetsXML", modSettingsDirectory .. "vehicles.xml", "vehicles")

  if xmlFile == nil then
    return
  end

  local keys = {}

  for key in pairs(self.vehicleCameraOffsets) do
    table.insert(keys, key)
  end

  table.sort(keys)

  for index, entryKey in ipairs(keys) do
    local entry = self.vehicleCameraOffsets[entryKey]
    local key = string.format("vehicles.vehicle(%d)", index - 1)
    local filename = NetworkUtil.convertToNetworkFilename(entry.filename)

    if entry.modName ~= nil then
      xmlFile:setString(key .. "#modName", entry.modName)
    end

    xmlFile:setString(key .. "#filename", HTMLUtil.encodeToHTML(filename))

    for _, profileKey in ipairs(CameraMotionSettings.VEHICLE_PROFILE_ORDER) do
      local offset = entry[profileKey]

      if offset ~= nil then
        local profilePath = key .. "." .. profileKey
        xmlFile:setBool(profilePath .. "#custom", offset.custom)

        for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
          xmlFile:setFloat(profilePath .. ".cameraOffset#" .. axis, offset[axis])
        end
      end
    end
  end

  if xmlFile:save() then
    self.cameraOffsetsDirty = false
    self:rememberCameraOffsets()
  end

  xmlFile:delete()
end
