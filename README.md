# Chạy môi trường Dev và Staging

## 1. Khởi động Cluster

Cần chạy minikube start --nodes 2 --disk-size='50000mb' --memory='20g' --driver=docker và minikube addons enable ingress

Nếu như Cluster là Cluster mới tinh, cần chạy script như sau:

- ./setup-keycloak.sh
- ./setup-redis.sh
- ./setup-cluster.sh

Sau khi chạy xong 3 file script trên, cần đảm bảo là các pods sau phải hoạt động:

- Keycloak: keycloak-0 phải 1/1 và Status: Running
- Postgres: postgres-0 phải 1/1 và Status: Running
- kafka: kafka-cluster-combined-0 phải 1/1 và Status: Running

## 2. Chỉnh sửa ingress-nginx-controller ClusterIP
```
hostAliases:
  - ip: "10.102.58.104"  # ingress-nginx-controller ClusterIP
    hostnames:
      - "identity.yas.test.com"
      - "backoffice.yas.test.com"
      - "storefront.yas.test.com"
      - "api.yas.test.com"
```
Dùng lệnh "kubectl get all -n ingress-nginx" và tìm đến ingress-nginx-controller, thay thế ip trên bằng IP đang tồn tại

Do giới hạn tài nguyên nên chỉ một trong hai môi trường là Dev và Staging được mở hoặc cả hai cùng tắt.
Tại folder dev hoặc staging, tìm đến file values-shared.yaml và chỉnh các trường replica như ví dụ bên dưới:

```yaml
backend:
  replicaCount: 0 # bật số này lên 1
  databaseConnectionUrl: jdbc:postgresql://postgresql.postgres.svc.cluster.local:5432
  livenessProbe:
    initialDelaySeconds: 120
  readinessProbe:
    initialDelaySeconds: 120
  ingress:
    className: nginx
  service:
    type: ClusterIP
  javaOpts: "-Xmx384m -Xms256m"
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
ui:
  replicaCount: 0 # bật dàn số 0 trở xuống là 1
replicaCount: 0
reloader:
  reloader:
    deployment:
      replicas: 0
```

Vào trong folder services, tìm đến file nginx-api-gateway.yaml và chỉnh phần Deployment như ví dụ:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: yas-dev
spec:
  replicas: 0 # Bật số 0 lên 1
  selector:
    matchLabels:
      app: nginx
```

Khi muốn tắt thì hãy bật 1 về 0.

## 3. Xoá làm lại

Sử dụng các lệnh dưới đây để setup lại từ đầu

```shell
kubectl delete namespace postgres
kubectl delete namespace kafka
kubectl delete namespace keycloak
kubectl delete namespace elasticsearch
kubectl delete namespace redis
kubectl delete namespace observability
kubectl delete namespace cert-manager
kubectl delete namespace zookeeper

# Xóa Helm releases còn sót lại (nếu có)
helm list -A

# Xóa Keycloak CRDs
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl delete -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
```

## 4. Lưu ý

- Việc deploy ứng dụng rất là lâu dù có dùng ArgoCD, ước tính là 5-10p là các ứng dụng có thể lên được. (Chưa kể sẽ có vài pods sẽ bị Out of memory nên phần này không thể tránh được)

- Khi cần thay đổi về thông số ứng dụng hay hạ tầng, sửa ở Repository này, nghiêm cấm sửa ở Repository đang chứa ứng dụng.

- Repository này Jenkins đã được cấp quyền để được cập nhật tag value latest (mã hash của nó) và tag version. Nghĩa là nó có quyền commit và ghi đè nội dung hiện có nên khi vào Repo này nhớ "git pull" liên tục.

- Hạn chế mở quá nhiều môi trường cùng lúc vì tài nguyên là hữu hạn, không thể sinh ra quá nhiều môi trường để phá. Đặc biệt ở Job Developer_build, xài xong là phải bật Job developer_clean liền. Lý do, hệ thống sẽ deploy tận 15-20 Services.

- Job Developer_build là deploy hệ thống bằng cách là NHẬP TAY. Dù dùng bất kì công cụ CI nào thì yêu cầu developer_build và clean là NHẬP TAY, không phải tự động hoàn toàn.

- Deploy môi trường Dev và Staging mới tự động hoàn toàn theo quy trình CI/CD. (cần Repo số hai, không dùng Repo gốc vì sẽ gây trạng thái lặp vô hạn).

## 5. Môi trường đang sử dụng

- Một Virtual Machine thông số CPU 6 core và 48GB RAM, Jenkins được cài sẵn ở trên máy VM, theo đúng flow yêu cầu của bài tập sinh viên.

- Sử dụng minikube làm cluster chính để học tập và thực hành làm đồ án.

- Jenkins sẽ deploy ứng dụng từ Repository này, không phải từ Repository gốc.

- Đồ án này được sử dụng với mục đích là học tập và tìm hiểu cách để mà áp dụng quy trình CI/CD.