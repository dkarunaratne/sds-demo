# Demo: Devops Best Practices

This repo is a fork of https://github.com/bobcatfish/ops202-cloud-next-23 which is meant to demonstrate
setting up a project in GCP that follows DevOps best practices.

The demo will be used to display:
- [x] GCB triggering
- [x] Build and push to AR
- [x] Provenance generation
- [x] Image scanning
- [x] SBOM generation
- [x] VEX upload to AR
- [x] Cloud Build security insights
- [x] Cloud Deploy deploy to test
- [x] Cloud Deploy promotion across environments
- [x] Cloud Deploy security insights
- [x] Cloud Deploy canary deployment w/ verification
- [x] Cloud Deploy with parallel deployment
- [x] BinAuthz cotinuous validation with SLSA policy

## Setup tutorial

## Setup: enable APIs

Set the PROJECT_ID environment variable. This variable will be used in forthcoming steps.

```bash
export PROJECT_ID=<walkthrough-project-id/>
# sets the current project for gcloud
gcloud config set project $PROJECT_ID
# Enables various APIs you'll need
gcloud services enable \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  clouddeploy.googleapis.com \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  containeranalysis.googleapis.com \
  containerscanning.googleapis.com \
  binaryauthorization.googleapis.com
```

## Add Deployment

### Setup AR repo to push images to


Create the repository:
```bash
gcloud artifacts repositories create pop-stats \
  --location=us-central1 \
  --repository-format=docker \
  --project=$PROJECT_ID
```

### Create GKE clusters

Create the GKE clusters:

```bash
./bootstrap/gke-cluster-init.sh
```

Verify that they were created in the [GKE UI](https://console.cloud.google.com/kubernetes/list/overview)

## BinAuthz continuous validation

### Update SLSA policy and bind to GKE

Update the `slsa-policy.yaml` for your project and repos.

Create the policy.

```bash
gcloud beta container binauthz policy create slsa-policy \
    --platform=gke \
    --policy-file=slsa-policy.yaml \
    --project=POLICY_PROJECT_ID
```

Bind the slsa-policy to your GKE clusters.

```bash
gcloud beta container clusters update stagingcluster \
    --location=us-central1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/slsa-policy \
    --project=$PROJECT_ID \
    --async

gcloud beta container clusters update prodcluster1 \
    --location=us-central1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/slsa-policy \
    --project=$PROJECT_ID \
    --async

gcloud beta container clusters update prodcluster2 \
    --location=europe-west1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/slsa-policy \
    --project=$PROJECT_ID \
    --async

gcloud beta container clusters update prodcluster3 \
    --location=asia-northeast1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/slsa-policy \
    --project=$PROJECT_ID \
    --async
```

### Build up the pipeline

```bash
# customize the clouddeploy.yamls
sed -i "s/project-id-here/${PROJECT_ID}/" clouddeploy*.yaml
```

View Google Cloud Deploy pipelines in the:
[Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines)

#### 0. Manual stuff

Building images as needed

```bash
export PREFIX=bug
export TAG=$PREFIX-$(date +%s)
export IMAGE="us-central1-docker.pkg.dev/$PROJECT_ID/pop-stats/pop-stats:$TAG"
docker build app/ -t $IMAGE -f app/Dockerfile
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push $IMAGE
```

Creating releases

```bash
export RELEASE=rel-$(date +%s)
gcloud deploy releases create ${RELEASE} \
  --delivery-pipeline pop-stats-pipeline \
  --region us-central1 \
  --images pop-stats=$IMAGE
```

#### 1. Staging environment with redundancy w/ multiple production targets and parallel deployment

```bash
gcloud deploy apply --file clouddeploy.yaml --region=us-central1 --project=$PROJECT_ID
```

### Setup a Cloud Build trigger to deploy on merge to main

#### IAM and service account setup

You must give Cloud Build explicit permission to trigger a Google Cloud Deploy release.
1. Read the [docs](https://cloud.google.com/deploy/docs/integrating-ci)
2. Navigate to [IAM](https://console.cloud.google.com/iam-admin/iam)
  * Check "Include Google-provided role grants"
  * Locate the service account named "Cloud Build service account"
3. Add these roles:
  * Cloud Deploy Releaser
  * Service Account User
  * Container Analysis Admin
  * Container Analysis service agent
  * Artifact registry reader

You must give the service account that runs your kubernetes workloads
permission to pull containers from artifact registry:
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/artifactregistry.reader"
```

You must give the service account that runs cloud deploy jobs the
permissions it needs to operate:
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/container.developer"
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/clouddeploy.jobRunner"
```

## Turn on automated container vulnerability analysis
Google Cloud Container Analysis can be set to automatically scan for vulnerabilities on push (see [pricing](https://cloud.google.com/container-analysis/pricing)). 

Enable Container Analysis API for automated scanning:

```bash
gcloud services enable containerscanning.googleapis.com --project=$PROJECT_ID
```

You can now view the vulnerabilities of each image in artifact registry
(e.g. `https://console.cloud.google.com/artifacts/docker/<your project>/<your region>/pop-stats/pop-stats`).

Images are scanned when built, so previously built images will not have vulnerabilities
listed. Open a PR to trigger a build and the newly built image will be scanned.

## Add CI

### Setup a Cloud Build trigger on PRs

Configure Cloud Build to run each time a change is pushed to the main branch. To do this, add a Trigger in Cloud Build:
  1. Follow https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github to connect
     your GitHub repo
  2. Follow https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github?generation=2nd-gen to setup triggering:
    * Setup PR triggering to run cloudbuild.yaml

Open a PR to create a Cloud Deploy release and deploy it to the
the `staging` environment.  You can see the progress via the
[Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines).

## Promote the release

In the [Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines),
you can promote the release from test to staging, and from staging to prod (with a manual
approval step in between).

## Security insights

* View Cloud Build security insights via the Cloud Build history view: https://cloud.google.com/build/docs/view-build-security-insights
* View Cloud Deploy security insights via the release artifacts view: https://cloud.google.com/deploy/docs/securing/security-insights

## About the Sample app - Population stats

Simple web app that pulls population and flag data based on country query.

Population data from restcountries.com API.

Feedback and contributions welcomed!
