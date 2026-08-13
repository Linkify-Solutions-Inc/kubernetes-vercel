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

# Single replica: the chart's default of 2 uses hard pod anti-affinity, which
# cannot be satisfied on a one-node cluster (the second replica Pends forever).
replicas: 1

controller:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 1
      memory: 512Mi
