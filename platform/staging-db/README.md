# Staging database (applied by hand)

The pipeline does NOT create these. Create them once, before the first staging
deploy. Why: the database has its own owner and its own lifecycle. The pipeline
only deploys the application.

## Contents
- postgres.yaml: Service, StatefulSet and a PVC (made from the volume template)
- Secret `petclinic-db`: created by hand, never stored in Git

## Steps
1. The namespace exists: `kubectl get ns petclinic-staging`
2. Create the Secret (keys: username, password, database):

   kubectl create secret generic petclinic-db -n petclinic-staging \
     --from-literal=username=petclinic \
     --from-literal=password="$(openssl rand -base64 18 | tr -d '/+=')" \
     --from-literal=database=petclinic

3. Apply the database: `kubectl apply -f platform/staging-db/postgres.yaml`
4. Wait for it: `kubectl get pods -n petclinic-staging -w` (petclinic-db-0 must be Ready)
5. Check: `kubectl get secret,pvc -n petclinic-staging`

## Who uses the Secret
- The Postgres pod: user, password and database name for first start.
- The PetClinic pod (k8s/staging/deployment.yaml): the same keys, as
  SPRING_DATASOURCE_USERNAME and SPRING_DATASOURCE_PASSWORD.
The pipeline's service account cannot read Secrets. Kubernetes gives them to the pods.

## Important
- Postgres sets the password only on its FIRST start with an empty volume. If you
  change the Secret later, the database still has the old password. For a test
  environment, delete the PVC too, or change the password inside Postgres.
- Deleting the StatefulSet does not delete the PVC. This is on purpose.
- The data lives on one kind node. `kind delete cluster` deletes it.
- Backup (keep the file out of Git):
  kubectl exec -n petclinic-staging petclinic-db-0 -- pg_dump -U petclinic petclinic > backup.sql