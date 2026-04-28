# WebSocket upgrade map – loaded by nginx main config (nginx.conf)
# Add this to your main nginx.conf http {} block if not already present:
#   include /etc/nginx/conf.d/websocket.inc;
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
