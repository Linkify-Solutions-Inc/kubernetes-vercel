nodeSelector:
  karpenter.sh/controller: "true"

dnsPolicy: Default

settings:
  clusterName: ${cluster_name}
  clusterEndpoint: ${cluster_endpoint}
  interruptionQueue: ${interruption_queue}
  enableZonalShift: true

webhook:
  enabled: false

controller:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 1
      memory: 512Mi
