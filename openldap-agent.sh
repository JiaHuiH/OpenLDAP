#!/bin/bash

# 初始化设置
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
setenforce 0
systemctl stop firewalld.service
systemctl disable firewalld.service
iptables -F

# 安装
yum -y install nfs-utils openldap openldap-clients
if [ $? -ne 0 ];then
    echo "安装失败，请检查yum源或网络后重试"
    exit 1
fi

# 写配置文件
## 10.0.10.2为Server端
echo "10.0.10.2 server.example.com" >>/etc/hosts

# 配置ldap认证
authconfig --enableldap --enableldapauth --ldapserver=server.example.com --ldapbasedn="dc=example,dc=org" --enableldaptls --ldaploadcacert=http://server.example.com/ca.crt   --update


