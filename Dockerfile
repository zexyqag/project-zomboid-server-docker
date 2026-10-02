###########################################################
# Dockerfile that builds a Project Zomboid Gameserver
###########################################################
FROM cm2network/steamcmd:root

ENV STEAMAPPID=380870
ENV STEAMAPP=pz
ENV STEAMAPPDIR="${HOMEDIR}/${STEAMAPP}-dedicated"
# Fix for a new installation problem in the Steamcmd client
ENV HOME="${HOMEDIR}"

# Steam beta branch to install; "public" is the stable release.
ARG STEAMAPPBRANCH="public"
ENV STEAMAPPBRANCH=$STEAMAPPBRANCH
# Space-separated locales to install besides en_US.UTF-8, for example "es_ES.UTF-8 de_DE.UTF-8".
ARG EXTRA_LOCALES=""

RUN apt-get update \
  && apt-get install -y --no-install-recommends --no-install-suggests \
  jq \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN for locale in en_US.UTF-8 ${EXTRA_LOCALES}; do \
       sed -i "s/^# *\(${locale}\)/\1/" /etc/locale.gen; \
     done \
  && locale-gen

# "-beta public" is not a valid beta, so the flag is only passed for other branches.
# SteamCMD can fail the first attempt with "Missing configuration" until the app info is cached.
RUN set -x \
  && mkdir -p "${STEAMAPPDIR}" \
  && if [ "${STEAMAPPBRANCH}" = "public" ]; then BETA_ARGS=""; \
     else BETA_ARGS="-beta ${STEAMAPPBRANCH}"; fi \
  && for attempt in 1 2 3; do \
       bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
         +login anonymous \
         +app_update "${STEAMAPPID}" ${BETA_ARGS} validate \
         +quit \
       && break; \
       if [ "${attempt}" = "3" ]; then exit 1; fi; \
       sleep 10; \
     done \
  # Created here so new named volumes start out owned by the steam user.
  && mkdir -p "${HOMEDIR}/Zomboid" "${STEAMAPPDIR}/steamapps/workshop" \
  && chown -R "${USER}:${USER}" "${HOMEDIR}"

COPY --chmod=755 scripts /server/scripts
# image-env lists the variables the image sets itself, so startup can warn about unknown ones.
RUN ln -s /server/scripts/list_env.sh /usr/local/bin/list-env \
  && ln -s /server/scripts/console.sh /usr/local/bin/console \
  && env | cut -d= -f1 | sort > /server/scripts/image-env

USER ${USER}
WORKDIR ${HOMEDIR}

EXPOSE 16261-16262/udp \
  27015/tcp

# Large modded servers can take a long time to start; the check only counts once the server is up.
HEALTHCHECK --start-period=30m --interval=30s --timeout=10s --retries=3 \
  CMD ["/server/scripts/healthcheck.sh"]

ENTRYPOINT ["/server/scripts/entry.sh"]
