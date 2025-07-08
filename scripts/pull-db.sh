#!/bin/sh

# Script to pull the database from the Kubernetes cluster for local development/debugging purposes

# Dump the db to a local file inside the running Pod
kubectl exec -it mongodb-1 -n hawakening -- bash -c \
  "mongodump --host=localhost --username=root \
  --password=\$(echo \$MONGODB_ROOT_PASSWORD) \
  --authenticationDatabase=admin --db=hawakening --gzip --archive=/tmp/db-dump.gz"

# Copy the dump file from the Pod to the local machine
kubectl cp hawakening/mongodb-1:/tmp/db-dump.gz ./local-mongodb-dump.gz

# Remove the dump file from the Pod
kubectl exec -it mongodb-1 -n hawakening -- rm /tmp/db-dump.gz
