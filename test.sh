#!/bin/bash
set -e 
export MY_EMAIL="gui.franchin12@gmail.com"
export MY_DOMAIN="franch.in"

rm -rf cluster cluster.bak kubernetes

mkdir -p cluster/core
mkdir -p cluster/apps
mkdir -p kubernetes/core/ingress-nginx
mkdir -p kubernetes/core/cert-manager
mkdir -p kubernetes/apps/media/plex

cat <<EOF > cluster/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - core
  - apps
EOF

cat <<EOF > cluster/core/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ingress-nginx.yaml
  - cert-manager.yaml
EOF

cat <<EOF > cluster/core/ingress-nginx.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 10m
  path: ./kubernetes/core/ingress-nginx
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
EOF

cat <<EOF > cluster/core/cert-manager.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: cert-manager
  namespace: flux-system
spec:
  interval: 10m
  path: ./kubernetes/core/cert-manager
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: ingress-nginx
EOF

cat <<EOF > cluster/apps/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - media-stack.yaml
EOF

cat <<EOF > cluster/apps/media-stack.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: media-stack
  namespace: flux-system
spec:
  interval: 10m
  path: ./kubernetes/apps/media
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: cert-manager
EOF

cat <<EOF > kubernetes/core/ingress-nginx/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - helm-repository.yaml
  - helm-release.yaml
EOF

cat <<EOF > kubernetes/core/ingress-nginx/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: networking
EOF

cat <<EOF > kubernetes/core/ingress-nginx/helm-repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 2h
  url: https://kubernetes.github.io/ingress-nginx
EOF

cat <<EOF > kubernetes/core/ingress-nginx/helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: networking
spec:
  interval: 30m
  chart:
    spec:
      chart: ingress-nginx
      version: 4.8.3
      sourceRef: {kind: HelmRepository, name: ingress-nginx, namespace: flux-system}
  install: {createNamespace: false}
  upgrade:
    remediation:
      retries: 3
  values:
    controller:
      service: {type: LoadBalancer}
      ingressClassResource: {name: nginx, enabled: true, default: true, controllerValue: "k8s.io/ingress-nginx"}
EOF

cat <<EOF > kubernetes/core/cert-manager/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helm-repository.yaml
  - helm-release.yaml
  - letsencrypt-issuer.yaml
EOF

cat <<EOF > kubernetes/core/cert-manager/helm-repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 2h
  url: https://charts.jetstack.io
EOF

cat <<EOF > kubernetes/core/cert-manager/helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 30m
  chart:
    spec:
      chart: cert-manager
      version: v1.13.2
      sourceRef: {kind: HelmRepository, name: jetstack, namespace: flux-system}
  install: {createNamespace: true, crds: Create}
  upgrade: {crds: CreateReplace}
EOF

cat <<EOF > kubernetes/core/cert-manager/letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${MY_EMAIL}
    privateKeySecretRef: {name: letsencrypt-production-key}
    solvers:
    - http01: {ingress: {class: nginx}}
EOF

cat <<EOF > kubernetes/apps/media/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - plex/
EOF

cat <<EOF > kubernetes/apps/media/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: media
EOF

cat <<EOF > kubernetes/apps/media/plex/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helm-repository.yaml
  - helm-release.yaml
EOF

cat <<EOF > kubernetes/apps/media/plex/helm-repository.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: bjw-s-charts
  namespace: flux-system
spec:
  interval: 2h
  url: https://bjw-s.github.io/helm-charts/
EOF

cat <<EOF > kubernetes/apps/media/plex/helm-release.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: plex
  namespace: media
spec:
  interval: 15m
  chart:
    spec:
      chart: app-template
      version: 2.4.0
      sourceRef: {kind: HelmRepository, name: bjw-s-charts, namespace: flux-system}
  values:
    image: {repository: lscr.io/linuxserver/plex, tag: latest}
    service:
      main: {ports: {http: {port: 32400}}}
    ingress:
      main:
        enabled: true
        annotations:
          cert-manager.io/cluster-issuer: "letsencrypt-production"
          kubernetes.io/ingress.class: "nginx"
        hosts:
        - host: "plex.${MY_DOMAIN}"
          paths:
          - {path: /, pathType: Prefix}
        tls:
        - secretName: plex-tls-cert
          hosts:
          - "plex.${MY_DOMAIN}"
    persistence:
      config: {enabled: true, mountPath: /config, type: hostPath, hostPath: /srv/k3s/configs/plex}
      media: {enabled: true, mountPath: /media, type: hostPath, hostPath: /mnt/media}
      transcode: {enabled: true, type: hostPath, hostPath: /srv/kths/configs/plex/transcode}
    env: {TZ: "America/Sao_Paulo"}
EOF
