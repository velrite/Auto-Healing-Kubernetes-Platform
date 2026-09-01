# Capacity and Cost

## Cluster Resources

Each node allocated: 2 CPU cores, 2000MB RAM
Total cluster: 6 cores, 6GB RAM allocated to nodes
Host: 8GB RAM (GitHub Codespace)

## HPA Configuration

| Deployment | Min | Max | CPU Threshold | Memory Threshold |
|------------|-----|-----|---------------|-----------------|
| api-ervice | 2 | 8 | 60% | 70% |
| frontend | 2 | 6 | 65% | — |

## HPA Test Results

- 3 parallel load generators
- CPU reached 86% — above 60% threshold
- Scaled from 2 to 8 pods (maximum replicas reached)
- CPU dropped to 2% after load removed
- Scale down automatic

## OpenCost Data

Sample from live API response:
```
api-service pod:
  cpuCores: 0.05
  cpuCost: $0.00015
  ramBytes: 67108864
  ramCost: $0.00003
  totalCost: $0.00018 per pod
```

Cost labels applied:
- api-service: team=backend, cost-center=platform, environment=production
- frontend: team=frontend, cost-center=product, environment=production
- postgres-db: team=data, cost-center=platform, environment=production

## Infrastructure Cost

GitHub Codespaces free tier used throughout.
All tools open source and self-hosted.
Zero cloud spend for this project.
