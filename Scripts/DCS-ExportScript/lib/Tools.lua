-- Ikarus and D.A.C. Export Script
-- Version 1.0.0 BETA
--
-- Tools
--
-- Copyright by Michael aka McMicha 2014
-- Contact dcs2arcaze.micha@farbpigmente.org

ExportScript.Tools = {}

function ExportScript.Tools.WriteToLog(message)
    if ExportScript.logFile then
		local ltmp, lMiliseconds = math.modf(os.clock())
		if lMiliseconds==0 then 
			lMiliseconds='000' 
		else 
			lMiliseconds=tostring(lMiliseconds):sub(3,5) 
		end
        ExportScript.logFile:write(os.date("%X")..":"..lMiliseconds.." : "..message.."\r\n")
    end
end

function ExportScript.Tools.ProcessInput()
    local lCommand, lCommandArgs, lDevice
    -- C1,3001,4
    -- lComand = C
    -- lCommandArgs[1] = 1 => lDevice
    -- lCommandArgs[2] = 3001
    -- lCommandArgs[3] = 4

    if ExportScript.Config.IkarusExport then
        local lInput,from,port    = ExportScript.UDPsender:receivefrom()

        if lInput then
            if ExportScript.Config.Debug then
                ExportScript.Tools.WriteToLog("lInput: "..lInput..", from: "..from..", port: "..port)
            end
            lCommand = string.sub(lInput,1,1)

            if lCommand == "R" then
                ExportScript.Tools.ResetChangeValues()
            end

            if (lCommand == "C") then
                lCommandArgs = ExportScript.Tools.StrSplit(string.sub(lInput,2),",")
                lDevice = GetDevice(lCommandArgs[1])
                if type(lDevice) == "table" then
                    lDevice:performClickableAction(lCommandArgs[2],lCommandArgs[3])    
                end
            end
        end
    end
    
    if ExportScript.Config.DACExport then
        local lInput2,from2,port2 = ExportScript.UDPListener:receivefrom() -- Hardware

        if lInput2 then
            if ExportScript.Config.Debug then
                ExportScript.Tools.WriteToLog("lInput2: "..lInput2..", from2: "..from2..", port2: "..port2)
            end
            lCommand = string.sub(lInput2,1,1)

            if lCommand == "C" then
                ExportScript.Tools.ResetChangeValuesDAC()
            end

            if (lCommand == "C") then
                lCommandArgs = ExportScript.Tools.StrSplit(string.sub(lInput2,2),",")
                lDevice = GetDevice(lCommandArgs[1])
                if lDevice ~= "1000" then
                    if type(lDevice) == "table" then
                        lDevice:performClickableAction(lCommandArgs[2],lCommandArgs[3])
                    end
                elseif lDevice == "1000" then
                    --ExportScript.genericRadio(key, value, hardware)
                    ExportScript.genericRadio(lCommandArgs[2],lCommandArgs[3], ExportScript.Config.genericRadioHardwareID)
                end
            end
        end
    end
end

function ExportScript.Tools.StrSplit(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local lResult = {}
    local lPat = "(.-)" .. delim .. "()"
    local lNb  = 0
    local lLastPos
    for part, pos in string.gfind(str, lPat) do
        lNb = lNb + 1
        lResult[lNb] = part
        lLastPos = pos
        if lNb == maxNb then break end
    end
    -- Handle the last field
    if lNb ~= maxNb then
        lResult[lNb + 1] = string.sub(str, lLastPos)
    end
    return lResult
end

function ExportScript.Tools.round(num, idp)
  local lMult = 10^(idp or 0)
  return math.floor(num * lMult + 0.5) / lMult
end

-- Status Gathering Functions
function ExportScript.Tools.ProcessArguments(device, arguments)
    local lArgument , lFormat , lArgumentValue
    local lCounter = 0

    if ExportScript.Config.Debug then
        ExportScript.Tools.WriteToLog("======Begin========")
    end

    for lArgument, lFormat in pairs(arguments) do 
        lArgumentValue = string.format(lFormat,device:get_argument_value(lArgument))
        if ExportScript.Config.Debug then
            lCounter = lCounter + 1
            ExportScript.Tools.WriteToLog(lCounter..". ID: "..lArgument..", Fromat: "..lFormat..", Value: "..lArgumentValue)
        end
        if ExportScript.Config.IkarusExport then
            ExportScript.Tools.SendData(lArgument, lArgumentValue)
        end
        if ExportScript.Config.DACExport then
            ExportScript.Tools.SendDataDAC(lArgument, lArgumentValue)
        end
    end
    
    if ExportScript.Config.Debug then
        ExportScript.Tools.WriteToLog("======End========")
    end
end

-- Network Functions for GlassCockpit
function ExportScript.Tools.SendData(id, value)    
    if string.len(value) > 3 and value == string.sub("-0.00000000",1, string.len(value)) then
        value = value:sub(2)
    end
    
    if ExportScript.LastData[id] == nil or ExportScript.LastData[id] ~= value then
        local ldata    =  id .. "=" .. value
        local ldataLen = string.len(ldata)

        if ldataLen + ExportScript.PacketSize > 576 then
            ExportScript.Tools.FlushData()
        end

        table.insert(ExportScript.SendStrings, ldata)
        ExportScript.LastData[id] = value    
        ExportScript.PacketSize   = ExportScript.PacketSize + ldataLen + 1
    end
end

-- Network Functions for DAC
function ExportScript.Tools.SendDataDAC(id, value)
	for hardware=1, #ExportScript.Config.DAC, 1 do
		if ExportScript.Config.DAC[hardware] == nil then
			ExportScript.Tools.WriteToLog("unknown hardware ID '"..hardware.."' for value: '"..id.."="..value.."'")
			return
		end

		if string.len(value) > 3 and value == string.sub("-0.00000000",1, string.len(value)) then
			value = value:sub(2)
		end

		if ExportScript.LastDataDAC[hardware][id] == nil or ExportScript.LastDataDAC[hardware][id] ~= value then
			local ldata    =  id .. "=" .. value
			local ldataLen = string.len(ldata)

			if ldataLen + ExportScript.PacketSizeDAC[hardware] > 576 then
				ExportScript.Tools.FlushDataDAC(hardware)
			end

			table.insert(ExportScript.SendStringsDAC[hardware], ldata)
			ExportScript.LastDataDAC[hardware][id] = value    
			ExportScript.PacketSizeDAC[hardware]   = ExportScript.PacketSizeDAC[hardware] + ldataLen + 1
			--ExportScript.Tools.WriteToLog("id=ldata: "..ldata)
			--ExportScript.Tools.WriteToLog("ExportScript.LastDataDAC["..hardware.."]: "..ExportScript.Tools.dump(ExportScript.LastDataDAC[hardware]))
		end
    end
end

function ExportScript.Tools.FlushData()
    if #ExportScript.SendStrings > 0 then
        local lES_SimID = ""
        if ExportScript.GlassCockpitType == 1 then
            lES_SimID = ExportScript.SimID
        elseif ExportScript.GlassCockpitType == 2 then
            lES_SimID = ""
        end
        local lPacket = lES_SimID .. table.concat(ExportScript.SendStrings, ExportScript.Config.IkarusSeparator) .. "\n"
        ExportScript.socket.try(ExportScript.UDPsender:sendto(lPacket, ExportScript.Config.IkarusHost, ExportScript.Config.IkarusPort))
        ExportScript.SendStrings = {}
        ExportScript.PacketSize  = 0
    end
end

function ExportScript.Tools.FlushDataDAC(hardware)
    hardware = hardware or 1

    if ExportScript.Config.DAC[hardware] == nil then
        ExportScript.Tools.WriteToLog("unknown hardware ID '"..hardware.."'")
        return
    end

    if #ExportScript.SendStringsDAC[hardware] > 0 then
        local lPacket = ExportScript.SimID .. table.concat(ExportScript.SendStringsDAC[hardware], ExportScript.Config.DAC[hardware].Separator) .. "\n"
        ExportScript.socket.try(ExportScript.UDPsender:sendto(lPacket, ExportScript.Config.DAC[hardware].Host, ExportScript.Config.DAC[hardware].SendPort))
        ExportScript.SendStringsDAC[hardware] = {}
        ExportScript.PacketSizeDAC[hardware]  = 0
    end
end

function ExportScript.Tools.ResetChangeValues()
    ExportScript.LastData   = {}
    ExportScript.TickCount  = 10
end

function ExportScript.Tools.ResetChangeValuesDAC()
    for i = 1, #ExportScript.Config.DAC, 1 do
        ExportScript.LastDataDAC[i] = {}
    end
    ExportScript.TickCount         = 10
    ExportScript.TickCountDAC       = 0
end

function ExportScript.Tools.SelectModule()
   -- Select Module...
    ExportScript.FoundDCSModule = false
    ExportScript.FoundFCModule  = false
    ExportScript.FoundNoModul   = true

    local lMyInfo      = LoGetSelfData()
    if lMyInfo == nil then  -- End SelectModule, if don't selected a aircraft
        return
    end
    
    ExportScript.ModuleName = lMyInfo.Name
    local lModuleName       = ExportScript.ModuleName..".lua"
    local lModuleFile       = ""
    
    ExportScript.FoundNoModul = false

    for file in lfs.dir(ExportScript.Config.ExportModulePath) do
        if lfs.attributes(ExportScript.Config.ExportModulePath..file,"mode") == "file" then 
            if file == lModuleName then
                lModuleFile = ExportScript.Config.ExportModulePath..file
            end
        end
    end

    ExportScript.Tools.WriteToLog("File Path: "..lModuleFile)

    if string.len(lModuleFile) > 1 then
        ExportScript.Tools.ResetChangeValuesDAC()
        
        -- load Aircraft File
        dofile(lModuleFile)
        ExportScript.Tools.SendDataDAC("File", lMyInfo.Name)
		for i=1, #ExportScript.Config.DAC, 1 do
            ExportScript.Tools.FlushDataDAC(i)
        end
		ExportScript.Tools.SendData("File", lMyInfo.Name)
        ExportScript.Tools.FlushData()
        
        ExportScript.Tools.WriteToLog("File '"..lModuleFile.."' loaded")
        
        ExportScript.FirstNewDataSend      = true
        ExportScript.FirstNewDataSendCount = 5

        if ExportScript.FoundDCSModule then
            local lCounter = 0
            for k, v in pairs(ExportScript.ConfigEveryFrameArguments) do
                lCounter = lCounter + 1
            end
            if ExportScript.Config.Debug then
                ExportScript.Tools.WriteToLog("ExportScript.ConfigEveryFrameArguments Count: "..lCounter)
            end
            if lCounter > 0 then
                ExportScript.EveryFrameArguments = ExportScript.ConfigEveryFrameArguments
            else
                -- no Arguments
                ExportScript.EveryFrameArguments = {}
            end
            lCounter = 0
            for k, v in pairs(ExportScript.ConfigArguments) do
                lCounter = lCounter + 1
            end
            if ExportScript.Config.Debug then
                ExportScript.Tools.WriteToLog("ExportScript.ConfigArguments Count: "..lCounter)
            end
            if lCounter > 0 then
                ExportScript.Arguments = ExportScript.ConfigArguments
            else
                -- no Arguments
                ExportScript.Arguments = {}
            end

            ExportScript.ProcessIkarusDCSHighImportance = ExportScript.ProcessIkarusDCSConfigHighImportance
            ExportScript.ProcessIkarusDCSLowImportance  = ExportScript.ProcessIkarusDCSConfigLowImportance
            ExportScript.ProcessDACHighImportance       = ExportScript.ProcessDACConfigHighImportance
            ExportScript.ProcessDACLowImportance        = ExportScript.ProcessDACConfigLowImportance

        elseif ExportScript.FoundFCModule then
            ExportScript.ProcessIkarusFCHighImportance  = ExportScript.ProcessIkarusFCHighImportanceConfig
            ExportScript.ProcessIkarusFCLowImportance   = ExportScript.ProcessIkarusFCLowImportanceConfig
            ExportScript.ProcessDACHighImportance       = ExportScript.ProcessDACConfigHighImportance
            ExportScript.ProcessDACLowImportance        = ExportScript.ProcessDACConfigLowImportance
        else
            ExportScript.Tools.WriteToLog("Unknown Module Type: "..lMyInfo.Name)
        end

    else -- Unknown Module
        ExportScript.ProcessIkarusDCSHighImportance     = ExportScript.ProcessIkarusDCSHighImportanceNoConfig
        ExportScript.ProcessIkarusDCSLowImportance      = ExportScript.ProcessIkarusDCSLowImportanceNoConfig
        ExportScript.ProcessIkarusFCHighImportance      = ExportScript.ProcessIkarusFCHighImportanceNoConfig
        ExportScript.ProcessIkarusFCLowImportance       = ExportScript.ProcessIkarusFCLowImportanceNoConfig
        ExportScript.ProcessDACHighImportance           = ExportScript.ProcessDACHighImportanceNoConfig
        ExportScript.ProcessDACLowImportance            = ExportScript.ProcessDACLowImportanceNoConfig
        ExportScript.EveryFrameArguments                = {}
        ExportScript.Arguments                          = {}
        ExportScript.Tools.WriteToLog("Unknown Module Name: "..lMyInfo.Name)
    end
end

-- The ExportScript.Tools.dump function show the content of the specified variable.
-- ExportScript.Tools.dump is similar to PHP function dump and show variables from type
-- "nil, "number", "string", "boolean, "table", "function", "thread" and "userdata"
function ExportScript.Tools.dump(var, depth)
        depth = depth or 0
        if type(var) == "string" then
            return 'string: "' .. var .. '"\n'
        elseif type(var) == "nil" then
            return 'nil\n' 
        elseif type(var) == "number" then
            return 'number: "' .. var .. '"\n'
        elseif type(var) == "boolean" then
            return 'boolean: "' .. tostring(var) .. '"\n'
        elseif type(var) == "function" then
            if debug and debug.getinfo then
                fcnname = tostring(var)
                local info = debug.getinfo(var, "S")
                if info.what == "C" then
                    return string.format('%q', fcnname .. ', C function') .. '\n'
                else 
                    if (string.sub(info.source, 1, 2) == [[./]]) then
                        return string.format('%q', fcnname .. ', defined in (' .. info.linedefined .. '-' .. info.lastlinedefined .. ')' .. info.source) ..'\n'
                    else
                        return string.format('%q', fcnname .. ', defined in (' .. info.linedefined .. '-' .. info.lastlinedefined .. ')') ..'\n'
                    end
                end                
            else
                return 'a function\n'    
            end
        elseif type(var) == "thread" then
            return 'thread\n'
        elseif type(var) == "userdata" then
            return tostring(var)..'\n'
        elseif type(var) == "table" then
                depth = depth + 1
                out = "{\n"
                for k,v in pairs(var) do
                        out = out .. (" "):rep(depth*4).. "["..k.."] = " .. ExportScript.Tools.dump(v, depth)
                end
                return out .. (" "):rep((depth-1)*4) .. "}\n"
        else 
                return tostring(var) .. "\n"
        end
end

-- round function for math libraray
-- number  : value
-- decimals: number of decimal
-- method  :  ceil: Returns the smallest integer larger than or equal to number
--           floor: Returns the smallest integer smaller than or equal to number
function ExportScript.Tools.round(number, decimals, method)
    if string.find(number, "%p" ) ~= nil then
        decimals = decimals or 0
        local lFactor = 10 ^ decimals
        if (method == "ceil" or method == "floor") then
            -- ceil: Returns the smallest integer larger than or equal to number
            -- floor: Returns the smallest integer smaller than or equal to number
            return math[method](number * lFactor) / lFactor
        else
            return tonumber(("%."..decimals.."f"):format(number))
        end
    else
        return number
    end
end

-- split function for string libraray
-- stringvalue: value
-- delimiter  : delimiter for split
-- for example, see http://www.lua.org/manual/5.1/manual.html#5.4.1
function ExportScript.Tools.split(stringvalue, delimiter)
    result = {};
    for match in (stringvalue..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end


-- Pointed to by ExportScript.ProcessIkarusDCSHighImportance, if the player aircraft is something else
function ExportScript.ProcessIkarusDCSHighImportanceNoConfig(mainPanelDevice)
end
-- Pointed to by ExportScript.ProcessIkarusDCSLowImportance, if the player aircraft is something else
function ExportScript.ProcessIkarusDCSLowImportanceNoConfig(mainPanelDevice)
end

-- the player aircraft is a Flaming Cliffs or similar aircraft
function ExportScript.ProcessIkarusFCHighImportanceNoConfig()
end
function ExportScript.ProcessIkarusFCLowImportanceNoConfig()
end

-- Hardware exports
function ExportScript.ProcessDACHighImportanceNoConfig(mainPanelDevice)
end
function ExportScript.ProcessDACLowImportanceNoConfig(mainPanelDevice)
end