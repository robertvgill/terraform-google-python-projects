import os
import datetime

from kubernetes import client, config

def create_volume_snapshot(pvc_name, namespace):
    # Load Kubernetes configuration
    config.load_incluster_config()

    # Create Kubernetes API client
    api = client.CustomObjectsApi()

    # Generate a timestamp for the snapshot
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")

    # Define the VolumeSnapshot resource body with a timestamp
    snapshot_name = f"{pvc_name}-snapshot-{timestamp}"
    snapshot_body = {
        "apiVersion": "snapshot.storage.k8s.io/v1",
        "kind": "VolumeSnapshot",
        "metadata": {"name": snapshot_name},
        "spec": {
            "volumeSnapshotClassName": "gcp-snapshot-class",
            "source": {"persistentVolumeClaimName": pvc_name}
        }
    }

    # Create the VolumeSnapshot custom object
    api.create_namespaced_custom_object(
        group="snapshot.storage.k8s.io",
        version="v1",
        namespace=namespace,
        plural="volumesnapshots",
        body=snapshot_body,
    )

    print(f"Created snapshot: {snapshot_name}")

def cleanup_old_snapshots(namespace, max_retention_days):
    # Load Kubernetes configuration
    config.load_incluster_config()

    # Create Kubernetes API client
    api = client.CustomObjectsApi()

    # List VolumeSnapshot objects in the namespace
    snapshots = api.list_namespaced_custom_object(
        group="snapshot.storage.k8s.io",
        version="v1",
        namespace=namespace,
        plural="volumesnapshots",
    )

    # Sort snapshots by creationTimestamp in descending order
    snapshots["items"].sort(key=lambda x: x["metadata"]["creationTimestamp"], reverse=True)

    # Keep the latest `max_retention_days` snapshots
    snapshots_to_delete = snapshots["items"][max_retention_days:]

    # Delete old snapshots
    for snapshot in snapshots_to_delete:
        snapshot_name = snapshot["metadata"]["name"]
        api.delete_namespaced_custom_object(
            group="snapshot.storage.k8s.io",
            version="v1",
            namespace=namespace,
            plural="volumesnapshots",
            name=snapshot_name,
            body=client.V1DeleteOptions(),
        )
        print(f"Deleted old snapshot: {snapshot_name}")

if __name__ == "__main__":
    # Set variables
    pvc_name = os.environ["PVC_NAME"]
    namespace = os.environ["NAMESPACE"]
    max_retention_days = int(os.environ["MAX_RETENTION_DAYS"])

    # Create VolumeSnapshot for the specified PVC
    create_volume_snapshot(pvc_name, namespace)

    # Cleanup old snapshots, keeping the latest `max_retention_days`
    cleanup_old_snapshots(namespace, max_retention_days)

