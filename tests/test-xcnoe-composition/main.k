import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import resources

_items = [
    # Test Coversion for Foundation Level - 1 - like vpc, sn, eks cluster, nodegroup, iam roles, etc
    metav1alpha1.CompositionTest {
        metadata.name: "Foundation Validation Test - Level 1"
        spec = {
            assertResources: [resources._network, resources._xeks, resources._xzone, resources._awslbrole, resources._awsdnsrole]
            compositionPath: "apis/cnoes/composition.yaml"
            xrPath: "examples/cnoe/platform-ref-aws-cnoe.yaml"
            xrdPath: "apis/cnoes/definition.yaml"
            timeoutSeconds: 60
            validate: False
        }
    },
    # Test GitOps for Application Level - 2 - like external-dns, openobserve, dns, grafana, etc
    metav1alpha1.CompositionTest {
        metadata.name: "GitOps Validation Test - Level 2"
        spec = {
            observedResources: [resources._network, resources._oxeks, resources._xzone, resources._awslbrole, resources._awsdnsrole]
            assertResources: [resources._xoss, resources._awslbchart, resources._xpchart]
            compositionPath: "apis/cnoes/composition.yaml"
            xrPath: "examples/cnoe/platform-ref-aws-cnoe.yaml"
            xrdPath: "apis/cnoes/definition.yaml"
            timeoutSeconds: 60
            validate: False
        }
    }
]
items = _items
