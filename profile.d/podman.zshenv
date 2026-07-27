if [[ $OSTYPE == darwin* ]]; then
  export DOCKER_HOST="unix:///var/run/docker.sock"
else
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$UID}/podman/podman.sock"
fi
export DOCKER_BUILDKIT=0
