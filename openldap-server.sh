#!/bin/bash

# 定义变量
PWD='123123'
GIP=`ip a | awk '/noprefixroute/{print $2}'`

# 初始化设置
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
systemctl stop firewalld.service
systemctl disable firewalld.service
iptables -F

# 安装
yum -y install openldap-clients openldap-servers openldap migrationtools expect httpd nfs-utils rpcbind wget unix2dos
if [ $? -ne 0 ];then
    echo "安装失败，请检查yum源或网络后重试"
    exit 1
fi

# 无交互生成密文
>/tmp/slappwd.log
/bin/expect <<EOF
set timeout 5
spawn /usr/sbin/slappasswd
expect "password"
send "${PWD}\r"
expect "password"
send "${PWD}\r"
log_file /tmp/slappwd.log
expect eof
EOF

# 写配置文件
SPWD=`cat /tmp/slappwd.log | sed -n '/SSHA/p'`
cat > /etc/openldap/slapd.conf <<EOF
include         /etc/openldap/schema/corba.schema
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/duaconf.schema
include         /etc/openldap/schema/dyngroup.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/java.schema
include         /etc/openldap/schema/misc.schema
include         /etc/openldap/schema/nis.schema
include         /etc/openldap/schema/openldap.schema
include         /etc/openldap/schema/pmi.schema
include         /etc/openldap/schema/ppolicy.schema
include         /etc/openldap/schema/collective.schema
allow bind_v2
pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args
####  Encrypting Connections
TLSCACertificateFile /etc/pki/tls/certs/ca.crt
TLSCertificateFile /etc/pki/tls/certs/slapd.crt
TLSCertificateKeyFile /etc/pki/tls/certs/slapd.key
### Database Config###          
database config
rootdn "cn=admin,cn=config"
rootpw ${SPWD}
access to * by dn.exact=gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth manage by * break
### Enable Monitoring
database monitor
# allow only rootdn to read the monitor
access to * by dn.exact="cn=admin,cn=config" read by * none
EOF
dos2unix /etc/openldap/slapd.conf

# 相应配置
rm -fr /etc/openldap/slapd.d/*
slaptest -f /etc/openldap/slapd.conf -F /etc/openldap/slapd.d/
chown -R ldap. /etc/openldap/slapd.d/
chmod 000 /etc/openldap/slapd.conf
chmod -R u+rwX /etc/openldap/slapd.d
wget ftp://172.25.254.250:/notes/project/UP200/UP200_ldap-master/openldap/other/mkcert.sh
chmod +x mkcert.sh
./mkcert.sh --create-ca-keys
./mkcert.sh --create-ldap-keys
cp /etc/pki/CA/my-ca.crt /etc/pki/tls/certs/ca.crt
cp /etc/pki/CA/ldap_server.crt /etc/pki/tls/certs/slapd.crt
cp /etc/pki/CA/ldap_server.key /etc/pki/tls/certs/slapd.key
rm -fr /var/lib/ldap/*
chown ldap.ldap /var/lib/ldap/
chown ldap.ldap /var/lib/ldap/
cp -p /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap.  /var/lib/ldap/DB_CONFIG
cp /etc/pki/tls/certs/ca.crt /var/www/html/
mkdir /ldapuser
echo "/ldapuser ${GIP}(rw)" >>/etc/exports
exportfs -r

# 启动相应服务
systemctl start slapd.service
systemctl enable slapd.service
systemctl start httpd.service
systemctl enable httpd.service
systemctl start rpcbind
systemctl enable rpcbind
systemctl start nfs
systemctl enable nfs

# 创建用户数据库
mkdir /root/ldif
cat /root/ldif/bdb.ldif <<EOF
dn: olcDatabase=bdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcBdbConfig
olcDatabase: {1}bdb
olcSuffix: dc=example,dc=org
olcDbDirectory: /var/lib/ldap
olcRootDN: cn=Manager,dc=example,dc=org
olcRootPW: redhat
olcLimits: dn.exact="cn=Manager,dc=example,dc=org" time.soft=unlimited time.hard=unlimited size.soft=unlimited size.hard=unlimited
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn,displayName pres,eq,approx,sub
olcDbIndex: uidNumber,gidNumber eq
olcDbIndex: memberUid eq
olcDbIndex: objectClass eq
olcDbIndex: entryUUID pres,eq
olcDbIndex: entryCSN pres,eq
olcAccess: to attrs=userPassword by self write by anonymous auth by dn.children="ou=admins,dc=example,dc=org" write  by * none
olcAccess: to * by self write by dn.children="ou=admins,dc=example,dc=org" write by * read
EOF
ldapadd -x -D "cn=admin,cn=config" -w 123123 -f /root/ldif/bdb.ldif -h localhost
sed -i 's/padl.com/example.org/g' /usr/share/migrationtools/migrate_common.ph
sed -i 's/dc=padl,dc=com/dc=example,dc=org/g' /usr/share/migrationtools/migrate_common.ph




