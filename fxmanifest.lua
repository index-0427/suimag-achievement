fx_version 'cerulean'
game 'gta5'

name 'suimag-achievement'
author 'SuiMag'
description 'Minimal Qbox achievements and titles for LB Phone'
version '0.1.0'

shared_script '@ox_lib/init.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'config.lua', 'server/main.lua' }
client_script 'client/main.lua'

-- A transparent NUI host registers callbacks without drawing over the game.
ui_page 'ui/bridge.html'
files { 'ui/bridge.html', 'ui/index.html', 'ui/style.css', 'ui/app.js', 'ui/icon.svg' }
dependencies { 'qbx_core', 'ox_lib', 'oxmysql', 'lb-phone', 'suimag-playernames-improved' }
