#!/usr/bin/env bash
exec sshpass -p "${DEV_ENV_VM_PASSWORD:-opencloudos}" /usr/bin/scp -o PubkeyAuthentication=no "$@"
