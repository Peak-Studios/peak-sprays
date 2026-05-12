fx_version 'cerulean'
game 'gta5'
author 'Peak Studios'
description 'Peak Sprays'
version '0.2.0'
lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/internal_config.lua',
    'shared/config.lua',
    'shared/locales.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/init.lua',
    'server/bridge.lua',
    'server/custom.lua',
    'server/manager.lua',
    'server/scenes.lua',
    'server/admin.lua',
    'server/logs.lua',
    'server/server-config.lua',
}

client_scripts {
    'client/init.lua',
    'client/bridge.lua',
    'client/custom.lua',
    'client/manager.lua',
    'client/painter.lua',
    'client/raycast.lua',
    'client/renderer.lua',
    'client/scene_utils.lua',
    'client/scene_renderer.lua',
    'client/scene_creator.lua',
    'client/nui.lua',
    'client/eraser.lua',
    'client/admin.lua',
}

ui_page 'ui/dist/index.html'

files {
    'ui/dist/index.html',
    'ui/dist/scene.html',
    'ui/dist/canvas.html',
    'ui/dist/**/*',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
