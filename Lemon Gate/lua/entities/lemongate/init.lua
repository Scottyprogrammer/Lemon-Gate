/*==============================================================================================
	Expression Advanced: Server Side Gate Entity.
	Purpose: This is the entity that does everything!
	Creditors: Rusketh
==============================================================================================*/
local E_A = LemonGate
local API = E_A.API

local Lemon = ENT
Lemon.IsLemonGate = true 

local ShortTypes = E_A.TypeShorts
local Operators = E_A.OperatorTable

local Tokenizer = E_A.Tokenizer
local Parser = E_A.Parser
local Compiler = E_A.Compiler

local CheckType = E_A.CheckType
local GetLongType = E_A.GetLongType
local GetShortType = E_A.GetShortType
local ValueToOp = E_A.ValueToOp

local UpperStr = string.upper -- Speed
local FormatStr = string.format -- Speed
local MathCeil = math.ceil -- Speed

local CurTime = CurTime -- Speed
local pairs = pairs -- Speed
local pcall = pcall -- Speed

local GoodColor = Color(255, 255, 255, 255)
local BadColor = Color(255, 0, 0, 0)

local MaxPerf = CreateConVar("lemongate_perf", "50000")

-- Other Files:
include("shared.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

/*==============================================================================================
	Section: Entity
==============================================================================================*/
function Lemon:Initialize( )
	-- Purpose: Initializes the Gate with physics.
	
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )
	
	self.Inputs = WireLib.CreateInputs( self, {} )
	self.Outputs = WireLib.CreateOutputs( self, {} )
	
	self.Name = "LemonGate"
	self.Errored = nil
	
	self:SetOverlayText( "LemonGate\nExpression Advanced\nOffline: 0%" )
	
	API.AddGate( self ) -- Let the api know this gate exists!
end

function Lemon:Think( )
	-- Purpose: Makes the entity think?
	
	local Time = CurTime( )
	
	if !self.Errored and self.Context then
		if Time > self.PerfTime then
			self.PerfTime = Time + 1
			local _A, _B, Percent = self:CaculatePerf( )
			self:UpdateOverlay( "Online: %i%%", Percent )
		end
		
		self:CallEvent( "think" )
		API.CallHook( "GateThink", self )
	end
	
	self.BaseClass.Think( self )
	self:NextThink( Time + 0.1 )
	return true
end

function Lemon:OnRemove() 
	self:CallEvent( "final" )
	API.CallHook( "ShutDown", self )
	API.RemoveGate( self ) -- Update the API.
end

/*==============================================================================================
	Section: Code Compiler
==============================================================================================*/
function Lemon:GetScript( )
	return self.Script or ""
end

function Lemon:LoadScript( Script )
	API.CallHook( "LoadScript", self, Script )
	self.Script = Script
	
	local Check, Tokens = Tokenizer.Execute( Script )
	if !Check then
		self:UpdateOverlay( "Failed to compile." )
		return WireLib.ClientError( Tokens, self.Player )
	end
	
	local Check, Instructions = Parser.Execute( Tokens )
	if !Check then
		self:UpdateOverlay( "Failed to compile." )
		return WireLib.ClientError( Instructions, self.Player )
	end
	
	local Check, Executable, Instance = Compiler.Execute( Instructions )
	if !Check then
		self:UpdateOverlay( "Failed to compile." )
		return WireLib.ClientError( Executable, self.Player )
	end
	
	self:LoadInstance( Instance )
	
	self.Executable = Executable
end

function Lemon:LoadInstance( Instance )
	self.Context = {
		Types = Instance.VarTypes, StackTrace = { },
		Memory = { }, Delta = { }, Click = { },
		Entity = self, Player = self.Player,
		Events = { }, VariantTypes = { }, WireLinkQue = { },
		Perf = MaxPerf:GetInt( ), 
	}
	
	setmetatable( self.Context, E_A.Context )
	
	self.InMemory = Instance.Inputs
	self.OutMemory = Instance.Outputs
	
	self.LastPerf = 0
	self.PerfTime = 0
	
	self:RefreshMemory()
	
end

/*==============================================================================================
	Section: Memory Handlers.
==============================================================================================*/
function Lemon:RefreshMemory( )
	-- Purpose: Clears and recreates the memory of the entire chip.
	
	API.CallHook( "BuildContext", self, Instance )
	
	local Context, PortLookUp = self.Context, { }
	local Memory, Delta, Types = Context.Memory, Context.Delta, Context.Types
	local _Inputs, _Outputs = self.Inputs, self.Outputs
	
/*****************************************************************************/
--	INPUTS:

	local InPuts, InTypes, I = { }, { }, 0 
	for Cell, Name in pairs( self.InMemory ) do
		PortLookUp[Name] = Cell
		
		local Type = ShortTypes[Types[Cell]]
		local WireName = Type[4] -- Wiremod type name.
		
		if !WireName or !Type[5] then
			return self:ScriptError( "Type '" .. Type[1] .. "' may not be used as input." )
		end
		
		local LastValue = _Inputs[Name] -- Restore input memory!
		
		if LastValue and LastValue.Type == WireName then
			Type[5]( Context, Cell, LastValue.Value )
		else
			Memory[Cell] = Type[3]( Context )
		end
		
		I = I + 1
		InPuts[I] = Name
		InTypes[I] = WireName
	end
	
	self.Inputs = WireLib.CreateSpecialInputs( self, InPuts, InTypes )
	
	for Key, _Input in pairs( _Inputs )  do
		local Input = self.Inputs[Key]
		if Input and Input.Type == _Input.Type then
			Input.Value = _Input.Value -- Restore input values.
		end
	end
	
/*****************************************************************************/
--	OUTPUTS:

	local Outputs, OutTypes, I = {}, {}, 0
	for Cell, Name in pairs( self.OutMemory ) do
		PortLookUp[Name] = Cell
		
		local Type = ShortTypes[Types[Cell]]
		local WireName = Type[4]
		
		if !WireName or !Type[6] then
			return self:ScriptError( "Type '" .. Type[1] .. "' may not be used as output." )
		end
		
		Memory[Cell] = Type[3]( Context )
		
		I = I + 1
		Outputs[I] = Name
		OutTypes[I] = WireName
	end
	
	self.Outputs = WireLib.CreateSpecialOutputs(self, Outputs, OutTypes)
	
	self.PortLookUp = PortLookUp
	
	self.Name = "LemonGate"
	self.Errored = nil
	self.LastPerf = 0
end

/*==============================================================================================
	Section: Wire Mod Stuff
==============================================================================================*/
function Lemon:TriggerInput( Key, Value )
	local Context = self.Context
	
	if !self.Errored and Context then
		local Cell = self.PortLookUp[Key]
		
		if Cell then
			ShortTypes[ Context.Types[Cell] ][5]( Context, Cell, Value )
			Context.Click[Cell] = true
			self:CallEvent( "trigger", E_A.ValueToOp( Key, "s" ) )
			Context.Click[Cell] = false
		end
	end
end

function Lemon:TriggerOutputs()
	local Context = self.Context
	local Memory, Types, Click = Context.Memory, Context.Types, Context.Click
	
	for Cell, Name in pairs( self.OutMemory ) do
		
		if Click[Cell] then
			local Value = ShortTypes[Types[Cell]][6]( Context, Cell )
			WireLib.TriggerOutput( self, Name, Value )
			Click[Cell] = false
		end
	end
	
	API.CallHook( "TriggerOutputs", self )
end

/*==============================================================================================
	Section: Executions.
==============================================================================================*/
local SafeCall = E_A.SafeCall

function Lemon:Restart()
	API.CallHook("ShutDown", self)
	self:RefreshMemory()
	self:Execute()
end

function Lemon:Execute()
	local Executable, Context = self.Executable, self.Context
	
	if Executable and Context then
		self:SetColor(GoodColor)
		self:UpdateOverlay("Online: 0%%")
		
		local Ok, Exit = SafeCall( Executable, Context )
	
		if !Ok and Exit ~= "exit" then
			return self:Exit( Exit )
		end	-- Inproper exit!
			
		self:TriggerOutputs()
	end
end

function Lemon:CallEvent( Name, ... )
	local Context = self.Context
	
	if !self.Errored and Context then
		local Event = Context.Events[ Name ]
		if Event then
			Event[1](Context, { ... })
			local Ok, Exit = SafeCall( Event[2], Context )
			
			if Ok or Exit == "Exit" then
				return self:TriggerOutputs()
			elseif Exit == "Return" then
				self:TriggerOutputs()
				return Context.ReturnValue( Context )
			else
				return self:Exit( Exit )
			end
		end
	end
end

/*==============================================================================================
	Section: Erroring!
==============================================================================================*/
function Lemon:Exit( Exit )
	if Exit == "Exception" and self.Context then
		local Exception = self.Context.Exception
		
		if Exception.Type == "script" then
			return self:ScriptError( Exception.Msg )
		else
			return self:ScriptError("uncatched exception '" .. Exception.Type .. "' in main thread")
		end
	end
	
	if Exit == "Return" or Exit == "Break" or Exit == "Continue" then
		return self:ScriptError("unexpected use of " .. Exit .. " in main thread")
	end
	
	return self:LuaError( Exit )
end

function Lemon:LuaError(Message)
	Message = Message or "Unkown Error"
	
	self.Errored = true
	self:SetColor(BadColor)
	API.CallHook("ShutDown", self)
	self:UpdateOverlay("LUA Error")
	MsgN("LemonGate LUA: " .. Message)
	WireLib.ClientError("LemonGate: Suffered a LUA error" , self.Player)
end

function Lemon:ScriptError(Message)
	Message = Message or "Unexpected Error"
	
	if self.Exception then
		local StackTrace = self.Exception.Trace
		local Trace = StackTrace[#StackTrace]
		if Trace then Message = Message .. " at Line " .. Trace[1] .. " Char " .. Trace[2] end
	end
	
	self.Errored = true
	self:SetColor(BadColor)
	API.CallHook("ShutDown", self)
	self:UpdateOverlay("Script Error")
	WireLib.ClientError(Message, self.Player)
end

/*==============================================================================================
	Section: Name and Overlay.
==============================================================================================*/
function Lemon:SetGateName(Name)
	self.Name = Name or "LemonGate"
end

function Lemon:UpdateOverlay(Status, Info, ...)
	if Info then Status = FormatStr(Status, Info, ...) end
	
	self:SetOverlayText(FormatStr("%s\n%s", self.Name, Status ))
end

/*==============================================================================================
	Section: Performance points
==============================================================================================*/
function Lemon:CaculatePerf(NoUpdate)
	local Context = self.Context
	if Context then
		local Perf, MaxPerf, Percent = Context.Perf, MaxPerf:GetInt(), 0
		Perf = (MaxPerf - Perf)
		
		if !NoUpdate then 
			Context.Perf = MaxPerf
			self.LastPerf = Perf
		end
			
		if Perf ~= MaxPerf then
			Percent = MathCeil((Perf / MaxPerf) * 100)
		end
		
		return Perf, MaxPerf, Percent
	end
	
	return 0, 0, 0
end

/*==============================================================================================
	Section: Duplication
==============================================================================================*/
function ENT:BuildDupeInfo( )
	local DupeTable = self.BaseClass.BuildDupeInfo( self )
	
	DupeTable.Script = self.Script
	
	API.CallHook("BuildDupeInfo", self, DupeTable)
	
	return DupeTable
end

function ENT:ApplyDupeInfo(Player, Entity, DupeTable, FromID)
	self.BaseClass.ApplyDupeInfo(self, Player, Entity, DupeTable, FromID)
	self.Player = Player
	
	self:LoadScript( DupeTable.Script or "" )
	self:Execute( )
	
	API.CallHook("ApplyDupeInfo", self, DupeTable, FromID)
end