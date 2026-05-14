# Những thiết lập được thay đổi 

- Kí hiệu: DevOps-YAS -> Repository Application, ArgoCD-Advanced -> Repository Configuration.

- Ở Repository DevOps-YAS, quy trình CI Pipeline sẽ hoạt động ở trên Application, Developer sẽ không cần quan tâm về vấn đề cấu hình K8S.

- Ở Repository ArgoCD-Advanced, quy trình cho Job Developer_Build hay ArgoCD sẽ đều thực hiện ở trên đây (thực hiện yêu cầu 4, 5, nâng cao 1 và nâng cao 2).

- Ở Repository Configuration, Repo này sử dụng folder k8s của Repository Application làm gốc và tuỳ biến. Thay vì sử dụng là đường dẫn yas.local.com thì thay đổi như sau:

    + Môi trường Test: yas.test.com
    + Môi trường Dev: yas.dev.com
    + Môi trường Staging: yas.staging.com

# Một số thay đổi so với Repository gốc

- Sủa đôi đường dẫn của backoffice-bff và storefront-bff ở các đoạn này trong file resources/application.yaml. Lý do, image gốc của nashtech-garage build bị lỗi dẫn đến không truy cập được vào đường dẫn

```yaml
# backoffice-bff
spring:
  config:
    activate:
      on-profile: "prod"
  cloud:
    gateway:
      default-filters:
        - SaveSession
      routes:
        - id: api
          uri: http://nginx
          predicates:
            - Path=/api/**
          filters:
            - DedupeResponseHeader=Origin Access-Control-Request-Method Access-Control-Request-Headers
            - TokenRelay=
            - StripPrefix=1
        - id: nextjs
          uri: http://backoffice-ui:3000 # sửa này thành ui thay vì next-js, đồng thời build và push image mới lên dockerhub
          # Làm tương tự như vậy cho storefront-bff
          predicates:
            - Path=/**

```

Sửa một số lỗi chính tả ở file k8s/deploy/postgres/postgresql/templates/postgresql.yaml
```yaml
# Trước khi sửa
databases:
    cart: {{ .Values.username }}
    customer: {{ .Values.username }}
    inventory: {{ .Values.username }}
    keycloak: {{ .Values.username }}
    location: {{ .Values.username }}
    media: {{ .Values.username }}
    order: {{ .Values.username }}
    payment: {{ .Values.username }}
    product: {{ .Values.username }}
    promotion: {{ .Values.username }}
    rating: {{ .Values.username }}
    tax: {{ .Values.username }}
    recommendation: { { .Values.username } } 
    webhook: { { .Values.username } }
    grafana: {{ .Values.username }}
```

```yaml
# Sau khi sửa
databases:
    cart: {{ .Values.username }}
    customer: {{ .Values.username }}
    inventory: {{ .Values.username }}
    keycloak: {{ .Values.username }}
    location: {{ .Values.username }}
    media: {{ .Values.username }}
    order: {{ .Values.username }}
    payment: {{ .Values.username }}
    product: {{ .Values.username }}
    promotion: {{ .Values.username }}
    rating: {{ .Values.username }}
    tax: {{ .Values.username }}
    recommendation: {{ .Values.username }}
    webhook: {{ .Values.username }}
    grafana: {{ .Values.username }}
```

Bổ sung một file tên là nginx-api-gateway.yaml có nội dung như dưới đây cho Swagger-UI có thể thao tác và truy vấn đến các Business Logic. Lý do: ở docker-compose.yaml thì có định nghĩa ngnix cho Services nhưng k8s thì lại không
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-api-config
  # Change your namespace here
  namespace: yas
data:
  default.conf: |
    server {
      listen 80;

      # Kubernetes CoreDNS
      resolver 10.96.0.10 valid=10s;

      # Change your domain here with your namespace.svc.cluster.local
      location /media/ {
        set $upstream "media.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /product/ {
        set $upstream "product.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /customer/ {
        set $upstream "customer.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /cart/ {
        set $upstream "cart.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /rating/ {
        set $upstream "rating.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /order/ {
        set $upstream "order.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /location/ {
        set $upstream "location.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /inventory/ {
        set $upstream "inventory.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /tax/ {
        set $upstream "tax.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /promotion/ {
        set $upstream "promotion.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
      location /search/ {
        set $upstream "search.yas.svc.cluster.local";
        proxy_pass http://$upstream;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: yas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: config
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: config
          configMap:
            name: nginx-api-config
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: yas
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-api-gateway
  namespace: yas
spec:
  ingressClassName: nginx
  rules:
    - host: api.yas.test.com
      http:
        paths:
          - path: /cart
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /customer
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /media
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /product
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /rating
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /order
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /location
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /inventory
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /tax
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
          - path: /search
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
```
Sau khi đã thêm vào thành phần nginx trên, ở job Developer Build, cần có phase để deploy phần này tự động thay vì thủ công:
```groovy
stage('Apply Namespace API Gateway (Swagger)') {
	steps {
		script {
			applyNamespaceApiGateway(this, env.CHARTS_DIR, env.TEST_NAMESPACE, env.DEPLOY_DOMAIN)
		}
	}
}
```
```groovy
def applyNamespaceApiGateway(def scriptCtx, String chartsDir, String namespace, String deployDomain) {
	def gatewayManifest = "${chartsDir}/infrastructure/scripts/nginx-api-gateway.yaml"

	scriptCtx.sh """
		set -e
		if [ ! -f '${gatewayManifest}' ]; then
			echo "Skipping API gateway apply: '${gatewayManifest}' not found."
			exit 0
		fi

		TMP_MANIFEST=\$(mktemp)
		cp '${gatewayManifest}' "\$TMP_MANIFEST"

		# Replace hardcoded namespace and host with the current developer namespace and domain.
		sed -i "s|namespace: test-minhhuy-baseline|namespace: ${namespace}|g" "\$TMP_MANIFEST"
		sed -i "s|\\.test-minhhuy-baseline\\.svc\\.cluster\\.local|.${namespace}.svc.cluster.local|g" "\$TMP_MANIFEST"
		sed -i "s|host: api.yas.test.com|host: api.${deployDomain}|g" "\$TMP_MANIFEST"

		kubectl apply -f "\$TMP_MANIFEST"
		kubectl rollout status deployment/nginx -n '${namespace}' --timeout=180s
		rm -f "\$TMP_MANIFEST"

		echo "Applied namespace-scoped API gateway to namespace '${namespace}' with host 'api.${deployDomain}'."
	"""
}
```
Thay đổi tag phiên bản của Swagger-Ui từ phiên bản 4.16 lên phiên bản 5.32.4 vì phiên bản cũ ngừng hỗ trợ dẫn đến không hiển thị được các lệnh gọi API
```yaml
# Trước
image:
  repository: swaggerapi/swagger-ui
  pullPolicy: IfNotPresent
  # Overrides the image tag whose default is the chart appVersion.
  tag: "v4.16.0"
```

```yaml
# Sau
image:
  repository: swaggerapi/swagger-ui
  pullPolicy: IfNotPresent
  # Overrides the image tag whose default is the chart appVersion.
  tag: "v5.32.4"
```
Ngoài ra, khi mà Developer truy cập vào trang cho khách hàng, một số hình ảnh lại không thể được load lên và bị trả lỗi 500 là do cấu hình k8s không mount dữ liệu của Sample Data vào service Media dẫn đến không hiện được hình ảnh, bổ sung thêm phase này ở Jenkinsfile.build 
```groovy
def seedMediaAssets(def scriptCtx, String namespace, String workspaceDir) {
	def sampleImagesPath = "${workspaceDir}/sampledata/images/sample"

	scriptCtx.sh """
		set -e
		if [ ! -d '${sampleImagesPath}' ]; then
			echo "Skipping media asset seeding: '${sampleImagesPath}' not found."
			exit 0
		fi

		kubectl rollout status deployment/media -n '${namespace}' --timeout=180s
		MEDIA_POD=\$(kubectl get pod -n '${namespace}' -l app.kubernetes.io/name=media -o jsonpath='{.items[0].metadata.name}')
		if [ -z "\$MEDIA_POD" ]; then
			echo "Skipping media asset seeding: media pod not found in namespace '${namespace}'."
			exit 0
		fi

		kubectl exec -n '${namespace}' "\$MEDIA_POD" -- mkdir -p /images
		kubectl cp '${sampleImagesPath}' '${namespace}/'"\$MEDIA_POD":/images/
		echo "Media assets seeded to pod '\$MEDIA_POD' in namespace '${namespace}'."
	"""
}
```

```groovy
stage('Seed Media Assets') {
	steps {
		script {
			seedMediaAssets(this, env.TEST_NAMESPACE, env.WORKSPACE)
		}
	}
}
```

Ngoài ra, thêm port 9200 cho ElasticSearch ở trong file k8s/charts/yas-configuration/values.yaml
```yaml
# Trước
searchApplicationConfig:
  elasticsearch:
    url: elasticsearch-es-http.elasticsearch
    username: ${ELASTICSEARCH_USERNAME}
    password: ${ELASTICSEARCH_PASSWORD}
```

```yaml
# Sau
searchApplicationConfig:
  elasticsearch:
    url: elasticsearch-es-http.elasticsearch:9200
    username: ${ELASTICSEARCH_USERNAME}
    password: ${ELASTICSEARCH_PASSWORD}
```