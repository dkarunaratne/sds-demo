set -ex

# Cleanup script to delete the three clusters created by the gke-cluster-init.sh script
# bail if PROJECT_ID is not set
if [[ -z "${PROJECT_ID}" ]]; then
  echo "The value of PROJECT_ID is not set. Be sure to run export PROJECT_ID=YOUR-PROJECT first"
  exit 1
fi
# sets the current project for gcloud
gcloud config set project $PROJECT_ID
# Staging cluster
echo "Deleting stagingcluster..."
gcloud container clusters delete stagingcluster --region "us-central1" --async
# Prod cluster 1
echo "Deleting prodcluster1..."
gcloud container clusters delete prodcluster1 --region "us-central1" --async
# Prod cluster 2
echo "Deleting prodcluster2..."
gcloud container clusters delete prodcluster2 --region "europe-west1" --async
# Prod cluster 2
echo "Deleting prodcluster3..."
gcloud container clusters delete prodcluster3 --region "asia-northeast1" --async