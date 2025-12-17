# Composition Resources for AWS CNOE Composition Test
import models.io.upbound.aws.iam.v1beta1 as iamv1beta1
import models.io.upbound.platform.aws.v1alpha1 as platformawsv1alpha1
import models.io.upbound.platform.gitops.v1alpha1 as gitopsv1alpha1
import models.io.upbound.platform.observe.v1alpha1 as platformobservev1alpha1
import models.io.upbound.aws.route53.v1beta1 as route53v1beta1
import models.io.crossplane.helm.v1beta1 as helmv1beta1
import json
import conditions


# Network Resource for AWS CNOE Composition Test
_network: any = platformawsv1alpha1.XNetwork {
    metadata = {
        annotations = {
            "crossplane.io/composition-resource-name" = "xnetwork"
        }
        generateName = "platform-ref-aws-cnoe-"
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        parameters = {
            id = "platform-ref-aws-cnoe"
            vpcCidrBlock = "192.168.0.0/16"
            region = "eu-west-1"
            deletionPolicy = "Delete"
            subnets: [
                {
                    availabilityZone = "eu-west-1a"
                    cidrBlock = "192.168.0.0/18"
                    type = "public"
                }
                {
                    availabilityZone = "eu-west-1b"
                    cidrBlock = "192.168.64.0/18"
                    type = "public"
                }
                {
                    availabilityZone = "eu-west-1a"
                    cidrBlock = "192.168.128.0/18"
                    type = "private"
                }
                {
                    availabilityZone = "eu-west-1b"
                    cidrBlock = "192.168.192.0/18"
                    type = "private"
                }
            ]
        }
    }
}

# Kubernetes Cluster Resource for AWS CNOE Composition Test
_xeks = platformawsv1alpha1.XEKS {
    metadata = {
        annotations = {
            "crossplane.io/composition-resource-name" = "xeks"
        }
        generateName = "platform-ref-aws-cnoe-"
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        parameters = {
            id = "platform-ref-aws-cnoe"
            accessConfig = {
                authenticationMode = "API_AND_CONFIG_MAP"
                bootstrapClusterCreatorAdminPermissions = True
            }
            version = "1.34"
            region = "eu-west-1"
            deletionPolicy = "Delete"
            nodes = {
                count = 8
                instanceType = "t3.small"
            }
        }
    }
}

# ArgoCD Resource for AWS CNOE Composition Test
_xargo = gitopsv1alpha1.XArgo {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "cnoe-argocd"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        parameters = {
            deletionPolicy = "Delete"
            providerConfigName = "platform-ref-aws-cnoe"
            operators = {
                argocd = {
                    version = "9.0.3"
                }
            }
            source = {
                git = {
                    path = "gitops"
                    url = "https://github.com/upbound/configuration-gitops-argocd.git"
                    ref = {
                        name = "HEAD"
                    }
                }
            }
        }
    }
}

# Route53 Zone Resource for AWS CNOE Composition Test
_xzone = route53v1beta1.Zone {
    metadata = {
        annotations = {
            "crossplane.io/composition-resource-name" = "route53zone"
        }
        generateName = "platform-ref-aws-cnoe-"
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        forProvider = {
            ## Must be us-east-1 for Route53
            region = "us-east-1"
        }
        ## Only observe to avoid conflicts with existing zones
        managementPolicies = ["Observe"]
        ## Orphan to avoid deleting existing zones
        deletionPolicy = "Orphan"
    }
}

# AWS Role for AWS Load Balancer Controller
_awslbrole = iamv1beta1.Role {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "aws-load-balancer-controller-role"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
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
        deletionPolicy = "Delete"
    }
}
_awsdnsrole = iamv1beta1.Role {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "external-dns-role"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
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
        deletionPolicy = "Delete"
    }
}

_xoss = platformobservev1alpha1.XOss {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "xoss"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        parameters = {
            deletionPolicy = "Delete"
            id = "platform-ref-aws-cnoe"
            operators = {
                prometheus = {
                    version = "52.1.0"
                }
            }
        }
    }
}
_externaldnschart = helmv1beta1.Release {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "cnoe-helmrelease-external-dns"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        forProvider = {
            chart = {
                name = "external-dns"
                repository = "https://kubernetes-sigs.github.io/external-dns/"
                version: "1.19.0"
            }            
            namespace = "external-dns"
            values = {
                provider = "aws"
                aws = {
                    region = "us-east-1" # Route53 region
                }
                rbac = {
                    create = True
                }
                source = "ingress" # watch ingress resources
                policy = "sync"
            }
        }
        deletionPolicy = "Delete"
    }
}

_xpchart = helmv1beta1.Release {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "cnoe-helmrelease-crossplane"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        forProvider = {
            chart = {
                name = "crossplane"
                repository = "https://charts.crossplane.io/stable"
                version: "1.14.3"
            }
            namespace = "crossplane-system"
        }
        deletionPolicy = "Delete"
    }
}

_awslbchart = helmv1beta1.Release {
    metadata = {
        generateName = "platform-ref-aws-cnoe-"
        annotations = {
            "crossplane.io/composition-resource-name" = "cnoe-helmrelease-awsLoadBalancerControllerChart"
        }
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        forProvider = {
            chart = {
                name = "aws-load-balancer-controller"
                repository = "https://aws.github.io/eks-charts"
                version: "1.14.0"
            }
            namespace = "kube-system"
            values = {
                region = "eu-west-1"
                clusterName = "platform-ref-aws-cnoe-hhrwd"
                serviceAccount = {
                    name = "aws-load-balancer-controller"
                }
                serviceMutatorWebhookConfig = {
                    failurePolicy = "Ignore"
                }
                podMutatorWebhookConfig = {
                    failurePolicy = "Ignore"
                }
            }
        }
        deletionPolicy = "Delete"
    }
}

# Observed EKS 
_oxeks = platformawsv1alpha1.XEKS {
    metadata = {
        annotations = {
            "crossplane.io/composition-resource-name" = "xeks"
        }
        generateName = "platform-ref-aws-cnoe-"
        name = "platform-ref-aws-cnoe-c5fbb21a8303" # Observed name
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        parameters = {
            id = "platform-ref-aws-cnoe"
            accessConfig = {
                authenticationMode = "API_AND_CONFIG_MAP"
                bootstrapClusterCreatorAdminPermissions = True
            }
            version = "1.33"
            region = "eu-west-1"
            deletionPolicy = "Delete"
            nodes = {
                count = 8
                instanceType = "t3.small"
            }
        }
    }
    status = {
        eks = {
            clusterName = "platform-ref-aws-cnoe-hhrwd"
        }
        conditions = conditions._readyConditions
    }
}