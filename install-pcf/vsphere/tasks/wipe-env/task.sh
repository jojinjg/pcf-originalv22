#!/bin/bash
set -eu

root=$(pwd)

export GOVC_TLS_CA_CERTS=/tmp/vcenter-ca.pem
echo "$GOVC_CA_CERT" > $GOVC_TLS_CA_CERTS

function check_opsman_available {
  local opsman_domain=$1

  if [[ -z $(dig +short $opsman_domain) ]]; then
    echo "unavailable"
    return
  fi

  status_code=$(curl -L -s -o /dev/null -w "%{http_code}" -k "https://${opsman_domain}/login/ensure_availability")
  if [[ $status_code != 200 ]]; then
    echo "unavailable"
    return
  fi

  echo "available"
}

opsman_available=$(check_opsman_available $OPSMAN_DOMAIN_OR_IP_ADDRESS)
if [[ $opsman_available == "available" ]]; then
  om-linux \
    --target "https://${OPSMAN_DOMAIN_OR_IP_ADDRESS}" \
    --skip-ssl-validation \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "$OPSMAN_USERNAME" \
    --password "$OPSMAN_PASSWORD" \
    delete-installation
fi

# Delete Active OpsMan
possible_opsmans=$(govc find ${GOVC_RESOURCE_POOL} -type m -guest.ipAddress ${OPSMAN_IP} -runtime.powerState poweredOn)

for opsman in ${possible_opsmans}; do
  network="$(govc vm.info -r=true -json ${opsman} | jq -r '.VirtualMachines[0].Guest.Net[0].Network')"
  if [[ ${network} == ${GOVC_NETWORK} ]]; then
    echo "Powering off and removing ${opsman}..."
    set +e
    govc vm.power -vm.ipath=${opsman} -off
    set -e
    govc vm.destroy -vm.ipath=${opsman}
  fi
done
