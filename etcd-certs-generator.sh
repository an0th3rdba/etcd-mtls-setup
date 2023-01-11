#!/bin/bash

set -e

####################
debug_print_array_elements() {

    printf "===== DEBUG =====\n"
    ARRAY=("$@")
    for i in ${!ARRAY[@]};
    do
        printf "= Element ${i} = ${ARRAY[${i}]}\n"
    done
    printf "=================\n"
}

####################
ask_for_vars() {

    ##### Get count of servers in Etcd cluster #####
    while true; do
        read -p "Enter the number of servers in your Etcd cluster [3]: " ETCD_MEMBERS_COUNT
        ETCD_MEMBERS_COUNT=${ETCD_MEMBERS_COUNT:-3}
        RE='^[1-9]+$'
        if ! [[ ${ETCD_MEMBERS_COUNT} =~ ${RE} ]]; then
            printf "WARN: Unrecognized value for ETCD_MEMBERS_COUNT variable (\"${ETCD_MEMBERS_COUNT}\").\n"
            continue
        else
            break
        fi
    done

    ##### Get fully qualified domain name of each cluster member #####
    ETCD_MEMBERS_FQDN_ARRAY=()
    for (( MEMBER_NUM=1; MEMBER_NUM<=${ETCD_MEMBERS_COUNT}; MEMBER_NUM++ ))
    do
        while true; do
            read -p "Enter FQDN of the ${MEMBER_NUM} member [etcd-node${MEMBER_NUM}.example.com]: " ETCD_MEMBER_FQDN
            ETCD_MEMBER_FQDN=${ETCD_MEMBER_FQDN:-"etcd-node${MEMBER_NUM}.example.com"}
            if [[ "${ETCD_MEMBERS_FQDN_ARRAY[@]}" =~ ${ETCD_MEMBER_FQDN} ]]; then
                printf "WARN: Duplicate identified! Member with FQDN \"${ETCD_MEMBER_FQDN}\" was entered earlier. Please provide correct FQDN for member ${MEMBER_NUM}.\n"
                continue
            else
                ETCD_MEMBERS_FQDN_ARRAY=("${ETCD_MEMBERS_FQDN_ARRAY[@]}" ${ETCD_MEMBER_FQDN})
                break
            fi
        done
    done
    #debug_print_array_elements ${ETCD_MEMBERS_FQDN_ARRAY[@]}

    ##### Get IP address of each cluster member #####
    ETCD_MEMBERS_IP_ARRAY=()
    for (( MEMBER_NUM=1; MEMBER_NUM<=${ETCD_MEMBERS_COUNT}; MEMBER_NUM++ ))
    do
        while true; do
            read -p "Enter IP address of the ${MEMBER_NUM} member [10.0.0.${MEMBER_NUM}]: " ETCD_MEMBER_IP
            ETCD_MEMBER_IP=${ETCD_MEMBER_IP:-"10.0.0.${MEMBER_NUM}"}
            RE='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
            if ! [[ ${ETCD_MEMBER_IP} =~ ${RE} ]]; then
                printf "WARN: Value of the variable ETCD_MEMBER_IP for member ${MEMBER_NUM} doesn't look like IP address (\"${ETCD_MEMBER_IP}\").\n"
                continue
            elif [[ "${ETCD_MEMBERS_IP_ARRAY[@]}" =~ ${ETCD_MEMBER_IP} ]]; then
                printf "WARN: Duplicate identified! Member with IP \"${ETCD_MEMBER_IP}\" was entered earlier. Please provide correct IP address for member ${MEMBER_NUM}.\n"
                continue
            else
                ETCD_MEMBERS_IP_ARRAY=("${ETCD_MEMBERS_IP_ARRAY[@]}" ${ETCD_MEMBER_IP})
                break
            fi
        done
    done
    #debug_print_array_elements ${ETCD_MEMBERS_IP_ARRAY[@]}

    ##### Get number of client certificates to issue #####
    while true; do
        read -p "Enter the number of client certificates to issue [1]: " ETCD_CLIENT_CERTS_COUNT
        ETCD_CLIENT_CERTS_COUNT=${ETCD_CLIENT_CERTS_COUNT:-1}
        RE='^[0-9]+$'
        if ! [[ ${ETCD_CLIENT_CERTS_COUNT} =~ ${RE} ]]; then
            printf "WARN: Unrecognized value for ETCD_CLIENT_CERTS_COUNT variable (\"${ETCD_CLIENT_CERTS_COUNT}\").\n"
            continue
        else
            break
        fi
    done

    ##### Get client certificates CN values #####
    ETCD_CLIENT_CERTS_CN_ARRAY=()
    for (( CLIENT_NUM=1; CLIENT_NUM<=${ETCD_CLIENT_CERTS_COUNT}; CLIENT_NUM++ ))
    do
        while true; do
            read -p "Enter CN for the ${CLIENT_NUM} client certificate [etcd-client]: " ETCD_CLIENT_CN_NAME
            ETCD_CLIENT_CN_NAME=${ETCD_CLIENT_CN_NAME:-"etcd-client"}
            if [[ "${ETCD_CLIENT_CERTS_CN_ARRAY[@]}" =~ ${ETCD_CLIENT_CN_NAME} ]]; then
                printf "WARN: Duplicate identified! Client with CN \"${ETCD_CLIENT_CN_NAME}\" was entered earlier. Please provide correct CN address for client ${CLIENT_NUM}.\n"
                continue
            else
                ETCD_CLIENT_CERTS_CN_ARRAY=("${ETCD_CLIENT_CERTS_CN_ARRAY[@]}" ${ETCD_CLIENT_CN_NAME})
                break
            fi
        done
    done
    #debug_print_array_elements ${ETCD_CLIENT_CERTS_CN_ARRAY[@]}

    ##### Directory to store certificates #####
    read -p "Enter the location to store certificates [/tmp/ssl]: " ETCD_SSL_DIR
    ETCD_SSL_DIR=${ETCD_SSL_DIR:-"/tmp/ssl"}

    ##### Name of the CA #####
    read -p "Enter the certificate authority (CA) name [TEST-CA]: " ETCD_CA_NAME
    ETCD_CA_NAME=${ETCD_CA_NAME:-"TEST-CA"}
}

####################
prepare_openssl_config() {

mkdir -p ${ETCD_SSL_DIR}
mkdir -p ${ETCD_SSL_DIR}
mkdir -p ${ETCD_SSL_DIR}/private
mkdir -p ${ETCD_SSL_DIR}/certs
mkdir -p ${ETCD_SSL_DIR}/newcerts
mkdir -p ${ETCD_SSL_DIR}/crl
touch ${ETCD_SSL_DIR}/index.txt
echo '01' > ${ETCD_SSL_DIR}/serial

cat <<EOF >> ${ETCD_SSL_DIR}/openssl.cnf
SAN = "IP:127.0.0.1"
dir = ${ETCD_SSL_DIR}

[ ca ]
default_ca = self_signed_ca

[ self_signed_ca ]
certs            = \$dir
certificate      = \$dir/root.crt
crl              = \$dir/crl.pem
crl_dir          = \$dir/crl
crlnumber        = \$dir/crlnumber
database         = \$dir/index.txt
email_in_dn      = no
new_certs_dir    = \$dir/newcerts
private_key      = \$dir/root.key
serial           = \$dir/serial
RANDFILE         = \$dir/private/.rand
name_opt         = ca_default
cert_opt         = ca_default
default_days     = 1095
default_crl_days = 30
default_md       = sha512
preserve         = no
policy           = custom_policy

[ custom_policy ]
organizationName = optional
commonName       = supplied

[ req ]
default_bits       = 4096
default_keyfile    = privkey.pem
distinguished_name = req_distinguished_name
attributes         = req_attributes
x509_extensions    = v3_ca
string_mask        = utf8only
req_extensions     = etcd_client

[ req_distinguished_name ]
countryName                = Country Name (2 letter code)
countryName_default        = RU
countryName_min            = 2
countryName_max            = 2

[ req_attributes ]

[ v3_ca ]
basicConstraints       = CA:true
keyUsage               = keyCertSign,cRLSign
subjectKeyIdentifier   = hash

[ etcd_server ]
basicConstraints       = CA:FALSE
extendedKeyUsage       = clientAuth, serverAuth
keyUsage               = digitalSignature, keyEncipherment
subjectAltName         = \${ENV::SAN}

[ etcd_client ]
basicConstraints       = CA:FALSE
extendedKeyUsage       = clientAuth
keyUsage               = digitalSignature, keyEncipherment
EOF
}

####################
create_ca_cert() {

    openssl req -new -x509 -days 3650 -nodes -keyout ${ETCD_SSL_DIR}/root.key -out ${ETCD_SSL_DIR}/root.crt -subj "/CN=${ETCD_CA_NAME}"  > /dev/null 2>&1
    openssl x509 -in ${ETCD_SSL_DIR}/root.crt -text -noout > ${ETCD_SSL_DIR}/root.info
    printf "CA certificate: ${ETCD_SSL_DIR}/root.crt\n"
    printf "CA key: ${ETCD_SSL_DIR}/root.key\n"
    printf "CA info: ${ETCD_SSL_DIR}/root.info\n"
}

####################
create_server_cert() {

    for (( MEMBER_NUM=0; MEMBER_NUM<${ETCD_MEMBERS_COUNT}; MEMBER_NUM++ ))
    do
        export SAN="DNS:${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}, IP:127.0.0.1, IP:${ETCD_MEMBERS_IP_ARRAY[${MEMBER_NUM}]}"
        openssl req -new -nodes -keyout ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.key -out ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.csr -subj "/CN=${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}" -config ${ETCD_SSL_DIR}/openssl.cnf > /dev/null 2>&1
        openssl ca -batch -config ${ETCD_SSL_DIR}/openssl.cnf -extensions etcd_server -keyfile ${ETCD_SSL_DIR}/root.key -cert ${ETCD_SSL_DIR}/root.crt -out ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.crt -infiles ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.csr > /dev/null 2>&1
        openssl x509 -in ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.crt -text -noout > ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.info
        printf "Member $((${MEMBER_NUM}+1)) server certificate: ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.crt\n"
        printf "Member $((${MEMBER_NUM}+1)) server key: ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.key\n"
        printf "Member $((${MEMBER_NUM}+1)) server info: ${ETCD_SSL_DIR}/${ETCD_MEMBERS_FQDN_ARRAY[${MEMBER_NUM}]}.info\n"
    done
}

####################
create_client_cert() {

    for (( CLIENT_NUM=0; CLIENT_NUM<${ETCD_CLIENT_CERTS_COUNT}; CLIENT_NUM++ ))
    do
        openssl req -new -nodes -keyout ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.key -out ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.csr -subj "/CN=${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}" -config ${ETCD_SSL_DIR}/openssl.cnf > /dev/null 2>&1
        openssl ca -batch -config ${ETCD_SSL_DIR}/openssl.cnf -extensions etcd_client -keyfile ${ETCD_SSL_DIR}/root.key -cert ${ETCD_SSL_DIR}/root.crt -out ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.crt -infiles ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.csr > /dev/null 2>&1
        openssl x509 -in ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.crt -text -noout > ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.info
        printf "Client $((${CLIENT_NUM}+1)) certificate: ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.crt\n"
        printf "Client $((${CLIENT_NUM}+1)) key: ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.key\n"
        printf "Client $((${CLIENT_NUM}+1)) info: ${ETCD_SSL_DIR}/${ETCD_CLIENT_CERTS_CN_ARRAY[${CLIENT_NUM}]}.info\n"
    done
}

####################
set_permissions_and_cleanup() {

    rm -rf ${ETCD_SSL_DIR}/private
    rm -rf ${ETCD_SSL_DIR}/certs
    rm -rf ${ETCD_SSL_DIR}/crl
    rm -rf ${ETCD_SSL_DIR}/newcerts
    rm -rf ${ETCD_SSL_DIR}/serial*
    rm -rf ${ETCD_SSL_DIR}/index*
    rm -rf ${ETCD_SSL_DIR}/*.csr
    rm -rf ${ETCD_SSL_DIR}/*.srl
    rm -rf ${ETCD_SSL_DIR}/openssl.cnf
    chmod 700 ${ETCD_SSL_DIR}
    chmod 600 ${ETCD_SSL_DIR}/*.key
}

####################
main() {

    printf "=============== Input ===============\n"
    ask_for_vars
    printf "=============== Output ==============\n"
    prepare_openssl_config
    create_ca_cert
    create_server_cert
    create_client_cert
    set_permissions_and_cleanup
}

main "$@"
