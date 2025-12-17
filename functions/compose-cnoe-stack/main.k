import models.io.crossplane.helm.v1beta1 as helmv1beta1
import models.io.crossplane.kubernetes.v1alpha2 as kubernetesv1alpha2
import models.io.crossplane.kubernetes.v1alpha1 as kubernetesv1alpha1
import models.io.upbound.platform.aws.v1alpha1 as platformawsv1alpha1
import models.io.upbound.platform.observe.v1alpha1 as observev1alpha1
import models.io.upbound.aws.iam.v1beta1 as iamv1beta1
import models.io.upbound.aws.eks.v1beta1 as eksv1beta1
import models.io.upbound.aws.route53.v1beta1 as route53v1beta1
import models.io.upbound.platform.gitops.v1alpha1 as gitopsv1alpha1
import regex
import json

# observed composite resource
oxr = option("params").oxr
# observed composed resources
_ocds = option("params").ocds
# desired composite resource
_dxr = option("params").dxr
# desired composed resources
dcds = option("params").dcds
ctx = option("params").ctx

# Helper functions
_metadata = lambda name: str -> any {
    {
        annotations = {"krm.kcl.dev/composition-resource-name" = name}
    }
}

_metadataWithClusterLabel = lambda name: str -> any {
    {
        **_metadata(name)
        labels = {
            "cnoe.io/cluster" = oxr.spec.parameters.id
        }
    }
}

ready = lambda o: any, statusPath = "atProvider" -> bool {
    status = o?.Resource?.status
    objstatus = status?.conditions or []
    len(objstatus) > 0 and all_true([c.status == "True" for c in objstatus])
}

exists: (str) -> bool = lambda o: str -> bool {
    resource = get(_ocds, o, {})
    resource != {}
}

get = lambda x: any, y: str, d: any -> any {
    """
        Get an item from a dictionary using a dot separated path.
        If the item is not found, return a default value.
    """
    p = regex.split(y, "\.")
    c = p[0]
    y = ".".join(p[1::])
    x[c] if len(p) == 1 and c in x else d if c not in x else get(x[c], y, d)
}

# Default variables
_region = "eu-west-1"
if oxr.spec?.parameters?.region:
    _region = oxr.spec.parameters.region

_azs = [_region + code for code in ["a", "b", "c"]]

_subnets = [
    {
        availabilityZone = _azs[0]
        cidrBlock = "192.168.0.0/18"
        type = "public"
    }
    {
        availabilityZone = _azs[1]
        cidrBlock = "192.168.64.0/18"
        type = "public"
    }
    {
        availabilityZone = _azs[0]
        cidrBlock = "192.168.128.0/18"
        type = "private"
    }
    {
        availabilityZone = _azs[1]
        cidrBlock = "192.168.192.0/18"
        type = "private"
    }
]

# Route53 Zone
xRoute53Zone = route53v1beta1.Zone {
    metadata = {
        annotations = {
            **_metadata("route53zone").annotations
            "crossplane.io/external-name" = oxr.spec?.parameters?.route53zoneId if oxr.spec?.parameters?.route53zoneId != None else "Z0000000000000000000"
        }
    }
    spec = {
        managementPolicies = ["Observe"]
        deletionPolicy = "Orphan"
        forProvider = {
            # Route53 is a global service, but must be managed in us-east-1
            region = "us-east-1"
        }
    }
}

_items: [any] = [xRoute53Zone]

# Update the dxr status immutably
_dxr = {
    **_dxr
    status: {
        cnoe: {
            route53Zone: {
                name: _ocds["route53zone"]?.Resource?.status?.atProvider?.name
            }
            keycloak: {
                argoCD: {
                    clientSecret: "{}".format(oxr.metadata.uid)
                }
            }
        }
    }
}

_items += [_dxr]

# External resources to be created as part of this composition.
_items += [
    # VPC
    platformawsv1alpha1.XNetwork {
        metadata = _metadata("xnetwork")
        spec = {
            parameters = {
                id = oxr.spec.parameters.id
                region = _region
                vpcCidrBlock = "192.168.0.0/16"
                subnets = _subnets
                deletionPolicy = oxr.spec?.parameters?.deletionPolicy
            }
        }
    }
    # EKS Cluster
    platformawsv1alpha1.XEKS {
        metadata = _metadataWithClusterLabel("xeks")
        spec = {
            parameters = {
                id = oxr.spec.parameters.id
                region = _region
                version = oxr.spec?.parameters?.version if oxr.spec?.parameters?.version != None else "1.33"
                nodes = {
                    count = oxr.spec?.parameters?.nodes?.count if oxr.spec?.parameters?.nodes?.count != None else 3
                    instanceType = oxr.spec?.parameters?.nodes?.instanceType if oxr.spec?.parameters?.nodes?.instanceType != None else "t3.small"
                }
                accessConfig = {
                    bootstrapClusterCreatorAdminPermissions = True
                    authenticationMode = "API_AND_CONFIG_MAP"
                }
                deletionPolicy = oxr.spec?.parameters?.deletionPolicy
            }
            writeConnectionSecretToRef = {
                name = "{}-{}".format(oxr.metadata.name, "kubeconfig")
                namespace = "crossplane-system"
            }
        }
    }
    # IAM Role for AWS Load Balancer Controller (used with EKS Pod Identity)
    iamv1beta1.Role {
        metadata = {
            **_metadata("aws-load-balancer-controller-role")
            labels = {
                role = "aws-load-balancer-controller"
            }
        }
        spec = {
            forProvider = {
                assumeRolePolicy = json.encode({
                    Version = "2012-10-17"
                    Statement = [{
                        Effect = "Allow"
                        Principal = {
                            Service = "pods.eks.amazonaws.com"
                        }
                        Action = [
                            "sts:AssumeRole"
                            "sts:TagSession"
                        ]
                    }]
                })
            }
        }
    }
    # IAM Role Policy for AWS Load Balancer Controller
    iamv1beta1.RolePolicy {
        metadata = _metadata("aws-load-balancer-controller-policy")
        spec = {
            forProvider = {
                roleSelector = {
                    matchControllerRef = True
                    matchLabels = {
                        role = "aws-load-balancer-controller"
                    }
                }
                policy = json.encode({
                    Version = "2012-10-17"
                    Statement = [
                        {
                            Effect = "Allow"
                            Action = [
                                "iam:CreateServiceLinkedRole"
                            ]
                            Resource = "*"
                            Condition = {
                                StringEquals = {
                                    "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:DescribeAccountAttributes"
                                "ec2:DescribeAddresses"
                                "ec2:DescribeAvailabilityZones"
                                "ec2:DescribeInternetGateways"
                                "ec2:DescribeVpcs"
                                "ec2:DescribeVpcPeeringConnections"
                                "ec2:DescribeSubnets"
                                "ec2:DescribeSecurityGroups"
                                "ec2:DescribeInstances"
                                "ec2:DescribeNetworkInterfaces"
                                "ec2:DescribeTags"
                                "ec2:GetCoipPoolUsage"
                                "ec2:DescribeCoipPools"
                                "elasticloadbalancing:DescribeLoadBalancers"
                                "elasticloadbalancing:DescribeLoadBalancerAttributes"
                                "elasticloadbalancing:DescribeListeners"
                                "elasticloadbalancing:DescribeListenerCertificates"
                                "elasticloadbalancing:DescribeSSLPolicies"
                                "elasticloadbalancing:DescribeRules"
                                "elasticloadbalancing:DescribeTargetGroups"
                                "elasticloadbalancing:DescribeTargetGroupAttributes"
                                "elasticloadbalancing:DescribeTargetHealth"
                                "elasticloadbalancing:DescribeTags"
                                "elasticLoadbalancing:DescribeListenerAttributes"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "cognito-idp:DescribeUserPoolClient"
                                "acm:ListCertificates"
                                "acm:DescribeCertificate"
                                "iam:ListServerCertificates"
                                "iam:GetServerCertificate"
                                "waf-regional:GetWebACL"
                                "waf-regional:GetWebACLForResource"
                                "waf-regional:AssociateWebACL"
                                "waf-regional:DisassociateWebACL"
                                "wafv2:GetWebACL"
                                "wafv2:GetWebACLForResource"
                                "wafv2:AssociateWebACL"
                                "wafv2:DisassociateWebACL"
                                "shield:GetSubscriptionState"
                                "shield:DescribeProtection"
                                "shield:CreateProtection"
                                "shield:DeleteProtection"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:AuthorizeSecurityGroupIngress"
                                "ec2:RevokeSecurityGroupIngress"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:CreateSecurityGroup"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:CreateTags"
                            ]
                            Resource = "arn:aws:ec2:*:*:security-group/*"
                            Condition = {
                                StringEquals = {
                                    "ec2:CreateAction" = "CreateSecurityGroup"
                                }
                                Null = {
                                    "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:CreateTags"
                                "ec2:DeleteTags"
                            ]
                            Resource = "arn:aws:ec2:*:*:security-group/*"
                            Condition = {
                                Null = {
                                    "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
                                    "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "ec2:AuthorizeSecurityGroupIngress"
                                "ec2:RevokeSecurityGroupIngress"
                                "ec2:DeleteSecurityGroup"
                            ]
                            Resource = "*"
                            Condition = {
                                Null = {
                                    "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:CreateLoadBalancer"
                                "elasticloadbalancing:CreateTargetGroup"
                            ]
                            Resource = "*"
                            Condition = {
                                Null = {
                                    "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:CreateListener"
                                "elasticloadbalancing:DeleteListener"
                                "elasticloadbalancing:CreateRule"
                                "elasticloadbalancing:DeleteRule"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:AddTags"
                                "elasticloadbalancing:RemoveTags"
                            ]
                            Resource = [
                                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
                                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*"
                                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
                            ]
                            Condition = {
                                Null = {
                                    "aws:RequestTag/elbv2.k8s.aws/cluster" = "true"
                                    "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:AddTags"
                                "elasticloadbalancing:RemoveTags"
                            ]
                            Resource = [
                                "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*"
                                "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*"
                                "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*"
                                "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
                            ]
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:ModifyLoadBalancerAttributes"
                                "elasticloadbalancing:SetIpAddressType"
                                "elasticloadbalancing:SetSecurityGroups"
                                "elasticloadbalancing:SetSubnets"
                                "elasticloadbalancing:DeleteLoadBalancer"
                                "elasticloadbalancing:ModifyTargetGroup"
                                "elasticloadbalancing:ModifyTargetGroupAttributes"
                                "elasticloadbalancing:DeleteTargetGroup"
                            ]
                            Resource = "*"
                            Condition = {
                                Null = {
                                    "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:AddTags"
                            ]
                            Resource = [
                                "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
                                "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*"
                                "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
                            ]
                            Condition = {
                                StringEquals = {
                                    "elasticloadbalancing:CreateAction" = [
                                        "CreateTargetGroup"
                                        "CreateLoadBalancer"
                                    ]
                                }
                                Null = {
                                    "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
                                }
                            }
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:RegisterTargets"
                                "elasticloadbalancing:DeregisterTargets"
                            ]
                            Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
                        }
                        {
                            Effect = "Allow"
                            Action = [
                                "elasticloadbalancing:SetWebAcl"
                                "elasticloadbalancing:ModifyListener"
                                "elasticloadbalancing:AddListenerCertificates"
                                "elasticloadbalancing:RemoveListenerCertificates"
                                "elasticloadbalancing:ModifyRule"
                            ]
                            Resource = "*"
                        }
                    ]
                })
            }
        }
    }
    # IAM Role for External DNS (used with EKS Pod Identity)
    iamv1beta1.Role {
        metadata = {
            **_metadata("external-dns-role")
            labels = {
                role = "external-dns"
            }
        }
        spec = {
            forProvider = {
                assumeRolePolicy = json.encode({
                    Version = "2012-10-17"
                    Statement = [{
                        Effect = "Allow"
                        Principal = {
                            Service = "pods.eks.amazonaws.com"
                        }
                        Action = [
                            "sts:AssumeRole"
                            "sts:TagSession"
                        ]
                    }]
                })
            }
        }
    }
    # IAM Role Policy for External DNS
    iamv1beta1.RolePolicy {
        metadata = _metadata("external-dns-policy")
        spec = {
            forProvider = {
                roleSelector = {
                    matchControllerRef = True
                    matchLabels = {
                        role = "external-dns"
                    }
                }
                policy = json.encode({
                    Version = "2012-10-17"
                    Statement = [
                        {
                            Effect = "Allow"
                            Action = [
                                "route53:ListResourceRecordSets"
                                "route53:ListHostedZones"
                            ]
                            Resource = "*"
                        }
                        {
                            Effect = "Allow"
                            Action = "route53:ChangeResourceRecordSets"
                            Resource = "arn:aws:route53:::hostedzone/{}".format(oxr.spec?.parameters?.route53zoneId if oxr.spec?.parameters?.route53zoneId != None else "*")
                        }
                    ]
                })
            }
        }
    }
    ## kubernetes-provider to manage resources inside control plane cluster
    kubernetesv1alpha1.ProviderConfig {
        metadata = {
            name = "{}-controlplane".format(oxr.spec.parameters.id)
            generateName = "{}-controlplane-".format(oxr.spec.parameters.id)
            annotations = {                
                "krm.kcl.dev/ready": "True"
                **_metadata("controlplane-provider-config").annotations
            }
        }
        spec = {
            credentials = {
                source = "InjectedIdentity"
            }
        }
    }
    # Keycloak admin credentials secret for the control plane (used by Keycloak provider)
    # This secret must exist in the control plane before the ProviderConfig can use it
    kubernetesv1alpha2.Object {
        metadata = _metadata("keycloak-admin-credentials-controlplane")
        spec = {
            deletionPolicy = oxr.spec?.parameters?.deletionPolicy
            providerConfigRef = {
                name = "{}-controlplane".format(oxr.spec.parameters.id)
            }
            forProvider = {
                manifest = {
                    apiVersion = "v1"
                    kind = "Secret"
                    metadata = {
                        name = "{}-keycloak".format(oxr.spec.parameters.id)
                        namespace = "crossplane-system"
                    }
                    type = "Opaque"
                    stringData = {
                        credentials = json.encode({
                            client_id: "admin-cli"
                            client_secret: "admin"
                            username: "admin"
                            password: "admin"
                            realm: "master"
                            url: "https://keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name if _ocds["route53zone"]?.Resource?.status?.atProvider?.name else "placeholder.example.com")
                        })
                    }
                }
            }
        }
    }
    # Key-Cloak ProviderConfig
    {
        apiVersion = "keycloak.crossplane.io/v1beta1"
        kind = "ProviderConfig"
        metadata = {
            name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
            annotations = {
                "krm.kcl.dev/composition-resource-name" = "keycloak-providerconfig"
                "krm.kcl.dev/ready": "True"
            }
        }
        spec = {
            credentials = {
                source = "Secret"
                secretRef = {
                    namespace = "crossplane-system"
                    name = "{}-keycloak".format(oxr.spec.parameters.id)
                    key = "credentials"
                }
            }
            # tlsInsecureSkipVerify = True
        }
    }
]
eksClusterName = _ocds["xeks"]?.Resource?.status?.eks?.clusterName

# Helm Release for AWS EKS Cluster
if eksClusterName and ready(get(_ocds, "xeks", "")):
    _items += [
        # PodIdentityAssociation for AWS Load Balancer Controller
        eksv1beta1.PodIdentityAssociation {
            metadata = _metadata("aws-load-balancer-controller-pod-identity")
            spec = {
                forProvider = {
                    clusterNameSelector = {
                        matchLabels = {
                            "crossplane.io/composite" = oxr.metadata.name
                        }
                    }
                    namespace = "kube-system"
                    serviceAccount = "aws-load-balancer-controller"
                    roleArn = _ocds["aws-load-balancer-controller-role"]?.Resource?.status?.atProvider?.arn
                    region = _region
                }
            }
        }
        # PodIdentityAssociation for External DNS
        eksv1beta1.PodIdentityAssociation {
            metadata = _metadata("external-dns-pod-identity")
            spec = {
                forProvider = {
                    clusterNameSelector = {
                        matchLabels = {
                            "crossplane.io/composite" = oxr.metadata.name
                        }
                    }
                    namespace = "external-dns"
                    serviceAccount = "external-dns"
                    roleArn = _ocds["external-dns-role"]?.Resource?.status?.atProvider?.arn
                    region = _region
                }
            }
        }
        # Observability stack
        observev1alpha1.XOss {
            metadata = _metadata("xoss")
            spec = {
                parameters = {
                    id = oxr.spec.parameters.id
                    operators = {
                        prometheus = {
                            version = oxr.spec?.parameters?.operators?.prometheus?.version if oxr.spec?.parameters?.operators?.prometheus?.version != None else "52.1.0"
                        }
                    }
                }
            }
        }
        # Helm Release for Crossplane
        helmv1beta1.Release {
            metadata = _metadataWithClusterLabel("cnoe-helmrelease-crossplane")
            spec = {
                deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                providerConfigRef = {
                    name = oxr.spec.parameters.id
                }
                forProvider = {
                    namespace = "crossplane-system"
                    chart: {
                        name = "crossplane"
                        repository = "https://charts.crossplane.io/stable"
                        version = "1.14.3"
                    }
                }
            }
        }
        # Helm Release for AWSLoadBalancerControllerChart Chart
        helmv1beta1.Release {
            metadata = _metadataWithClusterLabel("cnoe-helmrelease-awsLoadBalancerControllerChart")
            spec = {
                deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                providerConfigRef = {
                    name = oxr.spec.parameters.id
                }
                forProvider = {
                    namespace = "kube-system"
                    chart = {
                        name = "aws-load-balancer-controller"
                        repository = "https://aws.github.io/eks-charts"
                        version = "1.14.0"
                    }
                    wait = True
                    values: {
                        serviceAccount: {
                            name: "aws-load-balancer-controller"
                        }
                        region: _region
                        clusterName: eksClusterName
                        vpcId: _ocds["xnetwork"]?.Resource?.status?.vpcId
                        # Disable the race condition with Cert Manager for now.
                        serviceMutatorWebhookConfig: {
                            failurePolicy: "Ignore"
                        }
                        podMutatorWebhookConfig: {
                            failurePolicy: "Ignore"
                        }
                    }
                }
            }
        }
    ]

    # Usage Wave 1: Protect EKS cluster from deletion until all Helm releases are removed.
    # This prevents orphaned Kubernetes resources and resources created in AWS like AWS load balancers.
    _items += [
        {
            apiVersion = "apiextensions.crossplane.io/v1beta1"
            kind = "Usage"
            metadata = {
                **_metadata("usage-helm-releases-protect-eks")
                annotations = {
                    **_metadata("usage-helm-releases-protect-eks").annotations
                    "krm.kcl.dev/ready" = "True"
                }
            }
            spec = {
                replayDeletion = True  # Critical: enables fast cleanup once Helm releases are gone
                of = {
                    # The resource being protected (EKS cluster)
                    apiVersion = "platform.aws.upbound.io/v1alpha1"
                    kind = "XEKS"
                    resourceSelector = {
                        matchLabels = {
                            "cnoe.io/cluster" = oxr.spec.parameters.id ## Label to link Usage to EKS cluster
                        }
                    }
                }
                by = {
                    # The dependent resources (ALL Helm releases)
                    apiVersion = "helm.crossplane.io/v1beta1"
                    kind = "Release"
                    resourceSelector = {
                        matchLabels = {
                            "cnoe.io/cluster" = oxr.spec.parameters.id ## Label to link Usage to Helm releases
                        }
                    }
                }
                reason = "Helm releases must be deleted before EKS cluster to prevent orphaned Kubernetes resources like AWS load balancers."
            }
        }
    ]

    ## external DNS Chart has to wait for the external-dns-pod-identity to be ready, else we need to force restart the pods.
    if ready(get(_ocds, "external-dns-pod-identity", "")):
        _items += [
            # Helm Release for external DNS Chart
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-external-dns")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "external-dns"
                        chart: {
                            name = "external-dns"
                            repository = "https://kubernetes-sigs.github.io/external-dns/"
                            version = "1.19.0"
                        }
                        wait = True
                        values: {
                            replicaCount: 2
                            provider: "aws"
                            policy: "sync"
                            sources: ["ingress"]
                            registry: "txt"
                            txtOwnerId: "external-dns"
                            domainFilters: [_ocds["route53zone"]?.Resource?.status?.atProvider?.name]
                            aws: {
                                batchChangeSize: 5
                                zoneType: "public"
                                # DNS zones are in us-east-1
                                region: "us-east-1"
                            }
                            rbac: {
                                create: True
                            }
                            serviceAccount: {
                                create: True
                                name: "external-dns"
                            }
                            metrics: {
                                enabled: "false"
                                serviceMonitor: {
                                    enabled: "false"
                                }
                                replicas: 2
                                podDisruptionBudget: {
                                    minAvailable: 1
                                }
                            }
                        }
                    }
                }
            }
        ]
    # Cert Manager and nginx-ingress can be installed only after AWS Load Balancer Controller is ready
    if ready(get(_ocds, "cnoe-helmrelease-awsLoadBalancerControllerChart", "")):
        _items += [
            # Helm Release for CertManagerChart Chart
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-cert-manager")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "cert-manager"
                        chart: {
                            name = "cert-manager"
                            repository = "https://charts.jetstack.io"
                            version = "v1.19.1"
                        }
                        wait = True
                        values: {
                            crds: {
                                enabled: True
                                keep: True
                            }
                            global: {
                                leaderElection: {
                                    namespace: "cert-manager"
                                }
                            }
                        }
                    }
                }
            }
            # ClusterIssuer for Let's Encrypt certificate management
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-cluster-issuer")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "cert-manager.io/v1"
                            kind = "ClusterIssuer"
                            metadata = {
                                name = "letsencrypt-prod"
                            }
                            spec = {
                                acme = {
                                    server = "https://acme-v02.api.letsencrypt.org/directory"
                                    privateKeySecretRef = {
                                        name = "letsencrypt-prod"
                                    }
                                    solvers = [
                                        {
                                            http01 = {
                                                ingress = {
                                                    ingressClassName = "nginx"
                                                }
                                            }
                                        }
                                    ]
                                }
                            }
                        }
                    }
                }
            }
            # IngressNginxChart for IngressNginxChart
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-ingress-nginx")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "ingress-nginx"
                        chart: {
                            name = "ingress-nginx"
                            repository = "https://kubernetes.github.io/ingress-nginx"
                            version = "4.7.0"
                        }
                        wait = True # Had to wait. Else, custom-ingress creation fails
                        values: {
                            fullnameOverride: "ingress-nginx"
                            controller: {
                                config: {
                                    hsts: "false"
                                }
                                publishService: {
                                    enabled: True
                                }
                                service: {
                                    name: "ingress-nginx-controller"
                                    enabled: True
                                    type: "LoadBalancer"
                                    annotations: {
                                        "service.beta.kubernetes.io/aws-load-balancer-type" = "external"
                                        "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
                                        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
                                        "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
                                        "service.beta.kubernetes.io/aws-load-balancer-name" = oxr.spec.parameters.id
                                    }
                                    loadBalancerClass: "service.k8s.aws/nlb"
                                    targetPorts: {
                                        https: "https"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # Helm Release for the External Secret Operator
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-external-secrets")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "external-secrets"
                        chart: {
                            name = "external-secrets"
                            repository = "https://charts.external-secrets.io"
                            version = "0.9.2"
                        }
                        wait = True
                        values: {
                            installCRDs: "true"
                        }
                    }
                }
            }
            # ArgoCD Namespace (must be created before ArgoCD)
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-argocd-namespace")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Namespace"
                            metadata = {
                                name = "argocd"
                            }
                        }
                    }
                }
            }
            # ArgoCD client secret (for Keycloak OIDC)
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-argocd-client-secret")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "{}-argocd-client".format(oxr.spec.parameters.id)
                                namespace = "argocd"
                                labels = {
                                    "keycloak.crossplane.io/client-secret" = oxr.metadata.uid
                                }
                            }
                            type = "Opaque"
                            stringData = {
                                clientSecret = "{}".format(oxr.metadata.uid)
                                password = "backstagepassword"
                                database = "backstage"
                                host = "keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                port = "5432"
                            }
                        }
                    }
                }
            }
        ]

    # Usage Wave 2: Protect AWS Load Balancer Controller from deletion before dependent services
    # This prevents orphaned AWS Network Load Balancers and stuck Kubernetes Service finalizers
    _items += [
        # Usage 1: nginx-ingress depends on AWS Load Balancer Controller
        {
            apiVersion = "apiextensions.crossplane.io/v1beta1"
            kind = "Usage"
            metadata = {
                **_metadata("usage-nginx-uses-lb-controller")
                annotations = {
                    **_metadata("usage-nginx-uses-lb-controller").annotations
                    "krm.kcl.dev/ready" = "True"
                }
            }
            spec = {
                replayDeletion = True  # Critical: enables fast cleanup
                of = {
                    # The resource being protected (AWS Load Balancer Controller)
                    apiVersion = "helm.crossplane.io/v1beta1"
                    kind = "Release"
                    resourceSelector = {
                        matchLabels = {
                            "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
                        }
                    }
                }
                by = {
                    # The dependent resource (nginx-ingress)
                    apiVersion = "helm.crossplane.io/v1beta1"
                    kind = "Release"
                    resourceSelector = {
                        matchLabels = {
                            "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-ingress-nginx"
                        }
                    }
                }
                reason = "nginx-ingress creates LoadBalancer Service (AWS NLB) managed by AWS Load Balancer Controller - controller must process finalizers before being deleted."
            }
        }
        # Usage 2: cert-manager depends on AWS Load Balancer Controller
        {
            apiVersion = "apiextensions.crossplane.io/v1beta1"
            kind = "Usage"
            metadata = {
                **_metadata("usage-cert-manager-uses-lb-controller")
                annotations = {
                    **_metadata("usage-cert-manager-uses-lb-controller").annotations
                    "krm.kcl.dev/ready" = "True"
                }
            }
            spec = {
                replayDeletion = True
                of = {
                    # The resource being protected (AWS Load Balancer Controller)
                    apiVersion = "helm.crossplane.io/v1beta1"
                    kind = "Release"
                    resourceSelector = {
                        matchLabels = {
                            "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
                        }
                    }
                }
                by = {
                    # The dependent resource (cert-manager)
                    apiVersion = "helm.crossplane.io/v1beta1"
                    kind = "Release"
                    resourceSelector = {
                        matchLabels = {
                            "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-cert-manager"
                        }
                    }
                }
                reason = "cert-manager webhook service may use AWS Load Balancer Controller - controller must be available during cert-manager cleanup"
            }
        }
    ]

    # CloudNative-PG Operator and PostgreSQL Cluster depend on Cert Manager, Ingress NGINX, and External Secrets
    if ready(get(_ocds, "cnoe-helmrelease-cert-manager", "")) and ready(get(_ocds, "cnoe-helmrelease-ingress-nginx", "")) and ready(get(_ocds, "cnoe-helmrelease-external-secrets", "")):
        _items += [
            # Helm Release for CloudNative-PG Operator
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-cloudnative-pg")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "cnpg-system"
                        chart: {
                            name = "cloudnative-pg"
                            repository = "https://cloudnative-pg.github.io/charts"
                            version = "0.22.1"
                        }
                        wait = True # wait for the CNPG operator to be ready
                        values: {
                            crds: {
                                create: True
                            }
                            monitoring: {
                                podMonitorEnabled: True
                            }
                        }
                    }
                }
            }
        ]
    # PostgreSQL Cluster using CloudNative-PG depends on the operator being ready
    if ready(get(_ocds, "cnoe-helmrelease-cloudnative-pg", "")):
        _items += [
            # Keycloak Namespace (must be created first)
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-keycloak-namespace")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Namespace"
                            metadata = {
                                name = "keycloak"
                            }
                        }
                    }
                }
            }
            # Secret for PostgreSQL credentials (must be created before the cluster)
            # Wrapped in Kubernetes Object to deploy to EKS cluster
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-postgresql-credentials")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "keycloak-postgres-credentials"
                                namespace = "keycloak"
                            }
                            type = "Opaque"
                            stringData = {
                                username = "keycloak"
                                password = "keycloakpassword"
                            }
                        }
                    }
                }
            }
            # Secret for Keycloak admin credentials (for Keycloak provider in EKS Cluster)
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-keycloak-admin-secret")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "{}-keycloak".format(oxr.spec.parameters.id)
                                namespace = "keycloak"
                            }
                            type = "Opaque"
                            stringData = {
                                credentials = json.encode({
                                    client_id: "admin-cli"
                                    client_secret: "admin"
                                    username: "admin"
                                    password: "admin"
                                    realm: "master"
                                    url: "https://keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                })
                            }
                        }
                    }
                }
            }
            # PostgreSQL Cluster for Keycloak using CloudNative-PG
            # Wrapped in Kubernetes Object to deploy to EKS cluster
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-postgresql-cluster")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "postgresql.cnpg.io/v1"
                            kind = "Cluster"
                            metadata = {
                                name = "keycloak-postgres"
                                namespace = "keycloak"
                            }
                            spec = {
                                instances = 1
                                imageName = "ghcr.io/cloudnative-pg/postgresql:16"
                                storage = {
                                    size = "10Gi"
                                }
                                bootstrap = {
                                    initdb = {
                                        database = "keycloak"
                                        owner = "keycloak"
                                        secret = {
                                            name = "keycloak-postgres-credentials"
                                        }
                                    }
                                }
                                monitoring = {
                                    enabled = True
                                }
                            }
                        }
                    }
                }
            }
        ]

    # Keycloak Helm Release depends on PostgreSQL Cluster being ready
    if ready(get(_ocds, "cnoe-postgresql-cluster", "")):
        _items += [
            # Helm Release for Keycloak
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-keycloak")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        namespace = "keycloak"
                        chart: {
                            name = "keycloakx"
                            repository = "https://codecentric.github.io/helm-charts"
                            version = "7.1.4"
                        }
                        wait = True ## wait for the Keycloak pods to be ready.
                        values: {
                            # Override the full name to make service name predictable
                            fullnameOverride: "keycloakx"
                            # Admin credentials for keycloakx via extraEnv
                            extraEnv: "- name: KEYCLOAK_ADMIN\n  value: admin\n- name: KEYCLOAK_ADMIN_PASSWORD\n  value: admin\n"
                            # Custom command for Keycloak startup
                            command: [
                                "/opt/keycloak/bin/kc.sh"
                                "--verbose"
                                "start"
                                "--http-port=8080"
                                "--hostname=keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                "--hostname-strict=false"
                                "--proxy-headers=xforwarded"
                                "--http-relative-path=/"
                                "--spi-events-listener-jboss-logging-success-level=info"
                                "--spi-events-listener-jboss-logging-error-level=warn"
                            ]
                            # HTTP and Proxy configuration for edge proxy mode
                            http: {
                                relativePath: "/"
                            }
                            proxy: {
                                enabled: True
                                mode: "forwarded"
                                http: {
                                    enabled: True
                                }
                            }
                            # Metrics and monitoring
                            metrics: {
                                enabled: True
                            }
                            health: {
                                enabled: True
                            }
                            serviceMonitor: {
                                enabled: True
                            }
                            # Ingress configuration
                            ingress: {
                                enabled: True
                                ingressClassName: "nginx"
                                annotations: {
                                    "nginx.ingress.kubernetes.io/ssl-redirect" = "true"
                                    "nginx.ingress.kubernetes.io/proxy-body-size": "20m"
                                    "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
                                }
                                rules: [
                                    {
                                        host: "keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                        paths: [
                                            {
                                                path: "/"
                                                pathType: "Prefix"
                                            }
                                        ]
                                    }
                                ]
                                tls: [
                                    {
                                        secretName: "keycloak-tls"
                                        hosts: [
                                            "keycloak-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                        ]
                                    }
                                ]
                            }
                            # PostgreSQL database configuration using CloudNative-PG
                            database: {
                                vendor: "postgres"
                                hostname: "keycloak-postgres-rw"
                                port: 5432
                                username: "keycloak"
                                password: "keycloakpassword"
                                database: "keycloak"
                            }
                            dbchecker: {
                                enabled: True
                            }
                        }
                    }
                }
            }
            # Usage: Deletion Protection: Keycloak depends on AWS Load Balancer Controller
            # Keycloak creates an Ingress that uses nginx-ingress, which depends on AWS LB Controller
            {
                apiVersion = "apiextensions.crossplane.io/v1beta1"
                kind = "Usage"
                metadata = {
                    **_metadata("usage-keycloak-uses-lb-controller")
                    annotations = {
                        **_metadata("usage-keycloak-uses-lb-controller").annotations
                        "krm.kcl.dev/ready" = "True"
                    }
                }
                spec = {
                    replayDeletion = True
                    of = {
                        # The resource being protected (AWS Load Balancer Controller)
                        apiVersion = "helm.crossplane.io/v1beta1"
                        kind = "Release"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
                            }
                        }
                    }
                    by = {
                        # The dependent resource (Keycloak)
                        apiVersion = "helm.crossplane.io/v1beta1"
                        kind = "Release"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-keycloak"
                            }
                        }
                    }
                    reason = "Keycloak Ingress requires AWS Load Balancer Controller to clean up AWS NLB during deletion"
                }
            }
        ]
    # Backstage Helm Release depends on Keycloak and should be created last.
    if ready(get(_ocds, "cnoe-helmrelease-keycloak", "")):
        _items += [
            # ArgoCD installation (depends on nginx-ingress being ready). hence, moved to last leg.
            gitopsv1alpha1.XArgo {
                metadata = _metadata("cnoe-argocd")
                spec = {
                    parameters = {
                        providerConfigName = oxr.spec.parameters.id
                        deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                        operators = {
                            argocd = {
                                version = oxr.spec?.parameters?.operators?.argocd?.version if oxr.spec?.parameters?.operators?.argocd?.version != None else "9.0.3"
                            }
                        }
                        source = {
                            git = {
                                path = oxr.spec?.parameters?.gitops?.git?.path if oxr.spec?.parameters?.gitops?.git?.path != None else ""
                                ref = {
                                    name = oxr.spec?.parameters?.gitops?.git?.ref?.name if oxr.spec?.parameters?.gitops?.git?.ref?.name != None else "main"
                                }
                                url = oxr.spec?.parameters?.gitops.git?.url if oxr.spec?.parameters?.gitops?.git?.url != None else ""
                            }
                        }
                        ingressUrl = "argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        oidcConfig = json.encode({
                            name: "Keycloak"
                            clientID: "argocd"
                            clientSecret: oxr.metadata.uid
                            requestedScopes: ['openid', 'profile', 'email', 'groups']
                            realm: "master"
                            issuer: "https://keycloak-{}.{}/realms/master".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        })
                    }
                }
            }
            # 1. ArgoCD Custom Ingress with nginx and TLS (different name to avoid conflict)
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-argocd-custom-ingress")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "networking.k8s.io/v1"
                            kind = "Ingress"
                            metadata = {
                                name = "argocd-custom-ingress"
                                namespace = "argocd"
                                annotations = {
                                    "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
                                    "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
                                }
                            }
                            spec = {
                                ingressClassName = "nginx"
                                rules = [
                                    {
                                        host = "argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                        http = {
                                            paths = [
                                                {
                                                    path = "/"
                                                    pathType = "Prefix"
                                                    backend = {
                                                        service = {
                                                            name = "argocd-server"
                                                            port = {
                                                                name = "https"
                                                            }
                                                        }
                                                    }
                                                }
                                            ]
                                        }
                                    }
                                ]
                                tls = [
                                    {
                                        secretName = "argocd-custom-tls"
                                        hosts = [
                                            "argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                        ]
                                    }
                                ]
                            }
                        }
                    }
                }
            }
            #  Usage: Deletion Protection : ArgoCD Ingress uses nginx-ingress, which depends on AWS LB Controller
            {
                apiVersion = "apiextensions.crossplane.io/v1beta1"
                kind = "Usage"
                metadata = {
                    **_metadata("usage-argocd-ingress-uses-lb-controller")
                    annotations = {
                        **_metadata("usage-argocd-ingress-uses-lb-controller").annotations
                        "krm.kcl.dev/ready" = "True"
                    }
                }
                spec = {
                    replayDeletion = True
                    of = {
                        # The resource being protected (AWS Load Balancer Controller)
                        apiVersion = "helm.crossplane.io/v1beta1"
                        kind = "Release"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
                            }
                        }
                    }
                    by = {
                        # The dependent resource (ArgoCD Custom Ingress Object)
                        apiVersion = "kubernetes.crossplane.io/v1alpha2"
                        kind = "Object"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-argocd-custom-ingress"
                            }
                        }
                    }
                    reason = "ArgoCD custom Ingress requires AWS Load Balancer Controller to clean up AWS NLB during deletion"
                }
            }
            # 2. Secret for Backstage Keycloak OIDC client secret - keycloakBackstageClientSecret
            kubernetesv1alpha2.Object {
                metadata = _metadata("cnoe-backstage-client-secret")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "{}-backstage-client".format(oxr.spec.parameters.id)
                                namespace = "backstage"
                            }
                            type = "Opaque"
                            stringData = {
                                clientSecret = oxr.metadata.uid
                            }
                        }
                    }
                }
            }
            # 3. keycloakGroupArgoCD
            {
                apiVersion = "group.keycloak.crossplane.io/v1alpha1"
                kind = "Group"
                metadata = {
                    **_metadata("keycloakGroupArgoCD")
                    labels = {
                        type = "argocd-admin"
                    }
                }
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        name = "argocd-admin"
                        realmId = "master"
                    }
                }
            }
            # 4. keycloakGroupBackstage
            {
                apiVersion = "group.keycloak.crossplane.io/v1alpha1"
                kind = "Group"
                metadata = {
                    **_metadata("keycloakGroupBackstage")
                    labels = {
                        type = "backstage-admin"
                    }
                }
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        name = "backstage-admin"
                        realmId = "master"
                    }
                }
            }
            # 5. keycloakOpenIdClientScope
            {
                apiVersion = "openidclient.keycloak.crossplane.io/v1alpha1"
                kind = "ClientScope"
                metadata = _metadata("keycloakOpenIdClientScope")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        name = "groups"
                        includeInTokenScope = True
                        guiOrder = 1
                    }
                }
            }
            # 6. keycloakOpenIdGroupMembershipProtocolMapper
            {
                apiVersion = "openidgroup.keycloak.crossplane.io/v1alpha1"
                kind = "GroupMembershipProtocolMapper"
                metadata = _metadata("keycloakOpenIdGroupMembershipProtocolMapper")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        name = "groups"
                        claimName = "groups"
                        fullPath = False
                        clientScopeId = _ocds["keycloakOpenIdClientScope"]?.Resource?.status?.atProvider?.id
                    }
                }
            }
            # 7. keycloakArgoCDClientSecret (Control Plane Secret for Keycloak Provider)
            kubernetesv1alpha2.Object {
                metadata = _metadata("keycloakArgoCDClientSecret")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-controlplane".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "{}-argocd-client".format(oxr.spec.parameters.id)
                                namespace = "crossplane-system"
                            }
                            type = "Opaque"
                            stringData = {
                                clientSecret = oxr.metadata.uid
                            }
                        }
                    }
                }
            }
            # 7. keycloakArgoCDOpenIdClient
            {
                apiVersion = "openidclient.keycloak.crossplane.io/v1alpha1"
                kind = "Client"
                metadata = _metadata("keycloakArgoCDOpenIdClient")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        clientId = "argocd"
                        baseUrl = "/applications"
                        name = "argocd"
                        enabled = True
                        accessType = "CONFIDENTIAL"
                        clientSecretSecretRef = {
                            namespace = "crossplane-system"
                            name = "{}-argocd-client".format(oxr.spec.parameters.id)
                            key = "clientSecret"
                        }
                        standardFlowEnabled = True
                        directAccessGrantsEnabled = True
                        validRedirectUris = [
                            "https://argocd-{}.{}/*".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        ]
                        webOrigins = [
                            "https://argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        ]
                        validPostLogoutRedirectUris = [
                            "https://argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        ]
                        rootUrl = "https://argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        adminUrl = "https://argocd-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                    }
                }
            }
            # 8. keycloakArgoCDOpenIdClientDefaultScopes
            {
                apiVersion = "openidclient.keycloak.crossplane.io/v1alpha1"
                kind = "ClientDefaultScopes"
                metadata = _metadata("keycloakArgoCDOpenIdClientDefaultScopes")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        clientId = _ocds["keycloakArgoCDOpenIdClient"]?.Resource?.status?.atProvider?.id
                        defaultScopes = [
                            "profile"
                            "email"
                            "roles"
                            "web-origins"
                            "groups"
                        ]
                    }
                }
            }
            # 9. keycloakBackstageClientSecret (Control Plane Secret for Keycloak Provider)
            kubernetesv1alpha2.Object {
                metadata = _metadata("keycloakBackstageClientSecret")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-controlplane".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        manifest = {
                            apiVersion = "v1"
                            kind = "Secret"
                            metadata = {
                                name = "{}-backstage-client".format(oxr.spec.parameters.id)
                                namespace = "crossplane-system"
                            }
                            type = "Opaque"
                            stringData = {
                                clientSecret = oxr.metadata.uid
                            }
                        }
                    }
                }
            }
            # 10. keycloakBackstageOpenIdClient
            {
                apiVersion = "openidclient.keycloak.crossplane.io/v1alpha1"
                kind = "Client"
                metadata = _metadata("keycloakBackstageOpenIdClient")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        clientId = "backstage"
                        name = "backstage"
                        enabled = True
                        accessType = "CONFIDENTIAL"
                        clientSecretSecretRef = {
                            namespace = "crossplane-system"
                            name = "{}-backstage-client".format(oxr.spec.parameters.id)
                            key = "clientSecret"
                        }
                        standardFlowEnabled = True
                        directAccessGrantsEnabled = True
                        webOrigins = [
                            "/*"
                        ]
                        validRedirectUris = [
                            "https://backstage-{}.{}/api/auth/keycloak-oidc/handler/frame".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                        ]
                    }
                }
            }
            # 11. keycloakBackstageOpenIdClientDefaultScopes
            {
                apiVersion = "openidclient.keycloak.crossplane.io/v1alpha1"
                kind = "ClientDefaultScopes"
                metadata = _metadata("keycloakBackstageOpenIdClientDefaultScopes")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
                    }
                    forProvider = {
                        realmId = "master"
                        clientId = _ocds["keycloakBackstageOpenIdClient"]?.Resource?.status?.atProvider?.id
                        defaultScopes = [
                            "profile"
                            "email"
                            "roles"
                            "web-origins"
                            "groups"
                        ]
                    }
                }
            }
            # Helm Release for Backstage
            helmv1beta1.Release {
                metadata = _metadataWithClusterLabel("cnoe-helmrelease-backstage")
                spec = {
                    deletionPolicy = oxr.spec?.parameters?.deletionPolicy
                    providerConfigRef = {
                        name = oxr.spec.parameters.id
                    }
                    forProvider = {
                        # Note: clientSecret is now stored in a secret within the EKS cluster
                        # in the backstage namespace, accessible by the Backstage application
                        namespace = "backstage"
                        chart: {
                            name = "backstage"
                            repository = "https://backstage.github.io/charts"
                        }
                        values: {
                            # Override the full name to make resource names predictable
                            fullnameOverride: "backstage"
                            ingress: {
                                enabled: True
                                host: "backstage-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                className: "nginx"
                                annotations: {
                                    "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
                                }
                                tls: {
                                    enabled: True
                                    secretName: "backstage-tls"
                                }
                            }
                            backstage: {
                                image: {
                                    registry: "public.ecr.aws"
                                    repository: "cnoe-io/backstage"
                                    tag: "v0.0.2"
                                    pullPolicy: "IfNotPresent"
                                }
                                extraEnvVars: [
                                    {
                                        name: "KEYCLOAK_CLIENT_SECRET"
                                        valueFrom: {
                                            secretKeyRef: {
                                                name: "{}-backstage-client".format(oxr.spec.parameters.id)
                                                key: "clientSecret"
                                            }
                                        }
                                    }
                                ]
                                appConfig: {
                                    app: {
                                        title: "CNOE Backstage"
                                        baseUrl: "https://backstage-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                    }
                                    organization: {
                                        name: "CNOE"
                                    }
                                    backend: {
                                        baseUrl: "https://backstage-{}.{}".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                        listen: {
                                            port: 7007
                                        }
                                        csp: {
                                            "connect-src": ["'self'", "http:", "https:"]
                                        }
                                        cors: {
                                            origin: "http://localhost:3000"
                                            methods: ["GET", "HEAD", "PATCH", "POST", "PUT", "DELETE"]
                                            credentials: True
                                        }
                                        database: {
                                            client: "better-sqlite3"
                                            connection: ":memory:"
                                        }
                                    }
                                    proxy: {}
                                    techdocs: {
                                        builder: "local"
                                        generator: {
                                            runIn: "docker"
                                        }
                                        publisher: {
                                            type: "local"
                                        }
                                    }
                                    auth: {
                                        environment: "development"
                                        session: {
                                            secret: "MW2sV-sIPngEl26vAzatV-6VqfsgAx4bPIz7PuE_2Lk="
                                        }
                                        providers: {
                                            "keycloak-oidc": {
                                                development: {
                                                    clientId: "backstage"
                                                    clientSecret: "{}".format(oxr.metadata.uid)
                                                    scope: "openid profile email groups"
                                                    prompt: "auto"
                                                    metadataUrl: "https://keycloak-{}.{}/realms/master/.well-known/openid-configuration".format(oxr.spec.parameters.id, _ocds["route53zone"]?.Resource?.status?.atProvider?.name)
                                                }
                                            }
                                        }
                                    }
                                    scaffolder: {}
                                    catalog: {
                                        import: {
                                            entityFilename: "catalog-info.yaml"
                                            pullRequestBranchName: "backstage-integration"
                                        }
                                        rules: [
                                            {allow: ["Component", "System", "API", "Resource", "Location", "Template"]}
                                        ]
                                        locations: [
                                            {
                                                type: "url"
                                                target: "https://github.com/backstage/backstage/blob/master/packages/catalog-model/examples/acme/org.yaml"
                                                rules: [
                                                    {allow: ["Group", "User"]}
                                                ]
                                            }
                                        ]
                                    }
                                    kubernetes: {
                                        serviceLocatorMethod: {
                                            type: "multiTenant"
                                        }
                                        clusterLocatorMethods: [
                                            {type: "catalog"}
                                        ]
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # Usage: Deletion Protection: Backstage depends on AWS Load Balancer Controller
            # Backstage creates an Ingress that uses nginx-ingress, which depends on AWS LB Controller
            {
                apiVersion = "apiextensions.crossplane.io/v1beta1"
                kind = "Usage"
                metadata = {
                    **_metadata("usage-backstage-uses-lb-controller")
                    annotations = {
                        **_metadata("usage-backstage-uses-lb-controller").annotations
                        "krm.kcl.dev/ready" = "True"
                    }
                }
                spec = {
                    replayDeletion = True
                    of = {
                        # The resource being protected (AWS Load Balancer Controller)
                        apiVersion = "helm.crossplane.io/v1beta1"
                        kind = "Release"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
                            }
                        }
                    }
                    by = {
                        # The dependent resource (Backstage)
                        apiVersion = "helm.crossplane.io/v1beta1"
                        kind = "Release"
                        resourceSelector = {
                            matchLabels = {
                                "krm.kcl.dev/composition-resource-name" = "cnoe-helmrelease-backstage"
                            }
                        }
                    }
                    reason = "Backstage Ingress requires AWS Load Balancer Controller to clean up AWS NLB during deletion"
                }
            }
        ]


# all the resources that needs to be composed.
items = _items