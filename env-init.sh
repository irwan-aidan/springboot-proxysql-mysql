#!/usr/bin/env bash

echo
echo "Starting environment"
echo "===================="

echo
echo "Creating network"
echo "----------------"
docker network create springboot-proxysql-mysql

echo
echo "Starting mysql-master container"
echo "-------------------------------"
docker run -d \
  --name mysql-master \
  --network=springboot-proxysql-mysql \
  --restart=unless-stopped \
  --env "MYSQL_ROOT_PASSWORD=secret" \
  --env "MYSQL_DATABASE=customerdb" \
  --publish 3306:3306 \
  --health-cmd='mysqladmin ping -u root -p$${MYSQL_ROOT_PASSWORD}' \
  --health-start-period=10s \
  mysql:5.7.26 \
    --server-id=1 \
    --log-bin='mysql-bin-1.log' \
    --relay_log_info_repository=TABLE \
    --master-info-repository=TABLE \
    --gtid-mode=ON \
    --log-slave-updates=ON \
    --enforce-gtid-consistency

echo
echo "Starting mysql-slave-1 container"
echo "--------------------------------"
docker run -d \
  --name mysql-slave-1 \
  --network=springboot-proxysql-mysql \
  --restart=unless-stopped \
  --env "MYSQL_ROOT_PASSWORD=secret" \
  --env "MYSQL_DATABASE=customerdb" \
  --publish 3307:3306 \
  --health-cmd='mysqladmin ping -u root -p$${MYSQL_ROOT_PASSWORD}' \
  --health-start-period=10s \
  mysql:5.7.26 \
    --server-id=2 \
    --enforce-gtid-consistency=ON \
    --log-slave-updates=ON \
    --read_only=TRUE \
    --skip-log-bin \
    --skip-log-slave-updates \
    --gtid-mode=ON

echo
echo "Starting mysql-slave-2 container"
echo "--------------------------------"
docker run -d \
  --name mysql-slave-2 \
  --network=springboot-proxysql-mysql \
  --restart=unless-stopped \
  --env "MYSQL_ROOT_PASSWORD=secret" \
  --env "MYSQL_DATABASE=customerdb" \
  --publish 3308:3306 \
  --health-cmd='mysqladmin ping -u root -p$${MYSQL_ROOT_PASSWORD}' \
  --health-start-period=10s \
  mysql:5.7.26 \
    --server-id=3 \
    --enforce-gtid-consistency=ON \
    --log-slave-updates=ON \
    --read_only=TRUE \
    --skip-log-bin \
    --skip-log-slave-updates \
    --gtid-mode=ON

echo
echo "Waiting 20 seconds before setting MySQL replication ..."
sleep 20

echo
echo "Setting MySQL Replication"
echo "-------------------------"
docker exec -i mysql-master mysql -uroot -psecret < mysql/master-replication.sql
docker exec -i mysql-slave-1 mysql -uroot -psecret < mysql/slave-replication.sql
docker exec -i mysql-slave-2 mysql -uroot -psecret < mysql/slave-replication.sql

echo
echo "Checking MySQL Replication"
echo "--------------------------"
./env-check-replication-status.sh

echo
echo "Creating ProxySQL monitor user"
echo "------------------------------"
docker exec -i mysql-master mysql -uroot -psecret < mysql/master-proxysql-monitor-user.sql

echo
echo "Waiting 5 seconds before starting proxysql container ..."
sleep 5

echo
echo "Starting proxysql container"
echo "---------------------------"
docker run -d \
  --name proxysql \
  --network=springboot-proxysql-mysql \
  --restart=unless-stopped \
  --publish 6032:6032 \
  --publish 6033:6033 \
  --volume $PWD/proxysql/proxysql.cnf:/etc/proxysql.cnf \
  proxysql/proxysql:2.0.4

echo
echo "Waiting 5 seconds before checking mysql servers"
sleep 5

echo
echo "Checking mysql servers"
echo "----------------------"
docker exec -i mysql-master bash -c 'mysql -hproxysql -P6032 -uradmin -pradmin --prompt "ProxySQL Admin> " <<< "select * from mysql_servers;"'

echo
echo "Environment Up and Running"
echo "=========================="
echo