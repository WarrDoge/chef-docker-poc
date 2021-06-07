FROM centos:7

ENV container docker
RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ $i == \
systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*;\
rm -f /etc/systemd/system/*.wants/*;\
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*;\
rm -f /lib/systemd/system/anaconda.target.wants/*;
VOLUME [ "/sys/fs/cgroup" ]

RUN set -x \
    && rpm -Uvh https://packages.chef.io/files/stable/chef-server/12.17.33/el/7/chef-server-core-12.17.33-1.el7.x86_64.rpm

RUN yum install which -y && yum install crontabs -y

# Changes listen_adress to 127.0.0.1
RUN sed -i "s/default\['private_chef'\]\['postgresql'\]\['listen_address'\].*/default['private_chef']['postgresql']['listen_address'] = '127.0.0.1'/" /opt/opscode/embedded/cookbooks/private-chef/attributes/default.rb

EXPOSE 443 80

COPY chef-server.rb /etc/opscode
COPY entrypoint.sh /
COPY entrypoint.service /etc/systemd/system

RUN systemctl enable entrypoint.service

CMD /sbin/init