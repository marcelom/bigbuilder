FROM ubuntu:latest AS bigbuilder

# https://github.com/tailwindlabs/tailwindcss/releases
ARG TAILWINDCSS_VERSION=3.3.3
# https://github.com/gohugoio/hugo/releases
ARG HUGO_VERSION=0.118.2
# https://download.docker.com/linux/static/stable
ARG DOCKER_VERSION=24.0.6
# https://go.dev/dl/
ARG GOLANG_VERSION=1.21.1
ARG GOLANG_SHA256=b3075ae1ce5dab85f89bc7905d1632de23ca196bd8336afd93fa97434cfa55ae
# https://github.com/nodesource/distributions#nodejs-release-calendar
ARG NODEJS_VERSION=20
# https://github.com/actions/runner/releases
ARG GH_RUNNER_VERSION=2.309.0

# Install the apt stuff...
RUN DEBIAN_FRONTEND=noninteractive \
    && apt-get update \
    && apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends apt-utils dialog \
    #
    # install a lot of things...
    && apt-get install -y --no-install-recommends \
    #
    # Install the buildpack-curl equivalent, more info here: https://github.com/docker-library/buildpack-deps/blob/master/debian/bookworm/curl/Dockerfile
	ca-certificates curl gnupg netbase sq wget \
    #
    # Install the buildpack-scm equivalent, more info here: https://github.com/docker-library/buildpack-deps/blob/master/debian/bookworm/scm/Dockerfile
	git mercurial openssh-client subversion procps \
    #
    # Installs build-essentials
	build-essential \
    #
    # Install python3
    python3 python3-distutils python3-pip python3-apt \
    #
    # Some other random things
    jq rsync sudo tini \
    #
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install Nodejs
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_VERSION}.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    #
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install Go
RUN curl -fsSL https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz -o go.tgz \
    && echo "${GOLANG_SHA256} *go.tgz" | sha256sum -c - \
	&& tar -C /usr/local -xzf go.tgz \
	&& rm go.tgz \
    #
    # Cleanup
    && mkdir -p /go/bin /go/pkg /go/src \
    && chmod -R 1777 /go \
    && rm -rf /go/src /go/pkg /tmp/gotools \
    #
    # Install golangci-lint
    && curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /go/bin 2>&1

ENV GOPATH /go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH
ENV GO111MODULE=auto

# Install tailwind and hugo
RUN curl -fsSL https://github.com/tailwindlabs/tailwindcss/releases/download/v${TAILWINDCSS_VERSION}/tailwindcss-linux-x64 -o /usr/local/bin/tailwindcss \
    && chmod a+x /usr/local/bin/tailwindcss \
    #
    && curl -fsSL https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_linux-amd64.tar.gz -o /tmp/hugo.tgz \
    && tar -C /usr/local/bin -xf /tmp/hugo.tgz hugo \
    && rm /tmp/hugo.tgz


FROM bigbuilder AS tmpgobuilder

# Make sure bobin is empty!
RUN rm -rf /go/bin/*

# Installs gopls and its dependencies. This provides full Go support for vscode.
RUN mkdir -p /tmp/gotools \
    && cd /tmp/gotools \
    # Not sure why, but these break in go 1.18 if we build them all in one swoop
    && go install -v golang.org/x/tools/gopls@latest \
    && go install -v github.com/uudashr/gopkgs/v2/cmd/gopkgs@latest \
    && go install -v github.com/ramya-rao-a/go-outline@latest \
    && go install -v github.com/fatih/gomodifytags@latest \
    && go install -v github.com/haya14busa/goplay/cmd/goplay@latest \
    && go install -v github.com/josharian/impl@latest \
    && go install -v github.com/cweill/gotests/gotests@latest \
    && go install -v honnef.co/go/tools/cmd/staticcheck@latest \
    && go install -v golang.org/x/lint/golint@latest \
    && go install -v github.com/mgechev/revive@latest \
    && go install -v github.com/go-delve/delve/cmd/dlv@latest \
    #&& go install -v github.com/golangci/golangci-lint/cmd/golangci-lint@latest \
    #
    # Installs our extra tools (in addition to the ones above required for go vscode support)
    && go install -v \
        github.com/vektra/mockery/v2@latest


FROM bigbuilder AS bigdev

COPY --from=tmpgobuilder --chmod=755 /go/bin/* /go/bin

# The vscode-go team has been experimenting with dlv dap native interface. They expect the new binary to be named
# dlv-dap, but it is actually identical to dlv. Yeah... I have no idea why as well... Lets just make a copy
RUN ln -s /go/bin/dlv /go/bin/dlv-dap
