# Description

Step by step instructions on how to reconfigure existing Etcd cluster from HTTP to HTTPS.

**Case 1:** instruction for Etcd cluster only.

**Case 2:** instruction when Etcd cluster is used by Patroni PostgreSQL cluster (no downtime for postgres database).

**NOTE**: self-signed certificates generated by ``etcd-certs-generator.sh`` script are used in this example.