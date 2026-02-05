# Project Zomboid dedicated server container

This Dockerfile downloads the Project Zomboid dedicated server using SteamCMD. Will allow you to deploy with ease a server in Kubernetes, Docker...


The ready to use image is published automatically to GitHub Container Registry (GHCR).

Example image URL:
```
ghcr.io/zexyqag/project-zomboid-server-docker:stable
```

Additional tags are published for stable/unstable and versioned builds:

* `stable` / `unstable`
* `stable-<pz_version>` / `unstable-<pz_version>`
* `stable-<pz_version>-<repo_version>` / `unstable-<pz_version>-<repo_version>`

`<pz_version>` is the Project Zomboid server version.
`<repo_version>` is the first 7 characters of the Git commit SHA.

Tag meanings:

* `stable` points to the newest stable build.
* `unstable` points to the newest unstable build.
* `stable-<pz_version>` / `unstable-<pz_version>` track the newest repo build for that PZ version.
* `stable-<pz_version>-<repo_version>` / `unstable-<pz_version>-<repo_version>` pin an exact repo snapshot.

If you want **Build 42** multiplayer, use an `unstable` image tag. If you build the image yourself, set `STEAMAPPBRANCH=unstable` at build time.

**WARNING:** Running the image on Windows using WSL2 in Docker Desktop will make the server startup times significantly slower. This is fine unless you are running a lot of mods in which case server startup times may vary from 15 - 40 minutes. The best way to solve this problem is to run your container on a Linux based system or in a Linux VM.

## Using prebuilt images

Pick the tag you want (`stable` or `unstable`) and run with docker-compose.

Example (stable):

```yaml
services:
	ProjectZomboidDedicatedServer:
		image: ghcr.io/zexyqag/project-zomboid-server-docker:stable
		env_file:
			- .env
		ports:
			- "16261:16261/udp"
			- "16262:16262/udp"
			- "27015:27015/tcp"
		volumes:
			- ./data:/home/steam/Zomboid
			- ./workshop-mods:/home/steam/pz-dedicated/steamapps/workshop
```

If you want unstable, change the image tag to `unstable`.

## Building your own image

If you want to build locally, set `STEAMAPPBRANCH` at build time (see Build time environment variables).

Use .env.template as a starting point for your `.env` file.

## Run time environment variables

Boolean options accept: `1`, `true`, `yes`, `y`, `on` and `0`, `false`, `no`, `n`, `off`.

The image supports the following environment variables:
`ADMINUSERNAME:` Sets the administrator username, otherwise `admin` will be used.

`ADMINPASSWORD:` Sets or changes the admin password. Is mandatory at first startup or will fail. I recommend to remove it once the server is started because the server logs every argument in clear text (if you don't care, you can leave it).

`ADMINPASSWORD_FILE:` Path to a file containing the admin password. If set and the file exists, it takes precedence over `ADMINPASSWORD`.

`ADMINPASSWORD_ONCE:` If `true`, only passes `-adminpassword` when the server ini does not exist yet. This avoids logging the admin password on every startup.

`PASSWORD:` Sets or changes server password. Is optional.

`RCONPASSWORD:` Sets or changes RCON  password. Must be secure.

`PUBLIC:` Shows the server on the in-game browser if `true`, Hides it if `false`. Keeps the setting in the setting file if unset (`false` at first start). 

`DISPLAYNAME:` Sets or changes the servers name in the server browser. Keeps the setting in the setting file if unset.  

`CACHEDIR:` Set the folder where the data will be stored. By default the server stores the data in the Zomboid folder in home directory (/home/steam/Zomboid). It is recommended to store this data into a persistent volume to keep the server state.

`DEBUG:` Enable the debug mode in server

`FORCEUPDATE:` Force a server update on every start. This process can be slow if the image is old.

`FORCESTEAMCLIENTSOUPDATE:` Forcibly update the steamclient.so libraries in the pz-dedicated directory before starting the server. May help with Workshop item downloads. Do not set if everything works fine.

`IP:` Set the interface IP where the server will listen. By default all the interfaces.

`MIN_MEMORY:` Initial memory allocation for the JVM (e.g., 2048m).

`MAX_MEMORY:` Maximum memory limit for the JVM (e.g., 4096m).

`MEMORY:` Amount of memory to use in the server JVM (e.g., 8096m). This variable is used as a fallback for both minimum and maximum memory if `MIN_MEMORY` and `MAX_MEMORY` are not defined.

`MODFOLDERS`: Mod folders to use to load the game mods. Allowed options are workshop, steam, and mods. Options must be separated by comma, for example: workshop,steam,mods

`NOSTEAM:` Starts the server in NoSteam mode, allowing to non steam users to connect.

`PORT:` Set the server port. By default 16261

`SERVERNAME:` Set the server name, which allows you to have multiple server versions. Changing the name will create a new server data, so current progress will not be available. Also will not be lost, just reverting the server name change will load it again. **NOTE: Don't use spaces or special characters or admin user will fail**

`SERVERPRESET:` Set the new servers default preset. If not set, the default is apocalypse. Allowed options are Apocalypse, Beginner, Builder, FirstWeek, SixMonthsLater, Survival and Survivor.

`SERVERPRESETREPLACE:` Replace the server preset by the one set by the SERVERPRESET variable. By default false to avoid replacing custom configurations once the server has started.

`SOFTRESET:` Performs a soft reset in the server. More info in the Soft Reset section.

`STEAMPORT1 & STEAMPORT2:` Sets the two additional ports required for steam to work. I guess that those ports are UDP, but it can be also TCP.

`STEAMVAC:` Enables or disables SteamVac protection in server

`DISABLE_ANTICHEAT:` Comma-separated list or range of anti-cheat protection types to disable (e.g. `1,2,3-5`).

`WORKSHOP_IDS:` Semicolon separated list of Workshop IDs and/or Workshop Collection IDs to install to the server. You can mix individual mod IDs and collection IDs. Any collections will be automatically resolved to their contained mod IDs (including nested collections, with circular references prevented and duplicates removed). Leaving this empty will clear any existing WorkshopItems value. If collection resolution fails, WorkshopItems is left unchanged.

`STEAM_API_KEY:` Optional Steam Web API key used only for resolving Workshop collections. Not required for public collections but may be needed for private or rate-limited access.

`SANDBOXVARS_*:` Optional overrides for SandboxVars. Use single underscores as a path separator. Example: `SANDBOXVARS_ZombieLore_Transmission=4` updates `SandboxVars.ZombieLore.Transmission`. To include a literal underscore in a key name, use double underscores (`__`). Values are treated as raw Lua, so strings should be quoted (e.g., `"SomeText"`).

`SANDBOXVARS_CTRL_DRY_RUN:` If true, logs the changes that would be applied without modifying the file.

`SANDBOXVARS_CTRL_STRICT:` If true, exits with an error when an env var does not match any key in the SandboxVars file.

`SANDBOXVARS_CTRL_CASE_SENSITIVE:` If true, matches SandboxVars keys case-sensitively. Default is case-insensitive.

Example Lua overrides:

```bash
# Use single underscores as path separators
SANDBOXVARS_ZombieLore_Transmission=4
SANDBOXVARS_ZombieLore_Mortality=3

# Use double underscores to include a literal underscore in a key
SANDBOXVARS_World__Event=2
```

`INIVARS_*:` Optional overrides for the server ini file (servertest.ini). Use `INIVARS_Key=Value` for flat keys. For sectioned ini files, use `INIVARS_Section__Key=Value` to target `[Section]` keys (double underscore separates section and key).

`INIVARS_CTRL_DRY_RUN:` If true, logs the changes that would be applied without modifying the ini file.

`INIVARS_CTRL_STRICT:` If true, exits with an error when an env var does not match any key in the ini file.

Example INI overrides:

```bash
# Flat ini keys
INIVARS_Public=true
INIVARS_PublicName="My Server"

# Sectioned ini keys (if your ini uses [Section] headers)
INIVARS_ServerOptions__Public=true
INIVARS_ServerOptions__PublicName="My Server"
```

`CLEAN_WORKSHOP:` If true, removes workshop items on disk that are not listed in `WORKSHOP_IDS` (after collection resolution). This only runs when `WORKSHOP_IDS` is set and collection resolution succeeds to avoid wiping everything by accident.

`CLEAN_WORKSHOP_DRY_RUN:` If true, logs which workshop items would be removed without deleting anything. Requires `CLEAN_WORKSHOP=true`.

`CLEAN_WORKSHOP_ALLOW_REMOVE_ALL:` If true, allows cleanup to remove all workshop items when none of the keep IDs are found on disk. Default is false for safety.

`CLEAN_WORKSHOP_KEEP_FILE:` Optional path to write the resolved workshop keep list (one ID per line).

`MOD_IDS:` Semicolon separated list of Mod IDs to install to the server. NOTE - B42 changes the way mod IDs must be supplied (\mod1;\mod2 inside the servertest.ini file) when defining this variable, precede each mod id with two backslashes (\\) to escape the backslash into the ini file. Leaving this empty will clear any existing Mods value.

`MAP_SCAN_VERBOSE:` If true, logs per-item progress during workshop map scanning.

`MAP_SCAN_DRY_RUN:` If true, scans and reports maps but skips copying them.

`LANG:` This env variable will set the container locales, which will be used by the pz server to set the language. Example (en_EN.UTF-8, es_ES.UTF-8...). Note: the image currently generates `es_ES.UTF-8` by default; if you need other locales, customize the Dockerfile.

Mods will install on second server start

Maps are added on third server start, after mods are added

This is due to the server creating its config and data on the first start, downloading workshop content on the next start, and then wiring maps after they exist on disk. You can still change `MOD_IDS` and `WORKSHOP_IDS` later; updates apply on restart, but workshop downloads may require an extra restart. Changing maps on an existing world may require a new save depending on the map.

## Build time environment variables

Only used when you build the image yourself. Ignore these when using a prebuilt tag.

`STEAMAPPBRANCH:` Sets the Project Zomboid branch to download (e.g., `unstable`). If not set, the stable (public) branch will be downloaded. You can see a list of branches in the [SteamDB website](https://steamdb.info/app/108600/depots/).

If you are building the image using the `docker build` command, pass it as a build arg, for example:

```bash
docker build --compress --no-cache --build-arg STEAMAPPBRANCH=unstable .
```

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

## Required ports

The required ports are documented in the [Official wiki](https://pzwiki.net/wiki/Dedicated_Server#Forwarding_Required_Ports)

For now the ports are the following, but it can change.

### Steam clients ports

These ports are used by the Steam clients to connect with the server, so it must be opened in firewall and configured in NAT.

* 8766 UDP
* 8767 UDP
* 16261 UDP (configurable)

### Non Steam clients ports

These ports are used by the No Steam clients to connect with the server, so it must be opened in firewall and configured in NAT.

* 8766 UDP
* 8767 UDP
* 16261 UDP (configurable)
* 16262 - 16272 TCP (range depends of the above port and the clients slots)

### Notes

* The 16261 port can be changed using the PORT environment variable. This will affect at the TCP ports range, changing it to the next port. For example, if PORT is set to 12234, the TCP range will be 12234 - 12244.
* The TCP ports range is used by the clients, so every client slot will need a port. If your server plans to host 50 clients, then you will need to open 50 ports in firewall/nat... (16262 - 16312).
* The Wiki says that Non Steam ports are supposed to be for non steam clients, but I am using the steam client and those ports are used too.

When using docker-compose, be sure to map the UDP ports you need (16261 + 16262, or the range for your slot count) and the TCP port range if clients fail to connect.

## How to use the image

To setup the server you can use the docker-compose program:

* Copy the .env.template to .env and edit it with the settings you want. The only mandatory variable is ADMINPASSWORD and just the first time the server is executed (once is started at least once, it can be removed). The other variables are optional.
* Run the `docker-compose up -d` command to start the server.

