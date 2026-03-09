#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <custom_fakelag>
#include <nativevotes_rework>
#include <colors>


public Plugin myinfo = {
    name        = "Ping equalizer",
    author      = "TouchMe",
    description = "Provides a menu for viewing player latency and toggling automatic ping equalization",
    version     = "build_0001",
    url         = "https://github.com/TouchMe-Inc/l4d2_ping_equalizer"
};


#define TRANSLATIONS            "ping_equalizer.phrases"

#define VOTE_TIME 15

#define UPDATE_INTERVAL 5.0

#define MIN_LATENCY 0.0

#define TEAM_SPECTATOR 1


bool g_bEqualizePing = false;


public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    RegConsoleCmd("sm_fakelag", Cmd_FakeLag);

    CreateTimer(UPDATE_INTERVAL, Timer_EqualizePing, .flags = TIMER_REPEAT);
}

Action Timer_EqualizePing(Handle hTimer)
{
    if (!g_bEqualizePing) {
        return Plugin_Continue;
    }

    float fPlayerPing[MAXPLAYERS + 1];
    float fMaxPing = 0.0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) <= TEAM_SPECTATOR) {
            continue;
        }

        fPlayerPing[i] = GetPlayerLatency(i) - CFakeLag_GetPlayerLatency(i);

        if (fPlayerPing[i] > fMaxPing) {
            fMaxPing = fPlayerPing[i];
        }
    }

    if (fMaxPing <= 0.0) {
        return Plugin_Continue;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }

        float fSetLag = fMaxPing - fPlayerPing[i];

        CFakeLag_SetPlayerLatency(i, fSetLag < MIN_LATENCY ? MIN_LATENCY : fSetLag);
    }

    return Plugin_Continue;
}

Action Cmd_FakeLag(int iClient, int args)
{
    if (iClient <= 0) {
        return Plugin_Handled;
    }

    ShowFakeLagMenu(iClient);

    return Plugin_Handled;
}

void ShowFakeLagMenu(int iClient)
{
    Menu hMenu = CreateMenu(HandlerFakeLagMenu, MenuAction_Select|MenuAction_End);

    SetMenuTitle(hMenu, "%T", "MENU_TITLE", iClient);

    char szBuffer[64];
    FormatEx(szBuffer, sizeof szBuffer, "%T", !g_bEqualizePing ? "MENU_EQUALIZE_ENABLE" : "MENU_EQUALIZE_DISABLE", iClient);
    AddMenuItem(hMenu, "switcher", szBuffer, ITEMDRAW_DEFAULT);

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer)) {
            continue;
        }

        FormatEx(szBuffer, sizeof szBuffer, "%T", "MENU_ITEM", iPlayer, CFakeLag_GetPlayerLatency(iPlayer), iPlayer);

        AddMenuItem(hMenu, "player", szBuffer, ITEMDRAW_DISABLED);
    }

    DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

/**
 *
 */
int HandlerFakeLagMenu(Menu hMenu, MenuAction action, int iClient, int iItem)
{
    switch (action)
    {
        case MenuAction_End: delete hMenu;

        case MenuAction_Select: RunVote(iClient);
    }

    return 0;
}

void RunVote(int iClient)
{
    if (!NativeVotes_IsNewVoteAllowed())
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
        return;
    }

    int iTotalPlayers;
    int[] iPlayers = new int[MaxClients];

    for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
    {
        if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || GetClientTeam(iPlayer) <= 1) {
            continue;
        }

        iPlayers[iTotalPlayers++] = iPlayer;
    }

    NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo);
    hVote.Initiator = iClient;
    hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

/**
 * Called when a vote action is completed.
 *
 * @param hVote             The vote being acted upon.
 * @param tAction           The action of the vote.
 * @param iParam1           First action parameter.
 * @param iParam2           Second action parameter.
 */
Action HandlerVote(NativeVote hVote, VoteAction tAction, int iParam1, int iParam2)
{
    switch (tAction)
    {
        case VoteAction_Display:
        {
            char szVoteDisplayMessage[128];

            FormatEx(szVoteDisplayMessage, sizeof szVoteDisplayMessage, "%T", 
                !g_bEqualizePing ? "VOTE_EQUALIZE_ENABLE" : "VOTE_EQUALIZE_DISABLE" , iParam1);

            hVote.SetDetails(szVoteDisplayMessage);

            return Plugin_Changed;
        }

        case VoteAction_Cancel: hVote.DisplayFail();

        case VoteAction_Finish:
        {
            if (iParam1 == NATIVEVOTES_VOTE_NO)
            {
                hVote.DisplayFail();

                return Plugin_Continue;
            }

            if (g_bEqualizePing) {
                ResetFakeLatency();
                g_bEqualizePing = false;
            } else {
                g_bEqualizePing = true;
            }

            hVote.DisplayPass();
        }

        case VoteAction_End: hVote.Close();
    }

    return Plugin_Continue;
}

void ResetFakeLatency()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i)) {
            continue;
        }

        CFakeLag_SetPlayerLatency(i, MIN_LATENCY);
    }
}

float GetPlayerLatency(int iClient) {
    return GetClientAvgLatency(iClient, NetFlow_Outgoing) * 1000.0;
}
