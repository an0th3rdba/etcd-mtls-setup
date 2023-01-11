# Docs

* https://etcd.io/docs/v3.4/op-guide/security/
* https://etcd.io/docs/v3.4/op-guide/configuration/
* https://github.com/kelseyhightower/etcd-production-setup
* https://github.com/etcd-io/etcd/issues/8320
* https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices#23-use-secure-cipher-suites

# Current setup

```
$ ETCDCTL_API=2 etcdctl --endpoints=http://$(hostname -f):2379 member list
```

```
214e342c31d25d8: name=srv-pg-db02 peerURLs=http://srv-pg-db02.ru-central1.internal:2380 clientURLs=http://srv-pg-db02.ru-central1.internal:2379 isLeader=false
43cfaa679137736: name=srv-pg-arb peerURLs=http://srv-pg-arb.ru-central1.internal:2380 clientURLs=http://srv-pg-arb.ru-central1.internal:2379 isLeader=false
6b40fb7c1a183c62: name=srv-pg-db01 peerURLs=http://srv-pg-db01.ru-central1.internal:2380 clientURLs=http://srv-pg-db01.ru-central1.internal:2379 isLeader=true
```

**NOTE**: both client and peers traffic use http protocol.

# Issue certificates for each Etcd cluster member

```
$ chmod 700 ~/etcd-certs-generator.sh

$ ~/etcd-certs-generator.sh
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
Enter the number of client certificates to issue [1]: 0
Enter the location to store certificates [/tmp/ssl]: /etc/etcd/ssl
Enter the certificate authority (CA) name [TEST-CA]: MYCA
=============== Output ==============
CA certificate: /etc/etcd/ssl/root.crt
CA key: /etc/etcd/ssl/root.key
CA info: /etc/etcd/ssl/root.info
Member 1 server certificate: /etc/etcd/ssl/srv-pg-db01.ru-central1.internal.crt
Member 1 server key: /etc/etcd/ssl/srv-pg-db01.ru-central1.internal.key
Member 1 server info: /etc/etcd/ssl/srv-pg-db01.ru-central1.internal.info
Member 2 server certificate: /etc/etcd/ssl/srv-pg-db02.ru-central1.internal.crt
Member 2 server key: /etc/etcd/ssl/srv-pg-db02.ru-central1.internal.key
Member 2 server info: /etc/etcd/ssl/srv-pg-db02.ru-central1.internal.info
Member 3 server certificate: /etc/etcd/ssl/srv-pg-arb.ru-central1.internal.crt
Member 3 server key: /etc/etcd/ssl/srv-pg-arb.ru-central1.internal.key
Member 3 server info: /etc/etcd/ssl/srv-pg-arb.ru-central1.internal.info
```

# Copy certs folder to each Etcd cluster member

```
$ scp -rp /etc/etcd/ssl srv-pg-db02.ru-central1.internal:/etc/etcd
$ scp -rp /etc/etcd/ssl srv-pg-arb.ru-central1.internal:/etc/etcd
```

# Enable Client-Server mTLS

## Edit config file

> Ref. to https://etcd.io/docs/v3.5/op-guide/runtime-configuration/
To update the advertise client URLs of a member, simply restart that member with updated client urls flag (--advertise-client-urls) or 
environment variable (ETCD_ADVERTISE_CLIENT_URLS). The restarted member will self publish the updated URLs. 
A wrongly updated client URL will not affect the health of the etcd cluster.

```
{
export ETCD_CONF=/etc/etcd/etcd.conf
export ETCD_HOST_FQDN=$(hostname -f)
export ETCD_SSL_DIR=/etc/etcd/ssl
cp ${ETCD_CONF} ${ETCD_CONF}__BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S)
cat <<EOF >> ${ETCD_CONF}

### Client-Server mTLS ###
ETCD_LISTEN_CLIENT_URLS="https://0.0.0.0:2379"
ETCD_ADVERTISE_CLIENT_URLS="https://${ETCD_HOST_FQDN}:2379"
ETCD_CERT_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt"
ETCD_KEY_FILE="${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key"
ETCD_CIPHER_SUITES="TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
ETCD_TRUSTED_CA_FILE="${ETCD_SSL_DIR}/root.crt"
ETCD_CLIENT_CERT_AUTH="true"
EOF
}
```

## Restart each Etcd cluster member (one by one)

```
$ sudo systemctl stop etcd && sleep 5 && sudo systemctl start etcd && systemctl status etcd
```

## Check result

```
$ ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key member list
```

```
214e342c31d25d8: name=srv-pg-db02 peerURLs=http://srv-pg-db02.ru-central1.internal:2380 clientURLs=https://srv-pg-db02.ru-central1.internal:2379 isLeader=false
43cfaa679137736: name=srv-pg-arb peerURLs=http://srv-pg-arb.ru-central1.internal:2380 clientURLs=https://srv-pg-arb.ru-central1.internal:2379 isLeader=false
6b40fb7c1a183c62: name=srv-pg-db01 peerURLs=http://srv-pg-db01.ru-central1.internal:2380 clientURLs=https://srv-pg-db01.ru-central1.internal:2379 isLeader=true
```

```
$ ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key cluster-health
```

```
member 214e342c31d25d8 is healthy: got healthy result from https://srv-pg-db02.ru-central1.internal:2379
member 43cfaa679137736 is healthy: got healthy result from https://srv-pg-arb.ru-central1.internal:2379
member 6b40fb7c1a183c62 is healthy: got healthy result from https://srv-pg-db01.ru-central1.internal:2379
cluster is healthy
```

# Enable peer connections mTLS

## Edit config file

> Ref. to https://etcd.io/docs/v3.5/op-guide/runtime-configuration/
To update the advertise peer URLs of a member, first update it explicitly via member command and then restart the member. 
The additional action is required since updating peer URLs changes the cluster wide configuration and can affect the health of the etcd cluster.

```
{
export ETCD_CONF=/etc/etcd/etcd.conf
export ETCD_HOST_FQDN=$(hostname -f)
export ETCD_SSL_DIR=/etc/etcd/ssl
cp ${ETCD_CONF} ${ETCD_CONF}__BKP_$(hostname -f)_$(date +%Y%m%d)T$(date +%H%M%S)
cat <<EOF >> ${ETCD_CONF}

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

## Update each member using ``etcdctl``

**NOTE**: in my case Etcd authentication for APIv3 is enabled. If your setup doesn't have configured basic authentication then remove ``--user`` and ``--password`` flags.

Prepare update commands:
```
$ export ETCD_ROOT_USER="root"
$ export ETCD_ROOT_PWD="******"
$ ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key member list | awk -F'[: =]' '{print "ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --cacert=${ETCD_SSL_DIR}/root.crt --user ${ETCD_ROOT_USER} --password ${ETCD_ROOT_PWD} member update "$1" --peer-urls=https:"$7":"$8}'
```

Output:
```
ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --cacert=${ETCD_SSL_DIR}/root.crt --user ${ETCD_ROOT_USER} --password ${ETCD_ROOT_PWD} member update 214e342c31d25d8 --peer-urls=https://srv-pg-db02.ru-central1.internal:2380
ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --cacert=${ETCD_SSL_DIR}/root.crt --user ${ETCD_ROOT_USER} --password ${ETCD_ROOT_PWD} member update 43cfaa679137736 --peer-urls=https://srv-pg-arb.ru-central1.internal:2380
ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --cacert=${ETCD_SSL_DIR}/root.crt --user ${ETCD_ROOT_USER} --password ${ETCD_ROOT_PWD} member update 6b40fb7c1a183c62 --peer-urls=https://srv-pg-db01.ru-central1.internal:2380
```

Run commands above (from any Etcd cluster member):
```
Member 6b40fb7c1a183c62 updated in cluster  9bb0ad7d9a773ca
Member 214e342c31d25d8 updated in cluster  9bb0ad7d9a773ca
Member 43cfaa679137736 updated in cluster  9bb0ad7d9a773ca
```

**NOTE**: according to documentation each Etcd cluster member needs to be restarted. Meanwhile you will see below error messages in log file of each member ``prober detected unhealthy status``.

## Restart each Etcd cluster member (one by one)

```
$ sudo systemctl stop etcd && sleep 5 && sudo systemctl start etcd && systemctl status etcd
```

**NOTE**: There can be below messages in log file until each member will not be restarted.
```
Jan 07 21:21:59 srv-pg-db02.ru-central1.internal bash[5843]: {"level":"warn","ts":"2023-01-07T21:21:59.392+0300","caller":"embed/config_logging.go:169",
"msg":"rejected connection","remote-addr":"10.129.0.29:55694","server-name":"srv-pg-db02.ru-central1.internal","error":"remote error: tls: bad certificate"}
Jan 07 21:21:59 srv-pg-db02.ru-central1.internal bash[5843]: {"level":"warn","ts":"2023-01-07T21:21:59.396+0300","caller":"embed/config_logging.go:169",
"msg":"rejected connection","remote-addr":"10.129.0.29:55690","server-name":"srv-pg-db02.ru-central1.internal","error":"remote error: tls: bad certificate"}
```

## Check result

```
$ ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key member list
```

```
214e342c31d25d8: name=srv-pg-db02 peerURLs=https://srv-pg-db02.ru-central1.internal:2380 clientURLs=https://srv-pg-db02.ru-central1.internal:2379 isLeader=false
43cfaa679137736: name=srv-pg-arb peerURLs=https://srv-pg-arb.ru-central1.internal:2380 clientURLs=https://srv-pg-arb.ru-central1.internal:2379 isLeader=true
6b40fb7c1a183c62: name=srv-pg-db01 peerURLs=https://srv-pg-db01.ru-central1.internal:2380 clientURLs=https://srv-pg-db01.ru-central1.internal:2379 isLeader=false
```

```
$ ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key cluster-health
```

```
member 214e342c31d25d8 is healthy: got healthy result from https://srv-pg-db02.ru-central1.internal:2379
member 43cfaa679137736 is healthy: got healthy result from https://srv-pg-arb.ru-central1.internal:2379
member 6b40fb7c1a183c62 is healthy: got healthy result from https://srv-pg-db01.ru-central1.internal:2379
cluster is healthy
```

# (OPTIONAL) Update ad-hoc commands environment file

cat <<EOF >> ~/etcd.env
export ETCDCONF="/etc/etcd/etcd.conf"
export ETCD_SSL_DIR="/etc/etcd/ssl"
export ETCD_HOST_FQDN="\$(hostname -f)"
alias etcdconf='view \${ETCDCONF}'
alias etcdlog='sudo journalctl -u etcd | view -'
alias etcdlogtail='sudo journalctl -u etcd -f -n 1000'
alias etcdlogerr="sudo journalctl -u etcd -f -n 1000 | egrep -i 'WARNING|ERROR|FATAL'"
alias etcdver='etcd --version'
alias etcdlist='ETCDCTL_API=3 etcdctl --endpoints=https://\${ETCD_HOST_FQDN}:2379 --cert=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.crt --key=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.key --cacert=\${ETCD_SSL_DIR}/root.crt endpoint status --cluster -w table'
alias etcdmembers='ETCDCTL_API=2 etcdctl --endpoints=https://\${ETCD_HOST_FQDN}:2379 --ca-file=\${ETCD_SSL_DIR}/root.crt --cert-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.crt --key-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.key member list'
alias etcdhealth='ETCDCTL_API=2 etcdctl --endpoints=https://\${ETCD_HOST_FQDN}:2379 --ca-file=\${ETCD_SSL_DIR}/root.crt --cert-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.crt --key-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.key cluster-health'
alias etcdls='ETCDCTL_API=2 etcdctl --endpoints=https://\${ETCD_HOST_FQDN}:2379 --ca-file=\${ETCD_SSL_DIR}/root.crt --cert-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.crt --key-file=\${ETCD_SSL_DIR}/\${ETCD_HOST_FQDN}.key ls / --recursive'
alias etcdgetv2key='ETCDCTL_API=2 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --ca-file=${ETCD_SSL_DIR}/root.crt --cert-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key-file=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key get '
alias etcdmoveleader='ETCDCTL_API=3 etcdctl --endpoints=https://${ETCD_HOST_FQDN}:2379 --cert=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.crt --key=${ETCD_SSL_DIR}/${ETCD_HOST_FQDN}.key --cacert=${ETCD_SSL_DIR}/root.crt move-leader'
EOF
