apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: "${node_role}"
  subnetSelectorTerms:
    - tags:
        "karpenter.sh/discovery": "${cluster_name}"
  securityGroupSelectorTerms:
    - tags:
        "kubernetes.io/cluster/${cluster_name}": "owned"
  metadataOptions:
    httpTokens: required
