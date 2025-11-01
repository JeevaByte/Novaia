GCP compute (C2) quick-start (for Novaia repo)

This document shows example gcloud commands (Windows cmd.exe style) and notes for using Compute-Optimized C2 instances for CPU-heavy workloads.

Replace PROJECT_ID and ZONE with your project and desired zone.

1) Basic c2 VM (n2 vs c2): c2 is compute-optimized (good for CPU-bound tasks)

Create a c2-standard-8 instance (8 vCPU, 32GB):

```bat
REM Create a C2 VM and attach the startup script (runs as root)
gcloud compute instances create novaia-c2-1 ^
  --project=PROJECT_ID ^
  --zone=us-central1-a ^
  --machine-type=c2-standard-8 ^
  --image-family=ubuntu-2204-lts ^
  --image-project=ubuntu-os-cloud ^
  --boot-disk-size=100GB ^
  --boot-disk-type=pd-ssd ^
  --scopes=https://www.googleapis.com/auth/cloud-platform ^
  --metadata-from-file startup-script=./startup_c2.sh ^
  --tags=http-server,https-server
```

Create a larger c2 instance (c2-standard-16):

```bat
gcloud compute instances create novaia-c2-2 ^
  --project=PROJECT_ID ^
  --zone=us-central1-a ^
  --machine-type=c2-standard-16 ^
  --image-family=ubuntu-2204-lts ^
  --image-project=ubuntu-os-cloud ^
  --boot-disk-size=200GB ^
  --boot-disk-type=pd-ssd ^
  --scopes=https://www.googleapis.com/auth/cloud-platform ^
  --metadata-from-file startup-script=./startup_c2.sh ^
  --tags=http-server,https-server
```

2) Instance template + Managed Instance Group (MIG) for autoscaling

Create instance template (use the same startup script):

```bat
gcloud compute instance-templates create novaia-c2-template ^
  --project=PROJECT_ID ^
  --machine-type=c2-standard-8 ^
  --image-family=ubuntu-2204-lts ^
  --image-project=ubuntu-os-cloud ^
  --boot-disk-size=100GB ^
  --boot-disk-type=pd-ssd ^
  --metadata-from-file startup-script=./startup_c2.sh ^
  --tags=http-server,https-server
```

Create a zonal managed instance group from the template:

```bat
gcloud compute instance-groups managed create novaia-c2-mig ^
  --project=PROJECT_ID ^
  --base-instance-name=novaia-c2 ^
  --size=1 ^
  --template=novaia-c2-template ^
  --zone=us-central1-a
```

Set autoscaling (CPU-based):

```bat
gcloud compute instance-groups managed set-autoscaling novaia-c2-mig ^
  --zone=us-central1-a ^
  --min-num-replicas=1 ^
  --max-num-replicas=5 ^
  --target-cpu-utilization=0.6
```

3) Using preemptible (spot) instances for cost savings (good for batch jobs)

When creating the instance template, add `--preemptible` to reduce costs (can be terminated at short notice).

4) Local SSD vs PD-SSD

- PD-SSD (persistent disk) is durable and recommended for app disk storage.
- Local SSD gives very high IOPS but is ephemeral (data lost on stop) — better for temporary high IO caches.

Add `--local-ssd` to instance create if you need it.

5) Monitoring and Logging

- Install the Cloud Ops agent if you need detailed system metrics.
- Be sure to check `systemd` logs for the service: `journalctl -u novaia-c2` (or check Cloud Logging if you forward logs).

6) Security & IAM

- Avoid `--scopes=https://www.googleapis.com/auth/cloud-platform` in production; instead create a service account with least privilege and use `--service-account=SERVICE_ACCOUNT`.
- Use HTTPS load balancer for public web endpoints. Protect with Cloud Armor if needed.

7) Cost notes

- c2-standard-8 and c2-standard-16 are more expensive than general-purpose VMs, but they can greatly reduce job latency for CPU-bound tasks. Use preemptible for batch jobs.
- Use the GCP Pricing Calculator for exact estimates in your region.

8) Customizing the startup script

- Edit `startup_c2.sh` to change `REPO_URL`, `GIT_BRANCH` or the default `STARTUP_CMD`.
- You can override `STARTUP_CMD` at VM creation time using instance metadata, e.g.:

```bat
gcloud compute instances create novaia-c2-override ^
  --project=PROJECT_ID ^
  --zone=us-central1-a ^
  --machine-type=c2-standard-8 ^
  --image-family=ubuntu-2204-lts ^
  --metadata=STARTUP_CMD="/opt/novaia/venv/bin/python /opt/novaia/my_service.py" ^
  --metadata-from-file startup-script=./startup_c2.sh
```

9) Next steps & recommendations

- Start with a single c2-standard-8 and run your workload; measure latency and CPU utilization.
- For horizontal scaling, use MIG and autoscaler; for container-first ops, build a Docker image and migrate to GKE.
- If/when GPU is required later, add a GPU node pool in GKE or create GPU instances (note: GPUs are not in the c2 family; you'll use an n1/n2 + GPU accelerator or A2 family for A100).

---

If you want, I can also:
- Create a Dockerfile for the repo and a minimal Cloud Build config to build/push images.
- Create a tailored service unit, or modify the startup script to run a Docker container instead of the venv.
- Create a short benchmarking script to measure CPU throughput on your workload (helpful to choose c2 size).

