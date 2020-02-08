===============================================================================
-- OpenShift 3.11 Install Guide (3.11.59)
===============================================================================

RHBA-2018:3537 - Bug Fix Advisory
https://access.redhat.com/errata/RHBA-2018:3537

===============================================================================
--0. Architecture 구성
-------------------------------------------------------------------------------
dns.example.ocp: dns, repository, docker registry, image volume
master01,master02,master03: console, etcd
infra01,infra02: router
node01,node02,node03: containers

server     cpu        memory     os disk    docker storage    docker volume
-------------------------------------------------------------------------------
master01    16         32G         200        100
master02    16         32G         200        100
master03    16         32G         200        100
infra01      8         32G         200        200
infra02      8         32G         200        200
node01       8         32G         200        200
node02       8         32G         200        200
node03       8         32G         200        200
dns          8         16G         200        100               500

● Master
-------------------------------------------------------------------------------
vCPU: Minimum 4 core
RAM: Minimum 16 GB
/var: Minimum 40 GB
/usr/local/bin: Minimum 1 GB
/tmp: Minimum 1 GB
Masters with a co-located etcd: minimum 4 cores

● Node
-------------------------------------------------------------------------------
vCPU: Minimum 1 core
RAM: Minimum 8 GB
/var: Minimum 15 GB
/usr/local/bin: Minimum 1 GB
/tmp: Minimum 1 GB
running containers for Docker’s storage: additional minimum 15 GB Disk

● External etcd Nodes
-------------------------------------------------------------------------------
etcd data: Minimum 20 GB

● Storage management
-------------------------------------------------------------------------------
/var/lib/openshift   Less than 10GB
/var/lib/etcd        Less than 20 GB
/var/lib/docker      50 GB Disk, 16 GB memory. Additional 20-25 GB Disk, 8 GB of memory.
/var/lib/containers  50 GB Disk, 16 GB memory. Additional 20-25 GB Disk, 8 GB of memory.
/var/lib/origin/openshift.local.volumes
/var/log             10-30 GB

● Red Hat Gluster Storage hardware requirements
-------------------------------------------------------------------------------
minimum 3 storage nodes per group
minimum 8 GB RAM per storage node

● SELinux requirements
-------------------------------------------------------------------------------
vi /etc/selinux/config
SELINUX=enforcing
SELINUXTYPE=targeted

# Configuring Core Usage
export GOMAXPROCS=1

===============================================================================
--1. repository server, Docker Registry 설치 (yum repos 변경 전 할 것들)
-------------------------------------------------------------------------------
● Building a Repository Server (dns)
-------------------------------------------------------------------------------
tar zcvf - /var/www/html/repos |split -b 4200M - /volumes/repo_data/repos.tar.gz
cat repos.tar.gz* | tar zxvf -

# repodata 생성
cd /var/www/html/repos/rhel-7-server-rpms
createrepo -v .
나머지 package도 같이 진행

cp local.repo /etc/yum.repos.d/
yum -y install yum-utils createrepo

# apache install
yum -y install httpd
cp -a /root/.example/repos /var/www/html/
chmod -R +r /var/www/html/repos
restorecon -vR /var/www/html

iptables -I INPUT -m state --state NEW -p tcp -m tcp --dport 80 -j ACCEPT;
iptables-save > /etc/sysconfig/iptables;
firewall-cmd --permanent --add-service=http;
firewall-cmd --reload;

#dns 
iptables -I INPUT -m state --state NEW -p tcp -m tcp --dport 53 -j ACCEPT;
iptables-save > /etc/sysconfig/iptables;
firewall-cmd --permanent --zone=public --add-port=53/tcp
firewall-cmd --permanent --zone=public --add-port=53/udp
firewall-cmd --reload

systemctl enable httpd
systemctl start httpd

● Docker Registry Volume Utility install (dns)
-------------------------------------------------------------------------------
yum install nfs-utils libnfsidmap (모든 서버에 설치)

● Repository setting
-------------------------------------------------------------------------------
02_repo_setting_only.sh (Repository Server 설치 제외)
mv local.repo local.repo.bak
===============================================================================
--2. Host Registration (off line일 경우 생략)
-------------------------------------------------------------------------------
● Syncing Repositories
-------------------------------------------------------------------------------
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

● Register with RHSM
-------------------------------------------------------------------------------
subscription-manager register --username=<user_name> --password=<password> --force
subscription-manager refresh
subscription-manager list --available --matches '*OpenShift*'
subscription-manager attach --pool=8a85f99a6ae5e464016b08dc1811797c #구독선택
8a85f99a6ae5e464016b08dc4c6f799f (x)


subscription-manager repos --disable="*"
subscription-manager repos \
    --enable="rhel-7-server-rpms" \
    --enable="rhel-7-server-extras-rpms" \
    --enable="rhel-7-server-ose-3.11-rpms" \
    --enable="rhel-7-server-ansible-2.6-rpms"

yum clean all; yum repolist

● Repository rpm download
-------------------------------------------------------------------------------
mkdir -p /var/www/html/repos

nohup ./repos.sh & (session close 시)
-------------------------------------------------------------------------------
#!/bin/sh
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

for repo in \
rhel-7-server-rpms \
rhel-7-server-extras-rpms \
rhel-7-server-ansible-2.6-rpms \
rhel-7-server-ose-3.11-rpms
do
  reposync --gpgcheck -lm --repoid=${repo} --download_path=/var/www/html/repos
  createrepo -v /var/www/html/repos/${repo} -o /var/www/html/repos/${repo}
done

===============================================================================
--3. DNS, Network, hostname, sshkey_copy, chrony setting
-------------------------------------------------------------------------------
01_network_change.sh
02_hostname_change.sh
03_dns_setting.sh
04_sshkey_copy.sh
05_chrony_setting.sh

● /etc/sysconfig/network-scripts/ifcfg-eth0 (client)
-------------------------------------------------------------------------------
# dns
TYPE=Ethernet
BOOTPROTO=none
DEFROUTE=yes
DEVICE=eth0
ONBOOT=yes
IPADDR=192.168.50.118
NETMASK=255.255.255.0
GATEWAY=192.168.50.254
DNS1=192.168.50.118
PROXY_METHOD=none
BROWSER_ONLY=no
PREFIX=24
IPV4_FAILURE_FATAL=no
IPV6INIT=no
NAME="System eth0"
DOMAIN=example.ocp

# 기타
ZONE=public

● /etc/sysconfig/network-scripts/ifcfg-eth0 (server)
-------------------------------------------------------------------------------
TYPE=Ethernet
BOOTPROTO=none
DEVICE=eth0
ONBOOT=yes
IPADDR=192.168.50.57
NETMASK=255.255.255.0
GATEWAY=192.168.50.254
DNS1=192.168.100.1
DNS2=192.168.100.2
ZONE=public

nmtui edit connection-name
nmcli con show
nmcli device status

● dns test
-------------------------------------------------------------------------------
chkconfig named on
systemctl restart named
nslookup infra.example.ocp
dig +short example.ocp
dig @dns.example.ocp infra.example.ocp a

cat /etc/resolv.conf
search example.ocp
nameserver 192.168.50.78

===============================================================================
--4. Base Packages Install
-------------------------------------------------------------------------------
06_basepackages_install.sh
=> yum -y update 시 online일 경우 확인
systemctl reboot

yum -y install atomic-openshift-utils-3.11.51

===============================================================================
--5. Docker install, setting
-------------------------------------------------------------------------------
● docker storage disk 할당
-------------------------------------------------------------------------------
fdisk -l
/dev/vdb        (100G 할당)
lsblk
ansible -f 10 nodes -m shell -a "systemctl status docker | grep Active"
ansible nodes -m yum -a 'list=atomic-openshift-node'

● docker install
-------------------------------------------------------------------------------
07_docker_setting.sh
yum -y install docker-1.13.1
rpm -V docker-1.13.1
docker version

# docker registry server도 설치

vi /etc/sysconfig/docker
-------------------------------------------------------------------------------
OPTIONS=' --selinux-enabled --log-opt  max-size=100M --log-opt max-file=10 --insecure-registry 172.30.0.0/16 -l warn --log-driver=json-file --signature-verification=false'

#OPTIONS=' --selinux-enabled --insecure-registry=172.30.0.0/16 -l warn --log-driver=json-file --log-opt max-size=100M --log-opt max-file=10 --signature-verification=false --insecure-registry docker-registry-default.apps.devops.cloud'

ADD_REGISTRY='--add-registry registry.test.cloud:5000'
INSECURE_REGISTRY='--insecure-registry registry.test.cloud:5000'
# BLOCK_REGISTRY='--block-registry docker.io --block-registry registry.redhat.io'

## local setting
OPTIONS='--selinux-enabled --insecure-registry=172.40.0.0/16 -l warn --log-driver json-file --log-opt max-size=100M --log-opt max-file=10'
ADD_REGISTRY='--add-registry registry.access.redhat.com'
# BLOCK_REGISTRY='--block-registry docker.io --block-registry registry.access.redhat.com'
INSECURE_REGISTRY='--insecure-registry registry.access.redhat.com'

cat /etc/sysconfig/docker-storage
-------------------------------------------------------------------------------
DOCKER_STORAGE_OPTIONS="--storage-driver devicemapper --storage-opt dm.fs=xfs --storage-opt dm.thinpooldev=/dev/mapper/docker--vg-docker--pool --storage-opt dm.use_deferred_removal=true --storage-opt dm.use_deferred_deletion=true "
vgs
lvs

● case) Re install docker
-------------------------------------------------------------------------------
vgremove docker-vg
pvremove /dev/vdb1
fdisk /dev/vdb
d / w
yum remove docker
rm -rf /var/lib/docker/*
./07_docker-setting.sh

# Install and configure Docker on the remaining nodes
-------------------------------------------------------------------------------
ansible -f 10 nodes -m yum -a"name=docker"
ansible -f 10 nodes -m copy -a 'dest=/etc/sysconfig/docker-storage-setup content="DEVS=/dev/xvdb\nVG=docker-vg\nWIPE_SIGNATURES=true"'
ansible -f 10 nodes -m shell -a"docker-storage-setup"
ansible -f 10 nodes -m service -a"name=docker state=started enabled=yes"
ansible -f 10 nodes -m shell -a "systemctl status docker | grep Active"
ansible nodes -m yum -a 'list=atomic-openshift-node'

===============================================================================
--6. Docker Registry
-------------------------------------------------------------------------------
● Registry disk setting  (dns)
-------------------------------------------------------------------------------
fdisk -l

fdisk /dev/vdc
  Welcome to fdisk (util-linux 2.23.2).
  Changes will remain in memory only, until you decide to write them.
  Be careful before using the write command.
  Device does not contain a recognized partition table
  Building a new DOS disklabel with disk identifier 0xf3f4d873.
 
  Command (m for help): n
  Partition type:
     p   primary (0 primary, 0 extended, 4 free)
     e   extended
  Select (default p): p
  Partition number (1-4, default 1):
  First sector (2048-209715199, default 2048):
  Using default value 2048
  Last sector, +sectors or +size{K,M,G} (2048-209715199, default 209715199):
  Using default value 209715199
  Partition 1 of type Linux and of size 100 GiB is set
 
  Command (m for help): p
  Disk /dev/vdc: 107.4 GB, 107374182400 bytes, 209715200 sectors
  Units = sectors of 1 * 512 = 512 bytes
  Sector size (logical/physical): 512 bytes / 512 bytes
  I/O size (minimum/optimal): 512 bytes / 512 bytes
  Disk label type: dos
  Disk identifier: 0xf3f4d873
     Device Boot      Start         End      Blocks   Id  System
  /dev/vdc1            2048   209715199   104856576   83  Linux
 
  Command (m for help): t
  Selected partition 1
  Hex code (type L to list all codes): 8e
  Changed type of partition 'Linux' to 'Linux LVM'
 
  Command (m for help): w
  The partition table has been altered!

yum install lvm2
fdisk -l
pvcreate /dev/vdc1
vgcreate registry-vg /dev/vdc1
lvcreate -n registry-lv -l 100%FREE registry-vg

#mkfs.ext4 /dev/mapper/registry--vg-registry--lv
mkfs.xfs /dev/mapper/registry--vg-registry--lv

mkfs.xfs -f -ssize=4k /dev/mapper/registry--vg-registry--lv

fsck -y /dev/mapper/registry--vg-registry--lv

mkdir /volumes
mount /dev/mapper/registry--vg-registry--lv /volumes

vi /etc/fstab
#/dev/mapper/registry--vg-registry--lv         /volumes          ext4    defaults        0 0
/dev/mapper/registry--vg-registry--lv         /volumes          xfs    defaults        0 0

● Docker Registry Volume Mount
-------------------------------------------------------------------------------
yum install nfs-utils libnfsidmap

systemctl enable rpcbind
systemctl enable nfs-server

systemctl start rpcbind
systemctl start nfs-server
systemctl start rpc-statd
systemctl start nfs-idmapd

systemctl enable nfs.service
systemctl start nfs.service
chkconfig nfs on

# configure firewall on NFS server
firewall-cmd --permanent --zone public --add-service mountd
firewall-cmd --permanent --zone public --add-service rpc-bind
firewall-cmd --permanent --zone public --add-service nfs
firewall-cmd --reload

mkdir -p /volumes/registry
chmod 750 /volumes/registry
chown nfsnobody:nfsnobody /volumes/registry
vi /etc/exports
/volumes/registry *(rw,async,all_squash)
exportfs -a

setsebool -P virt_use_nfs on  (server, client 둘다 등록)

# nfs 공유 access 허용 방화벽 규칙 구성  (server, client 둘다 등록)
-------------------------------------------------------------
iptables -I INPUT 1 -p tcp --dport 53248 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 50825 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 20048 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 2049 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 111 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
exportfs -r
exportfs -v

chcon -R unconfined_u:object_r:svirt_sandbox_file_t:s0 /volumes
client)
mount -t nfs dns.devops.cloud:/volumes /mnt
mount -t nfs ocpcloudlb.ocp.cloud:/volumes /mnt

● Registry Certificate setting
-------------------------------------------------------------------------------
registry.example.ocp:5000
ocpadmin / ocpadmin.!

mkdir -p /volumes/cert

$ openssl genrsa -des3 -out /volumes/cert/registry.example.ocp.key 2048
  Generating RSA private key, 2048 bit long modulus
  .........................................+++
  ...+++
  e is 65537 (0x10001)
  Enter pass phrase for registry.example.ocp.key:
  Verifying - Enter pass phrase for registry.example.ocp.key:

$ openssl req -new -key /volumes/cert/registry.example.ocp.key -out /volumes/cert/registry.example.ocp.csr
  Enter pass phrase for /volumes/cert/registry.example.ocp.key:
  You are about to be asked to enter information that will be incorporated
  into your certificate request.
  What you are about to enter is what is called a Distinguished Name or a DN.
  There are quite a few fields but you can leave some blank
  For some fields there will be a default value,
  If you enter '.', the field will be left blank.
  -----
  Country Name (2 letter code) [XX]:KR
  State or Province Name (full name) []:Seoul
  Locality Name (eg, city) [Default City]:
  Organization Name (eg, company) [Default Company Ltd]:
  Organizational Unit Name (eg, section) []:
  Common Name (eg, your name or your server's hostname) []:registry.example.ocp
  Email Address []:
 
  Please enter the following 'extra' attributes
  to be sent with your certificate request
  A challenge password []:
  An optional company name []:

$ cp /volumes/cert/registry.example.ocp.key /volumes/cert/registry.example.ocp.key.origin

$ openssl rsa -in /volumes/cert/registry.example.ocp.key.origin -out /volumes/cert/registry.example.ocp.key
  Enter pass phrase for /volumes/cert/registry.example.ocp.key.origin:
  writing RSA key

$ openssl x509 -req -days 3650 -in /volumes/cert/registry.example.ocp.csr -signkey /volumes/cert/registry.example.ocp.key -out /volumes/cert/registry.example.ocp.crt
  Signature ok
  subject=/C=KR/ST=Seoul/L=Default City/O=Default Company Ltd/CN=registry.example.ocp
  Getting Private key

● docker-distribution install
-------------------------------------------------------------------------------
cat /etc/docker-distribution/registry/config.yml
version: 0.1
log:
  fields:
    service: registry
storage:
    cache:
        layerinfo: inmemory
    filesystem:
        rootdirectory: /volumes
http:
  addr: registry.example.ocp:5000
  headers:
    X-Content-Type-Options: [nosniff]
  tls:
    certificate: /volumes/cert/registry.example.ocp.crt
    key: /volumes/cert/registry.example.ocp.key

health:
  storagedriver:
    enabled: true
    interval: 60s
    threshold: 3

08_docker_distribution_only.sh

systemctl enable firewalld
systemctl start  firewalld
firewall-cmd --zone=public --add-port=5000/tcp
firewall-cmd --zone=public --add-port=5000/tcp --permanent
firewall-cmd --reload;
firewall-cmd --zone=public --list-ports
iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 5000 -j ACCEPT
iptables-save > /etc/sysconfig/iptables;

update-ca-trust enable
systemctl daemon-reload
systemctl restart docker

===============================================================================
--7. OpenShift Image Load
-------------------------------------------------------------------------------
tar zcvf - ose311.51-images.tar |split -b 4200M - ose311.51-images.tar.gz
tar zcvf - /volumes/ocp311.images/ose311.51-images.tar |split -b 4200M - /volumes/ocp311.images/ose311.51-images.tar.gz
tar zcvf - /volumes/ocp311.images/ose311.51-optional-imags.tar |split -b 4200M - /volumes/ocp311.images/ose311.51-optional-imags.tar.gz

cat /volumes/ocp311.images/ose311.51-images.tar.gz* | tar zxvf -

tar zcvf - /volumes/ocp311.images/ose-builder-images.tar |split -b 4200M - /volumes/ocp311.images/ose-builder-images.tar.gz
cat /volumes/ocp311.images/ose-builder-images.tar.gz* | tar zxvf -

docker load -i ose311.51-images.tar
docker load -i ose311.51-optional-imags.tar
docker load -i ose-builder-images.tar
=>
systemctl restart docker
systemctl status docker

#build image는 OCP 설치 후 나중에 load

09_dockertag.sh
09_dockerpush.sh

10_dockerrmi.sh

===============================================================================
--8. System Check
-------------------------------------------------------------------------------
11_system-check.sh
a. RHEL version
b. hostname
c. selinux (SELINUX=enforcing, SELINUXTYPE=targeted)
d. NetworkManager
e. yum repolist (rhel-7-server-rpms, rhel-7-server-extras-rpms, rhel-7-fast-datapath-rpms, rhel-7-server-ansible-2.4-rpms, rhel-7-server-ose-3.11-rpms)
f. chronyc sources -v

===============================================================================
--9. OpenShift 3.11 Install
-------------------------------------------------------------------------------
cp /root/.example/ocp311/hosts /etc/ansible/hosts
vi /etc/ansible/hosts

# webconsole ca certification
-------------------------------------------------------------------------------
https://paasmaster.example.ocp:8443/console
domain: paasmaster.example.ocp
/etc/origin/master/named_certificates/
#openshift_master_named_certificates=[{"certfile": "/root/console_cert/paasmaster.example.ocp.crt", "keyfile": "/root/console_cert/paasmaster.example.ocp.key", "names": ["paasmaster.example.ocp"]}]

openshift_master_ca_certificate={'certfile': '/root/console_cert/paasmaster.example.ocp.crt', 'keyfile': '/root/console_cert/paasmaster.example.ocp.key'}
#openshift_master_named_certificates=[{"certfile": "/path/to/custom1.crt", "keyfile": "/path/to/custom1.key", "cafile": "/path/to/custom-ca1.crt"}]
#openshift_master_named_certificates=[{"certfile": "/path/to/custom1.crt", "keyfile": "/path/to/custom1.key", "names": ["public-master-host.com"], "cafile": "/path/to/custom-ca1.crt"}]

openshift_master_overwrite_named_certificates=true

# /etc/origin/master/named_certificates/
cp /root/console_cert/* /usr/share/ansible/openshift-ansible/roles/openshift_ca/files/

openshift_master_named_certificates=[{"names": ["paasmaster.example.ocp"], "certfile": "/path/to/custom1.crt", "keyfile": "/path/to/custom1.key" ]

# Custom Wildcard Certificate for the Default Router
-------------------------------------------------------------------------------
www.example.ocp
openshift_hosted_router_certificate={"certfile": "/path/to/custom1.cert.pem", "keyfile": "/path/to/custom1.key.pem", "cafile": "/path/to/ca-chain.cert.pem"}

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/redeploy-certificates.yml

# wildcard API certificate
openshift_hosted_router_certificate={"certfile": "/path/to/custom1.crt", "keyfile": "/path/to/custom1.key", "cafile": "/path/to/ca-chain.cert.pem"}

● Router 관련 port
80, 443: HTTP/HTTPS use for the router
1936: template router to access statistics
=> router를 infra서버에 위치하였다면, 위의 해당 port가 중복으로 충돌하면 안됨 (console port는 가급적 8443을 사용)

vi /etc/hosts
192.168.50.54 master01
192.168.50.55 infra01
192.168.50.56 node01

# Set the log_path
log_path = ~/openshift-ansible.log

● Running the RPM-based Installer
-------------------------------------------------------------------------------
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml
ansible-playbook -i /root/.example/ocp3.11/hosts /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/adhoc/uninstall.yml
ansible nodes -a "rm -rf /etc/origin"
ansible nfs -a "rm -rf /srv/nfs/*"

# Health Check
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-checks/pre-install.yml

# Node Bootstrap
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node/bootstrap.yml

# etcd Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-etcd/config.yml

# NFS Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-nfs/config.yml

# Load Balancer Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-loadbalancer/config.yml

# Master Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-master/config.yml

# Master Additional Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-master/additional_config.yml

# Node Join
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node/join.yml

# GlusterFS Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-glusterfs/config.yml

# Hosted Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-hosted/config.yml

# Monitoring Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-monitoring/config.yml

# Web Console Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-web-console/config.yml

# Metrics Install
ansible-playbook -i /root/install_ocp311/hosts /usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml

# Logging Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-logging/config.yml

# Availability Monitoring (Prometheus) Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-monitor-availability/config.yml

# Service Catalog Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-service-catalog/config.yml

# Management Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-management/config.yml

# Descheduler Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-descheduler/config.yml

# Node Problem Detector Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node-problem-detector/config.yml

# Autoheal Install
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-autoheal/config.yml

# Operator Lifecycle Manager (OLM) Install (Technology Preview)
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/olm/config.yml
-------------------------------------------------------------------------------

oc rollout status -w dc/docker-registry

=> 재 설치 시에는 ocp 정지 후 설치
systemctl restart atomic-openshift-node
master-restart controllers
master-restart api
master-logs controllers
master-exec

ansible masters -m shell -a "/usr/local/bin/master-restart api"
ansible masters -m shell -a "/usr/local/bin/master-restart controllers"
ansible nodes -m shell -a "systemctl restart atomic-openshift-node"

ansible nodes -m shell -a "hostname; reboot"
ansible nodes -m shell -a "hostname; date"

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml -vvvv | tee ansible-install.log

# Verify OpenShift Cluster
-------------------------------------------------------------------------------
copy the .kube directory from master to your bastion host
scp /root/.kube bastion:/root/
ansible masters[0] -b -m fetch -a "src=/root/.kube/config dest=/root/.kube/config flat=yes"
=> oc login system:admin

oc get nodes --show-labels -o wide
oc get pod --all-namespaces -o wide
oc get users

ansible masters --list-hosts
ansible nodes --list-hosts
ansible all --list-hosts
ansible all -m ping

# Verify Installation and Configuration of Docker
-------------------------------------------------------------------------------
ansible nodes -m shell -a"systemctl status docker | grep Active"
ansible nodes -m shell -a"docker version|grep Version"

# Verify Yum Repositories and NFS Shared Volumes on Hosts
-------------------------------------------------------------------------------
ansible all -m shell -a"yum repolist"
ansible nfs -m shell -a"exportfs"

# bastion host
-------------------------------------------------------------------------------
yum -y install atomic-openshift-clients openshift-ansible

===============================================================================
--Registry Console Node Selector Chane
-------------------------------------------------------------------------------
oc edit dc/registry-console -n default
nodeSelector:
  region: infra

===============================================================================
Docker Registry Volume Mount
-------------------------------------------------------------------------------
oc project default
mount -t nfs dns.example.ocp:/volumes /mnt
mkdir /mnt/registry
chmod 775 /mnt/registry
oc create -f registry-pv.yaml
oc create -f registry-pvc.yaml -n default

oc set volume dc/docker-registry --add --name=registry-storage -t pvc -m /registry --claim-name=registry-claim --overwrite -n default
oc set volume -f dc.json --add --name=new-volume -t pvc --claim-name=new-pvc --mount-path=/data --containers=new-app

===============================================================================
--9. OpenShift Management
-------------------------------------------------------------------------------
● start / stop openshift
-------------------------------------------------------------------------------
# master restart
master-restart api
master-restart controllers
master-restart etcd

ansible masters -m shell -a "/usr/local/bin/master-restart api"
ansible masters -m shell -a "/usr/local/bin/master-restart controllers"
ansible nodes -m shell -a "systemctl restart atomic-openshift-node"

master-logs api api
master-logs controllers controllers
master-logs etcd etcd

ansible all -m ping
systemctl status docker
systemctl status atomic-openshift-node

# node restart
systemctl restart docker
systemctl restart atomic-openshift-node
systemctl status docker
systemctl status atomic-openshift-node

oc adm top nodes
oc adm top node --selector='region=infra'

● user management
-------------------------------------------------------------------------------
vi /etc/origin/master/master-config.yaml
oauthConfig:
...
    provider:
      apiVersion: v1
      file: /root/htpasswd.openshift
      kind: DenyAllPasswordIdentityProvider => HTPasswdPasswordIdentityProvider

--
/etc/origin/master/htpasswd
htpasswd -b /etc/origin/master/htpasswd ocpadmin test1234!
oc login ocpadmin
--


yum -y install httpd-tools
touch /root/htpasswd.openshift

oc create user ocpadmin
htpasswd -b /root/htpasswd.openshift ocpadmin test1234!
htpasswd /root/htpasswd.openshift developer

oc create user dongsu
htpasswd -b /etc/origin/master/htpasswd dongsu test1234

oc get users
oc delete user developer
oc delete identity htpasswd_auth:developer

# Give user account as cluster-admin privileges
oc adm policy add-cluster-role-to-user cluster-admin ocpadmin
oc adm policy add-role-to-user admin ocpadmin -n openshift
oc adm policy add-role-to-user view system:serviceaccount:default:default -n default

oc adm policy add-role-to-user system:registry ocpadmin
oc adm policy add-role-to-user system:image-builder ocpadmin

oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:default:router

# Grant all authenticated users access to the anyuid SCC
oc adm policy add-scc-to-user anyuid -n default -z router
oc adm policy add-scc-to-group anyuid system:authenticated

oc get nodes

===============================================================================
--10. S2I Builder Images Re-tagging, Push
-------------------------------------------------------------------------------
docker load -i /root/.example/ose311.16-images/ose311.16-builder-images.tar

vi /etc/sysconfig/docker
OPTIONS='--insecure-registry docker-registry-default.paas.example.ocp --signature-verification=false'

oc login -u ocpadmin -p ocpadmin.! https://paasmaster.example.ocp:8443 --insecure-skip-tls-verify=true
oc login -u=ocpadmin -p=ocpadmin.! --server=master01.example.ocp
oc login https://paasmaster.example.ocp --token=$(oc whoami -t)

oc login --certificate-authority=/etc/origin/master/ca.crt -u ocpadmin paasmaster.example.cloud

docker: docker login -u ocpadmin -p $(oc whoami -t) registry.example.ocp:5000
※ openshift: docker login -u ocpadmin -p $(oc whoami -t) docker-registry-default.paas.example.ocp
docker login -p OGs8jaeq-qeX0OOjR7Hj5DfK70Op0I_O61VR9dr921s -e unused -u unused docker-registry-default.paas.example.ocp

docker login -p $(oc whoami -t) -u ocpadmin docker-registry-default.paas.example.ocp
oc login --token $(oc whoami -t) paasmaster.example.ocp:8443

docker tag registry.example.ocp:5000/jboss-eap-7/eap71-openshift:latest docker-registry-default.paas.example.ocp/openshift/eap71-openshift:1.3

docker tag registry.access.redhat.com/jboss-eap-7/eap71-openshift:latest docker-registry-default.paas.example.ocp/openshift/eap71-openshift:1.3

docker push docker-registry-default.paas.example.ocp/openshift/eap71-openshift:1.3

docker pull docker-registry-default.paas.example.ocp/openshift/eap71-openshift:1.3

09-1_dockertag.sh
09-2_dockerpush.sh
09-3_dockerrmi.sh

oc rollout latest dc/docker-registry -n default
oc rollout pause dc/docker-registry
oc rollout resume dc/docker-registry

oc rollout status -w dc/docker-registry
oc rollout latest dc/registry-console -n default
-------------------------------------------------------------------------------
-- s2i images registry
-------------------------------------------------------------------------------
oc login -u ocpadmin -p ocpadmin.! https://paasmaster.example.ocp:8443

docker pull registry.access.redhat.com/jboss-eap-7/eap70-openshift:latest

1) private docker registry
docker login -u ocpadmin -p $(oc whoami -t) registry.example.ocp:5000

docker tag registry.access.redhat.com/jboss-eap-7/eap70-openshift:latest registry.example.ocp:5000/openshift/eap70-openshift:1.7

docker push registry.example.ocp:5000/openshift/eap70-openshift:1.7

2) openshift integrated registry

oc login --token a7QQhfcRltAea5Nh7Ru5li9xLNwtMU5kgGDdsNWtKcg paasmaster.example.ocp:8443
docker login -p a7QQhfcRltAea5Nh7Ru5li9xLNwtMU5kgGDdsNWtKcg -e unused -u unused docker-registry-default.paas.example.ocp

docker login -p $(oc whoami -t) -e unused -u unused docker-registry-default.paas.example.ocp

registry-console > Project > openshift> ocpadmin member 추가 후 admin role 부여
oc adm policy add-role-to-user admin ocpadmin -n openshift

docker login -u ocpadmin -p $(oc whoami -t) docker-registry-default.paas.example.ocp

docker pull registry.example.ocp:5000/openshift/eap70-openshift:1.7
docker tag registry.example.ocp:5000/openshift/eap70-openshift:1.7 docker-registry-default.paas.example.ocp/openshift/eap70-openshift:1.7
docker push docker-registry-default.paas.example.ocp/openshift/eap70-openshift:1.7

● OpenShift Template Image Registration
-------------------------------------------------------------------------------
11-1_oc_import.sh
oc import-image registry.access.redhat.com/jboss-eap-7/eap71-openshift:latest -n openshift --confirm

11-2_oc_tag.sh
oc tag eap71-openshift:latest jboss-eap71-openshift:1.4 -n openshift

# Removing Image Stream Tags from an Image Stream
oc tag -d jboss-eap71-openshift:1.4 -n openshift

docker: registry.example.ocp:5000/jboss-eap-7/eap71-openshift
oc: docker-registry-default.paas.example.ocp/openshift/eap71-openshift


oc set volume dc/docker-registry --add --name=registry-storage -t pvc -m /registry --claim-name=registry-claim --overwrite -n default

oc set volume deploymentconfigs/docker-registry --add --name=registry-storage -t pvc --claim-name=registry-claim --overwrite -n default

===============================================================================
--11. Logging, Metrics, prometheus 구성
-------------------------------------------------------------------------------
● Host Registration
-------------------------------------------------------------------------------
vi /etc/ansible/hosts
logging, metrics parameter 등록

● logging Volume Registration
-------------------------------------------------------------------------------
mkdir -p /volumes/logging-es-0
mkdir -p /volumes/logging-es-1
mkdir -p /volumes/logging-es-2
chown nfsnobody:nfsnobody logging-es-0
chown nfsnobody:nfsnobody logging-es-1
chown nfsnobody:nfsnobody logging-es-2
chmod 775 /volumes/logging-es-0
chmod 775 /volumes/logging-es-1
chmod 775 /volumes/logging-es-2

vi /etc/exports
/volumes/logging-es-0 *(rw,async,all_squash)
/volumes/logging-es-1 *(rw,async,all_squash)
/volumes/logging-es-2 *(rw,async,all_squash)
exportfs -a

setsebool -P virt_use_nfs on  (server, client 둘 다 등록)

oc create -f logging-es-0.yaml -n logging
oc create -f logging-es-1.yaml -n logging
oc create -f logging-es-2.yaml -n logging
oc create -f logging-es-0-pvc.yaml -n logging
oc create -f logging-es-1-pvc.yaml -n logging
oc create -f logging-es-2-pvc.yaml -n logging

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-logging/config.yml

oc adm policy add-scc-to-user privileged system:serviceaccount:logging:aggregated-logging-elasticsearch

# to view cluster monitoring UI
oc adm policy add-cluster-role-to-user cluster-monitoring-view developer -n openshift-monitoring
oc adm policy add-cluster-role-to-user cluster-admin developer -n openshift-monitoring

oc adm policy add-cluster-role-to-user cluster-monitoring-view ocpadmin
https://docs.openshift.com/container-platform/3.11/install_config/prometheus_cluster_monitoring.html

● openshift-infra (Metrics) Volume Registration
-------------------------------------------------------------------------------
mkdir -p /volumes/cassandra-data
vi /etc/exports
/volumes/cassandra-data *(rw,async,all_squash)
exportfs -a

oc create -f cassandra-pv.yaml -n openshift-infra
oc create -f cassandra-pvc.yaml -n openshift-infra

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml

oc adm diagnostics MetricsApiProxy

● openshift-metrics(prometheus) Volume Registration
-------------------------------------------------------------------------------
mkdir -p /volumes/metrics
chmod 750 /volumes/metrics
chown nfsnobody:nfsnobody /volumes/metrics

vi /etc/exports
/volumes/metrics *(rw,async,all_squash)
exportfs -a

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-prometheus/config.yml

● Router SCC
-------------------------------------------------------------------------------
oc edit scc privileged
users:
- system:serviceaccount:default:router

# ARP Cache Tuning for Large-scale Clusters
sysctl net.ipv4.neigh.default.gc_thresh1=8192
sysctl net.ipv4.neigh.default.gc_thresh2=32768
sysctl net.ipv4.neigh.default.gc_thresh3=65536

===============================================================================
--12. Router configuration
-------------------------------------------------------------------------------
# Deploying the Router to a Labeled Node
-------------------------------------------------------------------------------
1) Permission to Access Labels
-------------------------------------------------------------------------------
oc create serviceaccount router01 -n default
oc create serviceaccount router02 -n default
oc create serviceaccount router-app01 -n default

oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:default:router
oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:default:router-app01
oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:default:router02

# F5 Router Plug-in
oc adm policy add-cluster-role-to-user system:sdn-reader system:serviceaccount:default:router
oc adm policy add-cluster-role-to-user system:sdn-reader system:serviceaccount:default:router-app01

oc adm policy add-scc-to-user hostnetwork -z router01
oc adm policy add-scc-to-user hostnetwork -z router-app01

2) Node Router Labeling (node를 특정 router로 지정할 경우)
-------------------------------------------------------------------------------
oc get node -o wide --show-labels
node01.example.ocp,region=primary,router=router02,zone=service

#oc label node infra01.example.ocp "router=router01"
#oc label node infra02.example.ocp "router=router02"

iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables-save > /etc/sysconfig/iptables

2) Namespace Router Labeling
-------------------------------------------------------------------------------
oc label namespace default "router=router" --overwrite
oc label namespace s2i-build "router=router-app01" --overwrite

oc label namespace cicd-prod "router=router01" --overwrite
oc label namespace cicd-dev "router=router02"

oc get ns --show-labels

3) Deploying the Router to a Labeled Node
-------------------------------------------------------------------------------
oc adm router router-app01 --replicas=1 --selector='node-role.kubernetes.io/router=true' --service-account=router-app01 --images='registry.devops.cloud:5000/openshift3/ose-haproxy-router:v3.11.69'

oc patch namespace s2i-build -p     '{"metadata":{"annotations":{"openshift.io/node-selector":"node-role.kubernetes.io/router=true"}}}'
or
oc adm new-project s2i-build --node-selector='node-role.kubernetes.io/router=true'

oc adm router router02 --replicas=2 --selector='region=rg-rt-prd' --service-account=router02 --ports='8080:8080,1443:1443,2936:2936' --max-connections=10000

oc set env dc/router01 ROUTER_SERVICE_HTTP_PORT=8080  \
                     ROUTER_SERVICE_HTTPS_PORT=1443 \
                     ROUTER_LISTEN_ADDR='0.0.0.0:2936' \
                     STATS_PORT=2937 \
                     ROUTER_MAX_CONNECTIONS=20000

# Router Environment Variables
-------------------------------------------------------------------------------
ROUTER_METRICS_HAPROXY_BASE_SCRAPE_INTERVAL=5s
ROUTER_METRICS_HAPROXY_TIMEOUT=5s
ROUTER_TCP_BALANCE_SCHEME=source  # source, roundrobin, leastconn
ROUTER_LOAD_BALANCE_ALGORITHM=leastconn   # source, roundrobin, leastconn
TEMPLATE_FILE=/var/lib/haproxy/conf/custom/haproxy-config-custom.template
ROUTER_BLUEPRINT_ROUTE_POOL_SIZE=10
ROUTER_MAX_DYNAMIC_SERVERS=5

# Router timeout variables
-------------------------------------------------------------------------------
ROUTER_BACKEND_CHECK_INTERVAL=5000ms
ROUTER_CLIENT_FIN_TIMEOUT=1s
ROUTER_DEFAULT_CLIENT_TIMEOUT=30s
ROUTER_DEFAULT_CONNECT_TIMEOUT=5s
ROUTER_DEFAULT_SERVER_FIN_TIMEOUT=1s
ROUTER_DEFAULT_SERVER_TIMEOUT=30s
ROUTER_SLOWLORIS_HTTP_KEEPALIVE=300s
RELOAD_INTERVAL=5s
ROUTER_METRICS_HAPROXY_TIMEOUT=5s

oc set env dc/router01 ROUTER_SYSLOG_ADDRESS=127.0.0.1 ROUTER_LOG_LEVEL=debug

oc scale dc/router01 --replicas=2

oc edit dc/router01
spec:
      nodeSelector:      1
        router: infra

oc get routes --show-labels
oc get routes --show-labels -l router=router
oc get pod --show-labels -l router=router01

# Router (HAProxy) enhancements
-------------------------------------------------------------------------------
oc set env dc/router ROUTER_ENABLE_HTTP2=true

oc scale dc/router --replicas=0
oc adm router myrouter --threads=2 --images='registry.devops.cloud:5000/openshift3/ose-haproxy-router:v3.11.69'
oc set env dc/myrouter ROUTER_THREADS=7

# Dynamic changes
oc set env dc/router ROUTER_HAPROXY_CONFIG_MANAGER=true

# Client SSL/TLS cert validation (old mTLS enable)
oc adm router myrouter --mutual-tls-auth=optional --mutual-tls-auth-ca=/root/ca.pem --images="$image"

# Logs captured by aggregated logging/EFK
oc adm router myrouter --extended-logging --images='xxxx'
oc set env dc/myrouter ROUTER_LOG_LEVEL=debug
oc logs -f myrouter-x-xxxxx -c syslog

# To add basic active/backup HA to an existing project/namepace
oc patch netnamespace myproject -p '{"egressIPs":["10.0.0.1","10.0.0.2"]}'
oc patch hostsubnet node1 -p '{"egressIPs":["10.0.0.1"]}'
oc patch hostsubnet node2 -p '{"egressIPs":["10.0.0.2"]}'

# To enable the fully-automatic HA option
oc patch hostsubnet node1 -p '{"egressCIDRs":["10.0.0.0/24"]}'
oc patch netnamespace myproject -p '{"egressIPs":["10.0.0.1"]}'

# To configure the VXLAN port
vi master-config.yaml
vxlanPort: 4889  (default 4789)
oc delete clusternetwork default
master-restart api controllers
oc delete pod -n openshift-sdn -l app=sdn
iptables -i OS_FIREWALL_ALLOW -p udp -m state --state NEW -m udp --dport 4889 -j ACCEPT

===============================================================================
--13. Region, Zone Change
-------------------------------------------------------------------------------
# node region change
-------------------------------------------------------------------------------
oc label node node01.localocp.com region=primary zone=service
oc label node infra01.localocp.com region=infra zone=infra

oc label node infra01.localocp.com "router=router01"
oc edit dc router01
spec:
      nodeSelector:     
        router: "router01"

oc rollout latest dc/router -n default
oc rollout latest dc/router01 -n default

# namespace(project) region change
-------------------------------------------------------------------------------
oc edit -o json namespace default
"openshift.io/node-selector": "region=infra"

https://docs.openshift.com/container-platform/3.11/install_config/router/default_haproxy_router.html

# default node selector change
-------------------------------------------------------------------------------
/etc/origin/master/master-config.yaml
projectConfig:
defaultNodeSelector: "region=primary"
systemctl restart atomic-openshift-master-api atomic-openshift-master-controllers

# openshift-node 설정
-------------------------------------------------------------------------------
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node/join.yml

oc adm manage-node master01.example.ocp --schedulable=false
oc adm manage-node master02.example.ocp --schedulable=false
oc adm manage-node master03.example.ocp --schedulable=false

oc expose service my-service --name=my-service -l name='my-service'
oc rollback my-service --to-version=1 --dry-run
oc rollback my-service --to-version=1

# setting timezone for pods in OpenShift
-------------------------------------------------------------------------------
oc env deploymentconfigs/eap64-app1 TZ=Asia/Seoul
oc log -f po/eap64-app1-2-f8fn6 --timestamps

oc start-build eap-app -n eap71-mysql-project --follow
oc logs -f build/eap-app-n

# Restart all myapp pods in the myproject
-------------------------------------------------------------------------------
oc delete pod -n myproject -l app=myapp


# Deploy the OpenShift Router
-------------------------------------------------------------------------------
oc delete all -l router=router
oc adm router --replicas=1 --service-account=router

# Deploy an Internal Registry
-------------------------------------------------------------------------------
oc delete all -l docker-registry=default
oc adm registry

# API Authentication
-------------------------------------------------------------------------------
oc create clusterrolebinding <any_valid_name> --clusterrole=sudoer --user=<username>
oc new-project <project> --as=<user> \
--as-group=system:authenticated --as-group=system:authenticated:oauth

# To register additional clients
-------------------------------------------------------------------------------
oc create -f <(echo '
kind: OAuthClient
apiVersion: oauth.openshift.io/v1
metadata:
name: demo
secret: "..."
redirectURIs:
- "http://www.example.com/"
grantMethod: prompt
')

# Service Accounts as OAuth Clients
-------------------------------------------------------------------------------
oc sa get-token <serviceaccount_name>

# static pods limit
-------------------------------------------------------------------------------
oc logs master-api-<hostname> -n kube-system
oc delete pod master-api-<hostname> -n kube-system

# loglevel parameter
-------------------------------------------------------------------------------
/etc/origin/master/master.env

# node configuration groups
-------------------------------------------------------------------------------
node-config-master
node-config-infra
node-config-compute
node-config-all-in-one
node-config-master-infra

# Modifying Node Configurations
-------------------------------------------------------------------------------
/etc/origin/node/node-config.yaml

# edit node-config-compute ConfigMap
oc edit cm node-config-compute -n openshift-node

ansible all -m ping

rm -rf /etc/origin

# Create Quotas for Cluster User
-------------------------------------------------------------------------------
export OCP_USERNAME=developer
oc create clusterquota clusterquota-${OCP_USERNAME} \
--project-annotation-selector=openshift.io/requester=$OCP_USERNAME \
--hard pods=25 \
--hard requests.memory=6Gi \
--hard requests.cpu=5 \
--hard limits.cpu=25  \
--hard limits.memory=40Gi \
--hard configmaps=25 \
--hard persistentvolumeclaims=25  \
--hard services=25
oc get clusterresourcequota
oc describe clusterresourcequota clusterquota-developer
oc get events | grep clusterquota
oc delete clusterresourcequota clusterquota-developer

===============================================================================
--14. Node Group 추가하기
-------------------------------------------------------------------------------
1) ansible hosts inventory에 node 등록
/etc/ansible/hosts
# Node Groups 추가 (node-config-router)
openshift_node_groups=[{'name': 'node-config-master', 'labels': ['node-role.kubernetes.io/master=true','runtime=docker']}, {'name': 'node-config-infra', 'labels': ['node-role.kubernetes.io/infra=true','runtime=docker']}, {'name': 'node-config-router', 'labels': ['node-role.kubernetes.io/router=true','runtime=docker']}, {'name': 'node-config-compute', 'labels': ['node-role.kubernetes.io/compute=true','runtime=docker'], 'edits': [{ 'key': 'kubeletArguments.pods-per-core','value': ['20']}]}]

[nodes]
router01.example.ocp openshift_ip=192.168.50.58 openshift_public_ip=192.168.50.58 openshift_hostname=router01.example.ocp openshift_public_hostname=router01.example.ocp openshift_node_group_name='node-config-router' openshift_node_problem_detector_install=true

2) 추가 node 설치
추가 node vm에 Network, hostname, DNS, sshkey_copy, chrony setting
01_network_change.sh
02_hostname_change.sh
03_dns_setting.sh
04_sshkey_copy.sh
05_chrony_setting.sh

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node/bootstrap.yml
ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-node/join.yml

3) Node Group 추가 및 확인
openshift-node project에서 Config Map 등록
openshift-node > Resources > Config Maps > Create Config Map
ex) node-config-router

# default node config
-------------------------------------------------------------------------------
/usr/share/ansible/openshift-ansible/roles/openshift_facts/defaults/main.yml

openshift_node_groups:
  - name: node-config-master
    labels:
      - 'node-role.kubernetes.io/master=true'
    edits: []
  - name: node-config-master-crio
    labels:
      - 'node-role.kubernetes.io/master=true'
      - "{{ openshift_crio_docker_gc_node_selector | lib_utils_oo_dict_to_keqv_list | join(',') }}"
    edits: "{{ openshift_node_group_edits_crio }}"
  - name: node-config-infra
    labels:
      - 'node-role.kubernetes.io/infra=true'
    edits: []
  - name: node-config-infra-crio
    labels:
      - 'node-role.kubernetes.io/infra=true'
      - "{{ openshift_crio_docker_gc_node_selector | lib_utils_oo_dict_to_keqv_list | join(',') }}"
    edits: "{{ openshift_node_group_edits_crio }}"
  - name: node-config-compute
    labels:
      - 'node-role.kubernetes.io/compute=true'
    edits: []
  - name: node-config-compute-crio
    labels:
      - 'node-role.kubernetes.io/compute=true'
      - "{{ openshift_crio_docker_gc_node_selector | lib_utils_oo_dict_to_keqv_list | join(',') }}"
    edits: "{{ openshift_node_group_edits_crio }}"
  - name: node-config-master-infra
    labels:
      - 'node-role.kubernetes.io/master=true'
      - 'node-role.kubernetes.io/infra=true'
    edits: []
  - name: node-config-master-infra-crio
    labels:
      - 'node-role.kubernetes.io/master=true'
      - 'node-role.kubernetes.io/infra=true'
      - "{{ openshift_crio_docker_gc_node_selector | lib_utils_oo_dict_to_keqv_list | join(',') }}"
    edits: "{{ openshift_node_group_edits_crio }}"
  - name: node-config-all-in-one
    labels:
      - 'node-role.kubernetes.io/master=true'
      - 'node-role.kubernetes.io/infra=true'
      - 'node-role.kubernetes.io/compute=true'
    edits: []
  - name: node-config-all-in-one-crio
    labels:
      - 'node-role.kubernetes.io/master=true'
      - 'node-role.kubernetes.io/infra=true'
      - 'node-role.kubernetes.io/compute=true'
      - "{{ openshift_crio_docker_gc_node_selector | lib_utils_oo_dict_to_keqv_list | join(',') }}"
    edits: "{{ openshift_node_group_edits_crio }}"

# 프로젝트 별 node group 지정
-------------------------------------------------------------------------------
oc patch namespace s2i-build -p     '{"metadata":{"annotations":{"openshift.io/node-selector":"node-role.kubernetes.io/compute=true"}}}'
또는
oc adm new-project testproject --node-selector='node-role.kubernetes.io/compute=true'
oc adm new-project s2i-build --display-name=s2i-build --description=s2i-build-test --node-selector='node-role.kubernetes.io/compute=true'

oc edit project testproject
oc edit ns testproject
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  annotations:
    openshift.io/node-selector: node-role.kubernetes.io/compute=true

INSTALLER STATUS ********************************************************************************************************************
Initialization                 : Complete (0:01:17)
Health Check                   : Complete (0:00:17)
Node Bootstrap Preparation     : Complete (0:04:44)
etcd Install                   : Complete (0:01:26)
Load Balancer Install          : Complete (0:00:28)
Master Install                 : Complete (0:06:13)
Master Additional Install      : Complete (0:01:58)
Node Join                      : Complete (0:02:16)
Hosted Install                 : Complete (0:01:40)
Cluster Monitoring Operator    : Complete (0:00:54)
Web Console Install            : Complete (0:00:32)
Console Install                : Complete (0:00:27)
Metrics Install                : Complete (0:03:38)
metrics-server Install         : Complete (0:01:18)
Logging Install                : Complete (0:05:50)
Service Catalog Install        : Complete (0:04:10)
OLM Install                    : Complete (0:01:03)
Node Problem Detector Install  : Complete (0:00:18)

===============================================================================
--15. openshift-glusterfs
-------------------------------------------------------------------------------
subscription-manager repos --enable=rh-gluster-3-client-for-rhel-7-server-rpms
yum install glusterfs-fuse
yum update glusterfs-fuse

# To enable writing to Red Hat Gluster Storage volumes with SELinux
sudo setsebool -P virt_sandbox_use_fusefs on
sudo setsebool -P virt_use_fusefs on

# ansible glusterfs add
/etc/ansible/hosts

ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/openshift-glusterfs/config.yml

# Update all pods in the namespace
oc label pods --all status=unhealthy
