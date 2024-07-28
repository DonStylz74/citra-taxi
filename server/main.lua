if Config.framework == 'qb' then
    -- Variables
    local QBCore = exports['qb-core']:GetCoreObject()

    -- Commands
    QBCore.Commands.Add('taxi', 'Call a taxi', {}, false, function(source, _, _)
        TriggerClientEvent('citra-taxi:client:callOrCancelTaxi', source)
    end, 'user')

    QBCore.Commands.Add('stophere', 'Taxi to Stop', {}, false, function(source, _, _)
        TriggerClientEvent('citra-taxi:client:taxiStop', source)
    end, 'user')

    -- QBCore.Commands.Add('taxigo', 'Get taxi to go to waypoint', {}, false, function(source, _, _)
    --     TriggerClientEvent('citra-taxi:client:setDestination', source)
    -- end, 'user')

    -- QBCore.Commands.Add('taxifast', 'Tell driver to speed up', {}, false, function(source, _, _)
    --     TriggerClientEvent('citra-taxi:client:speedUp', source)
    -- end, 'user')

    -- QBCore.Commands.Add('taxislow', 'Tell driver to slow down', {}, false, function(source, _, _)
    --     TriggerClientEvent('citra-taxi:client:speedDown', source)
    -- end, 'user')

    -- Events
    RegisterNetEvent('citra-taxi:server:payFare', function(time)
        local src = source
        --local fare = math.ceil(Config.Fare.base + (Config.Fare.tick * (time / Config.Fare.tickTime)))
        local fare = Config.Fare.base + (Config.Fare.tick * math.floor(time / Config.Fare.tickTime))


        if fare > 0 then
            local Player = QBCore.Functions.GetPlayer(src)
            if Player.Functions.RemoveMoney('cash', fare, 'Taxi fare') then
                TriggerClientEvent('citra-taxi:client:farePaid', src, fare)
            elseif Player.Functions.RemoveMoney('money', fare, 'Taxi fare') then
                TriggerClientEvent('citra-taxi:client:farePaid', src, fare)
            else
                local data = { description = "You don't have enough money. Calling the cops!", type = "warning", position = "top-right" }
	            TriggerClientEvent('ox_lib:notify', src, data)
                TriggerClientEvent('citra-taxi:client:alertPolice', src)
            end
        end
    end)
elseif Config.framework == 'esx' then
    -- Variables
    local ESX = exports["es_extended"]:getSharedObject()

    -- Commands
    RegisterCommand('taxi', function(source)
        TriggerClientEvent('citra-taxi:client:callOrCancelTaxi', source)
    end)

    RegisterCommand('taxigo', function(source)
        TriggerClientEvent('citra-taxi:client:setDestination', source)
    end)

    RegisterCommand('taxifast', function(source)
        TriggerClientEvent('citra-taxi:client:speedUp', source)
    end)

    RegisterCommand('taxislow', function(source)
        TriggerClientEvent('citra-taxi:client:speedDown', source)
    end)

    -- Events
    RegisterNetEvent('citra-taxi:server:payFare', function(time)
        local src = source
        local fare = math.ceil(Config.Fare.base + (Config.Fare.tick * (time / Config.Fare.tickTime)))

        if fare > 0 then
            local xPlayer = ESX.GetPlayerFromId(src)
            xPlayer.removeMoney(fare)
            TriggerClientEvent('citra-taxi:client:farePaid', src, fare)
        end
    end)
end
