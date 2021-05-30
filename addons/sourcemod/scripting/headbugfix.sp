#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "dhooks"
#include "glib/assertutils"
#include "glib/addressutils"

#define SNAME "[HeadBugFix] "

public Plugin myinfo = 
{
	name = "HeadBugFix",
	description = "Fixes headbug bbox exploits",
	author = "GAMMA CASE",
	version = "1.0.0",
};

Handle gUpdateCollisionBounds;
Handle gSetCollisionBounds;
EngineVersion gEngineVersion;

int gFlagsPropOffset = -1;
bool gLate;

float gCSSStandingBBox[][] = {
	{ -16.0, -16.0, 0.0 },
	{ 16.0, 16.0, 62.0}
};

float gCSSDuckingBBox[][] = {
	{ -16.0, -16.0, 0.0 },
	{ 16.0, 16.0, 45.0}
};

public void OnPluginStart()
{
	gEngineVersion = GetEngineVersion();
	ASSERT_MSG(gEngineVersion == Engine_CSS || gEngineVersion == Engine_CSGO, "This plugin is only supported for CSGO and CSS.");
	
	GameData gd = new GameData("headbugfix.games");
	
	SetupSDKCalls(gd);
	SetupDhooks(gd);
	
	delete gd;
	
	if(gLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i))
				continue;
			
			OnClientPutInServer(i);
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gLate = late;
}

void SetupSDKCalls(GameData gd)
{
	if(gEngineVersion == Engine_CSGO)
	{
		//CBasePlayer::UpdateCollisionBounds
		StartPrepSDKCall(SDKCall_Raw);
		
		ASSERT_MSG(PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CBasePlayer::UpdateCollisionBounds"), "Failed to find signature for \"CBasePlayer::UpdateCollisionBounds\".");
		
		gUpdateCollisionBounds = EndPrepSDKCall();
		ASSERT_MSG(gUpdateCollisionBounds, "Failed to setup sdkcall to \"CBasePlayer::UpdateCollisionBounds\".");
	}
	else
	{
		//CCollisionProperty::SetCollisionBounds
		StartPrepSDKCall(SDKCall_Raw);
		
		ASSERT_MSG(PrepSDKCall_SetFromConf(gd, SDKConf_Signature, "CCollisionProperty::SetCollisionBounds"), "Failed to find signature for \"CCollisionProperty::SetCollisionBounds\".");
		
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
		PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
		
		gSetCollisionBounds = EndPrepSDKCall();
		ASSERT_MSG(gSetCollisionBounds, "Failed to setup sdkcall to \"CCollisionProperty::SetCollisionBounds\".");
	}
}

void SetupDhooks(GameData gd)
{
	//CCSGameMovement::Duck
	DynamicDetour dhook = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address);
	
	ASSERT_MSG(dhook.SetFromConf(gd, SDKConf_Signature, "CCSGameMovement::Duck"), "Failed to find signature for \"CCSGameMovement::Duck\".");
	
	ASSERT_MSG(dhook.Enable(Hook_Post, Duck_Dhook), "Failed to enable detour for \"CCSGameMovement::Duck\".");
}

public MRESReturn Duck_Dhook(Address pThis)
{
	// pThis + 4 refers to player member of gamemovement instance.
	if(gEngineVersion == Engine_CSGO)
	{
		SDKCall(gUpdateCollisionBounds, LoadFromAddress(pThis + 4, NumberType_Int32));
	}
	else if(gFlagsPropOffset != -1)
	{
		static int collision_offset = -1;
		
		if(collision_offset == -1)
		{
			collision_offset = FindSendPropInfo("CBasePlayer", "m_Collision");
			ASSERT_MSG(collision_offset != -1, "Failed to find \"CBasePlayer::m_Collision\" prop.");
		}
		
		Address player = view_as<Address>(LoadFromAddress(pThis + 4, NumberType_Int32));
		int buttons = LoadFromAddress(player + gFlagsPropOffset, NumberType_Int32);
		
		if(buttons & FL_DUCKING)
			SDKCall(gSetCollisionBounds, player + collision_offset, gCSSDuckingBBox[0], gCSSDuckingBBox[1]);
		else
			SDKCall(gSetCollisionBounds, player + collision_offset, gCSSStandingBBox[0], gCSSStandingBBox[1]);
	}
}

public void OnClientPutInServer(int client)
{
	if(gFlagsPropOffset == -1)
	{
		gFlagsPropOffset = FindDataMapInfo(client, "m_fFlags");
		ASSERT_MSG(gFlagsPropOffset != -1, "Failed to find \"m_fFlags\" prop.");
	}
}

