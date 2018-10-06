 // Header to go here

/*
    Kigen's Anti-Cheat
    Copyright (C) 2007-2011 CodingDirect LLC

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

//- Pre-processor Defines -//
#define PLUGIN_VERSION "1.2.2.0-B"
#define PLUGIN_BUILD 1

#define GAME_OTHER	0
#define GAME_CSS	1
#define GAME_TF2	2
#define GAME_DOD	3
#define GAME_INS	4
#define GAME_L4D	5
#define GAME_L4D2	6
#define GAME_HL2DM	7
#define GAME_CSGO	8

//- SM Includes -//
#include <sourcemod>
#include <sdktools>
#undef REQUIRE_EXTENSIONS
#include <sdkhooks>

//- Natives -// // Too LAZZZYY for includes
native void SBBanPlayer(client, target, time, char[] reason);
native void SBPP_BanPlayer(int iAdmin, int iTarget, int iTime, const char[] sReason);

//- Global Variables -//
bool g_bConnected[MAXPLAYERS + 1] =  { false, ... }; // I use these instead of the natives because they are cheaper to call
bool g_bAuthorized[MAXPLAYERS + 1] =  { false, ... }; // when I need to check on a client's state.  Natives are very taxing on
bool g_bInGame[MAXPLAYERS + 1] =  { false, ... }; // system resources as compared to these. - Kigen
bool g_bIsAdmin[MAXPLAYERS + 1] =  { false, ... };
bool g_bIsFake[MAXPLAYERS + 1] =  { false, ... };
bool g_bSourceBans = false;
bool g_bSourceBansPP = false;
bool g_bMapStarted = false;
Handle g_hCLang[MAXPLAYERS + 1] =  { INVALID_HANDLE, ... };
Handle g_hSLang = INVALID_HANDLE;
Handle g_hValidateTimer[MAXPLAYERS + 1] =  { INVALID_HANDLE, ... };
Handle g_hDenyArray = INVALID_HANDLE;
Handle g_hClearTimer = INVALID_HANDLE;
Handle g_hCVarVersion = INVALID_HANDLE;
int g_iGame = GAME_OTHER; // Game identifier.

//- KAC Modules -// Note: The ordering of these includes are imporant.
#include "kigenac/translations.sp"	// Translations Module - NEEDED FIRST
#include "kigenac/client.sp"		// Client Module
#include "kigenac/commands.sp"		// Commands Module
#include "kigenac/cvars.sp"		// CVar Module
#include "kigenac/eyetest.sp"		// Eye Test Module
#include "kigenac/network.sp"		// Network Module
#include "kigenac/rcon.sp"		// RCON Module
#include "kigenac/status.sp"		// Status Module
#include "kigenac/stocks.sp"		// Stocks Module


public Plugin myinfo = 
{
	name = "Kigen's Anti-Cheat", 
	author = "CodingDirect LLC (Playa Edit)", 
	description = "The greatest thing since sliced pie", 
	version = PLUGIN_VERSION, 
	url = "FunForBattle"
}

//- Plugin Functions -//

// SourceMod 1.3 uses the new native AskPluginLoad2 so that APLRes can be used.
public APLRes AskPluginLoad2(Handle myself, bool late, String:error[], err_max)
{
	MarkNativeAsOptional("SDKHook");
	MarkNativeAsOptional("SDKUnhook");
	MarkNativeAsOptional("SBBanPlayer");
	MarkNativeAsOptional("SBPP_BanPlayer");
	return APLRes_Success;
}

public OnPluginStart()
{
	Handle f_hTemp;
	char f_sGame[64], f_sLang[8];
	
	g_hDenyArray = CreateTrie();
	
	//- Identify the game -//
	GetGameFolderName(f_sGame, sizeof(f_sGame));
	if (StrEqual(f_sGame, "cstrike"))
		g_iGame = GAME_CSS;
	else if (StrEqual(f_sGame, "dod"))
		g_iGame = GAME_DOD;
	else if (StrEqual(f_sGame, "tf"))
		g_iGame = GAME_TF2;
	else if (StrEqual(f_sGame, "insurgency"))
		g_iGame = GAME_INS;
	else if (StrEqual(f_sGame, "left4dead"))
		g_iGame = GAME_L4D;
	else if (StrEqual(f_sGame, "left4dead2"))
		g_iGame = GAME_L4D2;
	else if (StrEqual(f_sGame, "hl2mp"))
		g_iGame = GAME_HL2DM;
	else if (StrEqual(f_sGame, "csgo"))
		g_iGame = GAME_CSGO;
	
	
	//- Module Calls -//
	Status_OnPluginStart();
	Client_OnPluginStart()
	Commands_OnPluginStart();
	CVars_OnPluginStart();
	Eyetest_OnPluginStart();
	Network_OnPluginStart();
	RCON_OnPluginStart();
	Trans_OnPluginStart();
	#if defined PRIVATE
	Private_OnPluginStart();
	#endif
	
	//- Get server language -//
	GetLanguageInfo(GetServerLanguage(), f_sLang, sizeof(f_sLang));
	if (!GetTrieValue(g_hLanguages, f_sLang, any:g_hSLang)) // If we can't find the server's language revert to English. - Kigen
		GetTrieValue(g_hLanguages, "en", any:g_hSLang);
	
	g_hClearTimer = CreateTimer(14400.0, KAC_ClearTimer, _, TIMER_REPEAT); // Clear the Deny Array every 4 hours.
	
	
	//- Prevent Speeds -//
	f_hTemp = FindConVar("sv_max_usercmd_future_ticks");
	if (f_hTemp != INVALID_HANDLE)
		SetConVarInt(f_hTemp, 1);
	
	AutoExecConfig(true, "kigenac");
	
	g_hCVarVersion = CreateConVar("kac_version", PLUGIN_VERSION, "KAC version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	// "notify" - So that we appear on server tracking sites.  "dontrecord" - So that we don't get saved to the auto cfg.
	SetConVarFlags(g_hCVarVersion, FCVAR_NOTIFY | FCVAR_DONTRECORD); // Make sure "dontrecord" is there so that AutoExecConfig won't auto generate kac_version into the cfg file.
	SetConVarString(g_hCVarVersion, PLUGIN_VERSION);
	HookConVarChange(g_hCVarVersion, VersionChange);
	
	KAC_PrintToServer(KAC_LOADED);
} // You are here because of the Client_OnMapStart Warning right? Well, i really dont know why it spits that out but its on my TODO

public OnAllPluginsLoaded()
{
	char f_sReason[256], f_sAuthID[64];
	
	if(FindPluginByFile("sourcebans.smx"))
		g_bSourceBans = true;
		
	else if(FindPluginByFile("sbpp_main.smx"))
		g_bSourceBansPP = true;
		
	//- Module Calls -//
	Commands_OnAllPluginsLoaded();
	
	//- Late load stuff -//
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i))
		{
			if(!OnClientConnect(i, f_sReason, sizeof(f_sReason)))
			{
				KickClient(i, "%s", f_sReason);
				continue;
			}
			
			if(IsClientAuthorized(i) && GetClientAuthId(i, AuthId_Steam3, f_sAuthID, sizeof(f_sAuthID))) // GetClientAuthString(i, f_sAuthID, sizeof(f_sAuthID))
			{
				OnClientAuthorized(i, f_sAuthID);
				OnClientPostAdminCheck(i);
			}
			
			if(IsClientInGame(i))
				OnClientPutInServer(i);
		}
	}
}

public OnPluginEnd()
{
	//Client_OnPluginEnd(); // Currently unused
	Commands_OnPluginEnd();
	Eyetest_OnPluginEnd();
	Network_OnPluginEnd();
	RCON_OnPluginEnd();
	//Status_OnPluginEnd(); // Currently unused
	#if defined PRIVATE
	Private_OnPluginEnd();
	#endif
	for (new i = 0; i <= MaxClients; i++)
	{
		g_bConnected[i] = false;
		g_bAuthorized[i] = false;
		g_bInGame[i] = false;
		g_bIsAdmin[i] = false;
		g_hCLang[i] = g_hSLang;
		g_bShouldProcess[i] = false;
		
		if (g_hValidateTimer[i] != INVALID_HANDLE)
			CloseHandle(g_hValidateTimer[i]);
		
		CVars_OnClientDisconnect(i);
	}
	
	if (g_hClearTimer != INVALID_HANDLE)
		CloseHandle(g_hClearTimer);
}

//- Map Functions -//

public OnMapStart()
{
	g_bMapStarted = true;
	CVars_CreateNewOrder();
	//Client_OnMapStart(); // Currently unused 
	RCON_OnMap();
}

public OnMapEnd()
{
	g_bMapStarted = false;
	Client_OnMapEnd();
	RCON_OnMap();
}

//- Client Functions -//

public bool OnClientConnect(client, char[] rejectmsg, size)
{
	if(IsFakeClient(client)) // Bots suck.
	{
		g_bIsFake[client] = true;
		return true;
	}
	
	g_bConnected[client] = true;
	g_hCLang[client] = g_hSLang;
	
	return Client_OnClientConnect(client, rejectmsg, size);
}

public OnClientAuthorized(client, const char[] auth)
{
	if(IsFakeClient(client)) // Bots are annoying...
		return;
		
	Handle f_hTemp;
	char f_sReason[256];
	
	if(GetTrieString(g_hDenyArray, auth, f_sReason, sizeof(f_sReason)))
	{
		KickClient(client, "%s", f_sReason);
		OnClientDisconnect(client);
		return;
	}
	
	g_bAuthorized[client] = true;
	
	if(g_bInGame[client])
		g_hPeriodicTimer[client] = CreateTimer(0.1, CVars_PeriodicTimer, client);
		
	f_hTemp = g_hValidateTimer[client];
	g_hValidateTimer[client] = INVALID_HANDLE;
	if(f_hTemp != INVALID_HANDLE)
		CloseHandle(f_hTemp);
}

public OnClientPutInServer(client)
{
	Eyetest_OnClientPutInServer(client); // Ok, we'll help them bots too.
	
	if (IsFakeClient(client)) // Death to them bots!
		return;
		
	char f_sLang[8];
	
	g_bInGame[client] = true;
	
	if (!g_bAuthorized[client]) // Not authorized yet?!?
		g_hValidateTimer[client] = CreateTimer(10.0, KAC_ValidateTimer, client);
		
	else
		g_hPeriodicTimer[client] = CreateTimer(0.1, CVars_PeriodicTimer, client);
		
	GetLanguageInfo(GetClientLanguage(client), f_sLang, sizeof(f_sLang));
	if (!GetTrieValue(g_hLanguages, f_sLang, g_hCLang[client]))
		g_hCLang[client] = g_hSLang;
}

public OnClientPostAdminCheck(client)
{
	if(IsFakeClient(client)) // Humans for the WIN!
		return;
		
	if((GetUserFlagBits(client) & ADMFLAG_GENERIC))
		g_bIsAdmin[client] = true;
}

public OnClientDisconnect(client)
{
	// if ( IsFake aww, screw it. :P
	Handle f_hTemp;
	
	g_bConnected[client] = false;
	g_bAuthorized[client] = false;
	g_bInGame[client] = false;
	g_bIsAdmin[client] = false;
	g_bIsFake[client] = false;
	g_hCLang[client] = g_hSLang;
	g_bShouldProcess[client] = false;
	g_bHooked[client] = false;
	
	for(new i = 1; i <= MaxClients; i++)
	if(g_bConnected[i] && (!IsClientConnected(i) || IsFakeClient(i)))
		OnClientDisconnect(i);
		
	f_hTemp = g_hValidateTimer[client];
	g_hValidateTimer[client] = INVALID_HANDLE;
	if(f_hTemp != INVALID_HANDLE)
		CloseHandle(f_hTemp);
		
	CVars_OnClientDisconnect(client);
	Network_OnClientDisconnect(client);
	
}

//- Timers -//

public Action KAC_ValidateTimer(Handle timer, any client)
{
	g_hValidateTimer[client] = INVALID_HANDLE;
	
	if (!g_bInGame[client] || g_bAuthorized[client])
		return Plugin_Stop;
	
	KAC_Kick(client, KAC_FAILEDAUTH);
	return Plugin_Stop;
}

public Action KAC_ClearTimer(Handle timer, any nothing)
{
	ClearTrie(g_hDenyArray);
}

//- ConVar Hook -//

public VersionChange(Handle convar, const char[] oldValue, const char[] newValue)
{
	if (!StrEqual(newValue, PLUGIN_VERSION))
		SetConVarString(g_hCVarVersion, PLUGIN_VERSION);
}