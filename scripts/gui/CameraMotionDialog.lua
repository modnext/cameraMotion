--
-- CameraMotionDialog
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modDirectory = g_currentModDirectory

CameraMotionDialog = {}

---
CameraMotionDialog.ADVANCED_SETTINGS = {
  "idleSway",
  "idleWhileMoving",
  "idleSwayConnection",
  "inertia",
  "cornering",
  "terrain",
  "headMovement",
  "walking",
}

local CameraMotionDialog_mt = Class(CameraMotionDialog, MessageDialog)

---Registers the CameraMotionDialog GUI
-- @includeCode
function CameraMotionDialog.register()
  local dialog = CameraMotionDialog.new()

  if g_gui ~= nil then
    g_gui:loadGui(modDirectory .. "gui/CameraMotionDialog.xml", "CameraMotionDialog", dialog)
  end

  CameraMotionDialog.INSTANCE = dialog
end

---Shows the CameraMotionDialog
-- @param string profileKey Profile key to show
-- @includeCode
function CameraMotionDialog.show(profileKey)
  local dialog = CameraMotionDialog.INSTANCE

  if dialog ~= nil then
    if profileKey == nil and g_cameraMotionSystem ~= nil then
      profileKey = g_cameraMotionSystem:getActiveProfileKey()
    end

    dialog.pendingProfileKey = profileKey
    g_gui:showDialog("CameraMotionDialog")
  end
end

---Creates a new CameraMotionDialog instance
-- @param any target Target for the dialog
-- @param table customMt Custom metatable
-- @return CameraMotionDialog New dialog instance
-- @includeCode
function CameraMotionDialog.new(target, customMt)
  local self = CameraMotionDialog:superClass().new(target, customMt or CameraMotionDialog_mt)

  self.selectedProfileIndex = 1
  self.profileIndexOffset = 0
  self.pendingProfileKey = nil
  self.isGlobalPage = false
  self.lastEditedProfileSettings = {}
  self.lastEditedGlobalSetting = nil
  self.isBackAllowed = true

  return self
end

---Gets the selected profile key
-- @return string Selected profile key
-- @includeCode
function CameraMotionDialog:getSelectedProfileKey()
  return CameraMotionSettings.PROFILE_ORDER[self.selectedProfileIndex]
end

---Sets up GUI elements for the dialog
-- @includeCode
function CameraMotionDialog:onGuiSetupFinished()
  CameraMotionDialog:superClass().onGuiSetupFinished(self)

  self.profileLayouts = {
    self.vehicleFirstPersonLayout,
    self.vehicleThirdPersonLayout,
    self.playerFirstPersonLayout,
    self.playerThirdPersonLayout,
  }

  local lineSize = (self.contentContainer.absSize[1] - self.headerText:getTextWidth()) / 2 - 20 * g_pixelSizeScaledX

  self.topLineLeft:setSize(lineSize, nil)
  self.topLineRight:setSize(lineSize, nil)

  self:setupProfileSelector()
  self:setupSliders()
  self:selectProfile(self.selectedProfileIndex)
end

---Handles opening of the camera dialog
-- @includeCode
function CameraMotionDialog:onOpen()
  CameraMotionDialog:superClass().onOpen(self)

  local pendingProfileKey = self.pendingProfileKey
  local wasGlobalPage = self.isGlobalPage

  self.pendingProfileKey = nil
  self.isGlobalPage = false
  self.globalSettingsPage:setVisible(false)
  self:setupProfileSelector()

  if pendingProfileKey == nil or not self:selectProfileByKey(pendingProfileKey) then
    self:selectProfile(self.profileIndexOffset + 1)
  end

  if wasGlobalPage then
    self:onClickGlobalSettings()
  else
    local element = self.lastEditedProfileSettings[self.selectedProfileIndex]

    if element == nil or not element:getIsVisible() or element:getIsDisabled() then
      element = self.enabled
    end

    FocusManager:setFocus(element)
  end
end

---Handles closing of the camera dialog
-- @includeCode
function CameraMotionDialog:onClose()
  if g_cameraMotionSystem ~= nil then
    g_cameraMotionSystem.settings:saveIfDirty()
  end

  CameraMotionDialog:superClass().onClose(self)
end

---Updates the idle sway connection line position
-- @param table element UI element for positioning
-- @includeCode
function CameraMotionDialog:onDrawIdleSwayConnection(element)
  local line = self.idleSwayConnectionLine
  local x = math.min(self.idleSway.absPosition[1], self.idleWhileMoving.absPosition[1]) - element.absPosition[1] - 12 * g_pixelSizeScaledX
  local top = self.idleSway.absPosition[2] + self.idleSway.absSize[2] * 0.5 - element.absPosition[2]
  local bottom = self.idleWhileMoving.absPosition[2] + self.idleWhileMoving.absSize[2] * 0.5 - element.absPosition[2]
  local height = top - bottom + self.idleSwayConnectionTop.absSize[2]
  local hasChanged = line.position[1] ~= x or line.position[2] ~= bottom or line.size[2] ~= height

  if hasChanged then
    line:setSize(nil, height)
    line:setPosition(x, bottom)

    self.idleSwayConnectionTop:setPosition(x, top)
    self.idleSwayConnectionBottom:setPosition(x, bottom)
  end
end

---Initializes the profile selector
-- @includeCode
function CameraMotionDialog:setupProfileSelector()
  local texts = {}
  local isVehicle

  if g_localPlayer ~= nil then
    isVehicle = g_localPlayer:getCurrentVehicle() ~= nil
  else
    isVehicle = g_activeVehicleCamera ~= nil
  end

  self.profileIndexOffset = isVehicle and 0 or 2
  self.selectedProfileIndex = self.profileIndexOffset + 1

  for index = 1, 2 do
    local profileKey = CameraMotionSettings.PROFILE_ORDER[self.profileIndexOffset + index]
    texts[index] = g_i18n:getText("cameraMotion_profile_" .. profileKey)
  end

  self.profileSelector:setTexts(texts)
  self.profileSelector:setState(1)
  self.profileSelector:setDisabled(false)
  self.profileSelector:setCanChangeState(true)
  self.pageSelector = self.profileSelector
end

---Configures sliders for camera settings
-- @includeCode
function CameraMotionDialog:setupSliders()
  local texts = { utf8ToUpper(g_i18n:getText("ui_off")) }
  local numSteps = MathUtil.round(CameraMotionSettings.INTENSITY_MAX / CameraMotionSettings.INTENSITY_STEP)

  for index = 1, numSteps do
    texts[index + 1] = string.format("%.0f%%", index * CameraMotionSettings.INTENSITY_STEP * 100)
  end

  for index, profileKey in ipairs(CameraMotionSettings.PROFILE_ORDER) do
    local page = self.profilePages[index]
    for _, name in ipairs(CameraMotionSettings.INTENSITY_SETTINGS) do
      local slider = page:getDescendantByName(name)

      if slider ~= nil then
        slider.mouseEvent = Utils.overwrittenFunction(slider.mouseEvent, CameraMotionDialog.sliderMouseEvent)
        slider:setTexts(texts)
      end
    end

    local limit = CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey]

    if limit ~= nil then
      page:getDescendantByName("modeElement"):setTexts({ g_i18n:getText("cameraMotion_modeGlobal"), g_i18n:getText("cameraMotion_modeCustom") })

      for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
        local offsetTexts = {}
        local axisLimit = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_MAX or limit
        local step = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_STEP or CameraMotionSettings.CAMERA_OFFSET_STEP[profileKey]
        local format = axis == "pitch" and "%+.0f°" or "%+.2f m"

        for state = 0, MathUtil.round(2 * axisLimit / step) do
          offsetTexts[state + 1] = string.format(format, -axisLimit + state * step)
        end

        local slider = page:getDescendantByName("cameraOffset" .. axis:sub(1, 1):upper() .. axis:sub(2))
        slider.mouseEvent = Utils.overwrittenFunction(slider.mouseEvent, CameraMotionDialog.sliderMouseEvent)
        slider:setTexts(offsetTexts)
      end
    end
  end
end

---Handles mouse events for slider interaction
-- @param table slider Slider object
-- @param function superFunc Super function to call
-- @param number posX Mouse X position
-- @param number posY Mouse Y position
-- @param boolean isDown Mouse down state
-- @param boolean isUp Mouse up state
-- @param integer button Mouse button pressed
-- @param boolean eventUsed Event usage status
-- @return boolean Event handling result
-- @includeCode
function CameraMotionDialog.sliderMouseEvent(slider, superFunc, posX, posY, isDown, isUp, button, eventUsed)
  if button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
    return eventUsed
  end

  return superFunc(slider, posX, posY, isDown, isUp, button, eventUsed)
end

---Updates control settings for the dialog
-- @includeCode
function CameraMotionDialog:updateControls()
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local settings = g_cameraMotionSystem.settings
  local profileKey = self:getSelectedProfileKey()
  local vehicle = g_activeVehicleCamera ~= nil and g_activeVehicleCamera.vehicle or nil
  local profile = settings:getProfile(profileKey)
  local defaults = CameraMotionSettings.DEFAULT_PROFILES[profileKey]
  local isCabHeadLookEnabled = profileKey == CameraMotionSettings.PROFILE.VEHICLE_FIRST_PERSON and profile.headLook > 0

  self.profileSelector:setState(self.selectedProfileIndex - self.profileIndexOffset)
  self:setBinaryOptionChecked(self.enabled, profile.enabled)
  self:updateSettingTitle(self.enabled, profile.enabled, defaults.enabled)

  self:setBinaryOptionChecked(self.idleWhileMoving, profile.idleWhileMoving)
  self.idleWhileMoving:setDisabled(not profile.enabled or profile.intensity == 0)
  self:updateSettingTitle(self.idleWhileMoving, profile.idleWhileMoving, defaults.idleWhileMoving)

  if self.leanHold ~= nil then
    self:setBinaryOptionChecked(self.leanHold, profile.leanHold)
    self.leanHold:setDisabled(not profile.enabled or profile.lean == 0)
    self:updateSettingTitle(self.leanHold, profile.leanHold, defaults.leanHold)
  end

  for _, name in ipairs(CameraMotionSettings.INTENSITY_SETTINGS) do
    local slider = self[name]

    if slider ~= nil then
      local state = MathUtil.round(profile[name] / CameraMotionSettings.INTENSITY_STEP + 0.000001) + 1
      local defaultState = MathUtil.round(defaults[name] / CameraMotionSettings.INTENSITY_STEP + 0.000001) + 1
      slider:setState(state)
      slider:setDisabled(not profile.enabled or (name == "headMovement" and isCabHeadLookEnabled))
      self:updateSettingTitle(slider, state, defaultState)
    end
  end

  local page = self.profilePages[self.selectedProfileIndex]

  for _, name in ipairs(CameraMotionDialog.ADVANCED_SETTINGS) do
    local container = page:getDescendantByName(name .. "Container")

    if container ~= nil then
      container:setVisible(settings.advancedMode)
    end
  end

  self.headMovementHint:setVisible(settings.advancedMode and isCabHeadLookEnabled)

  local offsetLimit = CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey]

  if offsetLimit ~= nil then
    page:getDescendantByName("cameraOffsetPitchContainer"):setVisible(settings.advancedMode)

    local offset = settings:getCameraOffset(vehicle, profileKey)
    self:setBinaryOptionChecked(self.modeElement, offset.custom == true)
    self.modeElement:setDisabled(not profile.enabled or vehicle == nil or vehicle.configFileName == nil)
    self:updateSettingTitle(self.modeElement, offset.custom == true, false)

    for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
      local limit = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_MAX or offsetLimit
      local step = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_STEP or CameraMotionSettings.CAMERA_OFFSET_STEP[profileKey]
      local slider = self["cameraOffset" .. axis:sub(1, 1):upper() .. axis:sub(2)]
      slider:setState(MathUtil.round((offset[axis] + limit) / step) + 1)
      slider:setDisabled(not profile.enabled)
      self:updateSettingTitle(slider, offset[axis], 0)
    end
  end

  self.profileLayouts[self.selectedProfileIndex]:invalidateLayout()
end

---Updates the title of a setting element
-- @param table element Element to update
-- @param any value Current value
-- @param any defaultValue Default value
-- @includeCode
function CameraMotionDialog:updateSettingTitle(element, value, defaultValue)
  local title = element.parent:getDescendantByName("settingTitle")
  local marker = title:getDescendantByName("changedMarker")
  local changed

  if type(value) == "number" and type(defaultValue) == "number" then
    changed = math.abs(value - defaultValue) > 0.000001
  else
    changed = value ~= defaultValue
  end

  marker:setVisible(changed)

  if changed then
    marker:setPosition(title:getTextWidth() + 6 * g_pixelSizeScaledX, nil)
  end
end

---Sets the checked state of a binary option
-- @param table element Element to check
-- @param boolean checked Checked state
-- @includeCode
function CameraMotionDialog:setBinaryOptionChecked(element, checked)
  if element:getIsChecked() ~= checked then
    element:setIsChecked(checked, true)
  end
end

---Selects a profile by its key
-- @param string profileKey Profile key to select
-- @return boolean Selection success status
-- @includeCode
function CameraMotionDialog:selectProfileByKey(profileKey)
  if self.isGlobalPage then
    return false
  end

  for index = self.profileIndexOffset + 1, self.profileIndexOffset + 2 do
    if CameraMotionSettings.PROFILE_ORDER[index] == profileKey then
      self:selectProfile(index)
      return true
    end
  end

  return false
end

---Selects a profile and updates UI elements
-- @param integer index Profile index to select
-- @includeCode
function CameraMotionDialog:selectProfile(index)
  local isAvailable = index == self.profileIndexOffset + 1 or index == self.profileIndexOffset + 2

  if self.isGlobalPage or not isAvailable then
    return
  end

  self.selectedProfileIndex = index

  for pageIndex, page in ipairs(self.profilePages) do
    page:setVisible(pageIndex == index)
  end

  local page = self.profilePages[index]
  self.enabled = page:getDescendantByName("enabled")
  self.idleWhileMoving = page:getDescendantByName("idleWhileMoving")
  self.idleSwayConnectionLine = page:getDescendantByName("idleSwayConnectionLine")
  self.idleSwayConnectionTop = page:getDescendantByName("idleSwayConnectionTop")
  self.idleSwayConnectionBottom = page:getDescendantByName("idleSwayConnectionBottom")
  self.leanHold = page:getDescendantByName("leanHold")

  for _, name in ipairs(CameraMotionSettings.INTENSITY_SETTINGS) do
    self[name] = page:getDescendantByName(name)
  end

  self.modeElement = page:getDescendantByName("modeElement")
  self.cameraOffsetX = page:getDescendantByName("cameraOffsetX")
  self.cameraOffsetY = page:getDescendantByName("cameraOffsetY")
  self.cameraOffsetZ = page:getDescendantByName("cameraOffsetZ")
  self.cameraOffsetPitch = page:getDescendantByName("cameraOffsetPitch")
  self.globalSettingsButton:setDisabled(false)
  self.resetButton:setDisabled(false)

  self:updateControls()
end

---Handles click on global settings button
-- @includeCode
function CameraMotionDialog:onClickGlobalSettings()
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  self.isGlobalPage = true

  for _, page in ipairs(self.profilePages) do
    page:setVisible(false)
  end

  self.globalSettingsPage:setVisible(true)
  self.profileSelector:setTexts({ g_i18n:getText("cameraMotion_globalSettings") })
  self.profileSelector:setState(1)
  self.profileSelector:setCanChangeState(false)
  self.profileSelector:setDisabled(true)
  self.pageSelector = nil
  self.globalSettingsButton:setDisabled(true)
  self.resetButton:setDisabled(true)

  local settings = g_cameraMotionSystem.settings
  self:setBinaryOptionChecked(self.advancedMode, settings.advancedMode)
  self:updateSettingTitle(self.advancedMode, settings.advancedMode, false)

  FocusManager:setFocus(self.lastEditedGlobalSetting or self.advancedMode)
end

---Updates advanced mode setting
-- @param any _ Unused parameter
-- @param UIElement element UI element for advanced mode
-- @includeCode
function CameraMotionDialog:onAdvancedModeChanged(_, element)
  if not self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local settings = g_cameraMotionSystem.settings
  settings:setAdvancedMode(element:getIsChecked())
  self:updateSettingTitle(self.advancedMode, settings.advancedMode, false)
  self.lastEditedGlobalSetting = element
end

---Handles profile selector click event
-- @param integer state State of the profile selector
-- @includeCode
function CameraMotionDialog:onClickProfileSelector(state)
  local isAvailable = state == 1 or state == 2

  if self.isGlobalPage or not isAvailable then
    return
  end

  local index = self.profileIndexOffset + state

  if self.isOpen and g_cameraMotionSystem ~= nil then
    g_cameraMotionSystem:switchCameraForProfile(CameraMotionSettings.PROFILE_ORDER[index])
  end

  self:selectProfile(index)
  self.profileLayouts[index]:scrollTo(0)

  if self.isOpen then
    FocusManager:setFocus(self.enabled)
  end
end

---Handles changes to slider values
-- @param number state Slider state value
-- @param UIElement element Slider UI element
-- @includeCode
function CameraMotionDialog:onSliderChanged(state, element)
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local value = (state - 1) * CameraMotionSettings.INTENSITY_STEP

  g_cameraMotionSystem.settings:setProfileValue(self:getSelectedProfileKey(), element.name, value)
  self:updateControls()
  self.lastEditedProfileSettings[self.selectedProfileIndex] = element
end

---Handles toggle change events for settings
-- @param any _ Unused parameter
-- @param table element UI element that triggered the event
-- @includeCode
function CameraMotionDialog:onToggleChanged(_, element)
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  g_cameraMotionSystem.settings:setProfileValue(self:getSelectedProfileKey(), element.name, element:getIsChecked())
  self:updateControls()
  self.lastEditedProfileSettings[self.selectedProfileIndex] = element
end

---Handles mode click events for camera settings
-- @param any _ Unused parameter
-- @param table element UI element that triggered the event
-- @includeCode
function CameraMotionDialog:onClickMode(_, element)
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local vehicle = g_activeVehicleCamera ~= nil and g_activeVehicleCamera.vehicle or nil
  g_cameraMotionSystem.settings:setCameraOffsetMode(vehicle, self:getSelectedProfileKey(), element:getIsChecked())
  self:updateControls()
  self.lastEditedProfileSettings[self.selectedProfileIndex] = element
end

---Handles changes to camera offset values
-- @param number state New offset state
-- @param table element UI element that triggered the event
-- @includeCode
function CameraMotionDialog:onOffsetChanged(state, element)
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local profileKey = self:getSelectedProfileKey()
  local limit = CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey]

  if limit == nil then
    return
  end

  local axis = string.lower(element.name:sub(#"cameraOffset" + 1))
  local step = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_STEP or CameraMotionSettings.CAMERA_OFFSET_STEP[profileKey]
  limit = axis == "pitch" and CameraMotionSettings.CAMERA_PITCH_MAX or limit
  local value = (state - 1) * step - limit
  local vehicle = g_activeVehicleCamera ~= nil and g_activeVehicleCamera.vehicle or nil
  g_cameraMotionSystem.settings:setCameraOffset(vehicle, profileKey, axis, value)
  self:updateControls()
  self.lastEditedProfileSettings[self.selectedProfileIndex] = element
end

---Resets camera settings to default values
-- @includeCode
function CameraMotionDialog:onClickReset()
  if self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local settings = g_cameraMotionSystem.settings
  local profileKey = self:getSelectedProfileKey()

  settings:resetProfile(profileKey)

  if CameraMotionSettings.CAMERA_OFFSET_MAX[profileKey] ~= nil then
    local vehicle = g_activeVehicleCamera ~= nil and g_activeVehicleCamera.vehicle or nil

    for _, axis in ipairs(CameraMotionSettings.OFFSET_AXES) do
      settings:setCameraOffset(vehicle, profileKey, axis, 0)
    end
  end

  self:updateControls()
end

---Resets all camera motion settings
-- @includeCode
function CameraMotionDialog:onClickResetAll()
  if not self.isGlobalPage or g_cameraMotionSystem == nil then
    return
  end

  local resetCallback = function(confirmed)
    if confirmed and g_cameraMotionSystem ~= nil then
      local settings = g_cameraMotionSystem.settings

      settings:resetAll()
      self:setBinaryOptionChecked(self.advancedMode, settings.advancedMode)
      self:updateSettingTitle(self.advancedMode, settings.advancedMode, false)
    end
  end

  YesNoDialog.show(resetCallback, nil, g_i18n:getText("cameraMotion_resetAllConfirm"), g_i18n:getText("cameraMotion_resetAll"))
end

---Handles back button click events
-- @return boolean Indicates if the action was successful
-- @includeCode
function CameraMotionDialog:onClickBack()
  if self.isGlobalPage then
    local index = self.selectedProfileIndex
    self.isGlobalPage = false
    self.globalSettingsPage:setVisible(false)
    self:setupProfileSelector()

    if index ~= self.profileIndexOffset + 1 and index ~= self.profileIndexOffset + 2 then
      index = self.profileIndexOffset + 1
    end

    self:selectProfile(index)
    self.profileLayouts[index]:scrollTo(0)
    FocusManager:setFocus(self.globalSettingsButton)
  else
    self:close()
  end

  return false
end

---
CameraMotionDialog.register()
