# Build AWS CLI V2 for linux alpine
# See https://stackoverflow.com/questions/60298619/awscli-version-2-on-alpine-linux
# See https://github.com/aws/aws-cli/issues/4685
ARG ALPINE_VERSION=3.16
FROM python:3.10.5-alpine${ALPINE_VERSION} as builder

ARG AWS_CLI_VERSION=2.7.20
RUN apk add --no-cache git unzip groff build-base libffi-dev cmake
RUN git clone --single-branch --depth 1 -b ${AWS_CLI_VERSION} https://github.com/aws/aws-cli.git

WORKDIR aws-cli
RUN sed -i'' 's/PyInstaller.*/PyInstaller==5.2/g' requirements-build.txt
RUN python -m venv venv
RUN . venv/bin/activate
RUN scripts/installers/make-exe
RUN unzip -q dist/awscli-exe.zip
RUN aws/install --bin-dir /aws-cli-bin
RUN /aws-cli-bin/aws --version

# reduce image size: remove autocomplete and examples
RUN rm -rf /usr/local/aws-cli/v2/current/dist/aws_completer /usr/local/aws-cli/v2/current/dist/awscli/data/ac.index /usr/local/aws-cli/v2/current/dist/awscli/examples
RUN find /usr/local/aws-cli/v2/current/dist/awscli/botocore/data -name examples-1.json -delete

# Install docker-credential-ecr-login
FROM golang:alpine AS golang
RUN apk add git && go install github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login@latest

# Build final docker image now that all binaries are OK
FROM docker:20 as base

ARG NODE_VERSION
ENV NODE_VERSION $NODE_VERSION
ARG FULL_NODE_VERSION
ENV FULL_NODE_VERSION $FULL_NODE_VERSION
ARG TERRAFORM_VERSION
ENV TERRAFORM_VERSION $TERRAFORM_VERSION
ARG TERRAGRUNT_VERSION
ENV TERRAGRUNT_VERSION $TERRAGRUNT_VERSION
ARG PULUMI_VERSION
ENV PULUMI_VERSION $PULUMI_VERSION

# Entrypoint file
ENV DOCKER_DRIVER overlay
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
COPY --from=golang /go/bin/docker-credential-ecr-login /usr/local/bin

# Install alpine packages
RUN apk update
RUN apk upgrade --available
RUN apk add --no-cache curl wget zip tar python3 py3-pip git openssl openssh-client jq
RUN apk add --no-cache bash tar gzip openrc yarn ansible
RUN pip3 install --upgrade pip --ignore-installed distlib
RUN pip3 install --upgrade yq --ignore-installed distlib
# https://github.com/docker/compose/issues/11168#issuecomment-1800362132
RUN pip install pyyaml==5.3.1
RUN pip3 install --upgrade --no-cache-dir docker-compose
RUN rm -rf /var/cache/apk/*
RUN ansible --version

# Install nodejs for musl linux
COPY files/node-linux-x64-musl.tar.gz /root/node-linux-x64-musl.tar.gz
RUN tar -xvzf /root/node-linux-x64-musl.tar.gz -C /root
RUN rm /root/node-linux-x64-musl.tar.gz
ENV PATH="/root/node-${FULL_NODE_VERSION}-linux-x64-musl/bin:${PATH}"
RUN echo "export PATH=$PATH" > /etc/environment
RUN node -v

# Install terraform
COPY files/terraform_linux_amd64.zip /root/terraform_linux_amd64.zip
RUN unzip /root/terraform_linux_amd64.zip -d /root
RUN rm /root/terraform_linux_amd64.zip
RUN mv /root/terraform /usr/local/bin/terraform
RUN chmod +x /usr/local/bin/terraform
RUN terraform -v

# Install terragrunt
COPY files/terragrunt /usr/local/bin/terragrunt
RUN chmod +x /usr/local/bin/terragrunt
RUN terragrunt -v

# Install pulumi
# COPY files/pulumi.tar.gz /root/pulumi.tar.gz
# RUN tar -xvzf /root/pulumi.tar.gz -C /root
# RUN rm /root/pulumi.tar.gz
# ENV PATH="/root/pulumi-v${PULUMI_VERSION}-linux-x64/pulumi:${PATH}"
# RUN echo "export PATH=$PATH" > /etc/environment
# RUN pulumi version

# Install node tools
RUN npm i -g pino pino-pretty

# Install AWS CLI V2
COPY --from=builder /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=builder /aws-cli-bin/ /usr/local/bin/
RUN aws --version

# Entrypoint
ENTRYPOINT ["entrypoint.sh"]
CMD ["/bin/sh"]

# Test the image before building
FROM base AS test

RUN node -v && \
    npm -v && \
    yarn -v && \
    terraform -v && \
    terragrunt -v && \
    ansible --version && \
#    pulumi version && \
    aws --version

# Create Image after tests
FROM base AS release
