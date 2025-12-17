import models.io.upbound.platformref.aws.v1alpha1 as platformrefawsv1alpha1
import file

# Read from environment variables with defaults
_route53ZoneIdEnv = file.read_env("ROUTE53_ZONE_ID")
_iamRoleArnEnv = file.read_env("IAM_ROLE_ARN")

_route53ZoneId = _route53ZoneIdEnv if _route53ZoneIdEnv else "ZXXXXXXXXXXXXX"
_iamRoleArn = _iamRoleArnEnv if _iamRoleArnEnv else "arn:aws:iam::123456789012:role/YourE2ETestRole"

_xcnoe = platformrefawsv1alpha1.XCNOE {
    metadata = {
        name = "platform-ref-aws-cnoe"
        labels = {
            "crossplane.io/composite" = "platform-ref-aws-cnoe"
        }
    }
    spec = {
        compositeDeletePolicy = "Foreground"
        parameters = {
            id = "platform-ref-aws-cnoe"
            deletionPolicy = "Delete"
            nodes   = {
                count = 9
                instanceType = "t3.small"
            }
            region = "eu-west-1"
            route53zoneId = _route53ZoneId
            version = "1.34"
            iam = {
                roleArn = _iamRoleArn
            }
            gitops = {
                git = {
                    url = "https://github.com/upbound/configuration-gitops-argocd.git"
                    path = "gitops"
                    ref = {
                        name = "HEAD"
                    }
                }
            }
        }
    }
}