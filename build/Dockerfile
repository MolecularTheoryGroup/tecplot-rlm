FROM ubuntu:18.04

# Install minimal required packages
RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    inotify-tools \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Create rlm user and group
RUN groupadd -r rlm && useradd -r -g rlm rlm

# Create installation directory
ENV INSTALL_DIR=/opt/rlm
RUN mkdir -p ${INSTALL_DIR}

# Copy the RLM installer script
COPY rlm*_linux*.sh /tmp/

# Install RLM
RUN sh /tmp/rlm*_linux*.sh --prefix=${INSTALL_DIR} --exclude-subdir \
    && rm /tmp/rlm*_linux*.sh \
    && chown -R rlm:rlm ${INSTALL_DIR}

# Create directory for config files
ENV CONFIG_DIR=/etc/rlm
RUN mkdir -p ${CONFIG_DIR} && chown -R rlm:rlm ${CONFIG_DIR}

# Copy startup script
COPY start.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/start.sh && \
    chown rlm:rlm /usr/local/bin/start.sh

VOLUME ["${CONFIG_DIR}"]

CMD ["bash", "/usr/local/bin/start.sh"]