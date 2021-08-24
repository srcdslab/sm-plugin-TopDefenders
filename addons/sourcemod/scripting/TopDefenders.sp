#include <zombiereloaded>
#include <clientprefs>
#include <multicolors>
#include <sourcemod>
#include <sdktools>
#include <LagReducer>

#include "loghelper.inc"
#include "utilshelper.inc"

#define SPECMODE_NONE           0
#define SPECMODE_FIRSTPERSON    4
#define SPECMODE_THIRDPERSON    5
#define SPECMODE_FREELOOK       6

#define HOLY_SOUND_COMMON		"nide/holy.wav"
#define CROWN_MODEL_CSGO		"models/topdefenders_perk/crown_v2.mdl"
#define CROWN_MODEL_CSS			"models/unloze/crown_v2.mdl"

bool g_bHideCrown[MAXPLAYERS+1];
bool g_bHideDialog[MAXPLAYERS+1];
bool g_bProtection[MAXPLAYERS+1];

Handle g_hCookie_HideCrown;
Handle g_hCookie_HideDialog;
Handle g_hCookie_Protection;

ConVar g_hCVar_Protection;
ConVar g_hCVar_ProtectionMinimal1;
ConVar g_hCVar_ProtectionMinimal2;
ConVar g_hCVar_ProtectionMinimal3;

ConVar g_cvPrint, g_cvPrintPos, g_cvPrintColor, g_cvDisplayType, g_cvScoreboardType;

int g_iPrintColor[3];
float g_fPrintPos[2];

int g_iCrownEntity = -1;
int g_iDialogLevel = 100000;

int g_iPlayerWinner[3];
int g_iPlayerKills[MAXPLAYERS+1];
int g_iPlayerDamage[MAXPLAYERS+1];
int g_iPlayerDamageFrom1K[MAXPLAYERS+1];

int g_iSortedList[MAXPLAYERS+1][2];
int g_iSortedCount = 0;

bool g_iPlayerImmune[MAXPLAYERS+1];

int g_iEntIndex[MAXPLAYERS + 1] = -1;

Handle g_hHudSync = INVALID_HANDLE;
Handle g_hUpdateTimer = INVALID_HANDLE;

bool g_bIsCSGO = false;

public Plugin myinfo =
{
	name         = "Top Defenders",
	author       = "Neon & zaCade & maxime1907 & Cloud Strife",
	description  = "Show Top Defenders after each round",
	version      = "1.7"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bIsCSGO = (GetEngineVersion() == Engine_CSGO);
	CreateNative("TopDefenders_IsTopDefender", Native_IsTopDefender);
	RegPluginLibrary("TopDefenders");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("plugin.topdefenders.phrases");

	g_hCVar_Protection         = CreateConVar("sm_topdefenders_protection", "1", "", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hCVar_ProtectionMinimal1 = CreateConVar("sm_topdefenders_minimal_1", "15", "", FCVAR_NONE, true, 1.0, true, 64.0);
	g_hCVar_ProtectionMinimal2 = CreateConVar("sm_topdefenders_minimal_2", "30", "", FCVAR_NONE, true, 1.0, true, 64.0);
	g_hCVar_ProtectionMinimal3 = CreateConVar("sm_topdefenders_minimal_3", "45", "", FCVAR_NONE, true, 1.0, true, 64.0);

	g_cvScoreboardType = CreateConVar("sm_topdefenders_scoreboard_type", "1", "0 = Disabled, 1 = Replace deaths by your topdefender position", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvDisplayType = CreateConVar("sm_topdefenders_display_type", "0", "0 = Ordered by damages, 1 = Ordered by kills", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvPrint = CreateConVar("sm_topdefenders_print", "0", "2 - Display in hud, 1 - In chat, 0 - Both", _, true, 0.0, true, 2.0);
	g_cvPrintPos = CreateConVar("sm_topdefenders_print_position", "0.02 0.25", "The X and Y position for the hud.");
	g_cvPrintColor = CreateConVar("sm_topdefenders_print_color", "255 255 255", "RGB color value for the hud.");

	g_cvPrint.AddChangeHook(OnConVarChange);
	g_cvPrintPos.AddChangeHook(OnConVarChange);
	g_cvPrintColor.AddChangeHook(OnConVarChange);

	g_hCookie_HideCrown  = RegClientCookie("topdefenders_hidecrown",  "", CookieAccess_Private);
	g_hCookie_HideDialog = RegClientCookie("topdefenders_hidedialog", "", CookieAccess_Private);
	g_hCookie_Protection = RegClientCookie("topdefenders_protection", "", CookieAccess_Private);

	g_hHudSync = CreateHudSynchronizer();

	AutoExecConfig(true);
	GetConVars();

	UpdateDefendersList(INVALID_HANDLE);

	RegConsoleCmd("sm_togglecrown",    OnToggleCrown);
	RegConsoleCmd("sm_toggledialog",   OnToggleDialog);
	RegConsoleCmd("sm_toggleimmunity", OnToggleImmunity);

	RegAdminCmd("sm_immunity",	Command_Immunity,	ADMFLAG_CONVARS,		"sm_immunity <#userid|name> <0|1>");
	RegAdminCmd("sm_debugcrown", Command_DebugCrown, ADMFLAG_ROOT);

	HookEvent("round_start",  OnRoundStart);
	HookEvent("round_end",    OnRoundEnding);
	HookEvent("player_hurt",  OnClientHurt);
	HookEvent("player_spawn", OnClientSpawn);
	HookEvent("player_death", OnClientDeath);

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i))
			OnClientPutInServer(i);
	}

	SetCookieMenuItem(MenuHandler_CookieMenu, 0, "Top Defenders");
}

public void OnPluginEnd()
{
	if (g_hHudSync != INVALID_HANDLE)
	{
		CloseHandle(g_hHudSync);
		g_hHudSync = INVALID_HANDLE;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i))
			OnClientDisconnect(i);
	}
}

public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	GetConVars();
}

public Action OnToggleCrown(int client, int args)
{
	ToggleCrown(client);
	return Plugin_Handled;
}

public Action OnToggleDialog(int client, int args)
{
	ToggleDialog(client);
	return Plugin_Handled;
}

public Action OnToggleImmunity(int client, int args)
{
	ToggleImmunity(client);
	return Plugin_Handled;
}

public void ResetImmunity()
{
	for(int i = 0; i < MAXPLAYERS + 1; i++)
	{
		g_iPlayerImmune[i] = false;
	}
}

public Action Command_DebugCrown(int client, int args)
{
	CreateTimer(1.0, OnClientSpawnPost, client, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action Command_Immunity(int client, int args)
{
	if (args < 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_immunity <target> <0|1>");
		return Plugin_Handled;
	}

	char pattern[96], immunity[32], notify[32];
	GetCmdArg(1, pattern, sizeof(pattern));
	GetCmdArg(2, immunity, sizeof(immunity));

	int im = StringToInt(immunity);

	int iNotify = 1;
	if (args == 3)
	{
		GetCmdArg(3, notify, sizeof(notify));
		iNotify = StringToInt(notify);
	}

	GiveImmunity(client, pattern, im ? true : false, iNotify ? true : false);
	return Plugin_Handled;
}

public void GiveImmunity(int client, char pattern[96], bool immunity, bool bNotify)
{
	char buffer[96];
	int targets[MAXPLAYERS+1];
	bool ml = false;

	int count = ProcessTargetString(pattern,client,targets,sizeof(targets),COMMAND_FILTER_CONNECTED,buffer,sizeof(buffer),ml);

	if (count <= 0)
	{
		if (IsValidClient(client))
			CPrintToChat(client,"{darkblue}%t {grey}%s", "Chat Prefix", (count < 0) ? "Bad target" : "No target");
	}
	else for (int i = 0; i < count; i++)
	{
		if (IsValidClient(client))
		{
			if (bNotify)
				CPrintToChatAll("{darkblue}%t {green}%N {grey}%s mother zombie immunity on player {fullred}%N", "Chat Prefix", client, immunity ? "enabled" : "disabled", targets[i]);
			g_iPlayerImmune[targets[i]] = immunity;
		}
	}
}

public void ToggleCrown(int client)
{
	g_bHideCrown[client] = !g_bHideCrown[client];
	if (g_bHideCrown[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iPlayerWinner[0] == GetSteamAccountID(client))
	{
		if (!g_bIsCSGO)
			RemoveHat_CSS(client);
		else
			RemoveHat_CSGO(client);
	}
	else if (!g_bHideCrown[client] && IsValidClient(client) && IsPlayerAlive(client) && g_iPlayerWinner[0] == GetSteamAccountID(client))
	{
		if (g_bIsCSGO)
			CreateHat_CSGO(client);
		else
			CreateHat_CSS(client);
	}
	CPrintToChat(client, "{darkblue}%t {grey}%t", "Chat Prefix", g_bHideCrown[client] ? "Crown Disabled" : "Crown Enabled");
}

public void ToggleDialog(int client)
{
	g_bHideDialog[client] = !g_bHideDialog[client];
	CPrintToChat(client, "{darkblue}%t {grey}%t", "Chat Prefix", g_bHideDialog[client] ? "Dialog Disabled" : "Dialog Enabled");
}

public void ToggleImmunity(int client)
{
	g_bProtection[client] = !g_bProtection[client];
	CPrintToChat(client, "{darkblue}%t {grey}%t", "Chat Prefix", g_bProtection[client] ? "Immunity Disabled" : "Immunity Enabled");
}

public void ShowSettingsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MainMenu);

	menu.SetTitle("%T", "Cookie Menu Title", client);

	AddMenuItemTranslated(menu, "0", "%t: %t", "Crown",    g_bHideCrown[client]  ? "Disabled" : "Enabled");
	AddMenuItemTranslated(menu, "1", "%t: %t", "Dialog",   g_bHideDialog[client] ? "Disabled" : "Enabled");
	AddMenuItemTranslated(menu, "2", "%t: %t", "Immunity", g_bProtection[client] ? "Disabled" : "Enabled");

	menu.ExitBackButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

public void MenuHandler_CookieMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch(action)
	{
		case(CookieMenuAction_DisplayOption):
		{
			Format(buffer, maxlen, "%T", "Cookie Menu", client);
		}
		case(CookieMenuAction_SelectOption):
		{
			ShowSettingsMenu(client);
		}
	}
}

public int MenuHandler_MainMenu(Menu menu, MenuAction action, int client, int selection)
{
	switch(action)
	{
		case(MenuAction_Select):
		{
			switch(selection)
			{
				case(0): ToggleCrown(client);
				case(1): ToggleDialog(client);
				case(2): ToggleImmunity(client);
			}

			ShowSettingsMenu(client);
		}
		case(MenuAction_Cancel):
		{
			ShowCookieMenu(client);
		}
		case(MenuAction_End):
		{
			delete menu;
		}
	}
}

public void OnMapStart()
{
	PrecacheSound(HOLY_SOUND_COMMON);

	if (g_bIsCSGO)
		PrecacheModel(CROWN_MODEL_CSGO);
	else
		PrecacheModel(CROWN_MODEL_CSS);

	AddFilesToDownloadsTable("topdefenders_downloadlist.ini");

	GetTeams();
	ResetImmunity();

	g_hUpdateTimer = CreateTimer(0.5, UpdateDefendersList, INVALID_HANDLE, TIMER_REPEAT);
}

public void OnMapEnd()
{
	if (g_hUpdateTimer != INVALID_HANDLE)
	{
		KillTimer(g_hUpdateTimer);
		g_hUpdateTimer = INVALID_HANDLE;
	}
}

public void OnClientPutInServer(int client)
{
	if(AreClientCookiesCached(client))
	{
		GetCookies(client);
	}
}

public void GetCookies(int client)
{
	char sBuffer[4];
	GetClientCookie(client, g_hCookie_HideCrown, sBuffer, sizeof(sBuffer));

	if (sBuffer[0])
		g_bHideCrown[client] = true;
	else
		g_bHideCrown[client] = false;

	GetClientCookie(client, g_hCookie_HideDialog, sBuffer, sizeof(sBuffer));

	if (sBuffer[0])
		g_bHideDialog[client] = true;
	else
		g_bHideDialog[client] = false;

	GetClientCookie(client, g_hCookie_Protection, sBuffer, sizeof(sBuffer));

	if (sBuffer[0])
		g_bProtection[client] = true;
	else
		g_bProtection[client] = false;
}

public void OnClientCookiesCached(int client)
{
	GetCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookie(client, g_hCookie_HideCrown, g_bHideCrown[client] ? "1" : "");
	SetClientCookie(client, g_hCookie_HideDialog, g_bHideDialog[client] ? "1" : "");
	SetClientCookie(client, g_hCookie_Protection, g_bProtection[client] ? "1" : "");

	g_iPlayerKills[client] = 0;
	g_iPlayerDamage[client] = 0;
	g_bHideCrown[client]  = false;
	g_bHideDialog[client] = false;
	g_bProtection[client] = false;
}

public int SortDefendersList(int[] elem1, int[] elem2, const int[][] array, Handle hndl)
{
	if (elem1[1] > elem2[1]) return -1;
	if (elem1[1] < elem2[1]) return 1;

	return 0;
}

public Action UpdateDefendersList(Handle timer)
{
	for (int i = 0; i < sizeof(g_iSortedList); i++)
	{
		g_iSortedList[i][0] = -1;
		g_iSortedList[i][1] = 0;
	}

	g_iSortedCount = 0;
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client))
			continue;

		if (GetConVarInt(g_cvDisplayType) == 0 && g_iPlayerDamage[client])
		{
			g_iSortedList[g_iSortedCount][0] = client;
			g_iSortedList[g_iSortedCount][1] = g_iPlayerDamage[client];
			g_iSortedCount++;
		}
		else if (GetConVarInt(g_cvDisplayType) == 1 && g_iPlayerKills[client])
		{
			g_iSortedList[g_iSortedCount][0] = client;
			g_iSortedList[g_iSortedCount][1] = g_iPlayerKills[client];
			g_iSortedCount++;
		}
	}

	SortCustom2D(g_iSortedList, g_iSortedCount, SortDefendersList);

	g_iDialogLevel--;

	if (timer == INVALID_HANDLE)
		return Plugin_Stop;

	return Plugin_Continue;
}

public Action UpdateClientUI(int iClient)
{
	if (!IsClientInGame(iClient))
		return;

	int rank = 0;
	while (rank < g_iSortedCount)
	{
		if (g_iSortedList[rank][0] == iClient)
			break;
		rank++;
	}

	// Scoreboard
	if (GetConVarInt(g_cvScoreboardType) == 1)
	{
		if (rank >= g_iSortedCount)
		{
			SetEntProp(iClient, Prop_Data, "m_iDeaths", 0);
			return;
		}
		else
		{
			SetEntProp(iClient, Prop_Data, "m_iDeaths", rank + 1);
		}
	}

	if (g_iDialogLevel <= 0)
		return;

	// Dialog
	switch(rank)
	{
		case(0): SendDialog(iClient, "#%d (D: %d | P: -%d)",          g_iDialogLevel, 1, rank + 1, g_iSortedList[rank][1], g_iSortedList[rank][1] - g_iSortedList[rank + 1][1]);
		case(1): SendDialog(iClient, "#%d (D: %d | N: +%d)",          g_iDialogLevel, 1, rank + 1, g_iSortedList[rank][1], g_iSortedList[rank - 1][1] - g_iSortedList[rank][1]);
		default: SendDialog(iClient, "#%d (D: %d | N: +%d | F: +%d)", g_iDialogLevel, 1, rank + 1, g_iSortedList[rank][1], g_iSortedList[rank - 1][1] - g_iSortedList[rank][1], g_iSortedList[0][1] - g_iSortedList[rank][1]);
	}
}

public void OnRoundStart(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	g_iDialogLevel = 100000;

	for (int client = 1; client <= MaxClients; client++)
	{
		g_iPlayerKills[client] = 0;
		g_iPlayerDamage[client] = 0;
		g_iPlayerDamageFrom1K[client] = 0;
	}
}

public void OnRoundEnding(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	g_iPlayerWinner = {-1, -1, -1};

	UpdateDefendersList(INVALID_HANDLE);

	for (int rank = 0; rank < g_iSortedCount; rank++)
	{
		LogMessage("%d - %L (%d)", rank + 1, g_iSortedList[rank][0], g_iSortedList[rank][1]);
	}

	if (!g_iSortedCount)
		return;

	char sBuffer[512];
	Format(sBuffer, sizeof(sBuffer), "TOP DEFENDERS:\n");

	for (int i = 0; i < sizeof(g_iPlayerWinner); i++)
	{
		if (g_iSortedList[i][0] > 0)
		{
			if (GetConVarInt(g_cvDisplayType) == 0)
				Format(sBuffer, sizeof(sBuffer), "%s\n%d. %N - %d DMG", sBuffer, i + 1, g_iSortedList[i][0], g_iSortedList[i][1]);
			else if (GetConVarInt(g_cvDisplayType) == 1)
				Format(sBuffer, sizeof(sBuffer), "%s\n%d. %N - %d KILLED", sBuffer, i + 1, g_iSortedList[i][0], g_iSortedList[i][1]);
			LogPlayerEvent(g_iSortedList[i][0], "triggered", i == 0 ? "top_defender" : (i == 1 ? "second_defender" : (i == 2 ? "third_defender" : "super_defender")));

			g_iPlayerWinner[i] = GetSteamAccountID(g_iSortedList[i][0]);
		}
	}

	if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 1)
		PrintToChatAll(sBuffer);

	if (g_cvPrint.IntValue <= 0 || g_cvPrint.IntValue == 2)
	{
		SetHudTextParams(g_fPrintPos[0], g_fPrintPos[1], 5.0, g_iPrintColor[0], g_iPrintColor[1], g_iPrintColor[2], 255, 0, 0.0, 0.1, 0.1);

		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsValidClient(client))
				continue;

			ClearSyncHud(client, g_hHudSync);
			ShowSyncHudText(client, g_hHudSync, "%s", sBuffer);
		}
	}
}

public void OnClientHurt(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("attacker"));
	int victim = GetClientOfUserId(hEvent.GetInt("userid"));

	if (client < 1 || client > MaxClients || victim < 1 || victim > MaxClients)
		return;

	if (client == victim || (IsPlayerAlive(client) && ZR_IsClientZombie(client)))
		return;

	int iDamage = hEvent.GetInt("dmg_health");

	g_iPlayerDamage[client] += iDamage;
	g_iPlayerDamageFrom1K[client] += iDamage;

	if (g_iPlayerDamageFrom1K[client] >= 1000)
	{
		g_iPlayerDamageFrom1K[client] -= 1000;
		LogPlayerEvent(client, "triggered", "damage_zombie");
	}
}

public void OnClientSpawn(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	int client = GetClientOfUserId(hEvent.GetInt("userid"));

	if (g_iPlayerWinner[0] == GetSteamAccountID(client) && !g_bHideCrown[client])
	{
		CreateTimer(7.0, OnClientSpawnPost, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

stock void RemoveHat_CSS(int client)
{
	if (g_iCrownEntity != INVALID_ENT_REFERENCE)
	{
		int iCrownEntity = EntRefToEntIndex(g_iCrownEntity);
		if(IsValidEntity(iCrownEntity))
			AcceptEntityInput(iCrownEntity, "Kill");
		g_iCrownEntity = INVALID_ENT_REFERENCE;
	}
}

stock void RemoveHat_CSGO(int client)
{
	RemoveHat_CSS(client);
}

stock void CreateHat_CSS(int client) 
{ 
	if ((g_iCrownEntity = EntIndexToEntRef(CreateEntityByName("prop_dynamic"))) == INVALID_ENT_REFERENCE)
		return;
	
	int iCrownEntity = EntRefToEntIndex(g_iCrownEntity);
	SetEntityModel(iCrownEntity, CROWN_MODEL_CSS);

	DispatchKeyValue(iCrownEntity, "solid",                 "0");
	DispatchKeyValue(iCrownEntity, "modelscale",            "1.5");
	DispatchKeyValue(iCrownEntity, "disableshadows",        "1");
	DispatchKeyValue(iCrownEntity, "disablereceiveshadows", "1");
	DispatchKeyValue(iCrownEntity, "disablebonefollowers",  "1");

	float fVector[3];
	float fAngles[3];
	GetClientAbsOrigin(client, fVector);
	GetClientAbsAngles(client, fAngles);

	fVector[2] += 80.0;
	fAngles[0] = 8.0;
	fAngles[2] = 5.5;

	TeleportEntity(iCrownEntity, fVector, fAngles, NULL_VECTOR);

	float fDirection[3];
	fDirection[0] = 0.0;
	fDirection[1] = 0.0;
	fDirection[2] = 1.0;

	TE_SetupSparks(fVector, fDirection, 1000, 200);
	TE_SendToAll();

	SetVariantString("!activator");
	AcceptEntityInput(iCrownEntity, "SetParent", client);
}

void CreateHat_CSGO(int client) 
{ 
	int m_iEnt = CreateEntityByName("prop_dynamic_override"); 
	DispatchKeyValue(m_iEnt, "model", CROWN_MODEL_CSGO); 
	DispatchKeyValue(m_iEnt, "spawnflags", "256"); 
	DispatchKeyValue(m_iEnt, "solid", "0");
	DispatchKeyValue(m_iEnt, "modelscale", "1.3");
	SetEntPropEnt(m_iEnt, Prop_Send, "m_hOwnerEntity", client); 

	float m_flPosition[3];
	float m_flAngles[3], m_flForward[3], m_flRight[3], m_flUp[3];
	GetClientAbsAngles(client, m_flAngles);
	GetAngleVectors(m_flAngles, m_flForward, m_flRight, m_flUp);
	GetClientEyePosition(client, m_flPosition);
	m_flPosition[2] += 7.0;

	DispatchSpawn(m_iEnt); 
	AcceptEntityInput(m_iEnt, "TurnOn", m_iEnt, m_iEnt, 0); 

	g_iEntIndex[client] = m_iEnt; 

	TeleportEntity(m_iEnt, m_flPosition, m_flAngles, NULL_VECTOR); 

	SetVariantString("!activator"); 
	AcceptEntityInput(m_iEnt, "SetParent", client, m_iEnt, 0); 

	SetVariantString(CROWN_MODEL_CSGO); 
	AcceptEntityInput(m_iEnt, "SetParentAttachmentMaintainOffset", m_iEnt, m_iEnt, 0);

	float fVector[3];
	GetClientAbsOrigin(client, fVector);

	fVector[2] += 80.0;

	float fDirection[3];
	fDirection[0] = 0.0;
	fDirection[1] = 0.0;
	fDirection[2] = 1.0;

	TE_SetupSparks(fVector, fDirection, 1000, 200);
	TE_SendToAll();
}

public Action OnClientSpawnPost(Handle timer, int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return;

	if (g_bIsCSGO)
		CreateHat_CSGO(client);
	else
		CreateHat_CSS(client);
}

public void OnClientDeath(Event hEvent, const char[] sEvent, bool bDontBroadcast)
{
	int attacker = GetClientOfUserId(hEvent.GetInt("attacker"));
	int client = GetClientOfUserId(hEvent.GetInt("userid"));

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && ZR_IsClientHuman(attacker))
	{
		g_iPlayerKills[attacker]++;
		LogPlayerEvent(attacker, "triggered", "zombie_kill");
	}

	if (g_iPlayerWinner[0] == GetSteamAccountID(client) && !IsPlayerAlive(client))
	{
		if (!g_bIsCSGO)
			RemoveHat_CSS(client);
		else
			RemoveHat_CSGO(client);
	}
}

public void SetImmunity(int client, char[] notifHudMsg, char[] notifChatMsg)
{
	Handle hMessageInfection = StartMessageOne("HudMsg", client);
	if (hMessageInfection)
	{
		if (GetUserMessageType() == UM_Protobuf)
		{
			PbSetInt(hMessageInfection, "channel", 50);
			PbSetInt(hMessageInfection, "effect", 0);
			PbSetColor(hMessageInfection, "clr1", {255, 255, 255, 255});
			PbSetColor(hMessageInfection, "clr2", {255, 255, 255, 255});
			PbSetVector2D(hMessageInfection, "pos", Float:{-1.0, 0.3});
			PbSetFloat(hMessageInfection, "fade_in_time", 0.1);
			PbSetFloat(hMessageInfection, "fade_out_time", 0.1);
			PbSetFloat(hMessageInfection, "hold_time", 5.0);
			PbSetFloat(hMessageInfection, "fx_time", 0.0);
			PbSetString(hMessageInfection, "text", notifHudMsg);
			EndMessage();
		}
		else
		{
			BfWriteByte(hMessageInfection, 50);
			BfWriteFloat(hMessageInfection, -1.0);
			BfWriteFloat(hMessageInfection, 0.3);
			BfWriteByte(hMessageInfection, 0);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 255);
			BfWriteByte(hMessageInfection, 0);
			BfWriteFloat(hMessageInfection, 0.1);
			BfWriteFloat(hMessageInfection, 0.1);
			BfWriteFloat(hMessageInfection, 5.0);
			BfWriteFloat(hMessageInfection, 0.0);
			BfWriteString(hMessageInfection, notifHudMsg);
			EndMessage();
		}
	}

	CPrintToChat(client, "{darkblue}%t {grey}%s", "Chat Prefix", notifChatMsg);

	EmitSoundToClient(client, HOLY_SOUND_COMMON, .volume=1.0);
}

public Action ZR_OnClientInfect(&client, &attacker, &bool:motherInfect, &bool:respawnOverride, &bool:respawn)
{
	if (g_hCVar_Protection.BoolValue && motherInfect && !g_bProtection[client])
	{
		if ((g_iPlayerWinner[0] == GetSteamAccountID(client) && GetClientCount() >= g_hCVar_ProtectionMinimal1.IntValue) ||
			(g_iPlayerWinner[1] == GetSteamAccountID(client) && GetClientCount() >= g_hCVar_ProtectionMinimal2.IntValue) ||
			(g_iPlayerWinner[2] == GetSteamAccountID(client) && GetClientCount() >= g_hCVar_ProtectionMinimal3.IntValue))
		{
			SetImmunity(
				client,
				"You have been protected from being Mother Zombie\nsince you were the Top Defender last round!",
				"You have been protected from being Mother Zombie since you were the Top Defender last round!"
			);
			return Plugin_Handled;
		}
	}

	if (motherInfect && g_iPlayerImmune[client] == true)
	{
		SetImmunity(client, "An administrator has protected you\nfrom being Mother Zombie", "An administrator has protected you from being Mother Zombie");
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void SendDialog(int client, const char[] display, const int level, const int time, any ...)
{
	char buffer[128];
	VFormat(buffer, sizeof(buffer), display, 5);

	KeyValues kv = new KeyValues("dialog", "title", buffer);
	kv.SetColor("color", 255, 255, 255, 255);
	kv.SetNum("level", level);
	kv.SetNum("time", time);

	if (!g_bHideDialog[client])
	{
		CreateDialog(client, kv, DialogType_Msg);
	}

	for (int spec = 1; spec <= MaxClients; spec++)
	{
		if (!IsClientInGame(spec) || !IsClientObserver(spec) || g_bHideDialog[spec])
			continue;

		int specMode   = GetClientSpectatorMode(spec);
		int specTarget = GetClientSpectatorTarget(spec);

		if ((specMode == SPECMODE_FIRSTPERSON || specMode == SPECMODE_THIRDPERSON) && specTarget == client)
		{
			CreateDialog(spec, kv, DialogType_Msg);
		}
	}

	delete kv;
}

public void GetConVars()
{
	char StringPos[2][8];
	char ColorValue[64];
	char PosValue[16];

	g_cvPrintPos.GetString(PosValue, sizeof(PosValue));
	ExplodeString(PosValue, " ", StringPos, sizeof(StringPos), sizeof(StringPos[]));

	g_fPrintPos[0] = StringToFloat(StringPos[0]);
	g_fPrintPos[1] = StringToFloat(StringPos[1]);

	g_cvPrintColor.GetString(ColorValue, sizeof(ColorValue));
	ColorStringToArray(ColorValue, g_iPrintColor);
}

int GetClientSpectatorMode(int client)
{
	return GetEntProp(client, Prop_Send, "m_iObserverMode");
}

int GetClientSpectatorTarget(int client)
{
	return GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
}

public void LagReducer_OnClientGameFrame(int iClient)
{
	UpdateClientUI(iClient);
}

//---------------------------------------
// Purpose: Natives
//---------------------------------------

public int Native_IsTopDefender(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (client && IsClientInGame(client))
	{
		for (int i = 0; i < 3; i++)
		{
			if (g_iPlayerWinner[i] == GetSteamAccountID(client))
				return i;
		}
	}
	return -1;
}