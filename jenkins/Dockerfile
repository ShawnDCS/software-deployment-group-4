# Custom Jenkins image: official LTS + Docker CLI + our plugins + JCasC config baked in.
# Rebuilding this image reproduces the whole Jenkins setup — no clicking in the UI.
FROM jenkins/jenkins:2.580.2-lts-jdk21

USER root
# Docker CLI (static binary) and buildx plugin, copied from the official pinned docker CLI image.
# Jenkins talks to the HOST's Docker daemon through the mounted /var/run/docker.sock.
COPY --from=docker:29.9.3-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29.9.3-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
USER jenkins

# Skip the setup wizard: security + admin user come from casc.yaml instead.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1g" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/casc.yaml
