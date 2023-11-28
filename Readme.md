# CNOE Platform Reference on AWS using Crossplane

![backstage](docs/backstage.png)

Every organization has unique requirements for their internal developer platforms (IDPs), making it unreasonable and impractical to design a one-size-fits-all solution.

While there are common practices in using various tools within IDPs, there is a lack of references on configuring and combining these tools effectively to implement desired platform engineering practices.

For more comprehensive information about CNOE and its objectives, visit the [CNOE website](https://cnoe.io/).

## CNOE Platform Overview

In this CNOE platform reference, we leverage AWS and rely on Crossplane as the backbone for our control plane. It's important to note that CNOE is not an effort by AWS alone; rather, it is a collaborative platform that incorporates a variety of technologies and is not limited to any specific cloud provider.

We use Crossplane's packaging features for our APIs and leverage Kubernetes' validation options for the entire stack. While our goal isn't to cover everything, we are committed to gathering community-driven patterns and best practices that reflect common deployments in production.

![overview](docs/cnoe-xp.png)

## Learn More

To explore a more comprehensive understanding of CNOE and its capabilities, refer to the [CNOE website](https://cnoe.io/).

## Reference Implementation

For detailed configurations, patterns, and practices, explore the CNOE reference implementation. The platform encompasses a growing list of technologies to cater to diverse organizational needs.

[Link to the Reference Implementation](https://github.com/cnoe-io/reference-implementation-aws)


  **Capability**              | **Technologies**
------------------------------|---------------------------------
Code Repository               | Git
Config Repository             | Git
Artifact Registry             | Container Registries
Secret Repository             | External Secrets (with Vault and KMS)
Validations                   | Crossplane Validation Webhooks
Secret Management             | Crossplane ESS, External Secrets
ControlPlane                  | Crossplane
Continuous Delivery           | Argo CD, Flux
Continuous Integration        | Argo Workflows, Tekton
Identity & Access             | Keycloak
Developer Portals             | Backstage
