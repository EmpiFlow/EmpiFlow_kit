# EmpiFlow kit — ERPNext 15 + Frappe HR in one image.
#
# The published image is built from this file; the client never builds it (D-003, D-011).
# Version pins live in apps.json — one row per app; the loop below adds every one of them.
#
# Build:
#   docker build -t ghcr.io/empiflow/empiflow-kit-erpnext:dev \
#     --build-arg ERPNEXT_VERSION=$(jq -r .base.tag apps.json) \
#     --build-arg HRMS_REF=$(jq -r '.apps[0].ref' apps.json) .
#
# Why this works inside the *production* image (measured 2026-11-15, T-010):
#   * node 22 + yarn are in the image under /home/frappe/.nvm (not on the login PATH — the ENV below fixes it);
#   * git and jq are installed;
#   * HRMS's pyproject declares no dependencies, so the missing gcc/build-essential is never needed.
ARG ERPNEXT_VERSION=v15.125.0
FROM frappe/erpnext:${ERPNEXT_VERSION}

ARG ERPNEXT_VERSION
ARG HRMS_REF=5e12e3a3
ARG HRMS_VERSION=15.64.8
ARG GIT_SHA=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="EmpiFlow kit — ERPNext 15 + Frappe HR" \
      org.opencontainers.image.description="ERPNext 15 with Frappe HR (hrms) baked in, plus the kit's create-site step" \
      org.opencontainers.image.source="https://github.com/EmpiFlow/EmpiFlow_kit" \
      org.opencontainers.image.url="https://github.com/EmpiFlow/EmpiFlow_kit" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${ERPNEXT_VERSION}" \
      com.empiflow.erpnext.version="${ERPNEXT_VERSION}" \
      com.empiflow.hrms.ref="${HRMS_REF}" \
      com.empiflow.hrms.version="${HRMS_VERSION}" \
      com.empiflow.base.image="frappe/erpnext:${ERPNEXT_VERSION}"

USER root
COPY --chown=frappe:0 apps.json /tmp/apps.json
RUN jq -e '.base and (.apps | type == "array")' /tmp/apps.json > /dev/null

# node lives in an nvm dir that is not on the default PATH; bench build and the websocket service need it.
ENV PATH=/home/frappe/.nvm/current/bin:${PATH}

USER frappe
WORKDIR /home/frappe/frappe-bench

# --- add every app in apps.json, then pin it to its exact commit ---
RUN set -eux; \
    for row in $(jq -r '.apps[] | @base64' /tmp/apps.json); do \
        _jq() { echo "${row}" | base64 -d | jq -r "$1"; }; \
        url=$(_jq '.url'); \
        branch=$(_jq '.branch'); \
        ref=$(_jq '.ref // empty'); \
        bench get-app --branch "${branch}" "${url}"; \
        app=$(basename "${url}" .git); \
        if [ -n "${ref}" ] && [ "${ref}" != "null" ]; then git -C "apps/${app}" checkout --quiet "${ref}"; fi; \
        bench setup requirements --python; \
    done; \
    rm -f /tmp/apps.json

# --- build assets into the image's *baked* asset dir (D-003) ---
# `sites/assets` is re-created as a symlink to `assets/` by the image entrypoint at every start, so anything
# built here must be copied into `assets/` or HRMS loads without CSS/JS.
RUN mkdir -p sites/assets \
 && bench build \
 && cp -a sites/assets/. assets/ \
 && rm -rf sites/assets

# One line per app, readable without starting a container: `docker run --rm <image> cat .../VERSIONS`
RUN bench version | tee /home/frappe/frappe-bench/VERSIONS

# --- the kit's create-site step, baked in so no file has to be bind-mounted at run time ---
# Kept last on purpose: editing this script rebuilds one layer, not the whole app build.
USER root
COPY --chown=root:root docker/create-site.sh /usr/local/bin/create-site.sh
RUN chmod 0755 /usr/local/bin/create-site.sh
USER frappe
