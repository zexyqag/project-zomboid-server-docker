# Project Zomboid dedicated server container

A Project Zomboid dedicated server image, configured through environment variables. Images are published to GitHub Container Registry:

```
ghcr.io/zexyqag/project-zomboid-server-docker:stable
```

Tags:

* `stable`: the newest image for the current stable game version.
* `stable-<pz_version>`: the newest image for that game version.
* `stable-<pz_version>-<repo_version>`: one exact build; `<repo_version>` is the first 7 characters of the commit.
* `unstable`, `unstable-<pz_version>`, ...: the same for the Steam beta branch, only while Project Zomboid has an open beta.

Only Build 42 is maintained. Images are rebuilt nightly when the game or this repo changed, and each one is booted and stopped in CI before it is published.

**WARNING:** On Windows with WSL2 in Docker Desktop, server startup is much slower. That's fine unless you run a lot of mods, where startup can take 15 to 40 minutes. Run the container on Linux or in a Linux VM if you can.

## Quick start

```yaml
services:
  ProjectZomboidDedicatedServer:
    image: ghcr.io/zexyqag/project-zomboid-server-docker:stable
    restart: unless-stopped
    stop_grace_period: 120s
    env_file:
      - .env
    ports:
      - "16261:16261/udp"
      - "16262:16262/udp"
      - "27015:27015/tcp"
    volumes:
      - data:/home/steam/Zomboid
      - workshop:/home/steam/pz-dedicated/steamapps/workshop

volumes:
  data:
  workshop:
```

`.env`:

```bash
ADMINPASSWORD=change-me
INI_Password=change-me-too
INI_PublicName=My server
INI_Public=false
SANDBOX_ZombieLore__Transmission=3
```

`ADMINPASSWORD` is required on the first start, when the server creates its database and admin account.

`docker stop` (and Portainer's stop) sends `quit` to the server so it saves the world. Keep `stop_grace_period` long enough for your world to save; 120s is plenty for most.

The container runs as the `steam` user (uid 1000). Named volumes work as they are. A bind-mounted folder must be writable by uid 1000: `chown -R 1000:1000 ./data ./workshop-mods`.

To send a command to the server console, use `console`; the reply shows up in the container log:

```bash
docker exec <container> console save
docker exec <container> console servermsg "Restart in 5 minutes"
```

For remote administration, set `INI_RCONPassword` and use any Source RCON client on port 27015.

The image has a health check: the container is `healthy` once the server has started, which can take a while with many mods.

## Configuration

Run `list-env` in the container to see every variable it reads, with the current value and the description from the server's own files, mod settings included. An optional argument filters by name or description:

```bash
docker exec <container> list-env
docker exec <container> list-env zombielore
```

The same list for each published image is at https://zexyqag.github.io/project-zomboid-server-docker/.

Boolean options accept `1`, `true`, `yes`, `y` or `on`; anything else is false.

### Server settings: `INI_<Key>`

Each `INI_<Key>` variable sets `Key` in `Zomboid/Server/pzserver.ini` on every start. Keys are matched case-insensitively; values are written as they are.

```bash
INI_Public=true
INI_PublicName=My server
INI_MaxPlayers=16
INI_Mods=\ModOne;\ModTwo
INI_AntiCheatProtectionType12=false
```

On Build 42, `Mods=` entries start with a backslash (`\ModId`). In an env file, write a single backslash; it is passed through unchanged.

`INI_<Key>_FILE` reads the value from a file instead, for Docker secrets, and wins over `INI_<Key>`:

```bash
INI_Password_FILE=/run/secrets/pz_password
INI_RCONPassword_FILE=/run/secrets/pz_rcon_password
```

`list-env` shows password settings as `(set)` instead of their value.

Settings apply from the very first start. A variable that matches no key in an existing INI is still written, with a warning in the log, since it's usually a typo. Set `CONFIG_STRICT=true` to refuse to start instead.

A variable you remove leaves the last value in the INI. Set it to an empty value to clear it.

### Sandbox settings: `SANDBOX_<Group>__<Key>`

Each `SANDBOX_` variable sets a value in `Zomboid/Server/pzserver_SandboxVars.lua`. Nested tables are separated with `__`:

```bash
SANDBOX_Zombies=4
SANDBOX_ZombieLore__Transmission=3
SANDBOX_ZombieLore__Mortality=7
SANDBOX_Map__AllowMiniMap=true
```

Values are Lua literals. A setting that holds a string keeps its quotes, so `SANDBOX_WorldItemRemovalList=Base.Hat,Base.Glasses` works without quoting.

The server writes the SandboxVars file during its first start, so sandbox settings apply from the second start. To have them on the first start, set `SERVERPRESET`, which creates the file from a preset before the server starts.

### Image settings

`ADMINUSERNAME`: Admin account name created on the first start (default: `admin`).

`ADMINPASSWORD`, `ADMINPASSWORD_FILE`: Admin password. Required on the first start, when the server creates its database; ignored afterwards, so it stays out of later launch lines. The `_FILE` variant reads the password from a file (for Docker secrets) and takes precedence.

`WORKSHOP_IDS`: Workshop item and collection IDs separated by `;`. Collections are expanded through the Steam API and written to `WorkshopItems`. Set it empty to clear `WorkshopItems`. Enable the mods themselves with `INI_Mods`.

`STEAM_API_KEY`: Steam Web API key, only needed to expand private or unlisted collections.

`SERVERPRESET`: Sandbox preset used to create the SandboxVars file when it doesn't exist. The names are the files in `media/lua/shared/Sandbox` of the game; the log lists them if the name is wrong.

`SERVERPRESETREPLACE`: If true, overwrite an existing SandboxVars file with `SERVERPRESET` on every start.

`CONFIG_STRICT`: If true, refuse to start when an `INI_` or `SANDBOX_` variable matches no setting.

`MEMORY`: Java heap size, for example `4096m` or `8g`. Sets both `-Xms` and `-Xmx`.

`SOFTRESET`, `DEBUG`, `COOP`, `NOSTEAM`: Start the server with `-Dsoftreset`, `-debug`, `-coop` or `-nosteam`.

`MODFOLDERS`: Mod folder search order, for example `workshop,steam,mods`.

`CACHEDIR`: Data folder for the server. Leave it unset; the volumes expect `/home/steam/Zomboid`.

`IP`, `PORT`, `UDPPORT`, `STEAMPORT1`, `STEAMPORT2`: Network options passed to the server. Change the published ports to match.

`STEAMVAC`: `true` or `false` to turn Valve Anti-Cheat on or off.

`LANG`: Locale for the server, for example `en_US.UTF-8`. Only `en_US.UTF-8` is installed; add others with the `EXTRA_LOCALES` build argument. The log warns about a locale that isn't installed.

### Mods and maps

Enable mods with `INI_Mods` and download them with `WORKSHOP_IDS`. The server downloads workshop items during its start.

Maps from enabled mods are added to the INI's `Map=` line automatically, before the vanilla map, keeping the order of maps that are already there. Their spawn points are added to `pzserver_spawnregions.lua` when the mod ships them. Because the downloads happen while the server starts, new maps are added on the start after the one that downloaded them.

### Backups

The server makes its own backups; configure them with `INI_BackupsCount`, `INI_BackupsOnStart`, `INI_BackupsOnVersionChange` and `INI_BackupsPeriod`. `INI_BackupsOnVersionChange=true` is worth having, since a newer image can bring a newer game version.

## Building your own image

```bash
docker build --build-arg STEAMAPPBRANCH=<branch> --build-arg EXTRA_LOCALES="es_ES.UTF-8 de_DE.UTF-8" .
```

`STEAMAPPBRANCH`: Steam beta branch to install; `public` (the default) is the stable release. The branches are listed on [SteamDB](https://steamdb.info/app/380870/depots/).

`EXTRA_LOCALES`: Space-separated locales to install besides `en_US.UTF-8`.

## Soft Reset

Soft reset will perform the following tasks:

* Removes items from the ground.
* Removes items from containers and replaces them with new loot. This includes player-made containers.
* Removes corpses and zombified players.
* Resets zombies.
* Removes blood splatter.
* Resets building alarms.
* Resets the game clock. I’m not positive if this resets to day 1, but the original blog post implies that it does. So this would bring water and electricity back. Assuming your server settings have them * available at day 1.
* Player-made buildings won’t be deleted.
* Player inventories won’t reset.

Removing the following files in the Server data folder (ToDo: I have to search the equivalent files in modern version):

* all zombie_X_Y.bin files
* map_t.bin
* map_meta.bin
* reanimated.bin

Currently is not working correctly and will cause the server to crash when it is active. Also the above points are not performed so nothing will change in the server.

## Ports

* 16261 UDP: game port (`PORT`).
* 16262 UDP: second game port (`UDPPORT`).
* 27015 TCP: RCON, only if you use it (`INI_RCONPort`).

Forward the UDP ports in your firewall/NAT. The log prints the ports the server uses on every start. The [official wiki](https://pzwiki.net/wiki/Dedicated_server) has the details.
