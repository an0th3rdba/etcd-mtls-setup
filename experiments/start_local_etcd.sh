#!/bin/bash

#
# arg1 - ssl mode: nossl, csssl, fullssl;
# arg2 - data dir;
# arg3 - rm: remove data dir before start;
# arg4 - ssl dir.
#
# example 1: ~/experiments/start_local_etcd.sh nossl ~/etcd_test_data_dir rm
# example 2: ~/experiments/start_local_etcd.sh nossl ~/etcd_test_data_dir rm authv2
# example 3: ~/experiments/start_local_etcd.sh nossl ~/etcd_test_data_dir rm authv3
# example 4: ~/experiments/start_local_etcd.sh ssl   ~/etcd_test_data_dir rm ~/experiments/ssl
# example 5: ~/experiments/start_local_etcd.sh ssl   ~/etcd_test_data_dir rm ~/experiments/ssl authv2
# example 6: ~/experiments/start_local_etcd.sh ssl   ~/etcd_test_data_dir rm ~/experiments/ssl authv3
#
# stop etcd: pkill etcd && rm -f ~/experiments/etcd*.log
#

set -e
#set -x


re_create_data_dir() {

    rm -rf ${1}
    mkdir -p ${1}
    chmod 700 ${1}
}


etcd_no_ssl() {

    nohup etcd --name $(hostname -s)1 \
               --data-dir ${1} \
               --enable-v2=true \
               --advertise-client-urls=http://127.0.0.1:2379 \
               --listen-client-urls=http://127.0.0.1:2379 > ~/experiments/etcd_nossl.log 2>&1 &
}


etcd_client_server_mtls() {

    nohup etcd --name $(hostname -s) \
               --data-dir ${1} \
               --enable-v2=true \
               --client-cert-auth \
               --trusted-ca-file=${2}/root.crt \
               --cert-file=${2}/$(hostname -f).crt \
               --key-file=${2}/$(hostname -f).key \
               --advertise-client-urls=https://127.0.0.1:2379 \
               --listen-client-urls=https://127.0.0.1:2379 > ~/experiments/etcd_ssl.log 2>&1 &
}

etcd_auth_v2_enable() {

    sleep 5
    if [[ ${1} == "ssl" ]]; then
        export ETCD_SSL_CMD="--endpoints=https://127.0.0.1:2379 --ca-file=${2}/root.crt --cert-file=${2}/$(hostname -f).crt --key-file=${2}/$(hostname -f).key"
        export CURL_SSL_CMD="--cacert ${2}/root.crt --cert ${2}/$(hostname -f).crt --key ${2}/$(hostname -f).key https://127.0.0.1:2379/v2/auth/enable"
    else
        export ETCD_SSL_CMD="--endpoints=http://127.0.0.1:2379"
        export CURL_SSL_CMD="http://127.0.0.1:2379/v2/auth/enable"
    fi
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user add root:root123
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user add user1:user123
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} role add user1_role
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} role grant user1_role --readwrite --path=/service/*
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} user grant --roles=user1_role user1
    ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} auth enable
    curl ${CURL_SSL_CMD}
    echo "root123" | ETCDCTL_API=2 etcdctl ${ETCD_SSL_CMD} -u root role remove guest
}

etcd_auth_v3_enable() {

    sleep 5
    if [[ ${1} == "ssl" ]]; then
        export ETCD_SSL_CMD="--endpoints=https://127.0.0.1:2379 --cacert=${2}/root.crt --cert=${2}/$(hostname -f).crt --key=${2}/$(hostname -f).key"
    else
        export ETCD_SSL_CMD="--endpoints=http://127.0.0.1:2379"
    fi
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user add root:root123
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user grant root root
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user add user1:user123
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} role add user1_role
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} role grant-permission user1_role readwrite /service/*
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} user grant user1 user1_role
    ETCDCTL_API=3 etcdctl ${ETCD_SSL_CMD} auth enable
}


main() {

    echo "Starting ..."
    if [[ ${3} == "rm" ]]; then re_create_data_dir ${2}; fi;
    if [[ ${1} == "nossl" ]]; then etcd_no_ssl ${2}; fi;
    if [[ ${1} == "ssl" ]]; then etcd_client_server_mtls ${2} ${4}; fi;
    if [[ ${5} == "authv2" ]] || [[ ${4} == "authv2" ]]; then etcd_auth_v2_enable ${1} ${4}; fi
    if [[ ${5} == "authv3" ]] || [[ ${4} == "authv3" ]]; then etcd_auth_v3_enable ${1} ${4}; fi
}


main "$@"

