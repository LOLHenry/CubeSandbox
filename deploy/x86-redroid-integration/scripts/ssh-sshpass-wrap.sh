#!/usr/bin/env bash
# Wrap ssh/scp for dev-env password auth via sshpass (headless Cloud Agent).
exec sshpass -p "${DEV_ENV_VM_PASSWORD:-opencloudos}" /usr/bin/ssh -o PubkeyAuthentication=no "$@"
