/**
 * This is the include file for TopDefenders
 * To check that TopDefenders is installed and running, verify that the "TopDefenders" library exists
 */

#if defined _TopDefenders_included
    #endinput
#endif
#define _TopDefenders_included

/**
 * Check if the given client is top defender
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not a top defender, otherwise it returns its top defender position.
 */
native int IsTopDefender(int client);

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
}
#endif