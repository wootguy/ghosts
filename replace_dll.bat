cd "C:\Games\Steam\steamapps\common\Sven Co-op\svencoop\addons\metamod\dlls"

if exist Ghosts_old.dll (
    del Ghosts_old.dll
)
if exist Ghosts.dll (
    rename Ghosts.dll Ghosts_old.dll 
)

exit /b 0