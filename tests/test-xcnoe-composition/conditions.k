import datetime

_readyConditions = [
    {
        reason: "Available"
        status: "True"
        type: "Ready"
        lastTransitionTime: datetime.now("%Y-%m-%dT%H:%M:%SZ")
    }
    {
        reason: "Success"
        status: "True"
        type: "LastAsyncOperation"
        lastTransitionTime: datetime.now("%Y-%m-%dT%H:%M:%SZ")
    }
    {
        reason: "ReconcileSuccess"
        status: "True"
        type: "Synced"
        lastTransitionTime: datetime.now("%Y-%m-%dT%H:%M:%SZ")
    }
]
