spark-submit \
  --master k8s://https://<do_kubernetes_cluster> \
  --deploy-mode cluster \
  --name sparkpyexample \
  --conf spark.executor.instances=3 \
  --conf spark.kubernetes.container.image=registry.digitalocean.com/<registry_name>/sparkpyexample:latest \
  local:///opt/sparkpyexample.py
