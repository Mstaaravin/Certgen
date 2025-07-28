rm -rf domains/lan/certs/wildcard.lan*
./certgen.sh -d lan -n "*" -a \
"traefik.lan \
gitea.lan \
gitlab.lan \
pve01.lan '
pve02.lan \
radarr.lan \
sonarr.lan \
plex.lan \
prowlarr.lan \
flaresolverr.lan \
jellyseerr.lan \
lidarr.lan \
bazarr.lan \
deluged.lan \
deluge.lan \
dozzle.lan \
immich.lan \
it.lan \
nextcloud.lan \
portainer.lan \
registry.lan \
minio01.lan \
minio02.lan \
esxi7a.lan \
esxi8.lan \
vcenter7.lan \
vcenter8.lan"

scp domains/lan/certs/wildcard.lan.key lserver01:/docker/traefik/config/certs/

scp domains/lan/certs/wildcard.lan-fullchain.crt lserver01:/docker/traefik/config/certs/wildcard.lan.pem

./certgen.sh -d lan -n "*" -a "openwrt.lan traefik.lan gitea.lan gitlab.lan pve01.lan radarr.lan sonarr.lan plex.lan prowlarr.lan flaresolverr.lan jellyseerr.lan lidarr.lan bazarr.lan deluged.lan deluge.lan dozzle.lan immich.lan it.lan nextcloud.lan portainer.lan registry.lan minio01.lan minio02.lan pve02.lan esxi7a.lan esxi8.lan vcenter7.lan vcenter8.lan wallos.lan vsc.lan"
