#!/bin/bash

# Install Postgress
# https://backstage.io/docs/deployment/k8s/#creating-a-namespace

# pg_user=$(echo "pgbkstguser" | base64)
# pg_pass=$(echo "pgbkstguser-random-pwd" | base64)


kubectl create namespace backstage

# cat <<EOF | tee postgres-secrets.yaml
# # kubernetes/postgres-secrets.yaml
# apiVersion: v1
# kind: Secret
# metadata:
#   name: postgres-secrets
#   namespace: backstage
# type: Opaque
# data:
#   POSTGRES_USER: $pg_user
#   POSTGRES_PASSWORD: $pg_pass
# EOF

cat <<EOF | tee postgres-secrets.yaml
# kubernetes/postgres-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secrets
  namespace: backstage
type: Opaque
data:
  POSTGRES_USER: YmFja3N0YWdl
  POSTGRES_PASSWORD: aHVudGVyMg==
EOF

kubectl apply -f postgres-secrets.yaml

cat <<EOF | tee postgres-storage.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-storage
  namespace: backstage
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 2G
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: '/mnt/data'
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-storage-claim
  namespace: backstage
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2G
EOF

kubectl apply -f postgres-storage.yaml

cat <<EOF | tee postgres.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: backstage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:13.2-alpine
          imagePullPolicy: 'IfNotPresent'
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: postgres-secrets
          volumeMounts:
            - mountPath: /var/lib/postgresql/data
              name: postgresdb
      volumes:
        - name: postgresdb
          persistentVolumeClaim:
            claimName: postgres-storage-claim
EOF

kubectl apply -f postgres.yaml

sleep 5

kubectl get pods --namespace=backstage

# Verify by connecting to pod
# $ kubectl exec -it --namespace=backstage postgres-<hash> -- /bin/bash
# bash-5.1# psql -U $POSTGRES_USER
# psql (13.2)
# backstage=# \q
# bash-5.1# exit

cat <<EOF | tee postgres-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: backstage
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
EOF

kubectl apply -f postgres-service.yaml