# Odoo 18 on EKS (deployed by Jenkins from the bastion host)

This repo deploys the following to an existing EKS cluster:

| App        | URL                          | Login                        |
|------------|------------------------------|------------------------------|
| Odoo 18    | `http://<odoo-lb-address>`   | create a database on first visit (needs the master password) |
| Keycloak   | `http://<keycloak-lb-address>` | `admin` / keycloak-admin-password |
| Grafana    | `http://<grafana-lb-address>` | `admin` / grafana-admin-password  |
| Prometheus | `http://<prometheus-lb-address>:9090` | none                         |

PostgreSQL 16 runs inside the cluster and is not exposed. Odoo and Keycloak use it, each with its own database user.
There are no domains, no ingress and no TLS. Every app gets its own public AWS load balancer; the pipeline prints the addresses at the end.
Public subnets must carry the tag `kubernetes.io/role/elb = 1` so AWS knows where to put the load balancers.

```
k8s/storageclass.yaml   EBS gp3 disks
k8s/postgres.yaml       PostgreSQL + metrics exporter
k8s/odoo.yaml           Odoo 18
k8s/keycloak.yaml       Keycloak 26
monitoring/values.yaml  Prometheus + Grafana (kube-prometheus-stack Helm chart)
Jenkinsfile             the pipeline
scripts/setup-bastion.sh  one-time bastion setup
```

## 1. Prerequisites (AWS side)

1. **EKS cluster** with the **Amazon EBS CSI Driver** add-on installed. Postgres and Odoo store their data on EBS disks.
2. **Bastion host** (Amazon Linux 2023 or Amazon Linux 2) with an **IAM role** that can manage the cluster. In EKS → Access → *Create access entry*, add the role with the `AmazonEKSClusterAdminPolicy`.
3. **Security groups**
   - Worker nodes: allow inbound TCP `30069, 30080, 30090, 30300` from your IP.
   - Bastion: allow inbound TCP `8080` (Jenkins) from your IP.
4. Worker nodes need **public IPs** so you can reach them from your laptop.
   If your nodes are private, change `type: NodePort` to `type: LoadBalancer` in the Services. You then use the AWS load balancer address instead of the node IP.

## 2. Set up the bastion (one time)

```bash
git clone <this-repo> && cd <repo>
sudo bash scripts/setup-bastion.sh
```

This installs Jenkins, AWS CLI, kubectl and Helm, and prints the Jenkins initial admin password.
Open `http://<bastion-ip>:8080`, finish the setup wizard and install the suggested plugins.

## 3. Configure Jenkins

1. **Manage Jenkins → Credentials → Global → Add**. Create 4 credentials of kind **Secret text** with these IDs:
   - `db-password`
   - `odoo-master-password`
   - `keycloak-admin-password`
   - `grafana-admin-password`
2. **New Item → Pipeline**, then under *Pipeline* choose **Pipeline script from SCM**. Set *Git*, this repo's URL and the branch. *Script Path*: `Jenkinsfile`.

## 4. Deploy

Click **Build with Parameters** and fill in:
- `ACTION` = `deploy`
- `CLUSTER_NAME` = your EKS cluster name
- `AWS_REGION` = your region

The last stage, *Access URLs*, prints the address of every app. Running it again is safe: the pipeline updates what is already there.

To remove everything, run the pipeline with `ACTION` = `destroy`.
**This also deletes the Postgres and Odoo data disks.**

## Notes

- **First Odoo login:** open Odoo, fill in the *Master Password* (`odoo-master-password`), pick a database name and admin email/password, and click *Create database*.
- **Keycloak over HTTP:** the pipeline turns off the "HTTPS required" check on the `master` realm, so the admin console works on a plain IP. When you create your own realms, set *Require SSL* to `none` too.
- **Grafana:** the standard Kubernetes dashboards are included, plus a *PostgreSQL* dashboard in the *Extra* folder.
- **Checking pods from the bastion:**
  ```bash
  kubectl get pods -n odoo
  kubectl get pods -n monitoring
  kubectl logs -n odoo deploy/odoo
  ```
