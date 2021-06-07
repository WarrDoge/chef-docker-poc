#!/bin/bash
# 
# Script staring and bootstrapping ChefServer
# 
# Require variables:
# - PGPASSWORD
# - DB_PORT
# - DB_HOST
# - DB_NAME
# - DB_USER
# - CHEFHA_CLUSTER_NAME

chef-server-ctl reconfigure --chef-license=accept

#------------------------------------------------------------
# First Part (templates/default >> start_chef_server.sh.erb)
#------------------------------------------------------------
set -e

SECRETS_FILE='/etc/opscode/private-chef-secrets.json'
MIGRATIONS_FILE='/var/opt/opscode/upgrades/migration-level'

# Run PSQL query
function psql_query(){
  if [[ "$1" == "" ]]; then
    q="$(cat /dev/stdin)"
  else
    q=$1
  fi
  echo "$q" | /opt/opscode/embedded/bin/psql -p "$DB_PORT" -h "$DB_HOST" -d "$DB_NAME" -qAtX  --pset='footer=off' -U "$DB_USER"  2>&1
}

echo "INFO: Creating 'chef_ha' table if doesn't exist..."
psql_query <<EOF
        CREATE TABLE IF NOT EXISTS chef_ha (id serial,
          cluster_name character varying(255) UNIQUE NOT NULL,
          priv_chef_secrets text,
          migration_level text,
          CONSTRAINT chef_ha_id PRIMARY KEY(id));
EOF


######################################################################################################################
#
# MAIN
#
######################################################################################################################
echo "INFO: Waiting for PSQL server"
until psql_query "SELECT 1;"; do
  echo "INFO: "`date`" - waiting for PSQL is up, sleeping for 3 sec"
  sleep 3
done
echo "INFO: OK, PSQL is ready..."

echo "INFO: Checking if I'm master (first node in ASG)"
if psql_query "INSERT INTO chef_ha (cluster_name) VALUES ('$CHEFHA_CLUSTER_NAME');"; then
  psql_query "INSERT INTO chef_ha (cluster_name) VALUES ('$HOSTNAME');" || echo "Looks like its second run of this script. but it's fine"
  echo "INFO: OK, I'm master: '$HOSTNAME'!"

  echo "INFO: Reconfiguring ChefServer..."
  <%= node[cookbook_name]['chef_server']['ctl_cmd'] %> reconfigure

  if ! test -s "$SECRETS_FILE"; then
   echo "Secrets file '$SECRETS_FILE' not found!"
   exit 1
  fi
  
  if ! test -s "$MIGRATIONS_FILE"; then
    echo "Migrations file '$MIGRAIONS_FILE' not found!"
    exit 1
  fi

  # Read secrets and migrations and encode them with Base64
  SECRETS64=$(base64 $SECRETS_FILE)
  MIGRATIONS64=$(base64 $MIGRATIONS_FILE)

  echo 'INFO: pushing secrets and migrations to DB'
  psql_query "UPDATE chef_ha SET priv_chef_secrets = '$SECRETS64', migration_level = '$MIGRATIONS64' where cluster_name = '$CHEFHA_CLUSTER_NAME';"

  # Mark as bootstrapped
  touch /var/opt/opscode/bootstrapped
else
  echo "INFO: OK, I'm not master. Master is: "
  psql_query "SELECT FROM chef_ha (cluster_name) WHERE cluster_name != '$CHEFHA_CLUSTER_NAME';";

  echo "OK: Waiting for master..."
  SECRETS64=""
  while [[ "$SECRETS" == "" ]]; do
    echo "INFO: Sleeping for 3 sec ("`date`")"
    sleep 3
    SECRETS64=$(psql_query "SELECT priv_chef_secrets FROM chef_ha WHERE cluster_name = '$CHEFHA_CLUSTER_NAME';")
  done

  MIGRATIONS64=$(psql_query "SELECT migration_level FROM chef_ha WHERE cluster_name = '$CHEFHA_CLUSTER_NAME';")

  echo "INFO: Saving Chef private secrets (required for ChefBrowser and/or Supermarket)"
  mkdir -p /etc/opscode/
  echo $SECRETS64 | base64 -d > $SECRETS_FILE
  echo "INFO: Saving Chef Server DB migrations level"
  mkdir -p /var/opt/opscode/upgrades/
  echo $MIGRATIONS64 | base64 -d > $MIGRATIONS_FILE
fi

#-------------------------------------------------------------
# Second Part (cookbooks/test_backend >> recipes >> default.rb)
#-------------------------------------------------------------
<< 'MULTILINE-COMMENT'
printf "chef_server_url		'https://#{Mixlib::ShellOut.new('hostname -f').run_command.stdout.strip}/organizations/#{node['tmint_shared_chef']['org']}/' \nnode_name           'pivotal' \nclient_key          '/etc/opscode/pivotal.pem' \nssl_verify_mode	:verify_none
" >> /tmp/knife.rb

# Mixlib::ShellOut.new >> ???
# What is and where to find "node.json.erb" ?

time = ${date +"%T"}

cp node.json.erb /tmp/node1.json && printf "node_name: 'node1',\nohai_time: $time" >> /tmp/node1.json
cp node.json.erb /tmp/node2.json && printf "node_name: 'node2',\nohai_time: $time" >> /tmp/node1.json

knife node from file /tmp/node1.json -c /tmp/knife.rb
knife node from file /tmp/node2.json -c /tmp/knife.rb

chef-server-ctl reindex -w -a
MULTILINE-COMMENT
