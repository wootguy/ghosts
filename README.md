# ghosts
Adds visible ghost models for observers. Type ".ghosts" in chat or console for help.

![ghosts](https://user-images.githubusercontent.com/12087544/86665159-3d2b2180-bfa4-11ea-8c9e-6c87c6b23916.gif)

# CVars
```
as_command ghosts.player_models 1
as_command ghosts.default_mode 2
```
- `ghosts.player_models` enables custom player models for ghosts if not set to 0. A camera model is used otherwise.
- `ghosts.default_mode` sets the default visibility mode for ghosts. Players can override this for themselves.
  - 0 = hide ghosts
  - 1 = show ghosts
  - 2 = show ghosts that don't block your view
  - 3 = show ghosts only while dead

# Installation

1. Install the [PlayerModelPrecacheDyn](https://github.com/incognico/svencoop-plugins/blob/master/PlayerModelPrecacheDyn.as) plugin. This is required if you want player models for ghosts instead of cameras.
1. Make sure the symlinked player model folder has _all_ available player models - **default models included!**
1. Download the latest [release](https://github.com/wootguy/ghosts/releases) and extract to svencoop_addon, or svencoop_downloads, or wtv.
1. Add this to `default_plugins.txt`:
```
  "plugin"
  {
    "name" "ghosts"
    "script" "ghosts/ghosts"
    "concommandns" "ghosts"
  }
  "plugin"
  {
    "name" "GhostEntity"
    "script" "ghosts/GhostEntity"
  }
```
