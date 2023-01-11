# Docs

* https://etcd.io/docs/v3.4/op-guide/security/
* https://etcd.io/docs/v3.4/op-guide/configuration/
* https://github.com/kelseyhightower/etcd-production-setup
* https://github.com/etcd-io/etcd/issues/8320
* https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices#23-use-secure-cipher-suites

# High level action plan

1. Check current setup
2. Generate new certificates
3. Copy certificates to each server
4. Disable Patroni autofailover mode (pause mode)
5. Stop Patroni on database servers
6. Stop and remove current Etcd cluster
7. Edit Etcd config to use mTLS
8. Start Etcd cluster
9. Enable Etcd apiV2 basic authentication
10. Enable Etcd apiV3 basic authentication
11. Edit Patroni config
12. Edit third-party tools config files
13. Start Patroni on Master
14. Start Patroni on Replicas
15. Enable Patroni autofailover (resume)
16. Check log files for error messages
17. (OPTIONAL) Take a Postgres switchover and switchback using Patroni
18. (OPTIONAL) Create environment file with ad-hoc commands

:red_circle: **In this scenario I suppose Etcd cluster is used by Patroni only and it's okay to re-create it from scratch. If you have to save your Etcd data then use ``case-1-etcd-cluster-reconfigure-http-to-https.md`` instruction.**

# 1. Check current setup

## Etcd

```
$ ETCDCTL_API=2 etcdctl --endpoints=http://$(hostname -f):2379 member list
```

```
214e342c31d25d8: name=srv-pg-db02 peerURLs=http://srv-pg-db02.ru-central1.internal:2380 clientURLs=http://srv-pg-db02.ru-central1.internal:2379 isLeader=false
43cfaa679137736: name=srv-pg-arb peerURLs=http://srv-pg-arb.ru-central1.internal:2380 clientURLs=http://srv-pg-arb.ru-central1.internal:2379 isLeader=false
6b40fb7c1a183c62: name=srv-pg-db01 peerURLs=http://srv-pg-db01.ru-central1.internal:2380 clientURLs=http://srv-pg-db01.ru-central1.internal:2379 isLeader=true
```

:information_source: **NOTE**: both client and peers traffic use http protocol.

```
$ etcd --version
```

```
etcd Version: 3.5.5
Git SHA: 19002cfc6
Go Version: go1.16.15
Go OS/Arch: linux/amd64
```

Check if basic authentication for API_2 is enabled:
```
$ curl -X GET http://127.0.0.1:2379/v2/auth/enable
```

```
{"enabled":false}
```

Check if basic authentication for API_3 is enabled:
```
$ curl -X POST http://127.0.0.1:2379/v3/auth/status
```

```
{"header":{"cluster_id":"701166089172120522","member_id":"7728453471000083554","revision":"1","raft_term":"2"},"authRevision":"1"}
```

:information_source: **NOTE**: basic auth for apiV2, apiV3 is not enabled (yet).

## Patroni

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
```

```
$ patroni --version
```

```
patroni 2.1.4
```

```
$ grep -A1 "etcd" /etc/patroni/postgres.yml
```

```
etcd:
    hosts:     srv-pg-db01.ru-central1.internal:2379,srv-pg-db02.ru-central1.internal:2379,srv-pg-arb.ru-central1.internal:2379
```

:information_source: **NOTE**: in this case patroni uses etcd apiV2.

# 2. Generate new certificates

```
$ {
mv ~/ssl ~/ssl___BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S) && \
chmod 700 ~/etcd-certs-generator.sh && \
~/etcd-certs-generator.sh
}
```

Script output example:
```
=============== Input ===============
Enter the number of servers in your Etcd cluster [3]:
Enter FQDN of the 1 member [etcd-node1.example.com]: srv-pg-db01.ru-central1.internal
Enter FQDN of the 2 member [etcd-node2.example.com]: srv-pg-db02.ru-central1.internal
Enter FQDN of the 3 member [etcd-node3.example.com]: srv-pg-arb.ru-central1.internal
Enter IP address of the 1 member [10.0.0.1]: 10.129.0.29
Enter IP address of the 2 member [10.0.0.2]: 10.128.0.5
Enter IP address of the 3 member [10.0.0.3]: 10.129.0.27
Enter the number of client certificates to issue [1]: 1
Enter CN for the 1 client certificate [etcd-client]: patroni_etcd_usr
Enter the location to store certificates [/tmp/ssl]: /home/postgres/ssl
Enter the certificate authority (CA) name [TEST-CA]:
=============== Output ==============
CA certificate: /home/postgres/ssl/root.crt
CA key: /home/postgres/ssl/root.key
CA info: /home/postgres/ssl/root.info
Member 1 server certificate: /home/postgres/ssl/srv-pg-db01.ru-central1.internal.crt
Member 1 server key: /home/postgres/ssl/srv-pg-db01.ru-central1.internal.key
Member 1 server info: /home/postgres/ssl/srv-pg-db01.ru-central1.internal.info
Member 2 server certificate: /home/postgres/ssl/srv-pg-db02.ru-central1.internal.crt
Member 2 server key: /home/postgres/ssl/srv-pg-db02.ru-central1.internal.key
Member 2 server info: /home/postgres/ssl/srv-pg-db02.ru-central1.internal.info
Member 3 server certificate: /home/postgres/ssl/srv-pg-arb.ru-central1.internal.crt
Member 3 server key: /home/postgres/ssl/srv-pg-arb.ru-central1.internal.key
Member 3 server info: /home/postgres/ssl/srv-pg-arb.ru-central1.internal.info
Client 1 certificate: /home/postgres/ssl/patroni_etcd_usr.crt
Client 1 key: /home/postgres/ssl/patroni_etcd_usr.key
Client 1 info: /home/postgres/ssl/patroni_etcd_usr.info
```

# 3. Copy certificates to each server

:red_circle: **NOTE**: replace ``ETCD_CERTS_SOURCE_SERVER`` variable value and setup passwordless ssh between servers (optional).

Run below on server on which the certificates were generated:
```
$ sudo cp -rp /home/postgres/ssl /etc/etcd/ && sudo chown -R etcd:etcd /etc/etcd/ssl && sudo chmod 755 /etc/etcd
$ sudo cp -rp /home/postgres/ssl /tmp/ && sudo chown -R $(whoami):$(whoami) /tmp/ssl
```

Run on each server:
```
$ export ETCD_CERTS_SOURCE_SERVER="srv-pg-db01.ru-central1.internal"
$ scp -rp $(whoami)@${ETCD_CERTS_SOURCE_SERVER}:/tmp/ssl /tmp && sudo cp -rp /tmp/ssl /home/postgres/ && sudo chown -R postgres:postgres /home/postgres/ssl && sudo rm -rf /tmp/ssl
$ scp -rp $(whoami)@${ETCD_CERTS_SOURCE_SERVER}:/tmp/ssl /tmp && sudo cp -rp /tmp/ssl /etc/etcd/ && sudo chown -R etcd:etcd /etc/etcd/ssl && sudo chmod 750 /etc/etcd && sudo rm -rf /tmp/ssl
```

:information_source: **NOTE**: In my case I had ``~/ssl`` folder with old server certificates used by Postgres. Once I've generated new ones there can be some problems with accessing database through certificate authentication until you make the ``pg_ctl -D $PGDATA reload`` so new CA "loaded" into a database. Otherwise you can see following messages in database log file ``LOG:  could not accept SSL connection: tlsv1 alert unknown ca``.

Optional step to avoid issues described above:
```
$ patronictl -c /etc/patroni/postgres.yml reload test_cluster
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
Are you sure you want to reload members srv-pg-db01.ru-central1.internal, srv-pg-db02.ru-central1.internal? [y/N]: y
Reload request received for member srv-pg-db01.ru-central1.internal and will be processed within 10 seconds
Reload request received for member srv-pg-db02.ru-central1.internal and will be processed within 10 seconds
```

# 4. Disable Patroni autofailover mode (pause mode)

```
$ patronictl -c /etc/patroni/postgres.yml pause
```

```
Success: cluster management is paused
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
 Maintenance mode: on
```

# 5. Stop Patroni on database servers

```
sudo systemctl stop patroni
```

# 6. Stop and remove current Etcd cluster

:red_circle: **NOTE**: replace ``ETCD_DATA_DIR`` variable value.

```
$ export ETCD_DATA_DIR="/var/lib/etcd"
$ sudo systemctl stop etcd && sudo rm -rf ${ETCD_DATA_DIR}
```

# 7. Edit Etcd config to use mTLS

:red_circle: **NOTE**: replace ``ETCD_CONF`` variable value.

Replace ``http`` to ``https`` in old config file:
```
$ {
export ETCD_CONF="/etc/etcd/etcd.conf"
cp ${ETCD_CONF} ${ETCD_CONF}___BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S)
sed -i 's,http://,https://,g' ${ETCD_CONF}
}
```

:red_circle: **NOTE**: replace ``ETCD_HOST_FQDN``,``ETCD_CONF``,``ETCD_SSL_DIR`` variables values.

Add variables related to mTLS:
```
$ {
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_CONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/etc/etcd/ssl"
cp ${ETCD_CONF} ${ETCD_CONF}___BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S)
cat <<EOF >> ${ETCD_CONF}

### Client-Server mTLS ###
ETCD_LISTEN_CLIENT_URLS="https://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="https://${ETCD_HOST_FQDN}:2379"
ETCD_CERT_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt"
ETCD_KEY_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key"
ETCD_CIPHER_SUITES="TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
ETCD_TRUSTED_CA_FILE="${ETCD_SSL_DIR}/root.crt"
ETCD_CLIENT_CERT_AUTH="true"

### Peer-Peer mTLS ###
ETCD_LISTEN_PEER_URLS="https://0.0.0.0:2380"
ETCD_PEER_CERT_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt"
ETCD_PEER_KEY_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key"
ETCD_CIPHER_SUITES="TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
ETCD_PEER_TRUSTED_CA_FILE="${ETCD_SSL_DIR}/root.crt"
ETCD_PEER_CLIENT_CERT_AUTH="true"
EOF
}
```

# 8. Start Etcd cluster

:red_circle: **NOTE**: replace ``ETCD_DATA_DIR`` variable value.

```
$ export ETCD_DATA_DIR="/var/lib/etcd"
$ sudo mkdir -p ${ETCD_DATA_DIR} && sudo chmod 700 ${ETCD_DATA_DIR} && sudo chown -R etcd:etcd ${ETCD_DATA_DIR} && sudo systemctl stop etcd && sleep 5 && sudo systemctl start etcd && systemctl status etcd
```

:red_circle: **NOTE**: replace ``ETCD_HOST_FQDN``,``ETCD_CONF``,``ETCD_SSL_DIR`` variables values.

```
$ {
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_CONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/etc/etcd/ssl"
ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key member list
}
```

```
9bf7cf2d10f76057: name=srv-pg-db01 peerURLs=https://srv-pg-db01.ru-central1.internal:2380 clientURLs=https://srv-pg-db01.ru-central1.internal:2379 isLeader=false
a903aa5dd5b48d20: name=srv-pg-db02 peerURLs=https://srv-pg-db02.ru-central1.internal:2380 clientURLs=https://srv-pg-db02.ru-central1.internal:2379 isLeader=false
f4188b4c8dacdebb: name=srv-pg-arb peerURLs=https://srv-pg-arb.ru-central1.internal:2380 clientURLs=https://srv-pg-arb.ru-central1.internal:2379 isLeader=true
```

# 9. Enable Etcd apiV2 basic authentication

:red_circle: **NOTE**: replace ``ETCD_DATA_DIR`` variable value.

```
{
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_CONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/home/postgres/ssl"
export ETCD_ROOT_PWD="root123v2"
export ETCD_NEW_USR="patroni_etcd_usr"
export ETCD_NEW_USR_PWD="patroni123"
export ETCD_NEW_ROLE="patroni_role"
export ETCD_SSL_CMD="--endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key"
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user add root:${ETCD_ROOT_PWD}
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user add ${ETCD_NEW_USR}:${ETCD_NEW_USR_PWD}
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} role add ${ETCD_NEW_ROLE}
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} role grant ${ETCD_NEW_ROLE} --readwrite --path=/service/*
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user grant --roles=${ETCD_NEW_ROLE} ${ETCD_NEW_USR}
ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} auth enable
echo "${ETCD_ROOT_PWD}" | ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} -u root role remove guest
}
```

Check:
```
$ {
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_SSL_DIR="/home/postgres/ssl"
curl -X GET --cacert ${ETCD_SSL_DIR}/root.crt --cert ${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key ${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key https://${ETCD_HOST_FQDN}:2379/v2/auth/enable
}
```

```
{"enabled":true}
```

# 10. Enable Etcd apiV3 basic authentication

```
$ {
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_CONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/home/postgres/ssl"
export ETCD_ROOT_PWD="root123v3"
export ETCD_SSL_CMD="--endpoints=https://${ETCD_HOST_FQDN}:2379 --cacert=${ETCD_SSL_DIR}/root.crt --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key"
ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user add root:root123
ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user grant root root
ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} auth enable
}
```

Check:
```
$ {
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_SSL_DIR="/home/postgres/ssl"
export ETCD_SSL_CMD="--endpoints=https://${ETCD_HOST_FQDN}:2379 --cacert=${ETCD_SSL_DIR}/root.crt --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --user root"
ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} auth status
}
```

```
Authentication Status: true
AuthRevision: 3
```

:information_source: **NOTE**: looks like ``auth status`` command is available since etcd v3.5.

:information_source: **NOTE**: In my setup Patroni will use Etcd apiV2, but I enabled basic auth for apiV3 to avoid any unauthorized access.

# 11. Edit Patroni config

```
$ cp /etc/patroni/postgres.yml /etc/patroni/postgres.yml___BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S)
```

```
$ grep -A5 "etcd:" /etc/patroni/postgres.yml
```

```
etcd:
    hosts:     srv-pg-db01.ru-central1.internal:2379,srv-pg-db02.ru-central1.internal:2379,srv-pg-arb.ru-central1.internal:2379
    protocol:  https
    cacert:    /home/postgres/ssl/root.crt
    cert:      /home/postgres/ssl/patroni_etcd_usr.crt
    key:       /home/postgres/ssl/patroni_etcd_usr.key
```

# 12. Edit third-party tools config files

## Vip-Manager example:

```
...
...
...
dcs-endpoints:
  - https://srv-pg-db01.ru-central1.internal:2379
  - https://srv-pg-db02.ru-central1.internal:2379
  - https://srv-pg-arb.ru-central1.internal:2379
etcd-ca-file: /home/postgres/ssl/root.crt
etcd-cert-file: /home/postgres/ssl/patroni_etcd_usr.crt
etcd-key-file: /home/postgres/ssl/patroni_etcd_usr.key
...
...
...
```

```
$ systemctl restart vip-manager
```

## Confd example

```
$ view /etc/systemd/system/confd.service
```

```
ExecStart=/opt/confd/bin/confd -watch -backend etcd -node https://127.0.0.1:2379 -client-ca-keys /home/postgres/ssl/root.crt -client-cert /home/postgres/ssl/patroni_etcd_usr.crt -client-key /home/postgres/ssl/patroni_etcd_usr.key
```

```
$ systemctl daemon-reload
$ systemctl restart confd
```

# 13. Start Patroni on Master

```
$ sudo systemctl start patroni
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------+---------+----+-----------+
| Member                           | Host                             | Role   | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader | running | 36 |           |
+----------------------------------+----------------------------------+--------+---------+----+-----------+
 Maintenance mode: on
```

# 14. Start Patroni on Replicas

```
$ sudo systemctl start patroni
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
 Maintenance mode: on
```

# 15. Enable Patroni autofailover (resume)

```
$ patronictl -c /etc/patroni/postgres.yml resume
```

```
Success: cluster management is resumed
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
```

# 16. Check log files for error messages

## Patroni

```
$ sudo journalctl -u patroni -n 100 -f
$ sudo journalctl -u patroni -n 1000 -f | egrep -i 'error|fatal|warn'
```

## Etcd
```
$ sudo journalctl -u etcd -n 100 -f
$ sudo journalctl -u etcd -n 1000 -f | egrep -i 'error|fatal|warn'
```

## (OPTIONAL) Confd

```
$ sudo journalctl -u confd -n 100 -f
$ sudo journalctl -u confd -n 1000 -f | egrep -i 'error|fatal|warn'
```

## (OPTIONAL) Vip-Manager

```
$ sudo journalctl -u vip-manager -n 100 -f
$ sudo journalctl -u vip-manager -n 1000 -f | egrep -i 'error|fatal|warn'
```

# 17. (OPTIONAL) Take a Postgres switchover and switchback using Patroni

## Switchover

```
$ patronictl -c /etc/patroni/postgres.yml switchover test_cluster
```

```
Master [srv-pg-db01.ru-central1.internal]:
Candidate ['srv-pg-db02.ru-central1.internal'] []:
When should the switchover take place (e.g. 2023-01-10T19:39 )  [now]:
Current cluster topology
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 36 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 36 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
Are you sure you want to switchover cluster test_cluster, demoting current master srv-pg-db01.ru-central1.internal? [y/N]: y
2023-01-10 18:39:09.65637 Successfully switched over to "srv-pg-db02.ru-central1.internal"
+ Cluster: test_cluster (7150267844858450339) ------------------------+---------+---------+----+-----------+
| Member                           | Host                             | Role    | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+---------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Replica | stopped |    |   unknown |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Leader  | running | 36 |           |
+----------------------------------+----------------------------------+---------+---------+----+-----------+
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Sync Standby | running | 37 |         0 |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Leader       | running | 37 |           |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
```

## Switchback


```
$ patronictl -c /etc/patroni/postgres.yml switchover test_cluster
```

```
Master [srv-pg-db02.ru-central1.internal]:
Candidate ['srv-pg-db01.ru-central1.internal'] []:
When should the switchover take place (e.g. 2023-01-10T19:40 )  [now]:
Current cluster topology
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Sync Standby | running | 37 |         0 |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Leader       | running | 37 |           |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
Are you sure you want to switchover cluster test_cluster, demoting current master srv-pg-db02.ru-central1.internal? [y/N]: y
2023-01-10 18:40:45.21883 Successfully switched over to "srv-pg-db01.ru-central1.internal"
+ Cluster: test_cluster (7150267844858450339) ------------------------+---------+---------+----+-----------+
| Member                           | Host                             | Role    | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+---------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader  | running | 37 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Replica | stopped |    |   unknown |
+----------------------------------+----------------------------------+---------+---------+----+-----------+
```

```
$ patronictl -c /etc/patroni/postgres.yml list
```

```
+ Cluster: test_cluster (7150267844858450339) ------------------------+--------------+---------+----+-----------+
| Member                           | Host                             | Role         | State   | TL | Lag in MB |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
| srv-pg-db01.ru-central1.internal | srv-pg-db01.ru-central1.internal | Leader       | running | 38 |           |
| srv-pg-db02.ru-central1.internal | srv-pg-db02.ru-central1.internal | Sync Standby | running | 38 |         0 |
+----------------------------------+----------------------------------+--------------+---------+----+-----------+
```

# 18. (OPTIONAL) Create environment file with ad-hoc commands

```
$ cat <<EOF >> ~/etcd.env
export ETCD_HOST_FQDN="$(hostname -f)"
export ETCD_USER="patroni_etcd_usr"
export ETCDCONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/home/postgres/ssl"

alias etcdver='etcd --version'
alias etcdconf='view \${ETCDCONF}'
alias etcdlog='sudo journalctl -u etcd | view -'
alias etcdlogtail='sudo journalctl -u etcd -f -n 1000'
alias etcdlogerr="sudo journalctl -u etcd -f -n 1000 | egrep -i 'WARNING|ERROR|FATAL'"

#apiV3
export ETCD_SSL_ARGS_V3="--endpoints=https://\${ETCD_HOST_FQDN}:2379 --cert=\${ETCD_SSL_DIR}/\${ETCD_USER}.crt --key=\${ETCD_SSL_DIR}/\${ETCD_USER}.key --cacert=\${ETCD_SSL_DIR}/root.crt"
alias etcdlist='ETCDCTL_API=3 etcdctl \${ETCD_SSL_ARGS_V3} endpoint status --cluster -w table'

#apiV2
export ETCD_SSL_ARGS_V2="--endpoints=https://\${ETCD_HOST_FQDN}:2379 --ca-file=\${ETCD_SSL_DIR}/root.crt --cert-file=\${ETCD_SSL_DIR}/\${ETCD_USER}.crt --key-file=\${ETCD_SSL_DIR}/\${ETCD_USER}.key"
alias etcdmembers='ETCDCTL_API=2 etcdctl \${ETCD_SSL_ARGS_V2} member list'
alias etcdhealth='ETCDCTL_API=2 etcdctl \${ETCD_SSL_ARGS_V2} cluster-health'
alias etcdls='ETCDCTL_API=2 etcdctl \${ETCD_SSL_ARGS_V2} ls /service/ --recursive'
alias etcdgetv2key='ETCDCTL_API=2 etcdctl \${ETCD_SSL_ARGS_V2} get '

#Move Etcd Leader
alias etcdmove="ETCDCTL_API=3 etcdctl \${ETCD_SSL_ARGS_V3} --endpoints=https:\$(ETCDCTL_API=2 etcdctl \${ETCD_SSL_ARGS_V2} member list | grep -i 'isleader=true' | awk  -F'[: =]' '{print \$7}'):2379 move-leader"
EOF
```
