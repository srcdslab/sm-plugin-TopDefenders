# Copilot Instructions for TopDefenders

## Repository Overview

This repository contains **TopDefenders**, a SourcePawn plugin for SourceMod that enhances Source engine games (Counter-Strike: Source/Global Offensive) with a ranking system for players who deal the most damage to zombies during Zombie:Reloaded gameplay. The plugin provides visual rewards, immunity protections, and comprehensive statistics tracking.

**Key Features:**
- Real-time damage/kill tracking and leaderboard display
- Crown visual effect for top defenders
- Mother zombie immunity protection system
- Client preference system with cookies
- Multi-language support via translation files
- Integration with optional plugins (AFKManager, DynamicChannels, KnifeMode)

## Technical Environment

- **Language**: SourcePawn (Source engine scripting language)
- **Platform**: SourceMod 1.12+ (minimum), 1.11.0-git6934 (current CI target)
- **Build System**: SourceKnight 0.2 (build automation tool for SourceMod)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight
- **Target Games**: Counter-Strike: Source, Counter-Strike: Global Offensive
- **Required Dependencies**: SourceMod, ZombieReloaded, ClientPrefs, MultiColors, SDKTools
- **Optional Dependencies**: AFKManager, DynamicChannels, KnifeMode, smlib

## Project Structure

```
/
├── .github/
│   ├── workflows/ci.yml           # CI/CD using action-sourceknight@v1
│   └── dependabot.yml             # GitHub Actions dependency management
├── addons/sourcemod/              # Standard SourceMod directory structure
│   ├── scripting/
│   │   ├── TopDefenders.sp        # Main plugin source (~1193 lines)
│   │   └── include/
│   │       └── TopDefenders.inc   # Public API definitions and version info
│   └── translations/
│       └── plugin.topdefenders.phrases.txt # Multi-language support
├── common/                        # Shared game assets
│   └── sound/topdefenders/        # Sound effects
├── cstrike/                       # Counter-Strike specific assets
│   ├── addons/sourcemod/configs/
│   │   └── topdefenders_downloadlist.ini # Client download manifest
│   ├── materials/models/unloze/   # Crown model textures (.vmt, .vtf)
│   └── models/unloze/             # Crown 3D model files (.mdl, .phy, .vtx, .vvd)
├── sourceknight.yaml             # Build configuration and dependencies
├── README.md                     # Basic installation guide
└── .gitignore                    # Excludes .smx, build/, .sourceknight/, etc.
```

## Code Standards & Conventions

### SourcePawn Style Guide
- **Indentation**: 4 spaces (tabs converted to spaces)
- **Variables**: camelCase for locals/parameters, PascalCase for functions, g_ prefix for globals
- **Functions**: PascalCase naming convention
- **Constants**: UPPERCASE_WITH_UNDERSCORES
- **Preprocessor**: Use `#pragma semicolon 1` and `#pragma newdecls required`
- **Memory Management**: Use `delete` operator instead of `CloseHandle()`, never check for null before delete
- **Collections**: Prefer StringMap/ArrayList over native arrays, use `delete` and recreate instead of `.Clear()`

### Code Organization Patterns
```sourcepawn
// Standard plugin structure observed:
public Plugin myinfo = { /* plugin metadata */ };

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Native registration
    CreateNative("PluginName_Function", Native_Function);
    RegPluginLibrary("PluginName");
    return APLRes_Success;
}

public void OnPluginStart()
{
    // ConVar creation, event hooks, command registration
    // Translation loading, cookie registration
}

public void OnPluginEnd()
{
    // Cleanup: delete handles, remove entities
}
```

### Error Handling & Safety
- Always validate client indices with `IsValidClient()` or similar
- Use `IsValidEntity()` before entity operations
- Verify entity models/classnames before removal to prevent accidents
- Log errors for debugging with `LogError()`, `LogMessage()` for events
- Handle SQL failures gracefully (though this plugin uses minimal SQL)

## Build & Development Workflow

### Building the Plugin
```bash
# The project uses SourceKnight for building (automated in CI)
# Locally, if SourceKnight is installed:
sourceknight build

# Manual compilation (if you have SourceMod compiler):
spcomp addons/sourcemod/scripting/TopDefenders.sp -o addons/sourcemod/plugins/TopDefenders.smx
```

### CI/CD Pipeline
- **Trigger**: Push to main/master, tags, or pull requests
- **Builder**: `maxime1907/action-sourceknight@v1`
- **Artifacts**: Packaged plugin with assets (.tar.gz)
- **Releases**: Automatic on tags, "latest" on main/master pushes

### Development Environment Setup
1. Install SourceMod development tools
2. Clone with dependencies resolved via SourceKnight
3. Understand that this plugin requires ZombieReloaded to function
4. Test on a development server with CS:S/CS:GO and ZR loaded

## Key Components Deep Dive

### Main Plugin File (`TopDefenders.sp`)
- **Core Arrays**: `g_iPlayerKills[]`, `g_iPlayerDamage[]`, `g_iPlayerWinner[]`, `g_iSortedList[][]`
- **Client Preferences**: Crown visibility, dialog display, immunity protection (saved via cookies)
- **Protection System**: Prevents top defenders from becoming mother zombies based on player count thresholds
- **UI Systems**: HUD text, chat messages, crown entity creation/removal
- **Event Handling**: `player_hurt`, `player_death`, `round_start`, `round_end`, `player_spawn`

### Public API (`TopDefenders.inc`)
```sourcepawn
// Native functions for other plugins
native int TopDefenders_GetClientRank(int client);  // Returns 1-based rank or -1
native int TopDefenders_IsTopDefender(int client);  // DEPRECATED

// Forward for integration
forward void TopDefenders_ClientProtected(int client);
```

### Configuration System
- **ConVars**: 15+ settings for display, protection thresholds, positioning, colors
- **Client Cookies**: Per-player preferences stored persistently
- **Translations**: Support for multiple languages via standard SM translation system

## Common Development Patterns

### Entity Management (Crown System)
```sourcepawn
// Safe entity creation and cleanup pattern
int iCrownEntity = CreateEntityByName("prop_dynamic");
g_iCrownEntities[client] = EntIndexToEntRef(iCrownEntity);

// Always validate before removal
if (g_iCrownEntities[client] != INVALID_ENT_REFERENCE) {
    int entity = EntRefToEntIndex(g_iCrownEntities[client]);
    if (IsValidEntity(entity)) {
        // Verify it's actually our crown model before deletion
        char sModel[128];
        GetEntPropString(entity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
        if (strcmp(sModel, CROWN_MODEL, false) == 0) {
            AcceptEntityInput(entity, "Kill");
        }
    }
}
```

### Translation Usage
```sourcepawn
// Always set target before using translations
SetGlobalTransTarget(client);
CPrintToChat(client, "{green}%t {white}%t", "Chat Prefix", "Crown Enabled");
```

### Performance Optimization
- Use `OnGameFrame()` with frame skipping (`g_cvFramesToSkip`) for UI updates
- Cache expensive calculations in timers rather than every frame
- Minimize string operations in frequently called functions

## Integration Points

### ZombieReloaded Integration
```sourcepawn
// Hook into ZR infection system
public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn)
{
    // Protection logic for top defenders
    return Plugin_Continue; // or Plugin_Changed/Plugin_Handled
}
```

### Optional Plugin Detection
```sourcepawn
// Runtime feature detection
bool g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");

#if defined _AFKManager_Included
    // Conditional compilation for optional features
#endif
```

## Testing & Quality Assurance

### Manual Testing Approach
1. **Setup**: Deploy on test server with ZombieReloaded and CS:S/CS:GO
2. **Scenarios**: Zombie rounds with damage dealing, crown spawning, immunity protection
3. **Edge Cases**: Player disconnection during rounds, protection threshold boundaries
4. **UI Testing**: Verify HUD positioning, chat colors, translation accuracy

### Debugging
- Use `sm_debugcrown` command for crown testing
- Monitor server console for LogPlayerEvent() outputs
- Check entity reference management for memory leaks
- Validate ConVar values are within expected ranges

## Performance Considerations

- **Timer Management**: Single repeating timer for leaderboard updates (0.5s interval)
- **Frame Rate Impact**: UI updates use frame skipping to maintain server tick rate
- **Memory Efficiency**: Proper cleanup in OnClientDisconnect(), entity reference tracking
- **Database Impact**: Minimal (plugin primarily uses in-memory tracking)

## Deployment Notes

### Server Requirements
- SourceMod 1.12+ installation
- ZombieReloaded plugin (required dependency)
- Counter-Strike: Source or Global Offensive
- File download system configured for custom assets

### Installation Process
1. Upload compiled .smx to `addons/sourcemod/plugins/`
2. Upload translation files to `addons/sourcemod/translations/`
3. Upload assets (models, materials, sounds) to appropriate game directories
4. Configure download list for clients
5. Restart server or use `sm plugins load TopDefenders`

### Common Configuration
```cfg
// Recommended ConVar settings for CS:S
sm_cvar sm_topdefenders_print_position "0.02 0.25"

// Recommended ConVar settings for CS:GO
sm_cvar sm_topdefenders_print_position "0.02 0.38"
```

## Troubleshooting Guide

### Common Issues
1. **Crown not spawning**: Check model precaching and file downloads
2. **Protection not working**: Verify ZombieReloaded integration and player count thresholds
3. **HUD position wrong**: Adjust `sm_topdefenders_print_position` for game version
4. **Memory leaks**: Ensure entity cleanup in OnClientDisconnect() and OnMapEnd()

### Debug Commands
- `sm_debugcrown` - Spawn crown on admin
- `sm_immunity <target> <0|1>` - Manual immunity control
- `sm_tdstatus [target]` - Check player ranking

## Version Management

- **Current Version**: 1.13.0 (defined in TopDefenders.inc)
- **Versioning Scheme**: Semantic versioning (MAJOR.MINOR.PATCH)
- **Release Process**: Git tags trigger automatic GitHub releases
- **Compatibility**: Maintains backward compatibility with SourceMod 1.12+

---

*This plugin is actively maintained by srcdslab. For issues, feature requests, or contributions, refer to the GitHub repository issues and pull request system.*