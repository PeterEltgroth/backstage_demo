#!/bin/bash
kubectl delete -f backstage.yaml
kubectl apply -f backstage-svc.yaml
kubectl apply -f backstage-ing.yaml
yarn build:backend --config ../../app-config.yaml --config ../../app-config.production.yaml
docker image build . -f packages/backend/Dockerfile --tag backstage
docker tag backstage:latest isvengtapfull.azurecr.io/backstage:latest
docker push isvengtapfull.azurecr.io/backstage:latest
kubectl apply -f backstage.yaml
