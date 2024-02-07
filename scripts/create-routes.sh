#!/usr/bin/env bash

if [ -n "$DEBUG" ]; then
  set -x
fi

set -e

sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirror.nju.edu.cn/alpine#g' /etc/apk/repositories
apk add iptables iptables-legacy

# the following vars should be the remote node's attribute.
NODE_IP=${NODE_IP:=}
FLANNEL_MAC=${MAC:-}
FLANNEL_SUBNET=${SUBNET:-}
# gets the flannel IP
FLANNEL_IP=${FLANNEL_SUBNET%/*}
CLUSTER1_CIDR=${CIDR1:-}
CLUSTER2_CIDR=${CIDR2:-}

if [ -z "${NODE_IP}" -o -z "${FLANNEL_MAC}" -o -z "${FLANNEL_SUBNET}" ]; then
  echo "missing require variable"
  exit 1
fi

if [-z "${CLUSTER1_CIDR}" -o -z "${CLUSTER2_CIDR}" ]; then
  echo "missing cluster1 or cluster2 cidr configuration"
  exit1
fi

# ensure arp table
ip neigh add "${FLANNEL_IP}" lladdr "${FLANNEL_MAC}" dev flannel.1 nud permanent
ip neigh show "${FLANNEL_IP}"
if [ $(command -v arping) ]; then
  arping -c 4 "${FLANNEL_IP}"
fi

# ensure route on flannel.1
ip route add "${FLANNEL_SUBNET}" via "${FLANNEL_IP}" dev flannel.1 onlink
ip route get "${FLANNEL_IP}"

# ensure fdb table
bridge fdb add "${FLANNEL_MAC}" dev flannel.1 self dst "${NODE_IP}"
bridge fdb show dev flannel.1 | grep "${FLANNEL_MAC}"

# modify iptables for not MASQUERADE traffic between clusters
if [ $(iptables-save | wc -l) -gt $(iptables-legacy-save | wc -l ) ]; then
  nft insert rule ip nat POSTROUTING ip saddr ${CLUSTER1_CIDR} ip daddr ${CLUSTER2_CIDR} counter return
  nft insert rule ip nat POSTROUTING ip saddr ${CLUSTER2_CIDR} ip daddr ${CLUSTER1_CIDR} counter return
else
  iptables-legacy -t nat -I POSTROUTING 1 -s ${CLUSTER1_CIDR} -d ${CLUSTER2_CIDR} -j RETURN
  iptables-legacy -t nat -I POSTROUTING 1 -s ${CLUSTER2_CIDR} -d ${CLUSTER1_CIDR} -j RETURN
fi
