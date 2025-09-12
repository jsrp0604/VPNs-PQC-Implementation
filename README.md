# VPNs-PQC-Implementation

This repo evaluates both classical and post-quantum cryptographic schemes in the VPN
protocols Wireguard, OpenVPN and strongSwan (IPSec). Tests will be carried in a tunnel communication
between 2 VMs: Client and Server. All of the different scheme permutations reside in Docker containers,
with every test being based on a metrics scheme.

## Build the base image

docker build -f base/Dockerfile -t pqc-base:22.04 .

## Build all permutation images

docker compose build

## Run one permutation (example: wg_pqc)

# On client VM:

ROLE=client docker compose up wg_pqc -d

# On server VM:

ROLE=server docker compose up wg_pqc -d

## Apply network profiles (in VM or container)

sudo bash scripts/netem.sh local
sudo bash scripts/netem.sh status
sudo bash scripts/netem.sh clear

## Sanity check

# Server side:

iperf3 -s

# Client side (replace IP):

bash scripts/sanity_check.sh $SERVER_IP
