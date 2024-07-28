fx_version 'cerulean'
game 'gta5'

author 'citRa'
description 'Simple taxi script'
version '1.0.0beta'
lua54 'yes'

shared_scripts {
	'config.lua',
	'@ox_lib/init.lua',
}

server_scripts {
    'server/*.lua',
}

client_scripts {
    'client/*.lua',
}