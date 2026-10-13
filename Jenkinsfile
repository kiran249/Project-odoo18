// Deploys Odoo 18 + PostgreSQL + Keycloak + Prometheus/Grafana to EKS.
// Runs on the EKS bastion host, added to Jenkins as an SSH agent with label "bastion".
pipeline {
    agent { label 'bastion' }

    parameters {
        choice(name: 'ACTION', choices: ['deploy', 'destroy'], description: 'deploy = install/update everything, destroy = remove everything (DELETES DATA)')
        string(name: 'CLUSTER_NAME', defaultValue: 'my-eks-cluster', description: 'EKS cluster name')
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS region of the cluster')
    }

    environment {
        // Jenkins credentials, kind "Secret text"
        DB_PASSWORD             = credentials('db-password')
        ODOO_MASTER_PASSWORD    = credentials('odoo-master-password')
        KEYCLOAK_ADMIN_PASSWORD = credentials('keycloak-admin-password')
        GRAFANA_ADMIN_PASSWORD  = credentials('grafana-admin-password')
    }

    stages {
        stage('Connect to EKS') {
            steps {
                sh '''
                    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
                    kubectl get nodes
                '''
            }
        }

        stage('Namespaces & Secrets') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    kubectl apply -f k8s/storageclass.yaml
                    kubectl create namespace odoo       --dry-run=client -o yaml | kubectl apply -f -
                    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

                    kubectl -n odoo create secret generic app-secrets \
                        --from-literal=db-password="$DB_PASSWORD" \
                        --from-literal=keycloak-admin-password="$KEYCLOAK_ADMIN_PASSWORD" \
                        --dry-run=client -o yaml | kubectl apply -f -

                    cat > odoo.conf <<CONF
[options]
admin_passwd = $ODOO_MASTER_PASSWORD
db_host = postgres
db_port = 5432
db_user = odoo
db_password = $DB_PASSWORD
data_dir = /var/lib/odoo
CONF
                    kubectl -n odoo create secret generic odoo-conf --from-file=odoo.conf \
                        --dry-run=client -o yaml | kubectl apply -f -
                    rm -f odoo.conf

                    kubectl -n monitoring create secret generic grafana-admin \
                        --from-literal=admin-user=admin \
                        --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
                        --dry-run=client -o yaml | kubectl apply -f -
                '''
            }
        }

        stage('PostgreSQL') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    kubectl apply -f k8s/postgres.yaml
                    kubectl -n odoo rollout status statefulset/postgres --timeout=300s
                '''
            }
        }

        stage('Odoo') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    kubectl apply -f k8s/odoo.yaml
                    kubectl -n odoo rollout restart deployment/odoo   # pick up config changes
                    kubectl -n odoo rollout status deployment/odoo --timeout=600s
                '''
            }
        }

        stage('Keycloak') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    kubectl apply -f k8s/keycloak.yaml
                    kubectl -n odoo rollout status deployment/keycloak --timeout=600s

                    # Allow the admin console over plain HTTP on an IP address
                    KCADM="kubectl -n odoo exec deploy/keycloak -- /opt/keycloak/bin/kcadm.sh"
                    $KCADM config credentials --config /tmp/kcadm.config \
                        --server http://localhost:8080 --realm master --user admin --password "$KEYCLOAK_ADMIN_PASSWORD"
                    $KCADM update realms/master --config /tmp/kcadm.config -s sslRequired=NONE
                '''
            }
        }

        stage('Prometheus & Grafana') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                    helm repo update
                    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
                        --namespace monitoring -f monitoring/values.yaml --wait --timeout 10m
                '''
            }
        }

        stage('Access URLs') {
            when { expression { params.ACTION == 'deploy' } }
            steps {
                sh '''
                    IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
                    [ -z "$IP" ] && IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
                    echo "=============================================="
                    echo " Odoo       : http://$IP:30069"
                    echo " Keycloak   : http://$IP:30080   (user: admin)"
                    echo " Grafana    : http://$IP:30300   (user: admin)"
                    echo " Prometheus : http://$IP:30090"
                    echo "=============================================="
                '''
            }
        }

        stage('Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                sh '''
                    helm uninstall monitoring -n monitoring || true
                    kubectl delete namespace odoo monitoring --ignore-not-found
                '''
            }
        }
    }
}
