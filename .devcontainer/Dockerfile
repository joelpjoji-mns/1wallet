FROM ghcr.io/cirruslabs/flutter:3.47.7

# Install Node.js 22 LTS for PWA & scripts
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs make git curl \
    && rm -rf /var/lib/apt/lists/*

# Add non-root developer user
RUN useradd -m -s /bin/bash developer \
    && chown -R developer:developer /sdks /workspace || true

USER developer
WORKDIR /workspace

CMD ["/bin/bash"]
