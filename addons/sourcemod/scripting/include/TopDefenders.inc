/**
 * This is the include file for TopDefenders
 * To check that TopDefenders is installed and running, verify that the "TopDefenders" library exists
 */

#if defined _TopDefenders_included
    #endinput
#endif
#define _TopDefenders_included

#define TopDefenders_V_MAJOR   "1"
#define TopDefenders_V_MINOR   "11"
#define TopDefenders_V_PATCH   "6"

#define TopDefenders_VERSION   TopDefenders_V_MAJOR..."."...TopDefenders_V_MINOR..."."...TopDefenders_V_PATCH

/**
 * Called after giving player immunity
 */
forward void TopDefenders_ClientProtected(int client);

/**
 * DEPRECATED NATIVE
 * Check if the given client is top defender
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not a top defender, otherwise it returns its top defender position.
 */
#pragma deprecated Use TopDefenders_GetClientRank() instead.
native int TopDefenders_IsTopDefender(int client);

/**
 * Check if the given client is top defender
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not ingame/ranked, otherwise it returns its top defender position.
 */
native int TopDefenders_GetClientRank(int client);

public SharedPlugin __pl_TopDefenders = 
{
	name = "TopDefenders",
	file = "TopDefenders.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_TopDefenders_SetNTVOptional()
{
	MarkNativeAsOptional("TopDefenders_IsTopDefender");
	MarkNativeAsOptional("TopDefenders_GetClientRank");
}
#endif