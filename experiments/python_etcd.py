import etcd

##
## NO-SSL, NO-AUTH
##

KEY = '/service/ssl'
VALUE = 'no'

client = etcd.Client(host='127.0.0.1', port=2379)
client.write(KEY, VALUE)
print("Key: " + KEY, "\nValue: " + client.read(KEY).value)

"""
##
## NO-SSL, AUTH
##

KEY = '/service/ssl'
VALUE = 'no'

client = etcd.Client(host='127.0.0.1', port=2379, username='user1', password='user1234')
client.write(KEY, VALUE)
print("Key: " + KEY, "\nValue: " + client.read(KEY).value)
"""

"""
##
## mTLS
##

KEY = '/service/ssl'
VALUE = 'yes'
CA_CERT='./ssl/root.crt'
CLIENT_CERT='./ssl/user1.crt'
CLIENT_KEY='./ssl/user1.key'

client = etcd.Client(host='127.0.0.1',
                     port=2379,
                     protocol='https',
                     ca_cert=CA_CERT,
                     cert=(CLIENT_CERT,CLIENT_KEY))
client.write(KEY, VALUE)
print("Key: " + KEY, "\nValue: " + client.read(KEY).value)
"""
