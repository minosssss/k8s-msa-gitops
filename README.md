# ☸️ k8s-msa-gitops

> **GitOps-driven MSA on Kubernetes**  
> Production-grade 쿠버네티스 MSA 구성을 GitOps 방식으로 관리하는 저장소

---

## 🏗️ Architecture

```
                        ┌─────────────────────────────────────┐
                        │           External Traffic           │
                        └──────────────┬──────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │    HAProxy LB    │
                              │  Active-Active   │
                              └────────┬────────┘
                                       │ :80
                         ┌─────────────▼─────────────┐
                         │     NGINX Gateway Fabric    │
                         │      Gateway API v1.4.1     │
                         └─────────────┬─────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │           Frontend (nginx)            │
                    └──────────────────┬──────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │           BFF / API Gateway           │
                    └──────┬────────────┬────────┬─────────┘
                           │            │        │
               ┌───────────▼──┐  ┌──────▼───┐  ┌▼──────────────────┐
               │  User Service │  │  Order   │  │ Notification Svc  │
               │              │  │ Service  │  │                   │
               └──────┬───────┘  └───┬──┬───┘  └───────────────────┘
                      │              │  │
                      │         ┌────┘  └──── (calls notification)
                      │         │
              ┌───────▼─────────▼────────┐
              │        PostgreSQL         │
              │  Primary ──── Replica    │
              │  (write)      (read)      │
              └──────────────────────────┘
```

---

## 🗂️ Repository Structure

```
k8s-msa-gitops/
├── apps/                          # 애플리케이션 계층
│   ├── frontend/                  # nginx 정적 서빙 + BFF 프록시
│   ├── bff/                       # API Gateway / 서비스 집약
│   ├── user-svc/                  # 사용자 관리 서비스
│   ├── order-svc/                 # 주문 처리 (HPA 자동확장)
│   │   └── hpa.yaml               # CPU 50% → 2~10 replica
│   └── notification-svc/          # 알림 서비스
└── infra/                         # 인프라 계층
    └── db/                        # PostgreSQL Primary/Replica
        ├── primary.yaml
        └── replica.yaml
```

---

## 🔧 Tech Stack

| Layer | Technology |
|---|---|
| **Container Orchestration** | Kubernetes v1.36.1 |
| **CNI** | Calico v3.25 (BGP, CrossSubnet) |
| **GitOps** | Argo CD |
| **Gateway** | NGINX Gateway Fabric v2.6.3 (Gateway API) |
| **Load Balancer** | HAProxy (Active-Active) |
| **Database** | PostgreSQL 15 (Primary/Replica 스트리밍 복제) |
| **Observability** | Prometheus + Grafana (kube-prometheus-stack) |
| **Autoscaling** | HPA (CPU 기반, metrics-server) |
| **Package Manager** | Helm v3 |

---

## 🏛️ Cluster Architecture

```
┌──────────────────────────────────────────────────┐
│               Single Cluster (HA)                 │
│                                                   │
│  ┌─────────────┐      ┌──────────────────────┐   │
│  │  Master-43  │      │     Master-235        │   │
│  │ control-plane│      │ control-plane + worker│   │
│  │  etcd-1     │◀────▶│      etcd-2           │   │
│  │  api-1      │      │      api-2            │   │
│  └─────────────┘      └──────────────────────┘   │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │              Worker-44                       │  │
│  │           (dedicated worker)                 │  │
│  └─────────────────────────────────────────────┘  │
│                                                   │
│  HAProxy → control-plane-endpoint :6443           │
│  Calico BGP + CrossSubnet 직접 라우팅              │
└──────────────────────────────────────────────────┘
```

| Node | Role | IP |
|---|---|---|
| k8s-master-43 | control-plane | 192.168.10.43 |
| k8s-master-235 | control-plane + worker | 192.168.10.235 |
| k8s-worker-44 | worker | 192.168.10.44 |
| HAProxy | LB (WSL2 mirrored) | 192.168.2.35 |

---

## 🚀 GitOps Flow

```
Developer
    │
    │  git push
    ▼
GitHub (k8s-msa-gitops)
    │
    │  poll / webhook
    ▼
Argo CD
    │
    │  sync (if diff detected)
    ▼
Kubernetes Cluster
    │
    ├── apps/frontend
    ├── apps/bff
    ├── apps/user-svc
    ├── apps/order-svc      ← HPA 자동확장
    ├── apps/notification-svc
    └── infra/db            ← Primary/Replica
```

**배포 = `kubectl apply` 대신 `git push`**  
**롤백 = `git revert`**  
**감사 로그 = `git log`**

---

## ⚡ Key Features

### 📊 HPA 자동확장
```
order-svc CPU > 50%
    → HPA 발동
    → replica: 2 → max 10
    → Grafana 대시보드로 실시간 확인
```

### 🗄️ DB 읽기/쓰기 분리
```
쓰기 (INSERT/UPDATE) → pg-write-svc → Primary
읽기 (SELECT)        → pg-read-svc  → Replica
```

### 🔍 관측성 스택
```
Prometheus  → 메트릭 수집 (30s 주기)
Grafana     → 대시보드 시각화
             ├── HOST 인프라 (CPU/메모리/디스크/네트워크)
             ├── HPA 스케일 이력
             └── MSA 서비스 상태
```

---

## 📋 Service Communication

```
BFF → user-svc          GET /users
BFF → order-svc         POST /orders, GET /orders
BFF → notification-svc  GET /notifications

order-svc → user-svc          사용자 확인
order-svc → notification-svc  주문 완료 알림

모두 ClusterIP DNS:
  http://user-svc.default.svc.cluster.local
  http://order-svc.default.svc.cluster.local
  http://notification-svc.default.svc.cluster.local
```

---

## 🔒 Secret Management

> ⚠️ Secret은 Git에 포함되지 않습니다.
> 클러스터에 직접 적용하거나 Sealed Secrets / External Secrets Operator 사용 권장.

```bash
# Secret은 별도 적용
kubectl apply -f secrets/  # Git 미포함
```

---

## 🗺️ Learning Journey

이 저장소는 아래 학습 과정의 실습 결과물입니다:

- [x] Docker Compose → Kubernetes 마이그레이션
- [x] 멀티클러스터 + Calico BGP 클러스터 간 네트워킹
- [x] PostgreSQL 스트리밍 복제 + 양방향 DR (Failover/Failback)
- [x] 단일 클러스터 마스터 HA (etcd quorum 실증)
- [x] MSA 3-tier + HPA 자동확장
- [x] 관측성 (Prometheus + Grafana)
- [x] GitOps (Argo CD)
- [ ] 배포 전략 (Canary / Blue-Green / Argo Rollouts)
- [ ] NetworkPolicy (서비스 간 트래픽 격리)
- [ ] 클라우드 실배포 (EKS/GKE)

---

## 📝 Troubleshooting Notes

실습 중 실제로 겪고 해결한 주요 이슈들:

| 이슈 | 원인 | 해결 |
|---|---|---|
| ECMP 비대칭 라우팅 | 마스터 BGP 피어 중복 광고 | 마스터 피어 제거 |
| SNAT 노드 IP | natOutgoing + 다른 IPPool | pg_hba에 노드 IP 허용 |
| NodePort 일부 노드 먹통 | externalTrafficPolicy: Local + Pod 없는 노드 | NginxProxy로 Cluster 전환 |
| etcd quorum 오해 | kubelet 중지로는 etcd 안 죽음 | manifest 이동 또는 셧다운 |
| HAProxy L7 체크 실패 | HTTP/1.0 + Host 헤더 없음 | L4 tcp-check 전환 |

---

<div align="center">

**Built with ❤️ on Kubernetes**

`k8s` `gitops` `argocd` `prometheus` `grafana` `calico` `postgresql` `msa` `hpa`

</div>
