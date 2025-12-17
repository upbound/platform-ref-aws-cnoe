import models.io.upbound.aws.v1beta1 as awsv1beta1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import resources

_items = [
    metav1alpha1.E2ETest {
        metadata.name: "e2e-test-xcnoe-platform-ref-aws"
        spec = {
            crossplane.autoUpgrade.channel: "None"
            crossplane.version : "1.20.4-up.1"
            defaultConditions: ["Ready"]
            manifests: [
                resources._xcnoe
            ]
            extraResources: [
                awsv1beta1.ProviderConfig {
                    metadata.name = "default"
                    spec = {
                        credentials = {
                            source = "Upbound"
                            upbound = {
                                webIdentity = {
                                    roleARN = "arn:aws:iam::609897127049:role/solutions-e2e-provider-aws"
                                }
                            }
                        }
                    }
                }
            ]
            skipDelete: True # Skip deletion to retain created resources for inspection
            timeoutSeconds: 4500
        }
    }
]
items = _items
