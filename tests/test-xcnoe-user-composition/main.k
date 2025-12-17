
####
##  Test XCNOE User Composition in Keycloak Environment provisioned by XCNOE. 
####
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import resources
_items = [
    # Test Coversion for Foundation Level - 1 - Users and its group creation in Keycloak
    metav1alpha1.CompositionTest {
        metadata.name: "Foundation User Creation Test with Membership - Level 1"
        spec = {
            assertResources: [resources._argocd_admin_user, _argocd_admin_group_membership]
            compositionPath: "apis/users/composition.yaml"
            xrPath: "examples/user/argocd-admin-user.yaml"
            xrdPath: "apis/users/definition.yaml"
            timeoutSeconds: 60
            validate: False
        }
    }
]
items = _items