# Shared proxy headers – included by gitea.conf locations
proxy_http_version 1.1;
proxy_set_header   Host              $host;
proxy_set_header   X-Real-IP         $remote_addr;
proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
# SSL is terminated upstream (NPM/Cloudflare), always tell Gitea the original scheme was HTTPS
proxy_set_header   X-Forwarded-Proto https;
proxy_set_header   Connection        "";
proxy_buffering    off;
proxy_request_buffering off;
