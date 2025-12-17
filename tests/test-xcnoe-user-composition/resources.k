# Composition Resources for AWS CNOE Composition Test

# USer created using XCNOE Composition
_argocd_admin_user = {
    "apiVersion": "user.keycloak.crossplane.io/v1alpha1"
    "kind": "User"
    "metadata": {
        "generateName": "argocd-admin-user-"
    }
    "spec": {
        "providerConfigRef": {
            "name": "platform-ref-aws-cnoe-keycloak-providerconfig"
        }
        "forProvider": {
            "emailVerified": True
            "email": "argocd-admin@upboundrocks.cloud"
            "firstName": "argocd"
            "lastName": "admin"
            "username": "argocd-admin"
            "enabled": True
            "realmId": "master"
            "initialPassword": [
                {
                    "temporary": False
                    "valueSecretRef": {
                        "name": "argocd-admin-user"
                        "key": "password"
                    }
                }
            ]
        }
    }
}


_argocd_admin_group_membership = {
    "apiVersion": "user.keycloak.crossplane.io/v1alpha1"
    "kind": "Groups"
    "metadata": {
        "generateName": "argocd-admin-user-"
    }
    "spec": {
        "providerConfigRef": {
            "name": "platform-ref-aws-cnoe-keycloak-providerconfig"
        }
        "forProvider": {
            "groupIdsSelector": {
                "matchLabels": {
                    "type": "argocd-admin"
                }
            }
            "realmId": "master"
            "userIdSelector": {
                "matchControllerRef": True
            }
        }
    }
}