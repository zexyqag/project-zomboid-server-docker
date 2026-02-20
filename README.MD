# Project Zomboid dedicated server container

This Dockerfile downloads the Project Zomboid dedicated server using SteamCMD. Will allow you to deploy with ease a server in Kubernetes, Docker...

If you are contributing to this repository (scripts, CI, release pipeline, env-doc generation), see [DEVELOPMENT.md](DEVELOPMENT.md).


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

Create a `.env` file with the settings you need (examples are shown below).

## Run time environment variables

Boolean options accept: `1`, `true`, `yes`, `y`, `on` and `0`, `false`, `no`, `n`, `off`.

Generated env var references are published to the docs/env branch of this repository. The branch contains JSON files per tag for the full, runtime-derived list.
You can browse them at https://github.com/zexyqag/project-zomboid-server-docker/tree/docs/env/docs/env.

The image supports the following environment variables:
`ADMINUSERNAME:` Sets the administrator username, otherwise `admin` will be used.


`ADMINPASSWORD:` Sets or changes the admin password. This is mandatory at first startup or the server will fail to start. After the first setup, the password is updated directly in the INI file if changed, and is not passed as a command-line argument again. This minimizes the risk of logging the password in clear text. You may remove this variable after the initial setup if you wish.

`ADMINPASSWORD_FILE:` Path to a file containing the admin password. If set and the file exists, it takes precedence over `ADMINPASSWORD`. Same safe handling applies as above.


`PASSWORD:` Sets or changes the server password. Is optional. After the first setup, the password is updated directly in the INI file if changed, and is not passed as a command-line argument again.

`PASSWORD_FILE:` Path to a file containing the server password. If set and the file exists, it takes precedence over `PASSWORD`.

`RCONPASSWORD:` Sets or changes the RCON password. Must be secure. After the first setup, the password is updated directly in the INI file if changed, and is not passed as a command-line argument again.

`RCONPASSWORD_FILE:` Path to a file containing the RCON password. If set and the file exists, it takes precedence over `RCONPASSWORD`.



**Server configuration:**

- Set server INI/Lua options using the generated docs-style env names (`ini__...` / `lua__...`).
- The exact available keys depend on the image tag and source config files; see the generated env docs JSON for your tag.
- The default server name is fixed to `pzserver` to keep env var prefixes consistent.
- For admin, server, and RCON passwords, use only `ADMINPASSWORD`, `ADMINPASSWORD_FILE`, `PASSWORD`, `PASSWORD_FILE`, `RCONPASSWORD`, or `RCONPASSWORD_FILE`.


`ini__*:` Overrides for any `.ini` under `Zomboid/Server`.

- Default server INI (e.g., `pzserver.ini`): `ini__pzserver__Key=Value`
- Sectioned INI: `ini__pzserver__Section__Key=Value`
- Additional INI files: `ini__<file>__Section__Key=Value` or `ini__<file>__Key=Value`

**Note:** Password keys are managed by dedicated variables. Use `PASSWORD` / `PASSWORD_FILE` / `RCONPASSWORD` / `RCONPASSWORD_FILE`.

`INI_CTRL_DRY_RUN:` If true, logs the changes that would be applied without modifying the ini file.

`INI_CTRL_STRICT:` If true, exits with an error when an env var does not match any key in the ini file.

Example INI overrides:

```bash
# Flat ini keys
ini__pzserver__Public=true
ini__pzserver__PublicName="My Server"

# Sectioned ini keys (if your ini uses [Section] headers)
ini__pzserver__ServerOptions__Public=true
ini__pzserver__ServerOptions__PublicName="My Server"

# Password and RCONPassword must use dedicated variables:
# PASSWORD, PASSWORD_FILE, RCONPASSWORD, RCONPASSWORD_FILE
```

`lua__*:` Overrides for any `.lua` under `Zomboid/Server`.

- Default server Lua file (e.g., `pzserver_SandboxVars.lua`): `lua__pzserver_SandboxVars__...=Value`
- Additional Lua files: `lua__<file>__...=Value`
- Lua paths are represented by `__`-separated table keys.
- For files with a named root table (e.g., `SandboxVars = { ... }`), include that root key in the env name.

`LUA_CTRL_DRY_RUN:` If true, logs the changes that would be applied without modifying the Lua file.

`LUA_CTRL_STRICT:` If true, exits with an error when an env var does not match any key in the Lua file.

`LUA_CTRL_CASE_SENSITIVE:` If true, matches Lua keys case-sensitively.

Example Lua overrides:

```bash
# Example for <servername>_SandboxVars.lua
lua__pzserver_SandboxVars__SandboxVars__ZombieLore__Transmission=4
lua__pzserver_SandboxVars__SandboxVars__World__Event=2

# Example for <servername>_othersettings.lua
lua__pzserver_othersettings__SomeTable__SomeKey=true
```

`CLEAN_WORKSHOP:` If true, removes workshop items on disk that are not listed in `WORKSHOP_IDS` (after collection resolution). This only runs when `WORKSHOP_IDS` is set and collection resolution succeeds to avoid wiping everything by accident.

`CLEAN_WORKSHOP_DRY_RUN:` If true, logs which workshop items would be removed without deleting anything. Requires `CLEAN_WORKSHOP=true`.

`CLEAN_WORKSHOP_ALLOW_REMOVE_ALL:` If true, allows cleanup to remove all workshop items when none of the keep IDs are found on disk. Default is false for safety.

`CLEAN_WORKSHOP_KEEP_FILE:` Optional path to write the resolved workshop keep list (one ID per line).

`MOD_IDS:` Semicolon separated list of Mod IDs to install to the server. NOTE - B42 changes the way mod IDs must be supplied (\mod1;\mod2 inside the pzserver.ini file) when defining this variable, precede each mod id with two backslashes (\\) to escape the backslash into the ini file. Leaving this empty will clear any existing Mods value.

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

* Create a `.env` file and set the variables you want. The only mandatory variable is ADMINPASSWORD and just the first time the server is executed (once is started at least once, it can be removed). The other variables are optional.
* Run the `docker-compose up -d` command to start the server.

