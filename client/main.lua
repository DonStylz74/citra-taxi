-- Variables
local curTaxi = {}
local blip, skippedOnCab = nil, false
local ESX = Config.framework == 'esx' and exports['es_extended']:getSharedObject() or nil
local QBCore = Config.framework == 'qb' and exports['qb-core']:GetCoreObject() or nil

CreateThread(function()
    while true do
        playerCoords = GetEntityCoords(cache.ped)
        Wait(1000)
    end
end)

-- Functions
local function notify(msg, type)
    if QBCore then
        QBCore.Functions.Notify(msg, type)
    elseif ESX then
        type = type == 'primary' and 'info' or type
        ESX.ShowNotification(msg, type)
    end
end

local function resetTaxiData()
    curTaxi = {
        vehicle = 0,
        ped = 0,
        dest = vector3(0, 0, 0),
        style = Config.DrivingStyles.Normal,
        speed = 26.0,
    }
end

local function getStoppingLocation(coords)
    local _, nCoords = GetClosestVehicleNode(coords.x, coords.y, coords.z, 1, 3.0, 0)
    return nCoords
end

local function getStartingLocation(coords)
    local dist, vector, nNode, heading = 0, vector3(0, 0, 0), math.random(10, 20), 0

    while dist < Config.MinSpawnDist do
        nNode = nNode + math.random(10, 20)
        _, vector, heading = GetNthClosestVehicleNodeWithHeading(coords.x, coords.y, coords.z, nNode, 9, 3.0, 2.5)
        dist = #(coords - vector)
    end

    return vector, heading
end

local function createBlip()
    blip = AddBlipForEntity(curTaxi.vehicle)
    SetBlipSprite(blip, 198)
    SetBlipColour(blip, 5)
    SetBlipDisplay(blip, 2)
    SetBlipFlashes(blip, true)
    SetBlipFlashInterval(blip, 750)
    BeginTextCommandSetBlipName('Taxi')
    AddTextComponentSubstringBlipName(blip)
    EndTextCommandSetBlipName(blip)
end

local function wanderOff()
    if curTaxi.vehicle ~= 0 then
        SetVehicleDoorsShut(curTaxi.vehicle, false)
        TaskVehicleDriveWander(curTaxi.ped, curTaxi.vehicle, 20.0, Config.DrivingStyles.Normal)
        SetPedKeepTask(curTaxi.ped, true)
        SetEntityAsNoLongerNeeded(curTaxi.ped)
        SetEntityAsNoLongerNeeded(curTaxi.vehicle)

        RemoveBlip(blip)
        blip = nil

        resetTaxiData()
        CreateMenu(false)
    end
end

local function driveTo()
    local speed = (curTaxi.style == Config.DrivingStyles.Rush) and curTaxi.speed * Config.RushSpeedMultiplier or curTaxi.speed
    TaskVehicleDriveToCoordLongrange(curTaxi.ped, curTaxi.vehicle, curTaxi.dest.x, curTaxi.dest.y, curTaxi.dest.z, speed, curTaxi.style, 5.0)
    SetPedKeepTask(curTaxi.ped, true)
    SetDriverAggressiveness(curTaxi.ped, (curTaxi.style == Config.DrivingStyles.Rush) and 0.75 or 0.5)

    for i = 0, GetNumberOfVehicleDoors(curTaxi.vehicle) do
        if GetVehicleDoorAngleRatio(curTaxi.vehicle, i) > 0.0 then
            SetVehicleDoorsShut(curTaxi.vehicle, false)
            break
        end
    end

    -- Monitor the taxi's position and park when close to the destination
    CreateThread(function()
        while curTaxi.vehicle ~= 0 do
            local dist = #(GetEntityCoords(curTaxi.vehicle) - curTaxi.dest)
            if dist < Config.SlowdownDist then
                park(IsPedInVehicle(cache.ped, curTaxi.vehicle, true))
                break
            end
            Wait(500)
        end
    end)
end

function park(inTaxi)
    local speed = curTaxi.speed
    curTaxi.speed = Config.SlowdownSpeed

    while speed > curTaxi.speed do
        speed = speed - 1.0
        TaskVehicleDriveToCoord(curTaxi.ped, curTaxi.vehicle, curTaxi.dest.x, curTaxi.dest.y, curTaxi.dest.z,
            speed, 0, joaat(Config.TaxiModel), curTaxi.style, 10.0, 1)
        Wait(100)
    end

    if inTaxi then
        print("Trying to launch menu.")
        lib.showMenu('pay_fare')
    end

    if not inTaxi then
        StartVehicleHorn(curTaxi.vehicle, 5000, joaat("NORMAL"), false)
    end
end

local function taxiDone()
    local plyPed = cache.ped

    if IsPedInVehicle(plyPed, curTaxi.vehicle, true) then
        local coords = GetEntityCoords(curTaxi.vehicle)
        curTaxi.dest = getStoppingLocation(coords)
        curTaxi.style = Config.DrivingStyles.Normal
        park()
        ClearGpsPlayerWaypoint()
    else
        wanderOff()
    end
end

local function waitForTaxiDone()
    inTaxi, inTime, taxiCoords = false, GetGameTimer(), GetEntityCoords(curTaxi.vehicle)

    CreateThread(function() -- Enter / exit taxi
        while curTaxi.vehicle ~= 0 do
            if IsControlJustPressed(0, 23) and not skippedOnCab then
                local plyPed = cache.ped

                if inTaxi then
                    if GetResourceState('qb-vehiclekeys') == "started" then
                        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', curTaxi.vehicle, 1)
                        Wait(500)
                    elseif Config.framework == 'esx' then
                        for i = 0, 5 do
                            SetVehicleDoorOpen(curTaxi.vehicle, i, false, true) -- will open every door from 0-5
                        end
                    end
                    TaskLeaveVehicle(plyPed, curTaxi.vehicle, 1)
                elseif GetVehiclePedIsTryingToEnter(plyPed) == curTaxi.vehicle then
                    ClearPedTasks(plyPed)
                    for i = 2, 1, -1 do
                        if IsVehicleSeatFree(curTaxi.vehicle, i) then
                            TaskEnterVehicle(plyPed, curTaxi.vehicle, 5000, i, 1.0, 1, 0)
                            break
                        end
                    end
                end
            end
            Wait(1)
        end
    end)

    CreateThread(function() -- Handle menu, & driver voice lines
        local lastSpoke = 0

        while curTaxi.vehicle ~= 0 and not skippedOnCab do
            local dist = #(curTaxi.dest - taxiCoords)
            local nowInTaxi = IsPedInVehicle(cache.ped, curTaxi.vehicle, true)

            if nowInTaxi ~= inTaxi then
                inTaxi = nowInTaxi
                CreateMenu(inTaxi)

                if inTaxi then
                    Wait(1000)--PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_WHERE_TO", "SPEECH_PARAMS_FORCE_NORMAL")
                    setDestination()
                    if inTime == 0 then inTime = GetGameTimer() end
                    while dist < 15.0 do
                        Wait(100)
                        dist = #(curTaxi.dest - taxiCoords)
                    end
                end
            end

            if inTaxi then
                if IsVehicleStuckOnRoof(curTaxi.vehicle) then
                    SetVehicleOnGroundProperly(curTaxi.vehicle)
                    Wait(1000)
                end

                if dist < 25.0 and GetGameTimer() - lastSpoke >= 30000 then
                    PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_CLOSE_AS_POSS", "SPEECH_PARAMS_FORCE_NORMAL")
                    lastSpoke = GetGameTimer()
                end
            end
            Wait(500)
        end
    end)

    Citizen.CreateThread(function() -- Taxi speed
        while curTaxi.vehicle ~= 0 and not skippedOnCab do
            taxiCoords = GetEntityCoords(curTaxi.vehicle)
            local dist = #(curTaxi.dest - taxiCoords)

            if dist < Config.SlowdownDist then
                if curTaxi.speed ~= Config.SlowdownSpeed then
                    park(inTaxi)
                end
            else
                local newSpeed

                if GetResourceState(Config.SpeedLimitResource) == "started" then
                    newSpeed = exports[Config.SpeedLimitResource][Config.SpeedLimitExport]()
                else
                    local _, _, flags = GetVehicleNodeProperties(taxiCoords.x, taxiCoords.y, taxiCoords.z)
                    newSpeed = Config.SpeedLimitZones[flags]
                end

                if newSpeed then
                    newSpeed = newSpeed * 0.44704
                    if newSpeed ~= curTaxi.speed then
                        curTaxi.speed = newSpeed
                        driveTo()
                    end
                end
            end

            Wait(100)
        end
    end)
end

local function spawnTaxi()
    local model = joaat(Config.TaxiModel)

    if IsModelValid(model) and IsThisModelACar(model) then
        local plyCoords = GetEntityCoords(cache.ped)
        local spawnCoords, spawnHeading = getStartingLocation(plyCoords)
        curTaxi.dest = getStoppingLocation(plyCoords)
        curTaxi.style = Config.DrivingStyles.Normal

        RequestModel(model)
        while not HasModelLoaded(model) do Wait(1) end

        curTaxi.vehicle = CreateVehicle(model, spawnCoords, spawnHeading, true, true)
        exports.ND_Fuel:SetFuel(curTaxi.vehicle, 100.0)

        while not DoesEntityExist(curTaxi.vehicle) do Wait(10) end
        SetVehicleEngineOn(curTaxi.vehicle, true, true, false)
        SetHornEnabled(curTaxi.vehicle, true)
        SetVehicleFuelLevel(curTaxi.vehicle, 100.0)
        DecorSetFloat(curTaxi.vehicle, '_FUEL_LEVEL', GetVehicleFuelLevel(curTaxi.vehicle))
        SetVehicleDoorLatched(curTaxi.vehicle, -1, true, true, true)

        SetVehicleAutoRepairDisabled(curTaxi.vehicle, false)
        for extra, enabled in pairs(Config.TaxiExtras) do
            SetVehicleExtra(curTaxi.vehicle, extra, enabled and 0 or 1)
        end

        SetModelAsNoLongerNeeded(model)

        model = joaat(Config.DriverModel)
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(1) end
        curTaxi.ped = CreatePed(1, model, spawnCoords, spawnHeading, true, true)
        while not DoesEntityExist(curTaxi.ped) do Wait(10) end

        SetPedIntoVehicle(curTaxi.ped, curTaxi.vehicle, -1)
        SetAmbientVoiceName(curTaxi.ped, Config.DriverVoice)
        SetBlockingOfNonTemporaryEvents(curTaxi.ped, true)
        SetDriverAbility(curTaxi.ped, 1.0)

        SetModelAsNoLongerNeeded(model)

        createBlip()
        notify('Taxi is on the way', 'success')

        if GetResourceState('qb-vehiclekeys') == "started" then
            exports['qb-vehiclekeys']:addNoLockVehicles(Config.TaxiModel)
            TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', curTaxi.vehicle, 1)
        end

        driveTo()
        waitForTaxiDone()
    end
end

function setDestination()
    local previousWaypoint = nil
    PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_WHERE_TO", "SPEECH_PARAMS_FORCE_NORMAL")
    Wait(2000)
    while true do
        local waypoint = GetFirstBlipInfoId(8)

        if DoesBlipExist(waypoint) then
            local currentCoords = GetBlipCoords(waypoint)
            if not curTaxi.dest or previousWaypoint ~= currentCoords then
                if curTaxi.dest then
                    PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_CHANGE_DEST", "SPEECH_PARAMS_FORCE_NORMAL")
                end
                curTaxi.dest = getStoppingLocation(currentCoords)
                driveTo()
                PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_BEGIN_JOURNEY", "SPEECH_PARAMS_FORCE_NORMAL")
                previousWaypoint = currentCoords
            end
        end

        Citizen.Wait(1000) -- Check every second
    end
end

local function callCab(cancelExisting)
    if skippedOnCab and curTaxi.vehicle ~= 0 then -- Waits until the skipped cab is cleared
        notify("You skipped out on your last taxi. No way we're sending another one right now!", 'error')
    elseif curTaxi.vehicle == 0 or curTaxi.vehicle == nil or not DoesEntityExist(curTaxi.vehicle) then
        skippedOnCab = false
        spawnTaxi()
    elseif cancelExisting then
        taxiDone()
    end
end

-- Events
RegisterNetEvent('citra-taxi:client:callOrCancelTaxi', function()
    callCab(true)
end)

-- Events
RegisterNetEvent('citra-taxi:client:taxiStop', function()
    taxiDone()
end)

RegisterNetEvent('citra-taxi:client:callTaxi')
AddEventHandler('citra-taxi:client:callTaxi', function()
    callCab(false)
end)

RegisterNetEvent('citra-taxi:client:cancelTaxi', function()
    if curTaxi.vehicle ~= 0 and not skippedOnCab then
        curTaxi.dest = getStoppingLocation(GetEntityCoords(curTaxi.vehicle))
        taxiDone()
    end
end)

RegisterNetEvent('citra-taxi:client:setDestination', function()
    if curTaxi.vehicle ~= 0 and IsPedInVehicle(cache.ped, curTaxi.vehicle, true) then
        setDestination()
    end
end)

RegisterNetEvent('citra-taxi:client:speedUp', function()
    if curTaxi.vehicle ~= 0 and IsPedInVehicle(cache.ped, curTaxi.vehicle, true) then
        PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_SPEED_UP", "SPEECH_PARAMS_FORCE_NORMAL")
        curTaxi.style = Config.DrivingStyles.Rush
        driveTo()
        CreateMenu(true, true)
    end
end)

RegisterNetEvent('citra-taxi:client:speedDown', function()
    if curTaxi.vehicle ~= 0 and IsPedInVehicle(cache.ped, curTaxi.vehicle, true) then
        PlayPedAmbientSpeechNative(curTaxi.ped, "TAXID_BEGIN_JOURNEY", "SPEECH_PARAMS_FORCE_NORMAL")
        curTaxi.style = Config.DrivingStyles.Normal
        driveTo()
        CreateMenu(true, false)
    end
end)

RegisterNetEvent('citra-taxi:client:farePaid', function(fare)
    notify('Fare of $' .. fare + 0.00 .. ' paid', 'success')
    Wait(2000)
    wanderOff()
end)

RegisterNetEvent('citra-taxi:client:alertPolice', function()
    local coords = GetEntityCoords(cache.ped)
    local alertMsg = 'Taxi Fare Theft'
    local taxiPed = curTaxi.ped
    skippedOnCab = true

    CreateThread(function()
        for i = 1, 60 do -- Keep cab around for 30 mins
            PlayPedAmbientSpeechNative(taxiPed, "TAXID_RUN_AWAY", "SPEECH_PARAMS_FORCE_NORMAL")
            Wait(30000)
        end
    end)

    -- Make cabbie fight player
    SetEntityInvincible(curTaxi.ped, false)
    GiveWeaponToPed(curTaxi.ped, GetHashKey("weapon_bat"),1, false, true)
    SetCurrentPedWeapon(curTaxi.ped, GetHashKey("weapon_bat"), true)
    SetCanAttackFriendly(curTaxi.ped, true, false)
    SetPedRelationshipGroupHash(curTaxi.ped, "VehicleOwners")
    SetPedDropsWeaponsWhenDead(curTaxi.ped, false)
    SetPedCombatAttributes(curTaxi.ped, 13, true)
    TaskCombatPed(curTaxi.ped, cache.ped, 0, 16)
    --Set NPC to call 911
    showSubtitle("I'm going to fuck you up!", 5000)
    local pos = playerCoords
    local postal = exports["postalscript"]:getPostal()
    if pos then
        s1, s2 = GetStreetNameAtCoord(pos.x, pos.y, pos.z)
    end
    local street1 = GetStreetNameFromHashKey(s1)
    local street2 = GetStreetNameFromHashKey(s2)
    local streetLabel = street1
    local callDescription = "Yellow Cab Dispatch is reporting a cabbie at "..postal.." "..streetLabel.." activated his panic button. He is armed. Dispatch is unable to contact their employee. Use caution."
    if street2 ~= nil then
        streetLabel = streetLabel .. ' ' .. street2
    end
    print(streetLabel, callDescription, GetPlayerServerId(PlayerId()))
    TriggerServerEvent('SonoranCAD::callcommands:SendCallApi', true, 'Yellow Cab', streetLabel, callDescription, GetPlayerServerId(PlayerId()), nil, nil, '911')
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        resetTaxiData()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        wanderOff()
    end
end)

-- Oxlib menu to pay fare
trafficMenu = lib.registerMenu({
    id = 'pay_fare',
    title = 'Pay Fare',
    position = 'top-right',
    onSideScroll = function(selected, scrollIndex, args)
    end,
    onSelected = function(selected, secondary, args)
    end,
    onCheck = function(selected, checked, args)
    end,
    onClose = function(keyPressed)
        if keyPressed then
        end
    end,
    options = {
        {label = 'Pay Fare', close = true},
        {label = 'Skip Out and Run!', close = true},
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        print("Paying fare.")
        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', curTaxi.vehicle, 1)
        Wait(500)
        TriggerServerEvent('citra-taxi:server:payFare', GetGameTimer() - inTime)
        TaskLeaveVehicle(cache.ped, curTaxi.vehicle, 1)
    elseif selected == 2 then
        TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', curTaxi.vehicle, 1)
        Wait(500)
        TaskLeaveVehicle(curTaxi.ped, curTaxi.vehicle, 1)
        TaskLeaveVehicle(cache.ped, curTaxi.vehicle, 1)
        TriggerEvent('citra-taxi:client:alertPolice')
    end
end)

--ShowTitle Function
function showSubtitle(message, duration)
    BeginTextCommandPrint('STRING')
    AddTextComponentString(message)
    EndTextCommandPrint(duration, true)
end
