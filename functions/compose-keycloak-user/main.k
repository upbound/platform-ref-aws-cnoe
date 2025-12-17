## Input parameters for the function
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

_items = [
    {
        apiVersion = "user.keycloak.crossplane.io/v1alpha1"
        kind = "User"
        metadata = _metadata("keycloakUser-{}".format(oxr.spec.parameters.id))
        spec = {
            deletionPolicy = oxr.spec?.parameters?.deletionPolicy
            providerConfigRef = {
                name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
            }
            forProvider = {
                realmId = "master"
                enabled = True
                emailVerified = True
                username = oxr.spec.parameters.username
                firstName = oxr.spec.parameters.firstname
                lastName = oxr.spec.parameters.lastname
                email = oxr.spec.parameters.email
                initialPassword = oxr.spec.parameters.initialPassword
            }
        }
    }
    {
        apiVersion = "user.keycloak.crossplane.io/v1alpha1"
        kind = "Groups"
        metadata = _metadata("keycloakGroups-{}".format(oxr.spec.parameters.id))
        spec = {
            deletionPolicy = oxr.spec?.parameters?.deletionPolicy
            providerConfigRef = {
                name = "{}-keycloak-providerconfig".format(oxr.spec.parameters.id)
            }
            forProvider = {
                realmId = "master"
                userIdSelector = {
                    matchControllerRef = True
                }
                groupIdsSelector = {
                    matchLabels = {
                        type = oxr.spec?.parameters?.group
                    }
                }
            }
        }
    }
]

## all resources to be composed
items = _items
